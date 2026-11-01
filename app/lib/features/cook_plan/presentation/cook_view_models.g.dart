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

/// The cooked batches of the week beginning [weekStart] with portions still
/// left today, live.

@ProviderFor(weekBatchLeftovers)
const weekBatchLeftoversProvider = WeekBatchLeftoversFamily._();

/// The cooked batches of the week beginning [weekStart] with portions still
/// left today, live.

final class WeekBatchLeftoversProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<BatchLeftover>>,
          List<BatchLeftover>,
          Stream<List<BatchLeftover>>
        >
    with
        $FutureModifier<List<BatchLeftover>>,
        $StreamProvider<List<BatchLeftover>> {
  /// The cooked batches of the week beginning [weekStart] with portions still
  /// left today, live.
  const WeekBatchLeftoversProvider._({
    required WeekBatchLeftoversFamily super.from,
    required DateTime super.argument,
  }) : super(
         retry: null,
         name: r'weekBatchLeftoversProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$weekBatchLeftoversHash();

  @override
  String toString() {
    return r'weekBatchLeftoversProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<BatchLeftover>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<BatchLeftover>> create(Ref ref) {
    final argument = this.argument as DateTime;
    return weekBatchLeftovers(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is WeekBatchLeftoversProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$weekBatchLeftoversHash() =>
    r'cf549ae50dadd16331e4c3267a81246216521715';

/// The cooked batches of the week beginning [weekStart] with portions still
/// left today, live.

final class WeekBatchLeftoversFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<BatchLeftover>>, DateTime> {
  const WeekBatchLeftoversFamily._()
    : super(
        retry: null,
        name: r'weekBatchLeftoversProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The cooked batches of the week beginning [weekStart] with portions still
  /// left today, live.

  WeekBatchLeftoversProvider call(DateTime weekStart) =>
      WeekBatchLeftoversProvider._(argument: weekStart, from: this);

  @override
  String toString() => r'weekBatchLeftoversProvider';
}

/// The leftovers a meal on [day] can be planned from, soonest use-by first:
/// cooked this week or last, still good on [day], and [day] not behind us.
/// Empty while either week loads.

@ProviderFor(leftoversGoodOn)
const leftoversGoodOnProvider = LeftoversGoodOnFamily._();

/// The leftovers a meal on [day] can be planned from, soonest use-by first:
/// cooked this week or last, still good on [day], and [day] not behind us.
/// Empty while either week loads.

final class LeftoversGoodOnProvider
    extends
        $FunctionalProvider<
          List<BatchLeftover>,
          List<BatchLeftover>,
          List<BatchLeftover>
        >
    with $Provider<List<BatchLeftover>> {
  /// The leftovers a meal on [day] can be planned from, soonest use-by first:
  /// cooked this week or last, still good on [day], and [day] not behind us.
  /// Empty while either week loads.
  const LeftoversGoodOnProvider._({
    required LeftoversGoodOnFamily super.from,
    required DateTime super.argument,
  }) : super(
         retry: null,
         name: r'leftoversGoodOnProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$leftoversGoodOnHash();

  @override
  String toString() {
    return r'leftoversGoodOnProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<BatchLeftover>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<BatchLeftover> create(Ref ref) {
    final argument = this.argument as DateTime;
    return leftoversGoodOn(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<BatchLeftover> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<BatchLeftover>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LeftoversGoodOnProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$leftoversGoodOnHash() => r'e1721828159cd4deff12d9f77c714f3602989773';

/// The leftovers a meal on [day] can be planned from, soonest use-by first:
/// cooked this week or last, still good on [day], and [day] not behind us.
/// Empty while either week loads.

final class LeftoversGoodOnFamily extends $Family
    with $FunctionalFamilyOverride<List<BatchLeftover>, DateTime> {
  const LeftoversGoodOnFamily._()
    : super(
        retry: null,
        name: r'leftoversGoodOnProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The leftovers a meal on [day] can be planned from, soonest use-by first:
  /// cooked this week or last, still good on [day], and [day] not behind us.
  /// Empty while either week loads.

  LeftoversGoodOnProvider call(DateTime day) =>
      LeftoversGoodOnProvider._(argument: day, from: this);

  @override
  String toString() => r'leftoversGoodOnProvider';
}

/// The viewed week's leftovers in one line for the Week band — `1 portion
/// binned · 2 left`. Null when nothing is left over.

@ProviderFor(weekLeftoverLine)
const weekLeftoverLineProvider = WeekLeftoverLineProvider._();

/// The viewed week's leftovers in one line for the Week band — `1 portion
/// binned · 2 left`. Null when nothing is left over.

final class WeekLeftoverLineProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  /// The viewed week's leftovers in one line for the Week band — `1 portion
  /// binned · 2 left`. Null when nothing is left over.
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

String _$weekLeftoverLineHash() => r'acaa4118d190fd0ae9dd71be3941268acc3729da';
