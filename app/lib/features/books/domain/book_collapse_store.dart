/// Which books are folded shut (pure Dart).
///
/// A viewing preference, stored per device and never synced. Absent means
/// expanded, and a key for a deleted book is inert.
library;

abstract interface class BookCollapseStore {
  /// The ids of every book folded shut on this device.
  Future<Set<String>> read();

  /// Records (or forgets) [bookId]'s fold.
  Future<void> write(String bookId, {required bool collapsed});
}
