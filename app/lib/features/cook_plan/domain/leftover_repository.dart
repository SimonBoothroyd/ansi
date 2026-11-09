/// The household's fridge and freezer: read through [readLeftovers], and put
/// right by the household. Pure Dart.
///
/// Every write names a [Leftover] as the page drew it. A row derived from a
/// cooked batch has no stored row yet: the first write about it stores one,
/// naming the batch, which from then on replaces the derived row.
library;

import 'leftovers.dart';

abstract interface class LeftoverRepository {
  /// The household's leftovers on [today], fridge first, and every meal
  /// served from one, live ([readLeftovers]). [weekStart] is the first day of
  /// the week holding [today]: the cooked batches read are those of
  /// [leftoverWeekStarts].
  Stream<LeftoverShelves> watchHouseholdLeftovers({
    required DateTime weekStart,
    required DateTime today,
  });

  /// Where every stored row is, by id, gone or not, live: a meal planned from
  /// one says which shelf it came from.
  Stream<Map<String, LeftoverPlace>> watchLeftoverPlaces();

  /// Says [portions] of [left] are in the box ([Leftover.inBox]); zero takes
  /// it off the page. Every tick or untick after it still moves the count
  /// ([readLeftovers]).
  Future<void> setLeftoverPortions(Leftover left, double portions);

  /// Moves [left] to the freezer, its count as it stands. Its date still
  /// counts from its cook day, whether it went in on the night or is said to
  /// have late.
  Future<void> freezeLeftover(Leftover left);

  /// Says every one of [lefts] is gone: eaten, binned or given away.
  Future<void> markLeftoversGone(List<Leftover> lefts);

  /// Puts every one of [lefts] back as the page drew it before a Freeze, a
  /// Froze it or a Remove gone off: a derived row by taking away the row that
  /// write stored for its batch, a stored one by saying again its place, its
  /// date and its count, and that it is not gone.
  Future<void> restoreLeftovers(List<Leftover> lefts);

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
