// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(bookRepository)
const bookRepositoryProvider = BookRepositoryProvider._();

final class BookRepositoryProvider
    extends $FunctionalProvider<BookRepository, BookRepository, BookRepository>
    with $Provider<BookRepository> {
  const BookRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bookRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bookRepositoryHash();

  @$internal
  @override
  $ProviderElement<BookRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BookRepository create(Ref ref) {
    return bookRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BookRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BookRepository>(value),
    );
  }
}

String _$bookRepositoryHash() => r'102740de361a4c92b80aa74a53e175d6291673be';

@ProviderFor(bookCollapseStore)
const bookCollapseStoreProvider = BookCollapseStoreProvider._();

final class BookCollapseStoreProvider
    extends
        $FunctionalProvider<
          BookCollapseStore,
          BookCollapseStore,
          BookCollapseStore
        >
    with $Provider<BookCollapseStore> {
  const BookCollapseStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bookCollapseStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bookCollapseStoreHash();

  @$internal
  @override
  $ProviderElement<BookCollapseStore> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BookCollapseStore create(Ref ref) {
    return bookCollapseStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BookCollapseStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BookCollapseStore>(value),
    );
  }
}

String _$bookCollapseStoreHash() => r'ccdd3bf396b2437f6e88e2311e682f7603f69463';
