// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'week_view_models.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The wall clock, overridable in tests. Keep-alive because [Today] is.

@ProviderFor(clock)
const clockProvider = ClockProvider._();

/// The wall clock, overridable in tests. Keep-alive because [Today] is.

final class ClockProvider
    extends
        $FunctionalProvider<
          DateTime Function(),
          DateTime Function(),
          DateTime Function()
        >
    with $Provider<DateTime Function()> {
  /// The wall clock, overridable in tests. Keep-alive because [Today] is.
  const ClockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clockProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clockHash();

  @$internal
  @override
  $ProviderElement<DateTime Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DateTime Function() create(Ref ref) {
    return clock(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime Function()>(value),
    );
  }
}

String _$clockHash() => r'3f65ad34ac6fcd532de9004042bdf2ed2bd85b13';

/// The current local calendar day (midnight, date-only).
///
/// Re-fires from a [Timer] armed for the next local midnight and from an
/// [AppLifecycleListener] on resume, since a sleeping phone suspends timers.
/// Listeners are told only when the day changes.

@ProviderFor(Today)
const todayProvider = TodayProvider._();

/// The current local calendar day (midnight, date-only).
///
/// Re-fires from a [Timer] armed for the next local midnight and from an
/// [AppLifecycleListener] on resume, since a sleeping phone suspends timers.
/// Listeners are told only when the day changes.
final class TodayProvider extends $NotifierProvider<Today, DateTime> {
  /// The current local calendar day (midnight, date-only).
  ///
  /// Re-fires from a [Timer] armed for the next local midnight and from an
  /// [AppLifecycleListener] on resume, since a sleeping phone suspends timers.
  /// Listeners are told only when the day changes.
  const TodayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'todayProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$todayHash();

  @$internal
  @override
  Today create() => Today();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime>(value),
    );
  }
}

String _$todayHash() => r'e4062fd47b074ebf11218806499ea11996d0ab42';

/// The current local calendar day (midnight, date-only).
///
/// Re-fires from a [Timer] armed for the next local midnight and from an
/// [AppLifecycleListener] on resume, since a sleeping phone suspends timers.
/// Listeners are told only when the day changes.

abstract class _$Today extends $Notifier<DateTime> {
  DateTime build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<DateTime, DateTime>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DateTime, DateTime>,
              DateTime,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// The first day of the week containing [Today]. Moves at midnight; the week on
/// screen ([ViewedWeekStart]) does not.

@ProviderFor(currentWeekStart)
const currentWeekStartProvider = CurrentWeekStartProvider._();

/// The first day of the week containing [Today]. Moves at midnight; the week on
/// screen ([ViewedWeekStart]) does not.

final class CurrentWeekStartProvider
    extends $FunctionalProvider<DateTime, DateTime, DateTime>
    with $Provider<DateTime> {
  /// The first day of the week containing [Today]. Moves at midnight; the week on
  /// screen ([ViewedWeekStart]) does not.
  const CurrentWeekStartProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentWeekStartProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentWeekStartHash();

  @$internal
  @override
  $ProviderElement<DateTime> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DateTime create(Ref ref) {
    return currentWeekStart(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime>(value),
    );
  }
}

String _$currentWeekStartHash() => r'f90ef269509924d46414be561d6be2ab81e255c3';

/// The first day of the week on screen; Cook and Shop derive from it. Defaults
/// to the week containing today, and re-seats there when the household's
/// [WeekShape] changes.

@ProviderFor(ViewedWeekStart)
const viewedWeekStartProvider = ViewedWeekStartProvider._();

/// The first day of the week on screen; Cook and Shop derive from it. Defaults
/// to the week containing today, and re-seats there when the household's
/// [WeekShape] changes.
final class ViewedWeekStartProvider
    extends $NotifierProvider<ViewedWeekStart, DateTime> {
  /// The first day of the week on screen; Cook and Shop derive from it. Defaults
  /// to the week containing today, and re-seats there when the household's
  /// [WeekShape] changes.
  const ViewedWeekStartProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'viewedWeekStartProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$viewedWeekStartHash();

  @$internal
  @override
  ViewedWeekStart create() => ViewedWeekStart();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime>(value),
    );
  }
}

