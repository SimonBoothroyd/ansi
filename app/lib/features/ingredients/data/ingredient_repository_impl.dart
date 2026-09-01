/// [IngredientRepository] over the local SQLite vocab (server-synced since
/// step 7 — `ensure_onboarded` clones the household's starter vocab).
///
/// Deterministic word-boundary search only — the phone never fuzzy-matches
/// (ADR-0004). The query is normalized with the same character rules the
/// server's normalizer builds `match_text` with ([normalizeSearchQuery], so
/// "all-purpose" hits "all purpose flour"), then matched as a word prefix
/// against the ingredient's own `match_text` and any alias — so "tofu" finds
/// "extra firm tofu" without any fuzziness.
library;

import 'dart:convert';

import 'package:sqlite3/common.dart' show Row;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
import '../domain/allowed_units.dart';
import '../domain/ingredient.dart';
import '../domain/ingredient_repository.dart';
import '../domain/normalize.dart';
import '../domain/search_query.dart';

const _uuid = Uuid();

/// The volume-unit names the chip row refuses as measure labels
/// (`isVolumeUnitLabel` — ids, display labels, and their simple s plurals),
/// lowercased for the SQL filter below. Static catalog values, no user input.
final _volumeLabelList = [
  for (final u in kAllUnits)
    if (u.family == UnitFamily.volume)
      for (final name in {u.id.toLowerCase(), u.label.toLowerCase()}) ...[
        name,
        '${name}s',
      ],
].map((l) => "'$l'").join(', ');

/// Distinct live labels, matching the merge-on-read view of the measures
/// (duplicate labels collapse to one chip, so they count once here too) and
/// the chip row's volume-label exclusion — the hint counts what is actually
/// offered, not rows the picker hides.
final _measureCount =
    '(SELECT COUNT(DISTINCT m.label) FROM ingredient_measure m '
    'WHERE m.ingredient_id = i.id AND m.deleted_at IS NULL '
    'AND LOWER(TRIM(m.label)) NOT IN ($_volumeLabelList)) AS measure_count';

/// The `macros` column's jsonb, or null when there are none — null (not `{}`,
/// and never four zeros) is how an absent panel is stored, on the create path
/// and the edit path alike (invariant 3).
String? _macrosJson(Macros? macros) => macros == null
    ? null
    : jsonEncode({
        'kcal': macros.kcal,
        'protein': macros.protein,
        'carb': macros.carb,
        'fat': macros.fat,
      });

class SqliteIngredientRepository implements IngredientRepository {
  const SqliteIngredientRepository(this._db, {required String householdId})
    : _householdId = householdId;

  final SqliteConnection _db;

  /// The household stamped on rows this repo writes (the add-new stub path).
  final String _householdId;

