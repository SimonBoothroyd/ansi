/// [ImportRepository] over the local PowerSync SQLite.
///
/// `startImport` is the **fake edge function** (0017): it parses the canned
/// payload and re-resolves its placeholder candidate ids against the real local
/// vocab by canonical name, so the pre-integration demo lands real matches. The
/// real `functions.invoke` replaces this method at the tail.
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
    // The fake edge function ignores the source and returns the canned payload,
    // with candidate ids re-pointed at whatever the local vocab actually holds.
    final payload = ReconciliationPayload.fromJson(
      jsonDecode(cannedReconciliationPayloadJson) as Map<String, Object?>,
    );
    final groups = [
      for (final group in payload.groups)
        group.copyWith(lines: [for (final l in group.lines) await _resolve(l)]),
    ];
    return payload.copyWith(groups: groups);
  }

  /// Re-points a canned line's placeholder candidates at real vocab ids: an
  /// exact canonical-name match first, then the same token-subset search the
  /// picker uses (so a candidate named "Parmesan" still lands on a seeded
  /// "Parmesan cheese" — the round-1 bug where suggestions silently vanished
  /// because only exact names resolved). A line whose candidates all miss
  /// degrades to `none` — the user resolves it, exactly as an unmatched line
  /// from the real server.
  Future<ReconLine> _resolve(ReconLine line) async {
    if (line.candidates.isEmpty) return line;
    final resolved = <MatchCandidate>[];
    for (final c in line.candidates) {
      final id = await _findVocabId(c.canonicalName);
      if (id != null) resolved.add(c.copyWith(ingredientId: id));
    }
    if (resolved.isEmpty) {
      return line.copyWith(band: MatchBand.none, candidates: const []);
    }
    return line.copyWith(candidates: resolved);
  }

  /// The live vocab id a candidate [name] resolves to: an exact canonical-name
  /// hit, else the top token-subset match (every token of [name] a word-prefix
  /// of the ingredient's `match_text`), else null.
  Future<String?> _findVocabId(String name) async {
    final exact = await _db.getOptional(
      'SELECT id FROM ingredient '
      'WHERE deleted_at IS NULL AND LOWER(canonical_name) = LOWER(?) LIMIT 1',
      [name],
    );
    if (exact != null) return exact['id'] as String;

    final tokens = searchTokens(name);
    if (tokens.isEmpty) return null;
    final where = StringBuffer('deleted_at IS NULL');
    final params = <Object?>[];
    for (final tok in tokens) {
      where.write(' AND (match_text LIKE ? OR match_text LIKE ?)');
      params.addAll(['$tok%', '% $tok%']);
    }
    final row = await _db.getOptional(
      'SELECT id FROM ingredient WHERE $where '
      'ORDER BY length(canonical_name), canonical_name LIMIT 1',
      params,
    );
    return row?['id'] as String?;
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
      for (final stub in payload.stubs) {
        await tx.execute(
          'INSERT INTO ingredient (id, household_id, canonical_name, '
          'default_unit, status, source, match_text, created_at, updated_at) '
          "VALUES (?, ?, ?, 'g', 'stub', 'import_stub', ?, ?, ?)",
          [
            stubIdByKey[stub.key],
            _householdId,
            stub.name,
            normalizeSearchQuery(stub.name),
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
      final bookId = await _defaultBookId(tx, now);
      await tx.execute(
        'INSERT INTO recipe (id, household_id, title, servings_base, steps, '
        'cook_time_seconds, total_time_seconds, book_id, created_at, '
        'updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          recipeId,
          _householdId,
          payload.title,
          payload.servingsBase,
          stepsJson,
          payload.cookTimeSeconds,
          payload.totalTimeSeconds,
          bookId,
          now,
          now,
        ],
      );

      // 3. Groups, then line items in flattened order. Every line resolves to a
      // real or just-created ingredient — ingredient_id is NOT NULL (0014).
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
          final ingredientId = line.ingredientId ?? stubIdByKey[line.stubKey];
          if (ingredientId == null) {
            throw StateError('line ${line.lineIndex} has no ingredient');
          }
          // A resolved measure (the user picked "can", "clove"…) persists as a
          // `measure_id` FK with `unit='piece'` (migration 0009) so the count↔
          // basis bridge survives commit, instead of degrading to a bare
          // "piece". Only an existing vocab row can carry measures — a
          // freshly-created stub never does — and a measure that has since
          // vanished still degrades to an honest count via [_unitId].
          final measureId = line.ingredientId == null
              ? null
              : await _measureIdFor(tx, line.ingredientId!, line.unit);
          await tx.execute(
            'INSERT INTO recipe_line_item (id, household_id, group_id, '
            'ingredient_id, quantity, unit, measure_id, note, sort_order, '
            'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              lineIds[line.lineIndex],
              _householdId,
              groupId,
              ingredientId,
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
      for (final c in payload.corrections) {
        await tx.execute(
          'INSERT INTO ingredient_alias (id, household_id, ingredient_id, '
          'alias_text, match_text, source, created_at, updated_at) '
          "VALUES (?, ?, ?, ?, ?, 'import_correction', ?, ?)",
          [
            _uuid.v4(),
            _householdId,
            c.ingredientId,
            c.aliasText,
            normalizeSearchQuery(c.aliasText),
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
  /// through; a ref to an out-of-range index is dropped (never invented).
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
        if (ids.isEmpty) return null; // no line survived — drop the chip
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