String _$viewedWeekStartHash() => r'6033277c1b4b16b4747df0761ee78702dae19961';

/// The first day of the week on screen; Cook and Shop derive from it. Defaults
/// to the week containing today, and re-seats there when the household's
/// [WeekShape] changes.

abstract class _$ViewedWeekStart extends $Notifier<DateTime> {
  DateTime build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<DateTime, DateTime>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DateTime, DateTime>,
              DateTime,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// The viewed week with its meals, or null while it has no row (seven empty
/// days).

@ProviderFor(viewedWeek)
const viewedWeekProvider = ViewedWeekProvider._();

/// The viewed week with its meals, or null while it has no row (seven empty
/// days).

final class ViewedWeekProvider
    extends
        $FunctionalProvider<AsyncValue<WeekPlan?>, WeekPlan?, Stream<WeekPlan?>>
    with $FutureModifier<WeekPlan?>, $StreamProvider<WeekPlan?> {
  /// The viewed week with its meals, or null while it has no row (seven empty
  /// days).
  const ViewedWeekProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'viewedWeekProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$viewedWeekHash();

  @$internal
  @override
  $StreamProviderElement<WeekPlan?> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<WeekPlan?> create(Ref ref) {
    return viewedWeek(ref);
  }
}

String _$viewedWeekHash() => r'50ef21a8dbfa2471f53e93b9489410ae325561d8';

/// The household eater roster, live.

@ProviderFor(members)
const membersProvider = MembersProvider._();

/// The household eater roster, live.

final class MembersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Member>>,
          List<Member>,
          Stream<List<Member>>
        >
    with $FutureModifier<List<Member>>, $StreamProvider<List<Member>> {
  /// The household eater roster, live.
  const MembersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'membersProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$membersHash();

  @$internal
  @override
  $StreamProviderElement<List<Member>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Member>> create(Ref ref) {
    return members(ref);
  }
}

String _$membersHash() => r'b6ee66656f2fed1b10e5fa8dbab1a42d1b36f9e7';

/// The most recent planned week before the viewed one — what "copy last week"
/// copies.

@ProviderFor(lastWeek)
const lastWeekProvider = LastWeekProvider._();

/// The most recent planned week before the viewed one — what "copy last week"
/// copies.

final class LastWeekProvider
    extends
        $FunctionalProvider<
          AsyncValue<WeekPlan?>,
          WeekPlan?,
          FutureOr<WeekPlan?>
        >
    with $FutureModifier<WeekPlan?>, $FutureProvider<WeekPlan?> {
  /// The most recent planned week before the viewed one — what "copy last week"
  /// copies.
  const LastWeekProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lastWeekProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lastWeekHash();

  @$internal
  @override
  $FutureProviderElement<WeekPlan?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<WeekPlan?> create(Ref ref) {
    return lastWeek(ref);
  }
}

String _$lastWeekHash() => r'479d2029464fa14268bc41325cff5c8127ec3e3f';

/// Most recent planned date per recipe, for the picker's "last planned".

@ProviderFor(lastPlannedByRecipe)
const lastPlannedByRecipeProvider = LastPlannedByRecipeProvider._();

/// Most recent planned date per recipe, for the picker's "last planned".

final class LastPlannedByRecipeProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, DateTime>>,
          Map<String, DateTime>,
          Stream<Map<String, DateTime>>
        >
    with
        $FutureModifier<Map<String, DateTime>>,
        $StreamProvider<Map<String, DateTime>> {
  /// Most recent planned date per recipe, for the picker's "last planned".
  const LastPlannedByRecipeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lastPlannedByRecipeProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lastPlannedByRecipeHash();

  @$internal
  @override
  $StreamProviderElement<Map<String, DateTime>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, DateTime>> create(Ref ref) {
    return lastPlannedByRecipe(ref);
  }
}

String _$lastPlannedByRecipeHash() =>
    r'4e7109b55cb289637548d7dd0a8b5a6682669edc';

/// Every override on the viewed week, keyed by recipe id.

@ProviderFor(viewedWeekOverrides)
const viewedWeekOverridesProvider = ViewedWeekOverridesProvider._();

/// Every override on the viewed week, keyed by recipe id.

final class ViewedWeekOverridesProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, List<LineOverride>>>,
          Map<String, List<LineOverride>>,
          Stream<Map<String, List<LineOverride>>>
        >
    with
        $FutureModifier<Map<String, List<LineOverride>>>,
        $StreamProvider<Map<String, List<LineOverride>>> {
  /// Every override on the viewed week, keyed by recipe id.
  const ViewedWeekOverridesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'viewedWeekOverridesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$viewedWeekOverridesHash();

  @$internal
  @override
  $StreamProviderElement<Map<String, List<LineOverride>>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, List<LineOverride>>> create(Ref ref) {
    return viewedWeekOverrides(ref);
  }
}

String _$viewedWeekOverridesHash() =>
    r'd3d4d070dc3274e8a5ddc4502f50f6f39e373e7b';

@ProviderFor(weekRecipePlacement)
const weekRecipePlacementProvider = WeekRecipePlacementFamily._();

final class WeekRecipePlacementProvider
    extends
        $FunctionalProvider<
          WeekRecipePlacement,
          WeekRecipePlacement,
          WeekRecipePlacement
        >
    with $Provider<WeekRecipePlacement> {
  const WeekRecipePlacementProvider._({
    required WeekRecipePlacementFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'weekRecipePlacementProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$weekRecipePlacementHash();

  @override
  String toString() {
    return r'weekRecipePlacementProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<WeekRecipePlacement> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WeekRecipePlacement create(Ref ref) {
    final argument = this.argument as (String, String);
    return weekRecipePlacement(ref, argument.$1, argument.$2);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WeekRecipePlacement value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WeekRecipePlacement>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WeekRecipePlacementProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$weekRecipePlacementHash() =>
    r'7c7b56e13dd1ee1e4eb8ff1483d5f0d1b3a1c0fa';

final class WeekRecipePlacementFamily extends $Family
    with $FunctionalFamilyOverride<WeekRecipePlacement, (String, String)> {
  const WeekRecipePlacementFamily._()
    : super(
        retry: null,
        name: r'weekRecipePlacementProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  WeekRecipePlacementProvider call(String recipeId, String weekKey) =>
      WeekRecipePlacementProvider._(argument: (recipeId, weekKey), from: this);

  @override
  String toString() => r'weekRecipePlacementProvider';
}

/// The week [weekKey] names, with its meals.

@ProviderFor(weekPlanFor)
const weekPlanForProvider = WeekPlanForFamily._();

/// The week [weekKey] names, with its meals.

final class WeekPlanForProvider
    extends
        $FunctionalProvider<AsyncValue<WeekPlan?>, WeekPlan?, Stream<WeekPlan?>>
    with $FutureModifier<WeekPlan?>, $StreamProvider<WeekPlan?> {
  /// The week [weekKey] names, with its meals.
  const WeekPlanForProvider._({
    required WeekPlanForFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'weekPlanForProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$weekPlanForHash();

  @override
  String toString() {
    return r'weekPlanForProvider'
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
    return weekPlanFor(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is WeekPlanForProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$weekPlanForHash() => r'feff1a1d7e4bb252111f99ece37797fde6945a9b';

/// The week [weekKey] names, with its meals.

final class WeekPlanForFamily extends $Family
    with $FunctionalFamilyOverride<Stream<WeekPlan?>, String> {
  const WeekPlanForFamily._()
    : super(
        retry: null,
        name: r'weekPlanForProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The week [weekKey] names, with its meals.

  WeekPlanForProvider call(String weekKey) =>
      WeekPlanForProvider._(argument: weekKey, from: this);

  @override
  String toString() => r'weekPlanForProvider';
}

/// That same week's overrides, keyed by recipe id.

@ProviderFor(weekOverridesFor)
const weekOverridesForProvider = WeekOverridesForFamily._();

/// That same week's overrides, keyed by recipe id.

final class WeekOverridesForProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, List<LineOverride>>>,
          Map<String, List<LineOverride>>,
          Stream<Map<String, List<LineOverride>>>
        >
    with
        $FutureModifier<Map<String, List<LineOverride>>>,
        $StreamProvider<Map<String, List<LineOverride>>> {
  /// That same week's overrides, keyed by recipe id.
  const WeekOverridesForProvider._({
    required WeekOverridesForFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'weekOverridesForProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$weekOverridesForHash();

  @override
  String toString() {
    return r'weekOverridesForProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Map<String, List<LineOverride>>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, List<LineOverride>>> create(Ref ref) {
    final argument = this.argument as String;
    return weekOverridesFor(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is WeekOverridesForProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$weekOverridesForHash() => r'4bd5cee3bba0bcd05efaf56f9c4aab1ea6bd5e95';

/// That same week's overrides, keyed by recipe id.

final class WeekOverridesForFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<Map<String, List<LineOverride>>>,
          String
        > {
  const WeekOverridesForFamily._()
    : super(
        retry: null,
        name: r'weekOverridesForProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// That same week's overrides, keyed by recipe id.

  WeekOverridesForProvider call(String weekKey) =>
      WeekOverridesForProvider._(argument: weekKey, from: this);

  @override
  String toString() => r'weekOverridesForProvider';
}

/// [variantRecipeMacros] for the week [weekKey] names. A recipe the week does
/// not vary is absent.

@ProviderFor(weekVariantMacrosFor)
const weekVariantMacrosForProvider = WeekVariantMacrosForFamily._();

/// [variantRecipeMacros] for the week [weekKey] names. A recipe the week does
/// not vary is absent.

final class WeekVariantMacrosForProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, RecipeMacroSummary>>,
          Map<String, RecipeMacroSummary>,
          Stream<Map<String, RecipeMacroSummary>>
        >
    with
        $FutureModifier<Map<String, RecipeMacroSummary>>,
        $StreamProvider<Map<String, RecipeMacroSummary>> {
  /// [variantRecipeMacros] for the week [weekKey] names. A recipe the week does
  /// not vary is absent.
  const WeekVariantMacrosForProvider._({
    required WeekVariantMacrosForFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'weekVariantMacrosForProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$weekVariantMacrosForHash();

  @override
  String toString() {
    return r'weekVariantMacrosForProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Map<String, RecipeMacroSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, RecipeMacroSummary>> create(Ref ref) {
    final argument = this.argument as String;
    return weekVariantMacrosFor(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is WeekVariantMacrosForProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$weekVariantMacrosForHash() =>
    r'f13c84664dd41e7bbf0f07ac82f3c6e53cc6f43d';

/// [variantRecipeMacros] for the week [weekKey] names. A recipe the week does
/// not vary is absent.

final class WeekVariantMacrosForFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<Map<String, RecipeMacroSummary>>,
          String
        > {
  const WeekVariantMacrosForFamily._()
    : super(
        retry: null,
        name: r'weekVariantMacrosForProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// [variantRecipeMacros] for the week [weekKey] names. A recipe the week does
  /// not vary is absent.

  WeekVariantMacrosForProvider call(String weekKey) =>
      WeekVariantMacrosForProvider._(argument: weekKey, from: this);

  @override
  String toString() => r'weekVariantMacrosForProvider';
}

/// The same for cost (ADR-0017).

@ProviderFor(weekVariantCostsFor)
const weekVariantCostsForProvider = WeekVariantCostsForFamily._();

/// The same for cost (ADR-0017).

final class WeekVariantCostsForProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, RecipeCostSummary>>,
          Map<String, RecipeCostSummary>,
          Stream<Map<String, RecipeCostSummary>>
        >
    with
        $FutureModifier<Map<String, RecipeCostSummary>>,
        $StreamProvider<Map<String, RecipeCostSummary>> {
  /// The same for cost (ADR-0017).
  const WeekVariantCostsForProvider._({
    required WeekVariantCostsForFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'weekVariantCostsForProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$weekVariantCostsForHash();

  @override
  String toString() {
    return r'weekVariantCostsForProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Map<String, RecipeCostSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, RecipeCostSummary>> create(Ref ref) {
    final argument = this.argument as String;
    return weekVariantCostsFor(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is WeekVariantCostsForProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$weekVariantCostsForHash() =>
    r'752a5c75f744ba0da433a75a1d762d1b7d68fc19';

/// The same for cost (ADR-0017).

final class WeekVariantCostsForFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<Map<String, RecipeCostSummary>>,
          String
        > {
  const WeekVariantCostsForFamily._()
    : super(
        retry: null,
        name: r'weekVariantCostsForProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The same for cost (ADR-0017).

  WeekVariantCostsForProvider call(String weekKey) =>
      WeekVariantCostsForProvider._(argument: weekKey, from: this);

  @override
  String toString() => r'weekVariantCostsForProvider';
}

/// Per-recipe cost summaries for the viewed week: the Library's figure,
/// overlaid by the week's own where it varies the recipe.

@ProviderFor(weekRecipeCosts)
const weekRecipeCostsProvider = WeekRecipeCostsProvider._();

/// Per-recipe cost summaries for the viewed week: the Library's figure,
/// overlaid by the week's own where it varies the recipe.

final class WeekRecipeCostsProvider
    extends
        $FunctionalProvider<
          Map<String, RecipeCostSummary>,
          Map<String, RecipeCostSummary>,
          Map<String, RecipeCostSummary>
        >
    with $Provider<Map<String, RecipeCostSummary>> {
  /// Per-recipe cost summaries for the viewed week: the Library's figure,
  /// overlaid by the week's own where it varies the recipe.
  const WeekRecipeCostsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'weekRecipeCostsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$weekRecipeCostsHash();

  @$internal
  @override
  $ProviderElement<Map<String, RecipeCostSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, RecipeCostSummary> create(Ref ref) {
    return weekRecipeCosts(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, RecipeCostSummary> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, RecipeCostSummary>>(
        value,
      ),
    );
  }
}

String _$weekRecipeCostsHash() => r'b72a44651663491449825a883c962adf449f494b';

/// The re-costed figures for the recipes the viewed week varies.

@ProviderFor(variantRecipeCosts)
const variantRecipeCostsProvider = VariantRecipeCostsProvider._();

/// The re-costed figures for the recipes the viewed week varies.

final class VariantRecipeCostsProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, RecipeCostSummary>>,
          Map<String, RecipeCostSummary>,
          Stream<Map<String, RecipeCostSummary>>
        >
    with
        $FutureModifier<Map<String, RecipeCostSummary>>,
        $StreamProvider<Map<String, RecipeCostSummary>> {
  /// The re-costed figures for the recipes the viewed week varies.
  const VariantRecipeCostsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'variantRecipeCostsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$variantRecipeCostsHash();

  @$internal
  @override
  $StreamProviderElement<Map<String, RecipeCostSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, RecipeCostSummary>> create(Ref ref) {
    return variantRecipeCosts(ref);
  }
}

String _$variantRecipeCostsHash() =>
    r'cf3ad59962a25379df74a9faf610af8b5d500c0b';

/// What the viewed week costs to cook under [lens], over the same entries and
/// portions as [weekMacros]. Recipes are priced from their summaries, bare
/// ingredients from the latest vocabulary prices.

@ProviderFor(weekCost)
const weekCostProvider = WeekCostFamily._();

/// What the viewed week costs to cook under [lens], over the same entries and
/// portions as [weekMacros]. Recipes are priced from their summaries, bare
/// ingredients from the latest vocabulary prices.

final class WeekCostProvider
    extends $FunctionalProvider<PlannedCost, PlannedCost, PlannedCost>
    with $Provider<PlannedCost> {
  /// What the viewed week costs to cook under [lens], over the same entries and
  /// portions as [weekMacros]. Recipes are priced from their summaries, bare
  /// ingredients from the latest vocabulary prices.
  const WeekCostProvider._({
    required WeekCostFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'weekCostProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$weekCostHash();

  @override
  String toString() {
    return r'weekCostProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<PlannedCost> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PlannedCost create(Ref ref) {
    final argument = this.argument as String?;
    return weekCost(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlannedCost value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlannedCost>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WeekCostProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$weekCostHash() => r'7d2f0dd2743245d426b74a761a70736004e3d337';

/// What the viewed week costs to cook under [lens], over the same entries and
/// portions as [weekMacros]. Recipes are priced from their summaries, bare
/// ingredients from the latest vocabulary prices.

final class WeekCostFamily extends $Family
    with $FunctionalFamilyOverride<PlannedCost, String?> {
  const WeekCostFamily._()
    : super(
        retry: null,
        name: r'weekCostProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// What the viewed week costs to cook under [lens], over the same entries and
  /// portions as [weekMacros]. Recipes are priced from their summaries, bare
  /// ingredients from the latest vocabulary prices.

  WeekCostProvider call(String? lens) =>
      WeekCostProvider._(argument: lens, from: this);

  @override
  String toString() => r'weekCostProvider';
}

/// Per-recipe macro summaries for the viewed week, by recipe id: the Library's
/// figure, re-summed over the week's effective lines where it varies the
/// recipe.

@ProviderFor(weekRecipeMacros)
const weekRecipeMacrosProvider = WeekRecipeMacrosProvider._();

/// Per-recipe macro summaries for the viewed week, by recipe id: the Library's
/// figure, re-summed over the week's effective lines where it varies the
/// recipe.

final class WeekRecipeMacrosProvider
    extends
        $FunctionalProvider<
          Map<String, RecipeMacroSummary>,
          Map<String, RecipeMacroSummary>,
          Map<String, RecipeMacroSummary>
        >
    with $Provider<Map<String, RecipeMacroSummary>> {
  /// Per-recipe macro summaries for the viewed week, by recipe id: the Library's
  /// figure, re-summed over the week's effective lines where it varies the
  /// recipe.
  const WeekRecipeMacrosProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'weekRecipeMacrosProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$weekRecipeMacrosHash();

  @$internal
  @override
  $ProviderElement<Map<String, RecipeMacroSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, RecipeMacroSummary> create(Ref ref) {
    return weekRecipeMacros(ref);
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
}

String _$weekRecipeMacrosHash() => r'1dadcaa8c3e79ed4381c5b4fc1e9541f50e84eca';

/// The re-summed figures for the recipes the viewed week varies.

@ProviderFor(variantRecipeMacros)
const variantRecipeMacrosProvider = VariantRecipeMacrosProvider._();

/// The re-summed figures for the recipes the viewed week varies.

final class VariantRecipeMacrosProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, RecipeMacroSummary>>,
          Map<String, RecipeMacroSummary>,
          Stream<Map<String, RecipeMacroSummary>>
        >
    with
        $FutureModifier<Map<String, RecipeMacroSummary>>,
        $StreamProvider<Map<String, RecipeMacroSummary>> {
  /// The re-summed figures for the recipes the viewed week varies.
  const VariantRecipeMacrosProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'variantRecipeMacrosProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$variantRecipeMacrosHash();

  @$internal
  @override
  $StreamProviderElement<Map<String, RecipeMacroSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, RecipeMacroSummary>> create(Ref ref) {
    return variantRecipeMacros(ref);
  }
}

String _$variantRecipeMacrosHash() =>
    r'e6ddb6b66e2e9c6151a9146f1d16399466c9c103';

/// What the last copy carried and left behind, held for the week it is about. A
/// state rather than a toast, so it stays until the week moves.

@ProviderFor(LastCopyReport)
const lastCopyReportProvider = LastCopyReportProvider._();

/// What the last copy carried and left behind, held for the week it is about. A
/// state rather than a toast, so it stays until the week moves.
final class LastCopyReportProvider
    extends
        $NotifierProvider<
          LastCopyReport,
          ({CopyLastWeekResult result, DateTime weekStart})?
        > {
  /// What the last copy carried and left behind, held for the week it is about. A
  /// state rather than a toast, so it stays until the week moves.
  const LastCopyReportProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lastCopyReportProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lastCopyReportHash();

  @$internal
  @override
  LastCopyReport create() => LastCopyReport();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    ({CopyLastWeekResult result, DateTime weekStart})? value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<
            ({CopyLastWeekResult result, DateTime weekStart})?
          >(value),
    );
  }
}

String _$lastCopyReportHash() => r'608644f5bdeaa870518ce8fcad952377f6e244ec';

/// What the last copy carried and left behind, held for the week it is about. A
/// state rather than a toast, so it stays until the week moves.

abstract class _$LastCopyReport
    extends $Notifier<({CopyLastWeekResult result, DateTime weekStart})?> {
  ({CopyLastWeekResult result, DateTime weekStart})? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref
            as $Ref<
              ({CopyLastWeekResult result, DateTime weekStart})?,
              ({CopyLastWeekResult result, DateTime weekStart})?
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                ({CopyLastWeekResult result, DateTime weekStart})?,
                ({CopyLastWeekResult result, DateTime weekStart})?
              >,
              ({CopyLastWeekResult result, DateTime weekStart})?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// The roster keyed by id.

@ProviderFor(membersById)
const membersByIdProvider = MembersByIdProvider._();

/// The roster keyed by id.

final class MembersByIdProvider
    extends
        $FunctionalProvider<
          Map<String, Member>,
          Map<String, Member>,
          Map<String, Member>
        >
    with $Provider<Map<String, Member>> {
  /// The roster keyed by id.
  const MembersByIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'membersByIdProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$membersByIdHash();

  @$internal
  @override
  $ProviderElement<Map<String, Member>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, Member> create(Ref ref) {
    return membersById(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, Member> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, Member>>(value),
    );
  }
}

String _$membersByIdHash() => r'e952de3b656972111633e5164c675f4d045e7674';

/// The viewed week's macros under [lens] (null = Everyone).

@ProviderFor(weekMacros)
const weekMacrosProvider = WeekMacrosFamily._();

/// The viewed week's macros under [lens] (null = Everyone).

final class WeekMacrosProvider
    extends $FunctionalProvider<MealSetMacros, MealSetMacros, MealSetMacros>
    with $Provider<MealSetMacros> {
  /// The viewed week's macros under [lens] (null = Everyone).
  const WeekMacrosProvider._({
    required WeekMacrosFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'weekMacrosProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$weekMacrosHash();

  @override
  String toString() {
    return r'weekMacrosProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<MealSetMacros> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MealSetMacros create(Ref ref) {
    final argument = this.argument as String?;
    return weekMacros(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MealSetMacros value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MealSetMacros>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WeekMacrosProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$weekMacrosHash() => r'5af7d3bbf0074e72f8990e0feaf2710491279159';

/// The viewed week's macros under [lens] (null = Everyone).

final class WeekMacrosFamily extends $Family
    with $FunctionalFamilyOverride<MealSetMacros, String?> {
  const WeekMacrosFamily._()
    : super(
        retry: null,
        name: r'weekMacrosProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The viewed week's macros under [lens] (null = Everyone).

  WeekMacrosProvider call(String? lens) =>
      WeekMacrosProvider._(argument: lens, from: this);

  @override
  String toString() => r'weekMacrosProvider';
}

/// One meal's macros under [lens], as served. Keyed by entry id so it follows
/// the live week; an id the week no longer has reads as an empty set.

@ProviderFor(mealMacros)
const mealMacrosProvider = MealMacrosFamily._();

/// One meal's macros under [lens], as served. Keyed by entry id so it follows
/// the live week; an id the week no longer has reads as an empty set.

final class MealMacrosProvider
    extends $FunctionalProvider<MealSetMacros, MealSetMacros, MealSetMacros>
    with $Provider<MealSetMacros> {
  /// One meal's macros under [lens], as served. Keyed by entry id so it follows
  /// the live week; an id the week no longer has reads as an empty set.
  const MealMacrosProvider._({
    required MealMacrosFamily super.from,
    required (String, String?) super.argument,
  }) : super(
         retry: null,
         name: r'mealMacrosProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mealMacrosHash();

  @override
  String toString() {
    return r'mealMacrosProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<MealSetMacros> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MealSetMacros create(Ref ref) {
    final argument = this.argument as (String, String?);
    return mealMacros(ref, argument.$1, argument.$2);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MealSetMacros value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MealSetMacros>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MealMacrosProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mealMacrosHash() => r'f0fa893ccf164c5e79b92b5ab95e617aa3ed3eb2';

/// One meal's macros under [lens], as served. Keyed by entry id so it follows
/// the live week; an id the week no longer has reads as an empty set.

final class MealMacrosFamily extends $Family
    with $FunctionalFamilyOverride<MealSetMacros, (String, String?)> {
  const MealMacrosFamily._()
    : super(
        retry: null,
        name: r'mealMacrosProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One meal's macros under [lens], as served. Keyed by entry id so it follows
  /// the live week; an id the week no longer has reads as an empty set.

  MealMacrosProvider call(String entryId, String? lens) =>
      MealMacrosProvider._(argument: (entryId, lens), from: this);

  @override
  String toString() => r'mealMacrosProvider';
}

/// One day's macros under [lens], from the same function as the week's so the
/// week is never a sum of rounded days.

@ProviderFor(dayMacros)
const dayMacrosProvider = DayMacrosFamily._();

/// One day's macros under [lens], from the same function as the week's so the
/// week is never a sum of rounded days.

final class DayMacrosProvider
    extends $FunctionalProvider<MealSetMacros, MealSetMacros, MealSetMacros>
    with $Provider<MealSetMacros> {
  /// One day's macros under [lens], from the same function as the week's so the
  /// week is never a sum of rounded days.
  const DayMacrosProvider._({
    required DayMacrosFamily super.from,
    required (int, String?) super.argument,
  }) : super(
         retry: null,
         name: r'dayMacrosProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$dayMacrosHash();

  @override
  String toString() {
    return r'dayMacrosProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<MealSetMacros> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MealSetMacros create(Ref ref) {
    final argument = this.argument as (int, String?);
    return dayMacros(ref, argument.$1, argument.$2);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MealSetMacros value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MealSetMacros>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DayMacrosProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$dayMacrosHash() => r'96e3a0a1cb4d45a3ac815badb9f5058bdf2b94de';

/// One day's macros under [lens], from the same function as the week's so the
/// week is never a sum of rounded days.

final class DayMacrosFamily extends $Family
    with $FunctionalFamilyOverride<MealSetMacros, (int, String?)> {
  const DayMacrosFamily._()
    : super(
        retry: null,
        name: r'dayMacrosProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One day's macros under [lens], from the same function as the week's so the
  /// week is never a sum of rounded days.

  DayMacrosProvider call(int dayOfWeek, String? lens) =>
      DayMacrosProvider._(argument: (dayOfWeek, lens), from: this);

  @override
  String toString() => r'dayMacrosProvider';
}