  @override
  Future<List<Ingredient>> search(String query, {int limit = 30}) async {
    // Normalization also strips `%`/`_`, so nothing user-typed can act as a
    // LIKE wildcard below.
    final q = normalizeSearchQuery(query);
    final tokens = searchTokens(query);

    if (tokens.isEmpty) {
      final rows = await _db.getAll(
        'SELECT i.*, $_measureCount FROM ingredient i '
        'WHERE i.deleted_at IS NULL '
        'ORDER BY i.canonical_name LIMIT ?',
        [limit],
      );
      return rows.map(_toIngredient).toList();
    }

    // Token-subset match: EVERY query token must be a word-prefix of the
    // ingredient's `match_text` OR one of its live aliases (order-independent,
    // so "canned tomatoes" finds "Canned Whole Tomatoes"). Each token is a
    // word-boundary LIKE (`tok%` = leading word, `% tok%` = any later word).
    // Rank exact full-query hits first, then shorter names, then by name.
    final where = StringBuffer('i.deleted_at IS NULL');
    final params = <Object?>[];
    for (final tok in tokens) {
      where.write(
        ' AND (i.match_text LIKE ? OR i.match_text LIKE ? '
        'OR EXISTS (SELECT 1 FROM ingredient_alias a '
        'WHERE a.ingredient_id = i.id AND a.deleted_at IS NULL '
        'AND (a.match_text LIKE ? OR a.match_text LIKE ?)))',
      );
      params.addAll(['$tok%', '% $tok%', '$tok%', '% $tok%']);
    }
    final rows = await _db.getAll(
      'SELECT i.*, $_measureCount FROM ingredient i '
      'WHERE $where '
      'ORDER BY (i.match_text = ?) DESC, length(i.canonical_name), '
      'i.canonical_name '
      'LIMIT ?',
      [...params, q, limit],
    );
    if (rows.isNotEmpty) return rows.map(_toIngredient).toList();

    // Nothing matched the exact/prefix pass. For a MULTI-word query it is
    // likely one token was mistyped ("chikn thigh") — fall back to a
    // deterministic typo-tolerant scan over the live vocab (name + aliases),
    // ranked by fuzzy score. A single-word query stays strict word-boundary
    // (a lone "nion" must not fuzzy-hit "onion"): the extra tokens are what
    // make a fuzzy match trustworthy. Deterministic, no fuzzy index
    // (ADR-0004): a scored character comparison, in Dart.
    if (tokens.length < 2) return const [];
    return _fuzzySearch(query, limit: limit);
  }

