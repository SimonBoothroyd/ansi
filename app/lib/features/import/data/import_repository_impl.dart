/// [ImportRepository] over the local PowerSync SQLite.
///
/// `startImport` here is the CANNED stand-in, not the app's import path: it
/// parses the canned payload and re-resolves its placeholder candidates against
/// the real local vocab, so tests and the on-device smoke test exercise the
/// whole reconciliation flow with no network and no LLM. The app itself calls
/// the real `import-recipe` edge function (`EdgeImportRepository`); this class
/// only reaches a running app when something names it directly.
///
/// `commit` is real. It writes the resolved recipe, its groups and line items,
/// and correction aliases in one transaction, generating ids up front so it can
/// remap each step token's `line_index` refs to the created `line_item_id`s
/// before the recipe row is written (§4.6). It creates no ingredient: every
/// line arrives with a real id, because "create new" at review runs the
/// ingredient form before the line resolves — the `import_stub` leg is gone.
/// Local tables are SQLite VIEWS, so every write is a plain INSERT, never
/// `ON CONFLICT`, which those views reject.
library;

import 'dart:convert';

import 'package:sqlite3/common.dart' show Row;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/search/search_query.dart';
import '../../../core/search/search_rank.dart';
import '../../../core/units/units.dart';
import '../../ingredients/data/name_holder.dart';
import '../../ingredients/domain/normalize.dart';
import '../../recipes/data/recipe_measure_repository_impl.dart'
    show writeRecipeMeasures;
import '../domain/commit_payload.dart';
import '../domain/import_repository.dart';
import '../domain/learnable_alias.dart';
import '../domain/reconciliation_payload.dart';
import 'sample_payloads.dart';

const _uuid = Uuid();

/// How many LIKE candidates are ranked. A commit resolves one name against a
/// household's own vocabulary, where a token-subset match returning more than
/// a handful of rows is already unusual; the cap is here so a pathological
/// name cannot walk the whole table.
const _page = 30;

/// A row's live aliases' `match_text`, newline-separated so each stays a
/// phrase of its own — the rule's tier 0 asks whether the query IS an alias,
/// which a space-joined blob could never answer. `match_text` cannot contain a
/// newline (the normalizer collapses all whitespace), so the split is exact.
const _aliasText =
    '(SELECT GROUP_CONCAT(a.match_text, char(10)) FROM ingredient_alias a '
    'WHERE a.ingredient_id = i.id AND a.deleted_at IS NULL) AS alias_text';

class SqliteImportRepository implements ImportRepository {
  const SqliteImportRepository(
    this._db, {
    required String householdId,
    String payloadJson = cannedReconciliationPayloadJson,
  }) : _householdId = householdId,
       _payloadJson = payloadJson;

  final SqliteConnection _db;
  final String _householdId;

  /// Which canned payload `startImport` serves. Defaults to
  /// [cannedReconciliationPayloadJson]; a smoke scenario driving a different
  /// recipe (see [peanutStirFryPayloadJson]) passes its own. Only the
  /// extract+match hop is fixed — the candidates are still re-resolved against
  /// the real local vocab below.
  final String _payloadJson;

  @override
  Future<ReconciliationPayload> startImport(
    ImportSource source, {
    void Function(ImportProgress)? onProgress,
  }) async {
    // The canned stand-in ignores the source and returns a fixed payload, with
    // candidate ids re-pointed at whatever the local vocab actually holds.
    final payload = ReconciliationPayload.fromJson(
      jsonDecode(_payloadJson) as Map<String, Object?>,
    );
    final groups = [
      for (final group in payload.groups)
        group.copyWith(lines: [for (final l in group.lines) await _resolve(l)]),
    ];
    return payload.copyWith(groups: groups);
  }

  /// Re-points a canned line's placeholder candidates at real vocab rows: an
  /// exact canonical-name match first, then the same token-subset search the
  /// picker uses (so a candidate named "Parmesan" still lands on a seeded
  /// "Parmesan cheese" — the round-1 bug where suggestions silently vanished
  /// because only exact names resolved). The RESOLVED row's own name replaces
  /// the canned one: a candidate that reads "Parmesan" while pointing at
  /// "Parmesan cheese" would put the wrong label on the chip the user taps,
  /// and that label is what the resolution stores as `chosenName`. A line
  /// whose candidates all miss degrades to `none` — the user resolves it,
  /// exactly as an unmatched line from the real server.
  Future<ReconLine> _resolve(ReconLine line) async {
    if (line.candidates.isEmpty) return line;
    final resolved = <MatchCandidate>[];
    for (final c in line.candidates) {
      final row = await _findVocabRow(c.canonicalName);
      if (row != null) {
        resolved.add(
          c.copyWith(ingredientId: row.id, canonicalName: row.canonicalName),
        );
      }
    }
    if (resolved.isEmpty) {
      return line.copyWith(band: MatchBand.none, candidates: const []);
    }
    return line.copyWith(candidates: resolved);
  }

