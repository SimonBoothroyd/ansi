/// The `SharedPreferences` keys this app writes PER DEVICE — never synced, and
/// swept together on sign-out.
///
/// Anything here is a *viewing* or *connection* fact about this phone, not
/// household data: syncing it would mean one member's tap changing the other's
/// screen under last-write-wins. Keeping the prefixes in one place is what lets
/// `SharedPrefsHouseholdCache.clear` sweep a feature's keys without `core/`
/// importing that feature (root AGENTS.md: `core/` never imports a feature).
///
/// Nothing here needs migrating — a key for a dead id is inert.
library;

abstract final class DevicePrefs {
  /// `+ userId` → the household that user resolved to on this device, so a
  /// signed-in relaunch reaches the Library without awaiting the onboarding
  /// RPC.
  static const householdIdPrefix = 'ansi.household_id.';

  /// `+ bookId` → `true` while that book is folded shut on this device
  /// (Library v2 / D3). Absent means expanded: a household's first book must
  /// not arrive folded.
  static const bookCollapsedPrefix = 'ansi.book_collapsed.';

  /// Every prefix above, in the order sign-out sweeps them.
  static const sweptOnSignOut = [householdIdPrefix, bookCollapsedPrefix];
}
