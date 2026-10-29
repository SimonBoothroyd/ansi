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

/// Whether a session shows the whole batch (×N, with the portions spare)
/// instead of the exact factor. Display-only and ephemeral by design.

@ProviderFor(WholeBatchDisplay)
const wholeBatchDisplayProvider = WholeBatchDisplayFamily._();

/// Whether a session shows the whole batch (×N, with the portions spare)
/// instead of the exact factor. Display-only and ephemeral by design.
final class WholeBatchDisplayProvider
    extends $NotifierProvider<WholeBatchDisplay, bool> {
  /// Whether a session shows the whole batch (×N, with the portions spare)
  /// instead of the exact factor. Display-only and ephemeral by design.
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

String _$wholeBatchDisplayHash() => r'240aee7ba05f06f3a6510fbb44434110472eda66';

/// Whether a session shows the whole batch (×N, with the portions spare)
/// instead of the exact factor. Display-only and ephemeral by design.

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

  /// Whether a session shows the whole batch (×N, with the portions spare)
  /// instead of the exact factor. Display-only and ephemeral by design.

  WholeBatchDisplayProvider call(String sessionKey) =>
      WholeBatchDisplayProvider._(argument: sessionKey, from: this);

  @override
  String toString() => r'wholeBatchDisplayProvider';
}

/// Whether a session shows the whole batch (×N, with the portions spare)
/// instead of the exact factor. Display-only and ephemeral by design.

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

/// What was said about the viewed week's leftovers, keyed by
/// [CookSession.leftoverKey].

@ProviderFor(viewedWeekLeftovers)
const viewedWeekLeftoversProvider = ViewedWeekLeftoversProvider._();

/// What was said about the viewed week's leftovers, keyed by
/// [CookSession.leftoverKey].

final class ViewedWeekLeftoversProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, LeftoverAnswer>>,
          Map<String, LeftoverAnswer>,
          Stream<Map<String, LeftoverAnswer>>
        >
    with
        $FutureModifier<Map<String, LeftoverAnswer>>,
        $StreamProvider<Map<String, LeftoverAnswer>> {
  /// What was said about the viewed week's leftovers, keyed by
  /// [CookSession.leftoverKey].
  const ViewedWeekLeftoversProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'viewedWeekLeftoversProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$viewedWeekLeftoversHash();

  @$internal
  @override
  $StreamProviderElement<Map<String, LeftoverAnswer>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, LeftoverAnswer>> create(Ref ref) {
    return viewedWeekLeftovers(ref);
  }
}

String _$viewedWeekLeftoversHash() =>
    r'ed50e568a58e30f2704c0c3ca1e75a617cc50a39';

/// How many of the viewed week's days are fully behind us: 0 for a week still
/// to come, 7 for one gone. A batch is over once its last day is.

@ProviderFor(viewedWeekDaysPassed)
const viewedWeekDaysPassedProvider = ViewedWeekDaysPassedProvider._();

/// How many of the viewed week's days are fully behind us: 0 for a week still
/// to come, 7 for one gone. A batch is over once its last day is.

final class ViewedWeekDaysPassedProvider
    extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  /// How many of the viewed week's days are fully behind us: 0 for a week still
  /// to come, 7 for one gone. A batch is over once its last day is.
  const ViewedWeekDaysPassedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'viewedWeekDaysPassedProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$viewedWeekDaysPassedHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return viewedWeekDaysPassed(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$viewedWeekDaysPassedHash() =>
    r'f8f6b54eadac7b60d49d6333ba0842863d9b5d8f';

/// The viewed week's leftovers in one line for the Week band — `1 portion
/// binned · 1 kept · 2 left` — counting only batches whose days are over.
/// Null when nothing is left over.

@ProviderFor(weekLeftoverLine)
const weekLeftoverLineProvider = WeekLeftoverLineProvider._();

/// The viewed week's leftovers in one line for the Week band — `1 portion
/// binned · 1 kept · 2 left` — counting only batches whose days are over.
/// Null when nothing is left over.

final class WeekLeftoverLineProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  /// The viewed week's leftovers in one line for the Week band — `1 portion
  /// binned · 1 kept · 2 left` — counting only batches whose days are over.
  /// Null when nothing is left over.
  const WeekLeftoverLineProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'weekLeftoverLineProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$weekLeftoverLineHash();

  @$internal
  @override
  $ProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String? create(Ref ref) {
    return weekLeftoverLine(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$weekLeftoverLineHash() => r'c544cc7205ef644ed2419438e68d6da3e7729017';
