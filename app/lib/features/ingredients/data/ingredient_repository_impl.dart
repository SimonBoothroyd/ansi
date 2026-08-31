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
    final rows = await _db.getAll(
      'SELECT i.*, $_measureCount, '
      '(SELECT GROUP_CONCAT(a.match_text, " ") FROM ingredient_alias a '
      'WHERE a.ingredient_id = i.id AND a.deleted_at IS NULL) AS alias_text '
      'FROM ingredient i WHERE i.deleted_at IS NULL '
      'ORDER BY i.canonical_name LIMIT 500',
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
  Future<Ingredient> createStub(String name) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final trimmed = name.trim();
    // The character-level normalizer only — the server's full phrase rules
    // (singularize, word classes) are a step-8 artifact; a locally created
    // stub just needs to be findable by what its author typed.
    final matchText = normalizeSearchQuery(trimmed);
    await _db.execute(
      'INSERT INTO ingredient (id, household_id, canonical_name, '
      'default_unit, status, source, match_text, created_at, updated_at) '
      "VALUES (?, ?, ?, 'g', 'stub', 'manual', ?, ?, ?)",
      [id, _householdId, trimmed, matchText, now, now],
    );
    return Ingredient(
      id: id,
      canonicalName: trimmed,
      defaultUnit: g,
      status: IngredientStatus.stub,
    );
  }

  @override
  Future<Ingredient?> setDensity(String ingredientId, double gPerMl) async {
    // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
    if (!(gPerMl > 0)) {
      throw ArgumentError.value(gPerMl, 'gPerMl', 'must be a positive number');
    }
    final current = await byId(ingredientId);
    if (current == null) return null;
    // Extend the explicit list with what this density unlocks, in the same
    // write (see the interface doc). A row still on the derived fallback is
    // materialized first, so the extension has something explicit to join.
    final unlocked = {
      ...current.allowedUnits ?? defaultAllowedUnitSet(current),
      ...densityUnlockedUnits(current),
    };
    final allowedJson = jsonEncode([for (final u in unlocked) u.id]);
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.execute(
      'UPDATE ingredient SET density_g_per_ml = ?, allowed_units = ?, '
      'updated_at = ? WHERE id = ?',
      [gPerMl, allowedJson, now, ingredientId],
    );
    return byId(ingredientId);
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
