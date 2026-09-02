// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book_view_models.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Every book with its sections and filed recipes, newest recipes first.

@ProviderFor(library)
const libraryProvider = LibraryProvider._();

/// Every book with its sections and filed recipes, newest recipes first.

final class LibraryProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Book>>,
          List<Book>,
          Stream<List<Book>>
        >
    with $FutureModifier<List<Book>>, $StreamProvider<List<Book>> {
  /// Every book with its sections and filed recipes, newest recipes first.
  const LibraryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryHash();

  @$internal
  @override
  $StreamProviderElement<List<Book>> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<List<Book>> create(Ref ref) {
    return library(ref);
  }
}

String _$libraryHash() => r'2a768802cf982e8a3792ba5998b6333229780a8f';

/// Which books are folded shut on this device (D3).
///
/// Keep-alive, and not optional: the toggle lands after a frame, and every
/// Library mutation beside it lands after an async dialog — a short-lived
/// notifier would be disposed before its callback ran. Hydrated once from the
/// store; each toggle writes through so the fold survives a relaunch.

@ProviderFor(FoldedBooks)
const foldedBooksProvider = FoldedBooksProvider._();

/// Which books are folded shut on this device (D3).
///
/// Keep-alive, and not optional: the toggle lands after a frame, and every
/// Library mutation beside it lands after an async dialog — a short-lived
/// notifier would be disposed before its callback ran. Hydrated once from the
/// store; each toggle writes through so the fold survives a relaunch.
final class FoldedBooksProvider
    extends $AsyncNotifierProvider<FoldedBooks, Set<String>> {
  /// Which books are folded shut on this device (D3).
  ///
  /// Keep-alive, and not optional: the toggle lands after a frame, and every
  /// Library mutation beside it lands after an async dialog — a short-lived
  /// notifier would be disposed before its callback ran. Hydrated once from the
  /// store; each toggle writes through so the fold survives a relaunch.
  const FoldedBooksProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'foldedBooksProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$foldedBooksHash();

  @$internal
  @override
  FoldedBooks create() => FoldedBooks();
}

String _$foldedBooksHash() => r'0a6bfed411a8dfd032dfef64eb4b3a1726934163';

/// Which books are folded shut on this device (D3).
///
/// Keep-alive, and not optional: the toggle lands after a frame, and every
/// Library mutation beside it lands after an async dialog — a short-lived
/// notifier would be disposed before its callback ran. Hydrated once from the
/// store; each toggle writes through so the fold survives a relaunch.

abstract class _$FoldedBooks extends $AsyncNotifier<Set<String>> {
  FutureOr<Set<String>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<Set<String>>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Set<String>>, Set<String>>,
              AsyncValue<Set<String>>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
