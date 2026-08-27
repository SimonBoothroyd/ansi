/// [IngredientRepository] over the local (bundle-seeded) SQLite vocab.
///
/// Exact/prefix search only — the phone never fuzzy-matches (ADR-0004). Matches
/// the ingredient's own name and any alias.
library;

import 'package:sqlite3/common.dart' show Row;
import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/units/units.dart';
import '../domain/ingredient.dart';
import '../domain/ingredient_repository.dart';

class SqliteIngredientRepository implements IngredientRepository {
  const SqliteIngredientRepository(this._db);

  final SqliteConnection _db;

  @override
  Future<List<Ingredient>> search(String query, {int limit = 30}) async {
    final q = query.trim().toLowerCase();

    if (q.isEmpty) {
      final rows = await _db.getAll(
        'SELECT * FROM ingredient ORDER BY canonical_name LIMIT ?',
        [limit],
      );
      return rows.map(_toIngredient).toList();
    }

    // Prefix match on the ingredient or any alias; rank exact hits first, then
    // shorter names (a closer match), then alphabetically.
    final rows = await _db.getAll(
      'SELECT DISTINCT i.* FROM ingredient i '
      'LEFT JOIN ingredient_alias a ON a.ingredient_id = i.id '
      'WHERE i.match_text LIKE ? OR a.match_text LIKE ? '
      'ORDER BY (i.match_text = ?) DESC, length(i.canonical_name), '
      'i.canonical_name '
      'LIMIT ?',
      ['$q%', '$q%', q, limit],
    );
    return rows.map(_toIngredient).toList();
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
  );
}
