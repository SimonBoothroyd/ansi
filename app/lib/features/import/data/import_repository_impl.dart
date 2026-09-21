/// [ImportRepository] over the local PowerSync SQLite.
///
/// `startImport` is the canned stand-in for tests and the smoke run; the app
/// calls `EdgeImportRepository`. `commit` writes the recipe, its groups, line
/// items and correction aliases in one transaction, generating ids up front so
/// step refs can be remapped to `line_item_id`s. It creates no ingredient.
/// Local tables are views, so every write is a plain INSERT, never `ON
/// CONFLICT`.
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

/// How many LIKE candidates are ranked; a cap so a pathological name cannot
/// walk the whole table.
const _page = 30;

/// A row's live aliases' `match_text`, newline-separated so each stays a
/// phrase; `match_text` never contains a newline.
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
  /// [cannedReconciliationPayloadJson]; a smoke scenario can pass its own (see
  /// [peanutStirFryPayloadJson]).
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
  /// exact canonical-name match first, then the picker's token-subset search.
  /// The resolved row's own name replaces the canned one, because the chip's
  /// label is what the resolution stores as `chosenName`. A line whose
  /// candidates all miss degrades to `none`.
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

  /// The live vocab row a candidate [name] resolves to, or null: the best
  /// [searchRank] hit over the rows a word-prefix LIKE pass selects from
  /// `match_text` and live aliases, each token raw or singularized.
  ///
  /// Tiers 0 and 1 only, never the typo tier. This seam picks a row at commit
  /// time with no human looking, and a guess would put a wrong ingredient on a
  /// saved line (ADR-0004).
  Future<({String id, String canonicalName})?> _findVocabRow(
    String name,
  ) async {
    final tokens = searchTokens(name);
    if (tokens.isEmpty) return null;
    final where = StringBuffer('i.deleted_at IS NULL');
    final params = <Object?>[];
    for (final tok in tokens) {
      // Raw or singular form, as the picker's search: `match_text` is
      // singularized, so "Almonds" must still find `almond`.
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
    // This pass selects a bounded page, ordered as the picker's is; ranking
    // follows.
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
      // 1. The recipe row, carrying the remapped steps and every header column
      // the editor's save writes, in the same order (a structural test pins the
      // two).
      //
      // `book_id` must not be null: the Library skips book-less recipes. A
      // draft that never resolved a book lands in the default one.
      // `buildCommit` guarantees both halves of a yield or neither, so the
      // `recipe_yield_pair` CHECKs cannot fail here.
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

      // 2. The recipe's own measures, before the lines, in the same order and
      // diff as `saveRecipe` (ADR-0018). Re-stamps this recipe's id over the
      // draft's placeholder.
      await writeRecipeMeasures(
        tx,
        recipeId: recipeId,
        householdId: _householdId,
        measures: payload.measures,
        now: now,
      );

      // 3. Groups, then line items in flattened order.
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
          // Exactly one identity (`line_item_identity_xor`): a linked line sets
          // `sub_recipe_id` and no `ingredient_id`; every other line names a
          // vocabulary row.
          final subRecipeId = line.subRecipeId;
          final ingredientId = subRecipeId != null ? null : line.ingredientId;
          if (subRecipeId == null && ingredientId == null) {
            throw StateError('line ${line.lineIndex} has no identity');
          }
          // A picked measure ("can", "clove") persists as a `measure_id` FK
          // with `unit='piece'`. A measure that has since vanished degrades to
          // a count via [_unitId]. A component line never carries one.
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

      // 4. Correction aliases (source='import_correction'). Written with
      // `normalizeMatchText`, the rules the server's cascade searches by. A
      // lookup plus a plain INSERT, since views reject `ON CONFLICT`.
      //
      // An alias is a name, so `nameHolderFor` is asked inside the write
      // (`ingredients/domain/name_namespace.dart`). A taken name writes nothing
      // and says nothing, whether another row holds the text or the picked row
      // already does (as its name or an existing alias).
      for (final c in payload.corrections) {
        // A whole printed line is not a name. Asked of the raw text, because
        // normalization erases the marks that give it away
        // (`domain/learnable_alias.dart`).
        if (!looksLikeAName(c.aliasText)) continue;
        final matchText = normalizeMatchText(c.aliasText);
        // A phrase with no identity word ("a good pinch of") could never match
        // anything, so it is not learned.
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

  /// The book an imported recipe is filed into: the household's first live
  /// book, creating "Our Cookbook" if there is none. Mirrors
  /// `BookRepository.ensureDefaultBook` inline so the commit stays in one
  /// transaction; the orphan-adoption leg is not mirrored.
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

  /// The stored unit id for a line: the catalog unit when the printed word
  /// maps; otherwise `to_taste` for a numberless line and `piece` for a counted
  /// one. A non-catalog measure word degrades to a count.
  String _unitId(CommitLine line) {
    final mapped = line.unit == null ? null : unitById(line.unit!);
    if (mapped != null) return mapped.id;
    return line.quantity == null ? toTaste.id : pieces.id;
  }

  /// The `ingredient_measure.id` that a line's [unit] names for [ingredientId],
  /// or null for a catalog unit or a word naming no live measure. A measure
  /// pick rides on the line as its raw label (see `sheetChoiceUnit`), matched
  /// case-insensitively.
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
  /// refs to the created `line_item_id`s. Text and timer tokens pass through. A
  /// ref whose lines all vanished (out of range, or dropped at review) demotes
  /// to its label as plain text.
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
          // No line survived: keep the label as text; a ref with no label goes.
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
