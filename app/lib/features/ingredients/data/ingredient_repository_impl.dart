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

import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
import '../domain/ingredient.dart';
import '../domain/ingredient_repository.dart';
import '../domain/search_query.dart';

class SqliteIngredientRepository implements IngredientRepository {
  const SqliteIngredientRepository(this._db);

  final SqliteConnection _db;

  @override
  Future<List<Ingredient>> search(String query, {int limit = 30}) async {
    // Normalization also strips `%`/`_`, so nothing user-typed can act as a
    // LIKE wildcard below.
    final q = normalizeSearchQuery(query);

    if (q.isEmpty) {
      final rows = await _db.getAll(
        'SELECT * FROM ingredient WHERE deleted_at IS NULL '
        'ORDER BY canonical_name LIMIT ?',
        [limit],
      );
      return rows.map(_toIngredient).toList();
    }

    // Word-boundary match (`q%` = leading word, `% q%` = any later word) on
    // the ingredient or any alias, live rows only; rank exact hits first, then
    // shorter names (a closer match), then alphabetically.
    final rows = await _db.getAll(
      'SELECT DISTINCT i.* FROM ingredient i '
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
  Future<Ingredient?> byId(String id) async {
    final row = await _db.getOptional(
      'SELECT * FROM ingredient WHERE id = ? AND deleted_at IS NULL',
      [id],
    );
    return row == null ? null : _toIngredient(row);
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
  );
}
