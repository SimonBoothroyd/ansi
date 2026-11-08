/// The household's fridge and freezer: read through [householdLeftovers], and
/// put right by the household. Pure Dart.
///
/// Every write names a [Leftover] as the page drew it. A row derived from a
/// cooked batch has no stored row yet: the first write about it stores one,
/// naming the batch, which from then on replaces the derived row.
library;

import 'leftovers.dart';

abstract interface class LeftoverRepository {
  /// The household's leftovers on [today], fridge first, live
  /// ([householdLeftovers]). [weekStart] is the first day of the week holding
  /// [today]: the cooked batches read are those of [leftoverWeekStarts].
  Stream<List<Leftover>> watchHouseholdLeftovers({
    required DateTime weekStart,
    required DateTime today,
  });

  /// Where every stored row is, by id, gone or not, live: a meal planned from
  /// one says which shelf it came from.
  Stream<Map<String, LeftoverPlace>> watchLeftoverPlaces();

  /// Says [portions] are left of [left]. The meals already planned from its
  /// stored row come off on read, so the row stores [portions] plus them.
  Future<void> setLeftoverPortions(Leftover left, double portions);

  /// Moves [left] to the freezer, dated [since]: today for a freeze, its
  /// fridge date for one frozen in time and said late.
  Future<void> freezeLeftover(Leftover left, {required DateTime since});

  /// Says every one of [lefts] is gone: eaten, binned or given away.
  Future<void> markLeftoversGone(List<Leftover> lefts);

  /// Adds food the app never saw: a recipe or the household's own [label],
  /// never both. Returns the new row's id.
  Future<String> addLeftover({
    required LeftoverPlace place,
    required double portions,
    required DateTime since,
    String? recipeId,
    String? label,
  });
}
