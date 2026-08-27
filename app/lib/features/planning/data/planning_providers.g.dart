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
    r'e90a2561274db50c756fa402eb79cf58edf36897';
