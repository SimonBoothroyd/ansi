/// Which books are folded shut — PURE DART (invariant 2).
///
/// This is a *viewing* preference, not household data, so it is stored per
/// device and never synced: under last-write-wins a synced `book.collapsed`
/// would mean one member's tap folding the other's screen mid-scroll, for the
/// price of a migration and a bucket entry.
///
/// **Absent means expanded.** A household's first book must not arrive folded,
/// and a key for a book that no longer exists is inert.
library;

abstract interface class BookCollapseStore {
  /// The ids of every book folded shut on this device.
  Future<Set<String>> read();

  /// Records (or forgets) [bookId]'s fold.
  Future<void> write(String bookId, {required bool collapsed});
}
