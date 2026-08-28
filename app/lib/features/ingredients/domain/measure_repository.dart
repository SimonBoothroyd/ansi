/// Read access to an ingredient's named measures — PURE DART (invariant 2).
///
/// Measures ("potato, large = 299 g", step 7.6) are per-household vocab rows,
/// synced like the ingredients they belong to. Pickers watch them so a
/// measure added on one device appears in the other's dropdown live.
library;

import '../../../core/units/measure.dart';

// ignore: one_member_abstracts — an interface for DI/testing, not a callback.
abstract interface class MeasureRepository {
  /// The live measures of [ingredientId], ordered by `sort_order` (then
  /// creation) so the first is the ingredient's primary measure.
  Stream<List<Measure>> watchMeasures(String ingredientId);
}
