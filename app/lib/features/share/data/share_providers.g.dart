// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'share_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(recipeShareRepository)
const recipeShareRepositoryProvider = RecipeShareRepositoryProvider._();

final class RecipeShareRepositoryProvider
    extends
        $FunctionalProvider<
          RecipeShareRepository,
          RecipeShareRepository,
          RecipeShareRepository
        >
    with $Provider<RecipeShareRepository> {
  const RecipeShareRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recipeShareRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recipeShareRepositoryHash();

  @$internal
  @override
  $ProviderElement<RecipeShareRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RecipeShareRepository create(Ref ref) {
    return recipeShareRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RecipeShareRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RecipeShareRepository>(value),
    );
  }
}

String _$recipeShareRepositoryHash() =>
    r'9906b149a87afa61caf59b69482223a4974869b3';

/// The share host's origin, or blank when this build offers no share link.

@ProviderFor(shareBaseUrl)
const shareBaseUrlProvider = ShareBaseUrlProvider._();

/// The share host's origin, or blank when this build offers no share link.

final class ShareBaseUrlProvider
    extends $FunctionalProvider<String, String, String>
    with $Provider<String> {
  /// The share host's origin, or blank when this build offers no share link.
  const ShareBaseUrlProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shareBaseUrlProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shareBaseUrlHash();

  @$internal
  @override
  $ProviderElement<String> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String create(Ref ref) {
    return shareBaseUrl(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$shareBaseUrlHash() => r'20d7befd0facf8e7e096dbe63c48da1bd1dac2e9';

/// Whether [recipeId] has a live link, asked of the server when the page's
/// menu is built. An error means the page could not ask.

@ProviderFor(recipeShared)
const recipeSharedProvider = RecipeSharedFamily._();

/// Whether [recipeId] has a live link, asked of the server when the page's
/// menu is built. An error means the page could not ask.

final class RecipeSharedProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Whether [recipeId] has a live link, asked of the server when the page's
  /// menu is built. An error means the page could not ask.
  const RecipeSharedProvider._({
    required RecipeSharedFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'recipeSharedProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$recipeSharedHash();

  @override
  String toString() {
    return r'recipeSharedProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    final argument = this.argument as String;
    return recipeShared(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RecipeSharedProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$recipeSharedHash() => r'a448cfab573ba3e161699cc83c224ec9b8d980bf';

/// Whether [recipeId] has a live link, asked of the server when the page's
/// menu is built. An error means the page could not ask.

final class RecipeSharedFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, String> {
  const RecipeSharedFamily._()
    : super(
        retry: null,
        name: r'recipeSharedProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether [recipeId] has a live link, asked of the server when the page's
  /// menu is built. An error means the page could not ask.

  RecipeSharedProvider call(String recipeId) =>
      RecipeSharedProvider._(argument: recipeId, from: this);

  @override
  String toString() => r'recipeSharedProvider';
}

@ProviderFor(handOffLink)
const handOffLinkProvider = HandOffLinkProvider._();

final class HandOffLinkProvider
    extends $FunctionalProvider<HandOffLink, HandOffLink, HandOffLink>
    with $Provider<HandOffLink> {
  const HandOffLinkProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'handOffLinkProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$handOffLinkHash();

  @$internal
  @override
  $ProviderElement<HandOffLink> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  HandOffLink create(Ref ref) {
    return handOffLink(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HandOffLink value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HandOffLink>(value),
    );
  }
}

String _$handOffLinkHash() => r'28da25ab357bac3e85f5cc0c4fcbb90017786c3d';
