// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health_sync.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The Account switch: whether this phone sends its member's meals. Turning
/// it on asks Health Connect for permission, and stays off if refused.
/// Turning it off stops sending and leaves what was sent where it is.

@ProviderFor(HealthEnabled)
const healthEnabledProvider = HealthEnabledProvider._();

/// The Account switch: whether this phone sends its member's meals. Turning
/// it on asks Health Connect for permission, and stays off if refused.
/// Turning it off stops sending and leaves what was sent where it is.
final class HealthEnabledProvider
    extends $AsyncNotifierProvider<HealthEnabled, bool> {
  /// The Account switch: whether this phone sends its member's meals. Turning
  /// it on asks Health Connect for permission, and stays off if refused.
  /// Turning it off stops sending and leaves what was sent where it is.
  const HealthEnabledProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'healthEnabledProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$healthEnabledHash();

  @$internal
  @override
  HealthEnabled create() => HealthEnabled();
}

String _$healthEnabledHash() => r'437c4d8bdc5a5ab6bdb09d826c79d49fd1d659db';

/// The Account switch: whether this phone sends its member's meals. Turning
/// it on asks Health Connect for permission, and stays off if refused.
/// Turning it off stops sending and leaves what was sent where it is.

abstract class _$HealthEnabled extends $AsyncNotifier<bool> {
  FutureOr<bool> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<bool>, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<bool>, bool>,
              AsyncValue<bool>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Whether Health Connect is on this phone at all.

@ProviderFor(healthAvailability)
const healthAvailabilityProvider = HealthAvailabilityProvider._();

/// Whether Health Connect is on this phone at all.

final class HealthAvailabilityProvider
    extends
        $FunctionalProvider<
          AsyncValue<HealthAvailability>,
          HealthAvailability,
          FutureOr<HealthAvailability>
        >
    with
        $FutureModifier<HealthAvailability>,
        $FutureProvider<HealthAvailability> {
  /// Whether Health Connect is on this phone at all.
  const HealthAvailabilityProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'healthAvailabilityProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$healthAvailabilityHash();

  @$internal
  @override
  $FutureProviderElement<HealthAvailability> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<HealthAvailability> create(Ref ref) {
    return healthAvailability(ref);
  }
}

String _$healthAvailabilityHash() =>
    r'b9f18e38730c5c19f8f131cb59a762fa5136243a';

/// One week as Health Connect reads it, by its first day's ISO date.

@ProviderFor(healthWeek)
const healthWeekProvider = HealthWeekFamily._();

/// One week as Health Connect reads it, by its first day's ISO date.

final class HealthWeekProvider
    extends
        $FunctionalProvider<AsyncValue<WeekPlan?>, WeekPlan?, Stream<WeekPlan?>>
    with $FutureModifier<WeekPlan?>, $StreamProvider<WeekPlan?> {
  /// One week as Health Connect reads it, by its first day's ISO date.
  const HealthWeekProvider._({
    required HealthWeekFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'healthWeekProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$healthWeekHash();

  @override
  String toString() {
    return r'healthWeekProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<WeekPlan?> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<WeekPlan?> create(Ref ref) {
    final argument = this.argument as String;
    return healthWeek(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is HealthWeekProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$healthWeekHash() => r'2231ec45675532bda6090b0c7cf00c522a57affd';

/// One week as Health Connect reads it, by its first day's ISO date.

final class HealthWeekFamily extends $Family
    with $FunctionalFamilyOverride<Stream<WeekPlan?>, String> {
  const HealthWeekFamily._()
    : super(
        retry: null,
        name: r'healthWeekProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One week as Health Connect reads it, by its first day's ISO date.

  HealthWeekProvider call(String weekKey) =>
      HealthWeekProvider._(argument: weekKey, from: this);

  @override
  String toString() => r'healthWeekProvider';
}

/// The recipes' figures for one week, its variants re-summed.

@ProviderFor(healthWeekMacros)
const healthWeekMacrosProvider = HealthWeekMacrosFamily._();

/// The recipes' figures for one week, its variants re-summed.

final class HealthWeekMacrosProvider
    extends
        $FunctionalProvider<
          Map<String, RecipeMacroSummary>,
          Map<String, RecipeMacroSummary>,
          Map<String, RecipeMacroSummary>
        >
    with $Provider<Map<String, RecipeMacroSummary>> {
  /// The recipes' figures for one week, its variants re-summed.
  const HealthWeekMacrosProvider._({
    required HealthWeekMacrosFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'healthWeekMacrosProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$healthWeekMacrosHash();

  @override
  String toString() {
    return r'healthWeekMacrosProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<Map<String, RecipeMacroSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, RecipeMacroSummary> create(Ref ref) {
    final argument = this.argument as String;
    return healthWeekMacros(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, RecipeMacroSummary> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, RecipeMacroSummary>>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is HealthWeekMacrosProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$healthWeekMacrosHash() => r'92434e8e41292ccc6157a5d7ae415cd496eea355';

/// The recipes' figures for one week, its variants re-summed.

final class HealthWeekMacrosFamily extends $Family
    with $FunctionalFamilyOverride<Map<String, RecipeMacroSummary>, String> {
  const HealthWeekMacrosFamily._()
    : super(
        retry: null,
        name: r'healthWeekMacrosProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The recipes' figures for one week, its variants re-summed.

  HealthWeekMacrosProvider call(String weekKey) =>
      HealthWeekMacrosProvider._(argument: weekKey, from: this);

  @override
  String toString() => r'healthWeekMacrosProvider';
}

/// What should be in Health Connect — this member's meals over this week and
/// last — and what cannot be sent. Null while who is signed in is not known,
/// or a week has not loaded: nothing is written or taken back on a guess.

@ProviderFor(healthMeals)
const healthMealsProvider = HealthMealsProvider._();

/// What should be in Health Connect — this member's meals over this week and
/// last — and what cannot be sent. Null while who is signed in is not known,
/// or a week has not loaded: nothing is written or taken back on a guess.

final class HealthMealsProvider
    extends
        $FunctionalProvider<
          ({List<HealthMeal> meals, List<String> notSent})?,
          ({List<HealthMeal> meals, List<String> notSent})?,
          ({List<HealthMeal> meals, List<String> notSent})?
        >
    with $Provider<({List<HealthMeal> meals, List<String> notSent})?> {
  /// What should be in Health Connect — this member's meals over this week and
  /// last — and what cannot be sent. Null while who is signed in is not known,
  /// or a week has not loaded: nothing is written or taken back on a guess.
  const HealthMealsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'healthMealsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$healthMealsHash();

  @$internal
  @override
  $ProviderElement<({List<HealthMeal> meals, List<String> notSent})?>
  $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  ({List<HealthMeal> meals, List<String> notSent})? create(Ref ref) {
    return healthMeals(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    ({List<HealthMeal> meals, List<String> notSent})? value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<({List<HealthMeal> meals, List<String> notSent})?>(
            value,
          ),
    );
  }
}

String _$healthMealsHash() => r'c2d8dd48f223625e6b8716a65bdd17bc737f9650';

/// Writes the difference between [healthMeals] and what was last sent, a
/// moment after anything changes, while the switch is on. Watched from the
/// app's root for the app's whole life, so it runs whatever is on screen and
/// keeps everything it reads alive.

@ProviderFor(HealthSyncRunner)
const healthSyncRunnerProvider = HealthSyncRunnerProvider._();

/// Writes the difference between [healthMeals] and what was last sent, a
/// moment after anything changes, while the switch is on. Watched from the
/// app's root for the app's whole life, so it runs whatever is on screen and
/// keeps everything it reads alive.
final class HealthSyncRunnerProvider
    extends $NotifierProvider<HealthSyncRunner, void> {
  /// Writes the difference between [healthMeals] and what was last sent, a
  /// moment after anything changes, while the switch is on. Watched from the
  /// app's root for the app's whole life, so it runs whatever is on screen and
  /// keeps everything it reads alive.
  const HealthSyncRunnerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'healthSyncRunnerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$healthSyncRunnerHash();

  @$internal
  @override
  HealthSyncRunner create() => HealthSyncRunner();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$healthSyncRunnerHash() => r'f434fd56a37d8269b823a3387d05a4f42caef5e4';

/// Writes the difference between [healthMeals] and what was last sent, a
/// moment after anything changes, while the switch is on. Watched from the
/// app's root for the app's whole life, so it runs whatever is on screen and
/// keeps everything it reads alive.

abstract class _$HealthSyncRunner extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  void runBuild() {
    build();
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    element.handleValue(ref, null);
  }
}
