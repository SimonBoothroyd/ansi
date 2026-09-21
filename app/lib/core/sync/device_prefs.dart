/// The `SharedPreferences` keys this app writes per device: never synced, and
/// swept together on sign-out.
///
/// These are viewing or connection facts about this phone, not household
/// data. The prefixes live here so `SharedPrefsHouseholdCache.clear` can sweep
/// a feature's keys without `core/` importing that feature.
library;

abstract final class DevicePrefs {
  /// `+ userId` → the household that user resolved to on this device, so a
  /// relaunch need not await the onboarding RPC.
  static const householdIdPrefix = 'ansi.household_id.';

  /// `+ bookId` → `true` while that book is folded shut on this device.
  /// Absent means expanded.
  static const bookCollapsedPrefix = 'ansi.book_collapsed.';

  /// Every prefix above, in the order sign-out sweeps them.
  static const sweptOnSignOut = [householdIdPrefix, bookCollapsedPrefix];
}
