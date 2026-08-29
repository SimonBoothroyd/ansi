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

import 'package:sqlite3/common.dart' show Row;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
import '../domain/ingredient.dart';
import '../domain/ingredient_repository.dart';
import '../domain/search_query.dart';

const _uuid = Uuid();

/// Distinct live labels, matching the merge-on-read view of the measures
/// (duplicate labels collapse to one chip, so they count once here too).
const _measureCount =
    '(SELECT COUNT(DISTINCT m.label) FROM ingredient_measure m '
    'WHERE m.ingredient_id = i.id AND m.deleted_at IS NULL) AS measure_count';

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

    if (q.isEmpty) {
      final rows = await _db.getAll(
        'SELECT i.*, $_measureCount FROM ingredient i '
        'WHERE i.deleted_at IS NULL '
        'ORDER BY i.canonical_name LIMIT ?',
        [limit],
      );
      return rows.map(_toIngredient).toList();
    }

    // Word-boundary match (`q%` = leading word, `% q%` = any later word) on
    // the ingredient or any alias, live rows only; rank exact hits first, then
    // shorter names (a closer match), then alphabetically.
    final rows = await _db.getAll(
      'SELECT DISTINCT i.*, $_measureCount FROM ingredient i '
      'LEFT JOIN ingredient_alias a '
      'ON a.ingredient_id = i.id AND a.deleted_at IS NULL '
      'WHERE i.deleted_at IS NULL AND '
      '(i.match_text LIKE ? OR i.match_text LIKE ? '
      'OR a.match_text LIKE ? OR a.match_text LIKE ?) '
      'ORDER BY (i.match_text = ?) DESC, length(i.canonical_name), '
      'i.canonical_name '
      'LIMIT ?',
      ['$q%', '% $q%', '$q%', '% $q%', q, limit],
    );
    return rows.map(_toIngredient).toList();
  }

  @override
  Future<List<Ingredient>> recentlyUsed({int limit = 8}) async {
    // "Used" = referenced by a live recipe line or a manual shopping top-up;
    // the newest reference wins. Mirrors what a cook actually reaches for.
    final rows = await _db.getAll(
      'SELECT i.*, $_measureCount, MAX(u.used_at) AS last_used '
      'FROM ingredient i '
      'JOIN ('
      'SELECT li.ingredient_id AS ingredient_id, li.created_at AS used_at '
      'FROM recipe_line_item li WHERE li.deleted_at IS NULL '
      'UNION ALL '
      'SELECT e.ingredient_id, c.created_at '
      'FROM shopping_list_contribution c '
      'JOIN shopping_list_entry e ON e.id = c.entry_id '
      'WHERE c.deleted_at IS NULL AND e.ingredient_id IS NOT NULL'
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
    measureCount: (r['measure_count'] as int?) ?? 0,
  );
}