  /// The live vocab row a candidate [name] resolves to: the best hit of the
  /// SAME ranking the pickers use ([searchRank]) over the rows a word-prefix
  /// LIKE pass selects — the ingredient's `match_text` **or any of its live
  /// aliases**, every token raw or singularized — else null.
  ///
  /// **Tiers 0 and 1 only — never the typo tier**, and that asymmetry is a
  /// rule, not an omission. This is the one search seam with no human in the
  /// loop: it picks one row at commit time and writes the answer into a
  /// saved recipe. A guess here is a wrong ingredient on a line nobody
  /// reviewed, which is what ADR-0004 exiles and what the never-invent
  /// invariant refuses. **Tier 2 is retrieval for a human to pick, never a
  /// resolution** — the pickers may guess because someone is looking at the
  /// list; this may not, and must not "have the job finished" for it by a
  /// later unification pass.
  ///
  /// What the ranking buys: the SQL knows which rows *could* match, and
  /// nothing more. Ordered by name length instead, `tom` committed `Tomato`
  /// where the picker offered `Cherry Tomato` first — its alias `tom` is an
  /// exact surface — so the seam nobody reviews answered differently from the
  /// one everybody sees. One rule now decides both.
  ///
  /// Aliases matter here for the same reason they matter in the picker: the
  /// learning loop's absorbed phrasing ("coco milk" → Coconut Milk) is a
  /// SPELLING the household taught us, not a guess. Searching only
  /// `ingredient.match_text` made that knowledge invisible to the one caller
  /// that most needed it.
  Future<({String id, String canonicalName})?> _findVocabRow(
    String name,
  ) async {
    final tokens = searchTokens(name);
    if (tokens.isEmpty) return null;
    final where = StringBuffer('i.deleted_at IS NULL');
    final params = <Object?>[];
    for (final tok in tokens) {
      // Raw form OR singular form, the same rule the picker's search uses:
      // `match_text` is singularized by the phrase normalizer, so a candidate
      // named "Almonds" must still resolve to the row holding `almond`.
      final patterns = [
        for (final form in matchTextForms(tok)) ...['$form%', '% $form%'],
      ];
      final own = patterns.map((_) => 'i.match_text LIKE ?').join(' OR ');
      final alias = patterns.map((_) => 'a.match_text LIKE ?').join(' OR ');
      where.write(
        ' AND ($own '
        'OR EXISTS (SELECT 1 FROM ingredient_alias a '
        'WHERE a.ingredient_id = i.id AND a.deleted_at IS NULL '
        'AND ($alias)))',
      );
      params.addAll([...patterns, ...patterns]);
    }
    // This pass SELECTS a page; it does not rank. The page is bounded and
    // ordered the way the picker's is, so the rows the cap keeps are the same
    // rows it would keep.
    final rows = await _db.getAll(
      'SELECT i.id, i.canonical_name, i.match_text, $_aliasText '
      'FROM ingredient i WHERE $where '
      'ORDER BY length(i.canonical_name), i.canonical_name LIMIT $_page',
      params,
    );

    final ranked = <({SearchHit hit, Row row})>[];
    for (final r in rows) {
      final hit = searchRank(name, [
        (r['match_text'] as String?) ?? '',
        ...((r['alias_text'] as String?) ?? '').split('\n'),
        normalizeSearchQuery(r['canonical_name'] as String),
      ]);
      if (hit == null) continue;
      ranked.add((hit: hit, row: r));
    }
    if (ranked.isEmpty) return null;
    ranked.sort((a, b) {
      final byTier = a.hit.tier.index.compareTo(b.hit.tier.index);
      if (byTier != 0) return byTier;
      final byScore = b.hit.score.compareTo(a.hit.score);
      if (byScore != 0) return byScore;
      final an = a.row['canonical_name'] as String;
      final bn = b.row['canonical_name'] as String;
      final byLength = an.length.compareTo(bn.length);
      return byLength != 0 ? byLength : an.compareTo(bn);
    });
    final best = ranked.first;
    // The whole asymmetry, in one line: a typo hit is an offer, and there is
    // nobody here to accept it.
    if (best.hit.tier == SearchTier.typo) return null;
    return (
      id: best.row['id'] as String,
      canonicalName: best.row['canonical_name'] as String,
    );
  }

