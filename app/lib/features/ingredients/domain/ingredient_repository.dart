/// Read-only ingredient vocabulary lookup — PURE DART (invariant 2).
///
/// Step 2's inline picker searches the local seeded vocab offline (exact/prefix,
/// per ADR-0004: the phone never fuzzy-matches). Create/stub flows are deferred.
library;

import 'ingredient.dart';

abstract interface class IngredientRepository {
  /// Ingredients whose name/aliases match [query] (exact then prefix),
  /// canonical-name ordered, capped at [limit]. Empty [query] → the first
  /// [limit] ingredients (so the picker has something to show unfiltered).
  Future<List<Ingredient>> search(String query, {int limit = 30});

  /// The live vocab row with [id], or null when it doesn't exist (or is
  /// tombstoned). Resolves an ingredient a caller only knows by reference —
  /// e.g. the edit-top-up sheet filtering its unit picker.
  Future<Ingredient?> byId(String id);
}