  /// The typo-tolerant fallback: scores every live ingredient's `match_text`
  /// (with its aliases joined) against [query] and returns those that clear
  /// the per-token floor, closest first. Runs only when the exact/prefix pass
  /// finds nothing, so the common path never pays for it.
  Future<List<Ingredient>> _fuzzySearch(
    String query, {
    required int limit,
  }) async {
    // The separator is a SINGLE-quoted string literal: SQLite reads `"x"` as an
    // identifier first and only falls back to a string as a legacy quirk, which
    // `SQLITE_DQS=0` builds disable outright. No LIMIT either — a cap would
    // silently stop typo-tolerance working for whatever fell off the end as the
    // household's vocab grew, and this pass only runs when the exact/prefix
    // search already found nothing.
    final rows = await _db.getAll(
      'SELECT i.*, $_measureCount, '
      "(SELECT GROUP_CONCAT(a.match_text, ' ') FROM ingredient_alias a "
      'WHERE a.ingredient_id = i.id AND a.deleted_at IS NULL) AS alias_text '
      'FROM ingredient i WHERE i.deleted_at IS NULL '
      'ORDER BY i.canonical_name',
    );
    final scored = <({double score, int length, Ingredient ingredient})>[];
    for (final r in rows) {
      final text = '${r['match_text'] ?? ''} ${r['alias_text'] ?? ''}'.trim();
      final score = fuzzyQueryScore(query, text);
      if (score < 0) continue;
      scored.add((
        score: score,
        length: (r['canonical_name'] as String).length,
        ingredient: _toIngredient(r),
      ));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byLength = a.length.compareTo(b.length);
      if (byLength != 0) return byLength;
      return a.ingredient.canonicalName.compareTo(b.ingredient.canonicalName);
    });
    return [for (final s in scored.take(limit)) s.ingredient];
  }

  @override
  Future<List<Ingredient>> recentlyUsed({int limit = 8}) async {
    // "Used" = referenced by a live recipe line or a manual shopping top-up;
    // the newest reference wins. Mirrors what a cook actually reaches for.
    final rows = await _db.getAll(
      'SELECT i.*, $_measureCount, MAX(u.used_at) AS last_used '
      'FROM ingredient i '
      'JOIN ( '
      'SELECT li.ingredient_id AS ingredient_id, li.created_at AS used_at '
      'FROM recipe_line_item li WHERE li.deleted_at IS NULL '
      'UNION ALL '
      'SELECT e.ingredient_id, c.created_at '
      'FROM shopping_list_contribution c '
      'JOIN shopping_list_entry e ON e.id = c.entry_id '
      'WHERE c.deleted_at IS NULL AND e.deleted_at IS NULL '
      'AND e.ingredient_id IS NOT NULL '
      ') u ON u.ingredient_id = i.id '
      'WHERE i.deleted_at IS NULL '
      'GROUP BY i.id ORDER BY last_used DESC LIMIT ?',
      [limit],
    );
    return rows.map(_toIngredient).toList();
  }

  @override
  Future<Ingredient?> byId(String id) async {
    final row = await _db.getOptional(
      'SELECT i.*, $_measureCount FROM ingredient i '
      'WHERE i.id = ? AND i.deleted_at IS NULL',
      [id],
    );
    return row == null ? null : _toIngredient(row);
  }

  @override
  Future<Map<String, Ingredient>> byIds(Set<String> ids) async {
    if (ids.isEmpty) return const {};
    // Ids are uuids we minted or synced, never user text; they still ride as
    // bound parameters rather than being interpolated into the SQL.
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await _db.getAll(
      'SELECT i.*, $_measureCount FROM ingredient i '
      'WHERE i.deleted_at IS NULL AND i.id IN ($placeholders)',
      ids.toList(),
    );
    return {for (final r in rows) r['id'] as String: _toIngredient(r)};
  }

  @override
  Future<Ingredient> createStub(
    String name, {
    String source = 'manual',
    Macros? macros,
    MacrosBasis macrosBasis = MacrosBasis.perG,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final trimmed = name.trim();
    // The server's OWN phrase rules, ported (plan 0020 D6). Before the port
    // this wrote the character-level normalization only, so a locally created
    // stub carried a `match_text` the server would never have written and the
    // next import's cascade missed it.
    final matchText = normalizeMatchText(trimmed);
    await _db.execute(
      'INSERT INTO ingredient (id, household_id, canonical_name, '
      'default_unit, status, source, match_text, macros, macros_basis, '
      'created_at, updated_at) '
      "VALUES (?, ?, ?, 'g', 'stub', ?, ?, ?, ?, ?, ?)",
      [
        id,
        _householdId,
        trimmed,
        source,
        matchText,
        // A source with no panel writes NULL, not zeros (invariant 3) — and
        // `status` stays 'stub' regardless of what arrived (D5).
        _macrosJson(macros),
        macrosBasis.dbValue,
        now,
        now,
      ],
    );
    return Ingredient(
      id: id,
      canonicalName: trimmed,
      defaultUnit: g,
      status: IngredientStatus.stub,
      macros: macros,
      macrosBasis: macrosBasis,
      source: source,
    );
  }

  @override
  Future<Ingredient?> setDensity(String ingredientId, double gPerMl) async {
    // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
    if (!(gPerMl > 0)) {
      throw ArgumentError.value(gPerMl, 'gPerMl', 'must be a positive number');
    }
    // Read-modify-write: the allowed set written back is derived from the row
    // as it is read, so the read and the write must be one transaction — a
    // concurrent density/allowed-units write between them would be clobbered.
    // This is the repo's only such pair; every other write is self-contained.
    final now = DateTime.now().toUtc().toIso8601String();
    final updated = await _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT i.*, $_measureCount FROM ingredient i '
        'WHERE i.id = ? AND i.deleted_at IS NULL',
        [ingredientId],
      );
      if (row == null) return false;
      final current = _toIngredient(row);
      // Extend the explicit list with what this density unlocks, in the same
      // write (see the interface doc). A row still on the derived fallback is
      // materialized first, so the extension has something explicit to join.
      final unlocked = {
        ...current.allowedUnits ?? defaultAllowedUnitSet(current),
        ...densityUnlockedUnits(current),
      };
      await tx.execute(
        'UPDATE ingredient SET density_g_per_ml = ?, allowed_units = ?, '
        'updated_at = ? WHERE id = ?',
        [
          gPerMl,
          jsonEncode([for (final u in unlocked) u.id]),
          now,
          ingredientId,
        ],
      );
      return true;
    });
    if (!updated) return null;
    return byId(ingredientId);
  }

  @override
  Future<Ingredient?> clearDensity(String ingredientId) async {
    // Read-modify-write for the same reason [setDensity] is: the list written
    // back is derived from the row as it is read.
    final now = DateTime.now().toUtc().toIso8601String();
    final updated = await _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT i.*, $_measureCount FROM ingredient i '
        'WHERE i.id = ? AND i.deleted_at IS NULL',
        [ingredientId],
      );
      if (row == null) return false;
      final current = _toIngredient(row);
      if (current.densityGPerMl == null) return true; // nothing to delete
      // D4b: the cross-family admission goes with the number it was derived
      // from. The basis family and the default unit's family survive — see
      // `densityStrippedUnits`. Curated units outside the derived rules are
      // untouched: only what the density unlocked is subtracted.
      final kept = {...current.allowedUnits ?? defaultAllowedUnitSet(current)}
        ..removeAll(densityStrippedUnits(current));
      await tx.execute(
        'UPDATE ingredient SET density_g_per_ml = NULL, allowed_units = ?, '
        'updated_at = ? WHERE id = ?',
        [
          jsonEncode([for (final u in kept) u.id]),
          now,
          ingredientId,
        ],
      );
      return true;
    });
    if (!updated) return null;
    return byId(ingredientId);
  }

  @override
  Future<Ingredient?> applyUsdaProbe(
    String ingredientId, {
    required String source,
    double? densityGPerMl,
    Macros? macros,
  }) async {
    if (densityGPerMl == null && macros == null) return null;
    final now = DateTime.now().toUtc().toIso8601String();
    final applied = await _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT i.*, $_measureCount FROM ingredient i '
        'WHERE i.id = ? AND i.deleted_at IS NULL',
        [ingredientId],
      );
      if (row == null) return false;
      final current = _toIngredient(row);
      // The guards re-checked inside the transaction, not just by the caller:
      // the row can change between the probe and this write (another device,
      // or the server trigger landing first). Same shape as the 0014/0015
      // trigger's WHEN clause, which is what makes the race benign.
      if (current.status != IngredientStatus.stub ||
          current.densityGPerMl != null ||
          current.macros != null) {
        return false;
      }
      // A landing density unlocks units, exactly as `setDensity` does — same
      // event, same rule (ADR-0009). No density, no change to the list.
      final units = densityGPerMl == null
          ? current.allowedUnits
          : [
              ...{
                ...current.allowedUnits ?? defaultAllowedUnitSet(current),
                ...densityUnlockedUnits(current),
              },
            ];
      await tx.execute(
        'UPDATE ingredient SET density_g_per_ml = ?, macros = ?, '
        'allowed_units = ?, source = ?, updated_at = ? WHERE id = ?',
        [
          densityGPerMl,
          _macrosJson(macros),
          if (units == null)
            null
          else
            jsonEncode([for (final u in units) u.id]),
          source,
          now,
          ingredientId,
        ],
      );
      return true;
    });
    return applied ? byId(ingredientId) : null;
  }

  // --- The manager's write half (step 8.5) -----------------------------------

  @override
  Stream<List<Ingredient>> watchVocabulary() => _db
      .watch(
        'SELECT i.*, $_measureCount FROM ingredient i '
        'WHERE i.deleted_at IS NULL ORDER BY i.canonical_name',
      )
      .map((rows) => rows.map(_toIngredient).toList());

  @override
  Stream<int> watchStubCount() => _db
      .watch(
        "SELECT COUNT(*) AS n FROM ingredient WHERE status = 'stub' "
        'AND deleted_at IS NULL',
      )
      .map((rows) => (rows.first['n'] as int?) ?? 0);

  @override
  Stream<List<String>> watchCategories() => _db
      .watch(
        'SELECT DISTINCT TRIM(category) AS c FROM ingredient '
        'WHERE deleted_at IS NULL AND category IS NOT NULL '
        "AND TRIM(category) <> '' "
        'ORDER BY c',
      )
      .map((rows) => [for (final r in rows) r['c'] as String]);

  @override
  Future<Ingredient?> saveEdit(String ingredientId, IngredientEdit edit) async {
    final name = edit.canonicalName.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(
        edit.canonicalName,
        'canonicalName',
        'must not be blank',
      );
    }
    final macros = edit.macros;
    final macrosJson = _macrosJson(macros);
    final now = DateTime.now().toUtc().toIso8601String();
    final updated = await _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT status FROM ingredient WHERE id = ? AND deleted_at IS NULL',
        [ingredientId],
      );
      if (row == null) return false;
      // D5's reversibility: clearing the macros of a complete row returns it
      // to `stub` rather than leaving it asserting a number it no longer has.
      // Filling them in never promotes — that is [confirmStub], a human act.
      final status = macros == null ? 'stub' : row['status'] as String;
      await tx.execute(
        'UPDATE ingredient SET canonical_name = ?, match_text = ?, '
        'category = ?, default_unit = ?, macros = ?, macros_basis = ?, '
        'allowed_units = ?, status = ?, updated_at = ? WHERE id = ?',
        [
          name,
          // The rename hazard (D6): the stored name and its match_text are
          // written together or the cascade searches for a name nothing
          // carries.
          normalizeMatchText(name),
          edit.category,
          edit.defaultUnit.id,
          macrosJson,
          edit.macrosBasis.dbValue,
          jsonEncode([for (final u in edit.allowedUnits) u.id]),
          status,
          now,
          ingredientId,
        ],
      );
      return true;
    });
    return updated ? byId(ingredientId) : null;
  }

  @override
  Future<Ingredient?> confirmStub(String ingredientId) async {
    final current = await byId(ingredientId);
    if (current == null) return null;
    if (current.macros == null) {
      // The CTA is disabled without macros; the gate holds here too, so a
      // future caller can't promote a row into every macro total by mistake.
      throw StateError(
        'cannot confirm "${current.canonicalName}" — it has no macros '
        '(plan 0020 D5: macros are the gate, density is not)',
      );
    }
    return _setStatus(ingredientId, 'complete');
  }

  @override
  Future<Ingredient?> unconfirm(String ingredientId) =>
      _setStatus(ingredientId, 'stub');

  Future<Ingredient?> _setStatus(String ingredientId, String status) async {
    await _db.execute(
      'UPDATE ingredient SET status = ?, updated_at = ? '
      'WHERE id = ? AND deleted_at IS NULL',
      [status, DateTime.now().toUtc().toIso8601String(), ingredientId],
    );
    return byId(ingredientId);
  }

  @override
  Future<({int recipeCount, int lineCount})> recipeReferences(
    String ingredientId,
  ) async {
    // A line's recipe is reached through its group, and both must be live —
    // a line inside a tombstoned group belongs to nothing a user can open.
    final row = await _db.get(
      'SELECT COUNT(*) AS lines, COUNT(DISTINCT gr.recipe_id) AS recipes '
      'FROM recipe_line_item li '
      'JOIN ingredient_group gr ON gr.id = li.group_id '
      'JOIN recipe r ON r.id = gr.recipe_id '
      'WHERE li.ingredient_id = ? AND li.deleted_at IS NULL '
      'AND gr.deleted_at IS NULL AND r.deleted_at IS NULL',
      [ingredientId],
    );
    return (
      recipeCount: (row['recipes'] as int?) ?? 0,
      lineCount: (row['lines'] as int?) ?? 0,
    );
  }

  @override
  Future<DeleteOutcome> softDelete(String ingredientId) async {
    final current = await byId(ingredientId);
    if (current == null) return const DeleteMissing();
    final refs = await recipeReferences(ingredientId);
    if (refs.lineCount > 0) {
      return DeleteRefused(
        recipeCount: refs.recipeCount,
        lineCount: refs.lineCount,
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.writeTransaction((tx) async {
      await tx.execute(
        'UPDATE ingredient SET deleted_at = ?, updated_at = ? WHERE id = ?',
        [now, now, ingredientId],
      );
      // The aliases go with it: an alias outliving its ingredient is a match
      // that resolves to nothing.
      await tx.execute(
        'UPDATE ingredient_alias SET deleted_at = ?, updated_at = ? '
        'WHERE ingredient_id = ? AND deleted_at IS NULL',
        [now, now, ingredientId],
      );
    });
    return const Deleted();
  }

  @override
  Future<List<IngredientAlias>> aliases(String ingredientId) async {
    final rows = await _db.getAll(
      'SELECT id, alias_text, source FROM ingredient_alias '
      'WHERE ingredient_id = ? AND deleted_at IS NULL '
      'ORDER BY created_at, id',
      [ingredientId],
    );
    return [
      for (final r in rows)
        IngredientAlias(
          id: r['id'] as String,
          text: r['alias_text'] as String,
          source: (r['source'] as String?) ?? 'manual',
        ),
    ];
  }

  @override
  Future<IngredientAlias> addAlias(String ingredientId, String text) async {
    final trimmed = text.trim();
    final matchText = normalizeMatchText(trimmed);
    if (matchText.isEmpty) {
      throw ArgumentError.value(
        text,
        'text',
        'an alias must carry at least one identity word',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final id = _uuid.v4();
    // Find-or-create, not blind insert (the import cascade's rule): two
    // identically matching aliases on one ingredient are noise that can only
    // ever tie.
    final existing = await _db.getOptional(
      'SELECT id, alias_text, source FROM ingredient_alias '
      'WHERE ingredient_id = ? AND match_text = ? AND deleted_at IS NULL '
      'LIMIT 1',
      [ingredientId, matchText],
    );
    if (existing != null) {
      return IngredientAlias(
        id: existing['id'] as String,
        text: existing['alias_text'] as String,
        source: (existing['source'] as String?) ?? 'manual',
      );
    }
    await _db.execute(
      'INSERT INTO ingredient_alias (id, household_id, ingredient_id, '
      'alias_text, match_text, source, created_at, updated_at) '
      "VALUES (?, ?, ?, ?, ?, 'manual', ?, ?)",
      [id, _householdId, ingredientId, trimmed, matchText, now, now],
    );
    return IngredientAlias(id: id, text: trimmed, source: 'manual');
  }

  @override
  Future<void> removeAlias(String aliasId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.execute(
      'UPDATE ingredient_alias SET deleted_at = ?, updated_at = ? WHERE id = ?',
      [now, now, aliasId],
    );
  }

  Ingredient _toIngredient(Row r) => Ingredient(
    id: r['id'] as String,
    canonicalName: r['canonical_name'] as String,
    // Seed units are always valid units.dart ids; fall back defensively.
    defaultUnit: unitById(r['default_unit'] as String) ?? pieces,
    status: r['status'] == 'complete'
        ? IngredientStatus.complete
        : IngredientStatus.stub,
    category: r['category'] as String?,
    densityGPerMl: (r['density_g_per_ml'] as num?)?.toDouble(),
    macros: Macros.tryParse(r['macros'] as String?),
    macrosBasis: MacrosBasis.fromDb(r['macros_basis'] as String?),
    allowedUnits: _parseAllowedUnits(r['allowed_units'] as String?),
    measureCount: (r['measure_count'] as int?) ?? 0,
    source: r['source'] as String?,
  );

  /// Parses the row's `allowed_units` jsonb (a JSON array of unit ids) into
  /// catalog units. Unknown ids are dropped (a newer server vocabulary must
  /// not orphan this client); a malformed/absent value is null, which sends
  /// the pickers to the derived-defaults fallback.
  static List<Unit>? _parseAllowedUnits(String? json) {
    if (json == null || json.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return null;
    }
    if (decoded is! List) return null;
    return [
      for (final id in decoded)
        if (id is String && unitById(id) != null) unitById(id)!,
    ];
  }
}