  @override
  Future<String> commit(CommitPayload payload) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final recipeId = _uuid.v4();

    // Ids up front so step refs can be remapped before the recipe row is
    // written.
    final lineIds = <int, String>{}; // flat line_index → line_item_id
    for (final group in payload.groups) {
      for (final line in group.lines) {
        lineIds[line.lineIndex] = _uuid.v4();
      }
    }

    final stepsJson = jsonEncode(_remapSteps(payload.steps, lineIds));

    await _db.writeTransaction((tx) async {
      // 1. The recipe row, carrying the remapped tokenized steps and EVERY
      // header column the editor's save writes — the same column list, in the
      // same order, which a structural test pins so the two writers cannot
      // drift apart again.
      //
      // Filing is load-bearing: the Library renders books and skips book-less
      // recipes, so a null `book_id` would save the recipe into a place
      // nothing shows it. The review's draft normally names the default book
      // from the start (FILE UNDER can move it); a draft that never resolved
      // one still lands in the default book here, exactly as the new-recipe
      // path does (`RecipeEditor.build` → `ensureDefaultBook`).
      //
      // `buildCommit` guarantees both halves of a yield or neither, so the
      // `recipe_yield_pair` CHECKs cannot be hit here.
      final bookId = payload.bookId ?? await _defaultBookId(tx, now);
      await tx.execute(
        'INSERT INTO recipe (id, household_id, title, servings_base, steps, '
        'keeps_for_days, freezable, freezer_days, book_id, section_id, '
        'yield_qty, yield_unit, yield_qty_2, yield_unit_2, '
        'cook_time_seconds, total_time_seconds, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          recipeId,
          _householdId,
          payload.title,
          payload.servingsBase,
          stepsJson,
          payload.keepsForDays,
          if (payload.freezable) 1 else 0,
          payload.freezerDays,
          bookId,
          payload.sectionId,
          payload.yieldQty,
          payload.yieldUnit?.id,
          payload.yieldQty2,
          payload.yieldUnit2?.id,
          payload.cookTimeSeconds,
          payload.totalTimeSeconds,
          now,
          now,
        ],
      );

      // 2. The recipe's own words, before the lines — the same order and the
      // same diff `saveRecipe` runs, through the one file that writes
      // `recipe_measure` at all. A commit carries them because the review hosts
      // the same MEASURES list the editor does (ADR-0018), and it re-stamps
      // this recipe's id over the draft's placeholder.
      await writeRecipeMeasures(
        tx,
        recipeId: recipeId,
        householdId: _householdId,
        measures: payload.measures,
        now: now,
      );

      // 3. Groups, then line items in flattened order. Every line carries
      // exactly one identity: an ingredient or, for a line the reviewer
      // LINKED, a sub-recipe (0017's XOR).
      var sortInGroup = 0;
      for (var gi = 0; gi < payload.groups.length; gi++) {
        final group = payload.groups[gi];
        final groupId = _uuid.v4();
        await tx.execute(
          'INSERT INTO ingredient_group (id, household_id, recipe_id, name, '
          'sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [groupId, _householdId, recipeId, group.name, gi, now, now],
        );
        sortInGroup = 0;
        for (final line in group.lines) {
          // Exactly one identity (migration 0017's `line_item_identity_xor`):
          // a review-LINKED line is a component — `sub_recipe_id` set,
          // `ingredient_id` null — and everything else resolves to a real
          // vocabulary row.
          final subRecipeId = line.subRecipeId;
          final ingredientId = subRecipeId != null ? null : line.ingredientId;
          if (subRecipeId == null && ingredientId == null) {
            throw StateError('line ${line.lineIndex} has no identity');
          }
          // A resolved measure (the user picked "can", "clove"…) persists as a
          // `measure_id` FK with `unit='piece'` (migration 0009) so the count↔
          // basis bridge survives commit, instead of degrading to a bare
          // "piece". Only an existing vocab row can carry measures — a
          // freshly-created stub never does — and a measure that has since
          // vanished still degrades to an honest count via [_unitId]. A
          // COMPONENT line never carries one at all — a measure is an
          // ingredient concept, and 0017 fences that with its own CHECK.
          final measureId = (subRecipeId != null || line.ingredientId == null)
              ? null
              : await _measureIdFor(tx, line.ingredientId!, line.unit);
          await tx.execute(
            'INSERT INTO recipe_line_item (id, household_id, group_id, '
            'ingredient_id, sub_recipe_id, quantity, unit, measure_id, note, '
            'optional, sort_order, created_at, updated_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              lineIds[line.lineIndex],
              _householdId,
              groupId,
              ingredientId,
              subRecipeId,
              line.quantity,
              if (measureId != null) pieces.id else _unitId(line),
              measureId,
              line.note,
              // 0/1 like the schema's other flags, on a component line as on
              // an ingredient one.
              if (line.optional) 1 else 0,
              sortInGroup,
              now,
              now,
            ],
          );
          sortInGroup++;
        }
      }

