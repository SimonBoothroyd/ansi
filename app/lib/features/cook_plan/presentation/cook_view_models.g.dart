// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cook_view_models.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The derived cook plan for the viewed week, reacting to plan/recipe changes.

@ProviderFor(currentCookPlan)
const currentCookPlanProvider = CurrentCookPlanProvider._();

/// The derived cook plan for the viewed week, reacting to plan/recipe changes.

final class CurrentCookPlanProvider
    extends
        $FunctionalProvider<AsyncValue<CookPlan>, CookPlan, Stream<CookPlan>>
    with $FutureModifier<CookPlan>, $StreamProvider<CookPlan> {
  /// The derived cook plan for the viewed week, reacting to plan/recipe changes.
  const CurrentCookPlanProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentCookPlanProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentCookPlanHash();

  @$internal
  @override
  $StreamProviderElement<CookPlan> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<CookPlan> create(Ref ref) {
    return currentCookPlan(ref);
  }
}

String _$currentCookPlanHash() => r'096c0fdd63465de1374ef5724f5d87306e691ac1';
