/// Ingredient vocabulary lookup — PURE DART (invariant 2).
///
/// The picker searches the local synced vocab offline (exact/prefix, per
/// ADR-0004: the phone never fuzzy-matches). Step 7.7 adds the recents feed
/// and the add-new stub path (the full flesh-out form is step 8).
library;

import 'ingredient.dart';

abstract interface class IngredientRepository {
  /// Ingredients whose name/aliases match [query] (exact then prefix),
  /// canonical-name ordered, capped at [limit]. Empty [query] → the first
  /// [limit] ingredients (so the picker has something to show unfiltered).
  Future<List<Ingredient>> search(String query, {int limit = 30});

  /// The ingredients most recently used in a recipe line or manual shopping
  /// top-up, newest first — the picker's "Recent" section (7.7). Empty when
  /// nothing has been used yet (the picker then falls back to [search]).
  Future<List<Ingredient>> recentlyUsed({int limit = 8});

  /// The live vocab row with [id], or null when it doesn't exist (or is
  /// tombstoned). Resolves an ingredient a caller only knows by reference —
  /// e.g. the edit-top-up sheet filtering its unit picker.
  Future<Ingredient?> byId(String id);

  /// Creates a stub vocab row named [name] (source `manual`, no density or
  /// macros — invariant 3 keeps it out of conversions until fleshed out) and
  /// returns it. The picker's "can't find it? add new" affordance.
  Future<Ingredient> createStub(String name);

  /// Stores [gPerMl] as the ingredient's density — the single volume⇄mass
  /// fact (ADR-0008; both entry styles resolve to this one number) — and
  /// extends its explicit `allowed_units` with the units the density
  /// unlocks, in the same write (the stored list is never silently
  /// recomputed; a density's arrival is the one explicit extension).
  /// Returns the updated row, or null when [ingredientId] doesn't resolve.
  ///
  /// Throws [ArgumentError] for a non-positive/NaN [gPerMl] — a zero density
  /// would fabricate Infinity conversions (invariant 3).
  Future<Ingredient?> setDensity(String ingredientId, double gPerMl);
}