      // 4. Correction aliases (source='import_correction') — lane B's loop.
      // The alias is written with the SERVER's phrase normalizer
      // (`normalizeMatchText`), not the character-level search normalizer,
      // because the cascade that will one day match on it searches by those
      // rules — "ripe tomatoes, chopped" is `ripe tomato chopped` to the
      // server. Local tables are VIEWS, so this is a lookup + a plain INSERT:
      // a view rejects `ON CONFLICT`.
      //
      // **An alias is a name, so it lands in the one namespace or not at all**
      // (`ingredients/domain/name_namespace.dart`), and the rule is asked
      // HERE, inside the write, by the same `nameHolderFor` the flesh-out
      // form's save asks. Learning is the silent half of this loop, so a taken
      // name is not an error and nothing is said about it: the line has
      // already resolved to the row the human picked, which is the whole of
      // what they asked for. Two cases, one answer — write nothing:
      //
      // * **another row holds the text.** "extra-firm tofu" corrected onto
      //   Super Firm Tofu normalizes to `extra firm tofu`, which IS Extra Firm
      //   Tofu's own name; learning it would make every later exact match
      //   between those two rows a coin toss.
      // * **the picked row holds it** — as its own name (the page printed what
      //   the row is already called) or as an alias it already has, which is
      //   also this loop's find-or-create rule: correcting "yellow onion" onto
      //   Onion on every import must not pile up a duplicate alias row per
      //   import, all of them matching identically.
      for (final c in payload.corrections) {
        // A whole printed LINE is not a name either — "olive oil or cooking
        // oil of choice" names two things and an aside, and normalizing it
        // would bury that in a bag of words nothing will ever ask for. Asked
        // of the raw text, because normalization erases the very marks that
        // give it away (`domain/learnable_alias.dart`).
        if (!looksLikeAName(c.aliasText)) continue;
        final matchText = normalizeMatchText(c.aliasText);
        // A phrase with no identity word ("a good pinch of") is not a name and
        // could never match anything; the form refuses one outright, and here
        // — where a refusal would cost the human their whole recipe — it is
        // simply not learned.
        if (matchText.isEmpty) continue;
        if (await nameHolderFor(tx, matchText) != null) continue;
        await tx.execute(
          'INSERT INTO ingredient_alias (id, household_id, ingredient_id, '
          'alias_text, match_text, source, created_at, updated_at) '
          "VALUES (?, ?, ?, ?, ?, 'import_correction', ?, ?)",
          [
            _uuid.v4(),
            _householdId,
            c.ingredientId,
            c.aliasText,
            matchText,
            now,
            now,
          ],
        );
      }
    });

    return recipeId;
  }

  /// The book an imported recipe is filed into: the household's first live book
  /// (creating "Our Cookbook" if there is somehow none), mirroring
  /// `BookRepository.ensureDefaultBook`. Kept inline rather than delegating so
  /// the whole commit stays in one transaction — a recipe must never land
  /// half-filed. The orphan-adoption leg of `ensureDefaultBook` is deliberately
  /// not mirrored: this write sets `book_id` directly.
  Future<String> _defaultBookId(SqliteWriteContext tx, String now) async {
    final existing = await tx.getOptional(
      'SELECT id FROM book WHERE deleted_at IS NULL '
      'ORDER BY sort_order, created_at LIMIT 1',
    );
    if (existing != null) return existing['id'] as String;

    final id = _uuid.v4();
    final order = await tx.get(
      'SELECT COALESCE(MAX(sort_order), -1) AS m FROM book '
      'WHERE deleted_at IS NULL',
    );
    await tx.execute(
      'INSERT INTO book (id, household_id, name, sort_order, created_at, '
      "updated_at) VALUES (?, ?, 'Our Cookbook', ?, ?, ?)",
      [id, _householdId, (order['m'] as int) + 1, now, now],
    );
    return id;
  }

  /// The stored unit id for a line: the catalog unit when the printed word maps
  /// (`tbsp`, `g`, `piece`…); otherwise `to_taste` for a numberless line and
  /// `piece` for a counted one. A non-catalog measure word (`clove`, `can`) is
  /// not fabricated into grams — it degrades to an honest count (invariant 3).
  String _unitId(CommitLine line) {
    final mapped = line.unit == null ? null : unitById(line.unit!);
    if (mapped != null) return mapped.id;
    return line.quantity == null ? toTaste.id : pieces.id;
  }

  /// The `ingredient_measure.id` that a line's [unit] names for [ingredientId],
  /// or null. Returns null for a catalog unit (`tbsp`, `g`, `piece`…) — those
  /// aren't measures — and for a measure word that names no live measure of the
  /// ingredient. A measure pick rides on the line as its raw `label` (see
  /// `sheetChoiceUnit`), so an exact case-insensitive label match resolves it
  /// back to the FK the commit persists.
  Future<String?> _measureIdFor(
    SqliteWriteContext tx,
    String ingredientId,
    String? unit,
  ) async {
    if (unit == null || unitById(unit) != null) return null;
    final row = await tx.getOptional(
      'SELECT id FROM ingredient_measure '
      'WHERE ingredient_id = ? AND deleted_at IS NULL '
      'AND LOWER(label) = LOWER(?) LIMIT 1',
      [ingredientId, unit],
    );
    return row?['id'] as String?;
  }

  /// Rebuilds the stored step JSON, remapping each ref token's `line_index`
  /// refs to the created `line_item_id`s (§4.6). Text and timer tokens pass
  /// through; a ref whose lines all vanished — an out-of-range index, or a line
  /// the user DROPPED at review — never invents a target: it demotes to its own
  /// label as plain prose, so "finish with basil" keeps the word and loses only
  /// the chip.
  List<Map<String, Object?>> _remapSteps(
    List<Step> steps,
    Map<int, String> lineIds,
  ) {
    return [
      for (final step in steps)
        {
          'tokens': [
            for (final token in step.tokens) _remapToken(token, lineIds),
          ].whereType<Map<String, Object?>>().toList(),
        },
    ];
  }

  Map<String, Object?>? _remapToken(StepToken token, Map<int, String> lineIds) {
    switch (token) {
      case TextToken(:final s):
        return {'t': 'text', 's': s};
      case TimerToken(:final lowSeconds, :final highSeconds):
        return {
          't': 'timer',
          'low_seconds': lowSeconds,
          'high_seconds': highSeconds,
        };
      case RefToken(:final refs, :final label, :final mention, :final portion):
        final ids = [
          for (final i in refs)
            if (lineIds[i] != null) lineIds[i]!,
        ];
        if (ids.isEmpty) {
          // No line survived. The chip's label is the extractor's own prose, so
          // keeping it as text loses the link and nothing else; a chip with no
          // label has nothing honest to say and goes.
          final text = label.trim();
          return text.isEmpty ? null : {'t': 'text', 's': text};
        }
        return {
          't': 'ref',
          'refs': ids,
          'label': label,
          'mention': _mentionJson(mention),
          'portion': portion == null ? null : _portionJson(portion),
        };
    }
  }

  String _mentionJson(MentionKind m) => switch (m) {
    MentionKind.isNew => 'new',
    MentionKind.rementioned => 'rementioned',
    MentionKind.fraction => 'fraction',
  };

  Map<String, Object?> _portionJson(RefPortion p) => {
    'qty': p.qty,
    'qty_low': p.qtyLow,
    'qty_high': p.qtyHigh,
    'unit': p.unit,
    'qualifier': p.qualifier,
  };
}
