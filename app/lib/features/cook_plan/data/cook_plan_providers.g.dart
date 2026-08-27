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
