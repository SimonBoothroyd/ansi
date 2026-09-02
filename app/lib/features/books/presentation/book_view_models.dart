/// Riverpod ViewModels for the books UI.
///
/// [library] is a thin stream off the repository. Mutations don't need their
/// own notifier — views call the keep-alive `bookRepositoryProvider` directly,
/// which stays valid across the async gaps a dialog introduces (a short-lived
/// notifier would be disposed before its callback ran).
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/book_providers.dart';
import '../domain/book.dart';

part 'book_view_models.g.dart';

/// Every book with its sections and filed recipes, newest recipes first.
@riverpod
Stream<List<Book>> library(Ref ref) =>
    ref.watch(bookRepositoryProvider).watchLibrary();

/// Which books are folded shut on this device (D3).
///
/// Keep-alive, and not optional: the toggle lands after a frame, and every
/// Library mutation beside it lands after an async dialog — a short-lived
/// notifier would be disposed before its callback ran. Hydrated once from the
/// store; each toggle writes through so the fold survives a relaunch.
@Riverpod(keepAlive: true)
class FoldedBooks extends _$FoldedBooks {
  @override
  Future<Set<String>> build() => ref.watch(bookCollapseStoreProvider).read();

  /// Folds [bookId] shut, or opens it again. Optimistic: the set flips before
  /// the write lands, because a chevron that waits on disk reads as broken.
  Future<void> toggle(String bookId) async {
    final next = {...state.asData?.value ?? const <String>{}};
    final collapsed = !next.remove(bookId);
    if (collapsed) next.add(bookId);
    state = AsyncData(next);
    await ref
        .read(bookCollapseStoreProvider)
        .write(bookId, collapsed: collapsed);
  }
}
