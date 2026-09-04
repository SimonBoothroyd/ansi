/// Read/write access to an ingredient's named measures — PURE DART
/// (invariant 2).
///
/// Measures ("potato, large = 299 g", step 7.6) are per-household vocab rows,
/// synced like the ingredients they belong to. Pickers watch them so a
/// measure added on one device appears in the other's chip row live. Step 7.7
/// adds the write path: the in-app measure editor authors `manual`-sourced
/// rows and soft-deletes unwanted ones.
///
/// **Duplicate labels merge on read**: no unique index guards `(ingredient_id,
/// label)` — one would make an offline duplicate fail upload and drop the whole
/// crud transaction (the shopping-entry doctrine). Instead every device
/// converges on the same canonical row per label: the *oldest* live one
/// (`created_at`, then `id`). Newer duplicates are hidden, never deleted — a
/// referencing line item still resolves them by id.
library;

import '../../../core/units/measure.dart';

abstract interface class MeasureRepository {
  /// The live measures of [ingredientId], ordered by `sort_order` (then
  /// creation) so the first is the ingredient's primary measure. Duplicate
  /// labels are merged deterministically (see the library doc).
  Stream<List<Measure>> watchMeasures(String ingredientId);

  /// The measures of MANY ingredients in one read, keyed by ingredient id —
  /// same ordering and duplicate-merge rules as [watchMeasures]. An id with
  /// no measures is absent from the map.
  ///
  /// The import review validates a whole recipe's lines at once and must not
  /// fan out to a stream per line: routing that through N autoDispose stream
  /// providers is what let a measure-word unit — "1 clove" of a garlic row that
  /// carries a `clove` measure — validate against an EMPTY measure list and get
  /// flagged "Pick a supported unit".
  Future<Map<String, List<Measure>>> measuresByIngredients(Set<String> ids);

  /// Authors a user measure of [ingredientId]: one [label] is [amount] of
  /// the ingredient's basis unit (g or ml — `macros_basis`, ADR-0008).
  /// Written with `source = 'manual'` after the ingredient's existing
  /// measures (`sort_order`), and returned for immediate selection.
  ///
  /// Throws [ArgumentError] for an empty or volume-unit-named [label]
  /// (density owns volume conversion) or non-positive/NaN [amount] — the
  /// rules hold at the repository, not just the sheet's form.
  Future<Measure> addMeasure({
    required String ingredientId,
    required String label,
    required double amount,
  });

  /// Soft-deletes one measure (tombstone, spec §3). A line item referencing
  /// it degrades to its honest stored count — never an invented amount.
  Future<void> softDeleteMeasure(String measureId);
}
