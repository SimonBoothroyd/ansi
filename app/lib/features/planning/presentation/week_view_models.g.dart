// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'week_view_models.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The wall clock, as a seam: production reads [DateTime.now]; a test
/// overrides this with a fixed or scripted clock and drives [Today] across a
/// midnight it chooses. Keep-alive because [Today] is, and a keep-alive
/// provider may only depend on keep-alive providers (riverpod_lint).

@ProviderFor(clock)
const clockProvider = ClockProvider._();

/// The wall clock, as a seam: production reads [DateTime.now]; a test
/// overrides this with a fixed or scripted clock and drives [Today] across a
/// midnight it chooses. Keep-alive because [Today] is, and a keep-alive
/// provider may only depend on keep-alive providers (riverpod_lint).

final class ClockProvider
    extends
        $FunctionalProvider<
          DateTime Function(),
          DateTime Function(),
          DateTime Function()
        >
    with $Provider<DateTime Function()> {
  /// The wall clock, as a seam: production reads [DateTime.now]; a test
  /// overrides this with a fixed or scripted clock and drives [Today] across a
  /// midnight it chooses. Keep-alive because [Today] is, and a keep-alive
  /// provider may only depend on keep-alive providers (riverpod_lint).
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

/// The current LOCAL calendar day — midnight, local time, date-only.
///
/// A `DateTime.now()` read once in a provider is stale from midnight until
/// something else rebuilds the tree, which the TODAY pill made visible. This
/// re-fires twice over: one [Timer] armed for the next local midnight, whose
/// callback re-arms it (a 23- or 25-hour DST day is simply a different wait),
/// and an [AppLifecycleListener] for resume, because a phone asleep in a
/// pocket suspends timers and may wake past several midnights. Keep-alive so
/// the timer outlives the screens that read it; both hooks are released in
/// `onDispose`, which also runs if [clock] is ever overridden mid-flight.
///
/// The state is a value, so listeners are told only when the day actually
/// changes — a resume at 3 pm on the same day is silent.

@ProviderFor(Today)
const todayProvider = TodayProvider._();

/// The current LOCAL calendar day — midnight, local time, date-only.
///
/// A `DateTime.now()` read once in a provider is stale from midnight until
/// something else rebuilds the tree, which the TODAY pill made visible. This
/// re-fires twice over: one [Timer] armed for the next local midnight, whose
/// callback re-arms it (a 23- or 25-hour DST day is simply a different wait),
/// and an [AppLifecycleListener] for resume, because a phone asleep in a
/// pocket suspends timers and may wake past several midnights. Keep-alive so
/// the timer outlives the screens that read it; both hooks are released in
/// `onDispose`, which also runs if [clock] is ever overridden mid-flight.
///
/// The state is a value, so listeners are told only when the day actually
/// changes — a resume at 3 pm on the same day is silent.
final class TodayProvider extends $NotifierProvider<Today, DateTime> {
  /// The current LOCAL calendar day — midnight, local time, date-only.
  ///
  /// A `DateTime.now()` read once in a provider is stale from midnight until
  /// something else rebuilds the tree, which the TODAY pill made visible. This
  /// re-fires twice over: one [Timer] armed for the next local midnight, whose
  /// callback re-arms it (a 23- or 25-hour DST day is simply a different wait),
  /// and an [AppLifecycleListener] for resume, because a phone asleep in a
  /// pocket suspends timers and may wake past several midnights. Keep-alive so
  /// the timer outlives the screens that read it; both hooks are released in
  /// `onDispose`, which also runs if [clock] is ever overridden mid-flight.
  ///
  /// The state is a value, so listeners are told only when the day actually
  /// changes — a resume at 3 pm on the same day is silent.
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

/// The current LOCAL calendar day — midnight, local time, date-only.
///
/// A `DateTime.now()` read once in a provider is stale from midnight until
/// something else rebuilds the tree, which the TODAY pill made visible. This
/// re-fires twice over: one [Timer] armed for the next local midnight, whose
/// callback re-arms it (a 23- or 25-hour DST day is simply a different wait),
/// and an [AppLifecycleListener] for resume, because a phone asleep in a
/// pocket suspends timers and may wake past several midnights. Keep-alive so
/// the timer outlives the screens that read it; both hooks are released in
/// `onDispose`, which also runs if [clock] is ever overridden mid-flight.
///
/// The state is a value, so listeners are told only when the day actually
/// changes — a resume at 3 pm on the same day is silent.

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

/// The Monday of the week containing [Today]. Moves with it, so it is right
/// across midnight and after a resume; the week on screen does not — that is
/// [ViewedWeekStart]'s job, and it is deliberately left alone.

@ProviderFor(currentWeekStart)
const currentWeekStartProvider = CurrentWeekStartProvider._();

/// The Monday of the week containing [Today]. Moves with it, so it is right
/// across midnight and after a resume; the week on screen does not — that is
/// [ViewedWeekStart]'s job, and it is deliberately left alone.

final class CurrentWeekStartProvider
    extends $FunctionalProvider<DateTime, DateTime, DateTime>
    with $Provider<DateTime> {
  /// The Monday of the week containing [Today]. Moves with it, so it is right
  /// across midnight and after a resume; the week on screen does not — that is
  /// [ViewedWeekStart]'s job, and it is deliberately left alone.
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

String _$currentWeekStartHash() => r'3d665c5bcd9d6937af169aec303fa09fb8e0bedd';

/// The Monday of the week on screen. Defaults to the week containing today;
/// the header switcher moves it and Cook/Shop derive from it (D3).

@ProviderFor(ViewedWeekStart)
const viewedWeekStartProvider = ViewedWeekStartProvider._();

/// The Monday of the week on screen. Defaults to the week containing today;
/// the header switcher moves it and Cook/Shop derive from it (D3).
final class ViewedWeekStartProvider
    extends $NotifierProvider<ViewedWeekStart, DateTime> {
  /// The Monday of the week on screen. Defaults to the week containing today;
  /// the header switcher moves it and Cook/Shop derive from it (D3).
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

String _$viewedWeekStartHash() => r'027189b49e1eaf402dce1c0eb5d5aaacd6cbe125';

/// The Monday of the week on screen. Defaults to the week containing today;
/// the header switcher moves it and Cook/Shop derive from it (D3).

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

/// The viewed week with its meals, or null while it has no row yet — which
/// means "seven empty days", not "a different screen" (D5).

@ProviderFor(viewedWeek)
const viewedWeekProvider = ViewedWeekProvider._();

/// The viewed week with its meals, or null while it has no row yet — which
/// means "seven empty days", not "a different screen" (D5).

final class ViewedWeekProvider
    extends
        $FunctionalProvider<AsyncValue<WeekPlan?>, WeekPlan?, Stream<WeekPlan?>>
    with $FutureModifier<WeekPlan?>, $StreamProvider<WeekPlan?> {
  /// The viewed week with its meals, or null while it has no row yet — which
  /// means "seven empty days", not "a different screen" (D5).
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

/// The household eater roster, live — a portion factor set on either phone
/// reaches every Portions row and the Household sheet as it lands.

@ProviderFor(members)
const membersProvider = MembersProvider._();

/// The household eater roster, live — a portion factor set on either phone
/// reaches every Portions row and the Household sheet as it lands.

final class MembersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Member>>,
          List<Member>,
          Stream<List<Member>>
        >
    with $FutureModifier<List<Member>>, $StreamProvider<List<Member>> {
  /// The household eater roster, live — a portion factor set on either phone
  /// reaches every Portions row and the Household sheet as it lands.
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

/// The most recent planned week before the VIEWED one — what "copy last week"
/// would copy, so it is relative to the week you are standing on.

@ProviderFor(lastWeek)
const lastWeekProvider = LastWeekProvider._();

/// The most recent planned week before the VIEWED one — what "copy last week"
/// would copy, so it is relative to the week you are standing on.

final class LastWeekProvider
    extends
        $FunctionalProvider<
          AsyncValue<WeekPlan?>,
          WeekPlan?,
          FutureOr<WeekPlan?>
        >
    with $FutureModifier<WeekPlan?>, $FutureProvider<WeekPlan?> {
  /// The most recent planned week before the VIEWED one — what "copy last week"
  /// would copy, so it is relative to the week you are standing on.
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

/// Most recent planned date per recipe, across every week — the picker
/// rows' "last planned" recency (7.7).

@ProviderFor(lastPlannedByRecipe)
const lastPlannedByRecipeProvider = LastPlannedByRecipeProvider._();

/// Most recent planned date per recipe, across every week — the picker
/// rows' "last planned" recency (7.7).

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
  /// Most recent planned date per recipe, across every week — the picker
  /// rows' "last planned" recency (7.7).
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

/// Every override on the viewed week, keyed by recipe id — what the dish
/// row's "edited for this week" mark and the cook card's sub-line read, and
/// what the editor's own draft starts from.

@ProviderFor(viewedWeekOverrides)
const viewedWeekOverridesProvider = ViewedWeekOverridesProvider._();

/// Every override on the viewed week, keyed by recipe id — what the dish
/// row's "edited for this week" mark and the cook card's sub-line read, and
/// what the editor's own draft starts from.

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
  /// Every override on the viewed week, keyed by recipe id — what the dish
  /// row's "edited for this week" mark and the cook card's sub-line read, and
  /// what the editor's own draft starts from.
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
    r'59f2525a9cf8129e44dd6a43efcff55d873c79ce';

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

/// The week [weekKey] names, with its meals — a sibling of [viewedWeek] keyed
/// by the link rather than by what is on screen.

@ProviderFor(weekPlanFor)
const weekPlanForProvider = WeekPlanForFamily._();

/// The week [weekKey] names, with its meals — a sibling of [viewedWeek] keyed
/// by the link rather than by what is on screen.

final class WeekPlanForProvider
    extends
        $FunctionalProvider<AsyncValue<WeekPlan?>, WeekPlan?, Stream<WeekPlan?>>
    with $FutureModifier<WeekPlan?>, $StreamProvider<WeekPlan?> {
  /// The week [weekKey] names, with its meals — a sibling of [viewedWeek] keyed
  /// by the link rather than by what is on screen.
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

String _$weekPlanForHash() => r'f47025e4ea7022c50416f643ba3731bed97246d7';

/// The week [weekKey] names, with its meals — a sibling of [viewedWeek] keyed
/// by the link rather than by what is on screen.

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

  /// The week [weekKey] names, with its meals — a sibling of [viewedWeek] keyed
  /// by the link rather than by what is on screen.

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

String _$weekOverridesForHash() => r'4adc11a8c655c9f068ef2616864485034100c617';

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

/// The re-summed figures for the recipes the week [weekKey] names varies — the
/// sibling of [variantRecipeMacros] keyed by the link rather than by the week
/// on screen, for the recipe page opened from a week that plans it.
///
/// A recipe the week does not vary is absent, and its reader falls back to the
/// Library's figure, which is exactly right for it.

@ProviderFor(weekVariantMacrosFor)
const weekVariantMacrosForProvider = WeekVariantMacrosForFamily._();

/// The re-summed figures for the recipes the week [weekKey] names varies — the
/// sibling of [variantRecipeMacros] keyed by the link rather than by the week
/// on screen, for the recipe page opened from a week that plans it.
///
/// A recipe the week does not vary is absent, and its reader falls back to the
/// Library's figure, which is exactly right for it.

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
  /// The re-summed figures for the recipes the week [weekKey] names varies — the
  /// sibling of [variantRecipeMacros] keyed by the link rather than by the week
  /// on screen, for the recipe page opened from a week that plans it.
  ///
  /// A recipe the week does not vary is absent, and its reader falls back to the
  /// Library's figure, which is exactly right for it.
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
    r'35262d63e726d3d93ce0d281b468973c87fdb4a4';

/// The re-summed figures for the recipes the week [weekKey] names varies — the
/// sibling of [variantRecipeMacros] keyed by the link rather than by the week
/// on screen, for the recipe page opened from a week that plans it.
///
/// A recipe the week does not vary is absent, and its reader falls back to the
/// Library's figure, which is exactly right for it.

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

  /// The re-summed figures for the recipes the week [weekKey] names varies — the
  /// sibling of [variantRecipeMacros] keyed by the link rather than by the week
  /// on screen, for the recipe page opened from a week that plans it.
  ///
  /// A recipe the week does not vary is absent, and its reader falls back to the
  /// Library's figure, which is exactly right for it.

  WeekVariantMacrosForProvider call(String weekKey) =>
      WeekVariantMacrosForProvider._(argument: weekKey, from: this);

  @override
  String toString() => r'weekVariantMacrosForProvider';
}

/// Per-recipe macro summaries **for the viewed week**, indexed by recipe id.
///
/// The Library's figure underneath, the week's own on top. A recipe the week
/// does not vary is still exactly what `watchRecipes` computed — the same
/// figure the picker rows and the recipe panel show — and a recipe it does
/// vary is re-summed over the week's effective lines, because the Library's
/// number is wrong for this week and right everywhere else.

@ProviderFor(weekRecipeMacros)
const weekRecipeMacrosProvider = WeekRecipeMacrosProvider._();

/// Per-recipe macro summaries **for the viewed week**, indexed by recipe id.
///
/// The Library's figure underneath, the week's own on top. A recipe the week
/// does not vary is still exactly what `watchRecipes` computed — the same
/// figure the picker rows and the recipe panel show — and a recipe it does
/// vary is re-summed over the week's effective lines, because the Library's
/// number is wrong for this week and right everywhere else.

final class WeekRecipeMacrosProvider
    extends
        $FunctionalProvider<
          Map<String, RecipeMacroSummary>,
          Map<String, RecipeMacroSummary>,
          Map<String, RecipeMacroSummary>
        >
    with $Provider<Map<String, RecipeMacroSummary>> {
  /// Per-recipe macro summaries **for the viewed week**, indexed by recipe id.
  ///
  /// The Library's figure underneath, the week's own on top. A recipe the week
  /// does not vary is still exactly what `watchRecipes` computed — the same
  /// figure the picker rows and the recipe panel show — and a recipe it does
  /// vary is re-summed over the week's effective lines, because the Library's
  /// number is wrong for this week and right everywhere else.
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

/// The re-summed figures for the recipes the viewed week varies — usually
/// none, in which case the map above is the Library's, untouched.

@ProviderFor(variantRecipeMacros)
const variantRecipeMacrosProvider = VariantRecipeMacrosProvider._();

/// The re-summed figures for the recipes the viewed week varies — usually
/// none, in which case the map above is the Library's, untouched.

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
  /// The re-summed figures for the recipes the viewed week varies — usually
  /// none, in which case the map above is the Library's, untouched.
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

/// What the last copy carried, and what it left behind — held for the week it
/// is about, so moving off that week and back does not re-announce it.
///
/// A **state**, not a toast: it reports a part of an act that did not happen,
/// it stays true until the person does something about it, and it names rows
/// they may want to open. Cleared by reading it once the week moves.

@ProviderFor(LastCopyReport)
const lastCopyReportProvider = LastCopyReportProvider._();

/// What the last copy carried, and what it left behind — held for the week it
/// is about, so moving off that week and back does not re-announce it.
///
/// A **state**, not a toast: it reports a part of an act that did not happen,
/// it stays true until the person does something about it, and it names rows
/// they may want to open. Cleared by reading it once the week moves.
final class LastCopyReportProvider
    extends
        $NotifierProvider<
          LastCopyReport,
          ({CopyLastWeekResult result, DateTime weekStart})?
        > {
  /// What the last copy carried, and what it left behind — held for the week it
  /// is about, so moving off that week and back does not re-announce it.
  ///
  /// A **state**, not a toast: it reports a part of an act that did not happen,
  /// it stays true until the person does something about it, and it names rows
  /// they may want to open. Cleared by reading it once the week moves.
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

/// What the last copy carried, and what it left behind — held for the week it
/// is about, so moving off that week and back does not re-announce it.
///
/// A **state**, not a toast: it reports a part of an act that did not happen,
/// it stays true until the person does something about it, and it names rows
/// they may want to open. Cleared by reading it once the week moves.

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

/// The roster keyed by id — the portion factors every demand and lens share is
/// weighted by.

@ProviderFor(membersById)
const membersByIdProvider = MembersByIdProvider._();

/// The roster keyed by id — the portion factors every demand and lens share is
/// weighted by.

final class MembersByIdProvider
    extends
        $FunctionalProvider<
          Map<String, Member>,
          Map<String, Member>,
          Map<String, Member>
        >
    with $Provider<Map<String, Member>> {
  /// The roster keyed by id — the portion factors every demand and lens share is
  /// weighted by.
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

/// The viewed week's macros under [lens] (null = Everyone) — D4.

@ProviderFor(weekMacros)
const weekMacrosProvider = WeekMacrosFamily._();

/// The viewed week's macros under [lens] (null = Everyone) — D4.

final class WeekMacrosProvider
    extends $FunctionalProvider<MealSetMacros, MealSetMacros, MealSetMacros>
    with $Provider<MealSetMacros> {
  /// The viewed week's macros under [lens] (null = Everyone) — D4.
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

/// The viewed week's macros under [lens] (null = Everyone) — D4.

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

  /// The viewed week's macros under [lens] (null = Everyone) — D4.

  WeekMacrosProvider call(String? lens) =>
      WeekMacrosProvider._(argument: lens, from: this);

  @override
  String toString() => r'weekMacrosProvider';
}

/// One day's macros under [lens] — the SAME function over a narrower set, so
/// the week is never a sum of rounded day totals.

@ProviderFor(dayMacros)
const dayMacrosProvider = DayMacrosFamily._();

/// One day's macros under [lens] — the SAME function over a narrower set, so
/// the week is never a sum of rounded day totals.

final class DayMacrosProvider
    extends $FunctionalProvider<MealSetMacros, MealSetMacros, MealSetMacros>
    with $Provider<MealSetMacros> {
  /// One day's macros under [lens] — the SAME function over a narrower set, so
  /// the week is never a sum of rounded day totals.
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

/// One day's macros under [lens] — the SAME function over a narrower set, so
/// the week is never a sum of rounded day totals.

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

  /// One day's macros under [lens] — the SAME function over a narrower set, so
  /// the week is never a sum of rounded day totals.

  DayMacrosProvider call(int dayOfWeek, String? lens) =>
      DayMacrosProvider._(argument: (dayOfWeek, lens), from: this);

  @override
  String toString() => r'dayMacrosProvider';
}
