// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cook_plan_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(cookPlanRepository)
const cookPlanRepositoryProvider = CookPlanRepositoryProvider._();

final class CookPlanRepositoryProvider
    extends
        $FunctionalProvider<
          CookPlanRepository,
          CookPlanRepository,
          CookPlanRepository
        >
    with $Provider<CookPlanRepository> {
  const CookPlanRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cookPlanRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cookPlanRepositoryHash();

  @$internal
  @override
  $ProviderElement<CookPlanRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CookPlanRepository create(Ref ref) {
    return cookPlanRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CookPlanRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CookPlanRepository>(value),
    );
  }
}

String _$cookPlanRepositoryHash() =>
    r'779ee247e15cc4152afc8a086f1c963071603838';

@ProviderFor(leftoverRepository)
const leftoverRepositoryProvider = LeftoverRepositoryProvider._();

final class LeftoverRepositoryProvider
    extends
        $FunctionalProvider<
          LeftoverRepository,
          LeftoverRepository,
          LeftoverRepository
        >
    with $Provider<LeftoverRepository> {
  const LeftoverRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'leftoverRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$leftoverRepositoryHash();

  @$internal
  @override
  $ProviderElement<LeftoverRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LeftoverRepository create(Ref ref) {
    return leftoverRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LeftoverRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LeftoverRepository>(value),
    );
  }
}

String _$leftoverRepositoryHash() =>
    r'817606c5d00814fa7d2cb8fa900aa53ab3e6cfd5';

/// The carry-over from the last release's fridge rows and answers
/// ([carryOverCookings]): once a session is ready, after this launch's first
/// download has finished, so the cookings the server converted are here
/// before any is born on this phone. Idempotent, so a second run (a sign-in
/// again) changes nothing. Listened from the app's root; it goes with the old
/// tables.

@ProviderFor(cookingCarryOver)
const cookingCarryOverProvider = CookingCarryOverProvider._();

/// The carry-over from the last release's fridge rows and answers
/// ([carryOverCookings]): once a session is ready, after this launch's first
/// download has finished, so the cookings the server converted are here
/// before any is born on this phone. Idempotent, so a second run (a sign-in
/// again) changes nothing. Listened from the app's root; it goes with the old
/// tables.

final class CookingCarryOverProvider
    extends $FunctionalProvider<AsyncValue<void>, void, FutureOr<void>>
    with $FutureModifier<void>, $FutureProvider<void> {
  /// The carry-over from the last release's fridge rows and answers
  /// ([carryOverCookings]): once a session is ready, after this launch's first
  /// download has finished, so the cookings the server converted are here
  /// before any is born on this phone. Idempotent, so a second run (a sign-in
  /// again) changes nothing. Listened from the app's root; it goes with the old
  /// tables.
  const CookingCarryOverProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cookingCarryOverProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cookingCarryOverHash();

  @$internal
  @override
  $FutureProviderElement<void> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<void> create(Ref ref) {
    return cookingCarryOver(ref);
  }
}

String _$cookingCarryOverHash() => r'2a33705bd1e9c7b4a52eeae99f7d940df4228531';
