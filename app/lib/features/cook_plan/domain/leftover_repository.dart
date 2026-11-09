/// The household's fridge and freezer: every cooking read through
/// [readCookings], and put right by the household. Pure Dart.
///
/// Every write names a [Leftover] (one shelf of one cooking) as the page drew
/// it, and is measured against the cooking as it stands when the write lands.
/// A correction is a change row, so a later tick or untick still moves the
/// count; Undo takes the write back ([LeftoverRepository.undoLeftovers]).
library;

import 'leftovers.dart';

/// What a write did, for its Undo: the change rows it wrote and the
/// cookings it said were gone.
typedef LeftoverUndo = ({List<String> changes, List<String> gone});

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

  /// Says every one of [lefts] has gone off. A cooking whose every shelf is
  /// in the list is gone for good (`gone_at`: an untick never brings it
  /// back); one with food left on the other shelf has these shelves counted
  /// to nothing instead.
  Future<LeftoverUndo> markLeftoversGone(List<Leftover> lefts);

  /// Takes back what [undo] names: its change rows soft-deleted, its
  /// cookings no longer gone.
  Future<void> undoLeftovers(LeftoverUndo undo);

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
