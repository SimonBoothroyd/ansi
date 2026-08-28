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

/// Whether a session tile shows the whole-batch view (×N + leftover line)
/// instead of the honest raw factor. Display-only and ephemeral by design.

@ProviderFor(WholeBatchDisplay)
const wholeBatchDisplayProvider = WholeBatchDisplayFamily._();

/// Whether a session tile shows the whole-batch view (×N + leftover line)
/// instead of the honest raw factor. Display-only and ephemeral by design.
final class WholeBatchDisplayProvider
    extends $NotifierProvider<WholeBatchDisplay, bool> {
  /// Whether a session tile shows the whole-batch view (×N + leftover line)
  /// instead of the honest raw factor. Display-only and ephemeral by design.
  const WholeBatchDisplayProvider._({
    required WholeBatchDisplayFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'wholeBatchDisplayProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$wholeBatchDisplayHash();

  @override
  String toString() {
    return r'wholeBatchDisplayProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  WholeBatchDisplay create() => WholeBatchDisplay();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WholeBatchDisplayProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$wholeBatchDisplayHash() => r'13937e7076a9284e2341c022dfa4dddf851367a3';

/// Whether a session tile shows the whole-batch view (×N + leftover line)
/// instead of the honest raw factor. Display-only and ephemeral by design.

final class WholeBatchDisplayFamily extends $Family
    with $ClassFamilyOverride<WholeBatchDisplay, bool, bool, bool, String> {
  const WholeBatchDisplayFamily._()
    : super(
        retry: null,
        name: r'wholeBatchDisplayProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether a session tile shows the whole-batch view (×N + leftover line)
  /// instead of the honest raw factor. Display-only and ephemeral by design.

  WholeBatchDisplayProvider call(String sessionKey) =>
      WholeBatchDisplayProvider._(argument: sessionKey, from: this);

  @override
  String toString() => r'wholeBatchDisplayProvider';
}

/// Whether a session tile shows the whole-batch view (×N + leftover line)
/// instead of the honest raw factor. Display-only and ephemeral by design.

abstract class _$WholeBatchDisplay extends $Notifier<bool> {
  late final _$args = ref.$arg as String;
  String get sessionKey => _$args;

  bool build(String sessionKey);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
