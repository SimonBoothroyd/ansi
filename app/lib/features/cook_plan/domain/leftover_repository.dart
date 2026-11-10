/// The household's fridge and freezer: every cooking read through
/// [readCookings], and put right by the household. Pure Dart.
///
/// Every write names a [Leftover] (one shelf of one cooking) as the page drew
/// it, and is measured against the cooking as it stands when the write lands.
/// A correction is a change row, so a later tick or untick still moves the
/// count; Undo takes the write back ([LeftoverRepository.undoLeftovers]).
library;

import 'leftovers.dart';

/// What a write did, for its Undo: the change rows it wrote, and the
/// cookings it said were gone off, each with the `gone_at` it had before
/// (null when it had none).
typedef LeftoverUndo = ({List<String> changes, Map<String, String?> gone});

abstract interface class LeftoverRepository {
  /// The household's leftovers on [today], fridge first, and every meal
  /// served from one, live ([readCookings]).
  Stream<LeftoverShelves> watchHouseholdLeftovers({required DateTime today});

  /// Says [portions] of [left] are on its shelf ([Leftover.inBox]): one
  /// change row with the difference. Zero takes it off the page. Every tick
  /// or untick after it still moves the count.
  Future<void> setLeftoverPortions(Leftover left, double portions);

  /// Moves what is in [left]'s fridge box to the freezer (Freeze, or Froze it
  /// for one past its date): one change row, out of one shelf and into the
  /// other. Its dates still count from its cook day.
  Future<LeftoverUndo> freezeLeftover(Leftover left);

  /// Says every one of [lefts], each past its date, has gone off: final, an
  /// untick after it never brings any of it back. Its cooking's `gone_at` is
  /// set: the fridge part is gone for good, and the freezer part too unless
  /// it is still in date that day ([readCooking]). A freezer part gone off
  /// beside a fridge part still in date is counted to nothing instead.
  Future<LeftoverUndo> markLeftoversGone(List<Leftover> lefts);

  /// Takes back what [undo] names: its change rows soft-deleted, its
  /// cookings' `gone_at` as it was before.
  Future<void> undoLeftovers(LeftoverUndo undo);

  /// Says the pot [pot] is cooked as a whole batch ([whole]) or at the exact
  /// scale: the spare portions of a whole batch are made, bought and left
  /// over. [pot] is a cooking's id, or a meal of a group not in one yet,
  /// which is born into one here.
  Future<void> setWholeBatch(String pot, {required bool whole});

  /// Adds food the app never saw: a recipe or the household's own [label],
  /// never both, on [place] since [since]. Returns the new cooking's id.
  Future<String> addLeftover({
    required LeftoverPlace place,
    required double portions,
    required DateTime since,
    String? recipeId,
    String? label,
  });
}
