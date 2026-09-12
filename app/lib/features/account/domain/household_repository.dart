/// The household row itself — the standing facts that are neither a person nor
/// a device. Today that is one fact: which day the week begins on.
///
/// PURE DART (invariant 2).
library;

import '../../../core/week_shape.dart';

abstract interface class HouseholdRepository {
  /// The household's [WeekShape], live. Emits Monday until the row arrives —
  /// a household that has never said otherwise starts its week on Monday, and
  /// so does a device that has not synced the row yet.
  Stream<WeekShape> watchWeekShape();

  /// Moves the household's week to start on [startsOn] (ISO 1=Mon..7=Sun),
  /// re-homing every week it has planned.
  ///
  /// **A server call, not a local write.** Flipping the day changes the key
  /// every `week_plan`, `plan_entry` and `shopping_list_entry` row is
  /// addressed by; that is one transaction across four tables, and a phone
  /// that wrote the column locally would be reading its own rows under a key
  /// they do not carry. So this is online-only, and the column reaches the
  /// device by sync like every other synced fact. It is idempotent: it moves
  /// only the weeks whose day does not already match, so running it again
  /// after a meal queued offline puts that meal back where it belongs.
  ///
  /// Throws when the server cannot be reached or refuses; the household is
  /// unchanged in that case, because the re-home is one transaction.
  Future<void> setWeekStart(int startsOn);
}
