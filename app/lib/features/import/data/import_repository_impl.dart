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
/// any create-new stubs, and correction aliases in one transaction, generating
/// ids up front so it can remap each step token's `line_index` refs to the
/// created `line_item_id`s before the recipe row is written (§4.6). Local
/// tables are SQLite VIEWS, so every write is a plain INSERT — never
/// `ON CONFLICT` ([mise-powersync-views-no-upsert]).
library;

import 'dart:convert';

import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/units/units.dart';
import '../../ingredients/domain/normalize.dart';
import '../../ingredients/domain/search_query.dart';
import '../domain/commit_payload.dart';
import '../domain/import_repository.dart';
import '../domain/reconciliation_payload.dart';
import 'canned_payload.dart';

const _uuid = Uuid();

class SqliteImportRepository implements ImportRepository {
  const SqliteImportRepository(this._db, {required String householdId})
    : _householdId = householdId;

  final SqliteConnection _db;
  final String _householdId;

  @override
  Future<ReconciliationPayload> startImport(ImportSource source) async {
    // The canned stand-in ignores the source and returns a fixed payload, with
    // candidate ids re-pointed at whatever the local vocab actually holds.
    final payload = ReconciliationPayload.fromJson(
      jsonDecode(cannedReconciliationPayloadJson) as Map<String, Object?>,
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

  /// The live vocab row a candidate [name] resolves to: an exact canonical-name
  /// hit, else the top token-subset match (every token of [name], raw or
  /// singularized, a word-prefix of the ingredient's `match_text`), else null.
  Future<({String id, String canonicalName})?> _findVocabRow(
    String name,
  ) async {
    final exact = await _db.getOptional(
      'SELECT id, canonical_name FROM ingredient '
      'WHERE deleted_at IS NULL AND LOWER(canonical_name) = LOWER(?) LIMIT 1',
      [name],
    );
    if (exact != null) {
      return (
        id: exact['id'] as String,
        canonicalName: exact['canonical_name'] as String,
      );
    }

    final tokens = searchTokens(name);
    if (tokens.isEmpty) return null;
    final where = StringBuffer('deleted_at IS NULL');
    final params = <Object?>[];
    for (final tok in tokens) {
      // Raw form OR singular form, the same rule the picker's search uses:
      // `match_text` is singularized by the phrase normalizer, so a candidate
      // named "Almonds" must still resolve to the row holding `almond`.
      final patterns = [
        for (final form in matchTextForms(tok)) ...['$form%', '% $form%'],
      ];
      where.write(
        ' AND (${patterns.map((_) => 'match_text LIKE ?').join(' OR ')})',
      );
      params.addAll(patterns);
    }
    final row = await _db.getOptional(
      'SELECT id, canonical_name FROM ingredient WHERE $where '
      'ORDER BY length(canonical_name), canonical_name LIMIT 1',
      params,
    );
    if (row == null) return null;
    return (
      id: row['id'] as String,
      canonicalName: row['canonical_name'] as String,
    );
  }

  @override
  Future<String> commit(CommitPayload payload) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final recipeId = _uuid.v4();

    // Ids up front so step refs can be remapped before the recipe row is
    // written. Stub ids are keyed by the coalescing key, so identical no-match
    // lines share one created ingredient.
    final stubIdByKey = {for (final s in payload.stubs) s.key: _uuid.v4()};
    final lineIds = <int, String>{}; // flat line_index → line_item_id
    for (final group in payload.groups) {
      for (final line in group.lines) {
        lineIds[line.lineIndex] = _uuid.v4();
      }
    }

    final stepsJson = jsonEncode(_remapSteps(payload.steps, lineIds));

    await _db.writeTransaction((tx) async {
      // 1. Create-new stubs (status='stub', source='import_stub'). USDA flesh-
      // out is a later view over these rows — no macros/density invented now.
      //
      // `match_text` is written with the SERVER's phrase rules
      // (`normalizeMatchText`, the plan-0020 D6 port), not the character-level
      // search normalizer: this row is what the *next* import's cascade
      // searches, and the cascade searches by the server's rules. The two
      // genuinely differ — "Chicken thighs, boneless" is `chicken thigh
      // boneless` to the server and `chicken thighs boneless` to the search
      // normalizer — so writing the wrong one here is the same silent
      // matching regression D6 closed everywhere else.
      for (final stub in payload.stubs) {
        await tx.execute(
          'INSERT INTO ingredient (id, household_id, canonical_name, '
          'default_unit, status, source, match_text, created_at, updated_at) '
          "VALUES (?, ?, ?, 'g', 'stub', 'import_stub', ?, ?, ?)",
          [
            stubIdByKey[stub.key],
            _householdId,
            stub.name,
            normalizeMatchText(stub.name),
            now,
            now,
          ],
        );
      }

      // 2. The recipe row, carrying the remapped tokenized steps. It is FILED
      // into the default book, exactly as the new-recipe path does
      // (`RecipeEditor.build` → `ensureDefaultBook`): the Library renders books
      // and skips book-less recipes, so a null `book_id` here saves the recipe
      // into a place nothing shows it.
      //
      // It also carries what one batch MAKES when the review stated it (8.6 /
      // D2): prefilled from `yield_raw` where that was a plain amount + unit,
      // else whatever the human typed, else nothing at all. `buildCommit`
      // guarantees both halves or neither, so the `recipe_yield_pair` CHECK
      // cannot be hit here. The optional SECOND denomination is an editor
      // affordance — the review states one, and a yield-less recipe is a
      // perfectly good save.
      final bookId = await _defaultBookId(tx, now);
      await tx.execute(
        'INSERT INTO recipe (id, household_id, title, servings_base, steps, '
        'cook_time_seconds, total_time_seconds, yield_qty, yield_unit, '
        'book_id, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          recipeId,
          _householdId,
          payload.title,
          payload.servingsBase,
          stepsJson,
          payload.cookTimeSeconds,
          payload.totalTimeSeconds,
          payload.yieldQty,
          payload.yieldUnit?.id,
          bookId,
          now,
          now,
        ],
      );

      // 3. Groups, then line items in flattened order. Every line carries
      // exactly one identity: an ingredient (real or just-created) or, for a
      // line the reviewer LINKED, a sub-recipe (0017's XOR).
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
          // `ingredient_id` null — and everything else resolves to a real or
          // just-created ingredient.
          final subRecipeId = line.subRecipeId;
          final ingredientId = subRecipeId != null
              ? null
              : (line.ingredientId ?? stubIdByKey[line.stubKey]);
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
            'sort_order, created_at, updated_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
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
              sortInGroup,
              now,
              now,
            ],
          );
          sortInGroup++;
        }
      }

      // 4. Correction aliases (source='import_correction') — lane B's loop.
      // Find-or-create, not blind insert: correcting "yellow onion" onto Onion
      // on every import would otherwise pile up a duplicate alias row per
      // import, all of them matching identically. Local tables are VIEWS, so
      // this is an existence check + a plain INSERT, never an UPSERT
      // ([mise-powersync-views-no-upsert]). Same D6 rule as the stub above:
      // the alias is written with the server's phrase normalizer, because the
      // cascade that will one day match on it searches by those rules.
      for (final c in payload.corrections) {
        final matchText = normalizeMatchText(c.aliasText);
        final existing = await tx.getOptional(
          'SELECT id FROM ingredient_alias '
          'WHERE ingredient_id = ? AND match_text = ? AND deleted_at IS NULL '
          'LIMIT 1',
          [c.ingredientId, matchText],
        );
        if (existing != null) continue;
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
