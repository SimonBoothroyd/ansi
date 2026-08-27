// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cook_view_models.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The derived cook plan for the active week, reacting to plan/recipe changes.

@ProviderFor(currentCookPlan)
const currentCookPlanProvider = CurrentCookPlanProvider._();

/// The derived cook plan for the active week, reacting to plan/recipe changes.

final class CurrentCookPlanProvider
    extends
        $FunctionalProvider<AsyncValue<CookPlan>, CookPlan, Stream<CookPlan>>
    with $FutureModifier<CookPlan>, $StreamProvider<CookPlan> {
  /// The derived cook plan for the active week, reacting to plan/recipe changes.
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

String _$currentCookPlanHash() => r'362c1380367a0163c728b826e0f3d2d4130ec029';
