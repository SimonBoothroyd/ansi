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
