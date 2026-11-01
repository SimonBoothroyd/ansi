// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'planning_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(planningRepository)
const planningRepositoryProvider = PlanningRepositoryProvider._();

final class PlanningRepositoryProvider
    extends
        $FunctionalProvider<
          PlanningRepository,
          PlanningRepository,
          PlanningRepository
        >
    with $Provider<PlanningRepository> {
  const PlanningRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'planningRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$planningRepositoryHash();

  @$internal
  @override
  $ProviderElement<PlanningRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PlanningRepository create(Ref ref) {
    return planningRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlanningRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlanningRepository>(value),
    );
  }
}

String _$planningRepositoryHash() =>
    r'132ed2490d08143a764890c252a0fb773f968d53';

@ProviderFor(useUpRepository)
const useUpRepositoryProvider = UseUpRepositoryProvider._();

final class UseUpRepositoryProvider
    extends
        $FunctionalProvider<UseUpRepository, UseUpRepository, UseUpRepository>
    with $Provider<UseUpRepository> {
  const UseUpRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'useUpRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$useUpRepositoryHash();

  @$internal
  @override
  $ProviderElement<UseUpRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  UseUpRepository create(Ref ref) {
    return useUpRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UseUpRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UseUpRepository>(value),
    );
  }
}

String _$useUpRepositoryHash() => r'cc43b6392b112e553dc0ac269c7ef1ad1b68f94e';

@ProviderFor(weekVariantRepository)
const weekVariantRepositoryProvider = WeekVariantRepositoryProvider._();

final class WeekVariantRepositoryProvider
    extends
        $FunctionalProvider<
          WeekVariantRepository,
          WeekVariantRepository,
          WeekVariantRepository
        >
    with $Provider<WeekVariantRepository> {
  const WeekVariantRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'weekVariantRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$weekVariantRepositoryHash();

  @$internal
  @override
  $ProviderElement<WeekVariantRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WeekVariantRepository create(Ref ref) {
    return weekVariantRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WeekVariantRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WeekVariantRepository>(value),
    );
  }
}

String _$weekVariantRepositoryHash() =>
    r'42e0cef1bce93f4369d0b057031b5c84ca2bfb3f';
