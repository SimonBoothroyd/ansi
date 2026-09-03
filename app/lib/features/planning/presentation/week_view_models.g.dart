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
/// (plan 0027) reaches every Portions row and the Household sheet as it lands.

@ProviderFor(members)
const membersProvider = MembersProvider._();

/// The household eater roster, live — a portion factor set on either phone
/// (plan 0027) reaches every Portions row and the Household sheet as it lands.

final class MembersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Member>>,
          List<Member>,
          Stream<List<Member>>
        >
    with $FutureModifier<List<Member>>, $StreamProvider<List<Member>> {
  /// The household eater roster, live — a portion factor set on either phone
  /// (plan 0027) reaches every Portions row and the Household sheet as it lands.
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

/// Per-recipe macro summaries, indexed by recipe id.
///
/// `watchRecipes()` already carries `macros` on every `RecipeSummary`, so the
/// week needs NO new repository method and no second summation — it reads the
/// same figure the picker rows and the recipe panel show.

@ProviderFor(recipeMacrosById)
const recipeMacrosByIdProvider = RecipeMacrosByIdProvider._();

/// Per-recipe macro summaries, indexed by recipe id.
///
/// `watchRecipes()` already carries `macros` on every `RecipeSummary`, so the
/// week needs NO new repository method and no second summation — it reads the
/// same figure the picker rows and the recipe panel show.

final class RecipeMacrosByIdProvider
    extends
        $FunctionalProvider<
          Map<String, RecipeMacroSummary>,
          Map<String, RecipeMacroSummary>,
          Map<String, RecipeMacroSummary>
        >
    with $Provider<Map<String, RecipeMacroSummary>> {
  /// Per-recipe macro summaries, indexed by recipe id.
  ///
  /// `watchRecipes()` already carries `macros` on every `RecipeSummary`, so the
  /// week needs NO new repository method and no second summation — it reads the
  /// same figure the picker rows and the recipe panel show.
  const RecipeMacrosByIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recipeMacrosByIdProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recipeMacrosByIdHash();

  @$internal
  @override
  $ProviderElement<Map<String, RecipeMacroSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, RecipeMacroSummary> create(Ref ref) {
    return recipeMacrosById(ref);
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

String _$recipeMacrosByIdHash() => r'bcce65c48ca6eabca10ea29ed99479705f17030d';

/// The roster keyed by id — the portion factors every demand and lens share
/// is weighted by (plan 0027).

@ProviderFor(membersById)
const membersByIdProvider = MembersByIdProvider._();

/// The roster keyed by id — the portion factors every demand and lens share
/// is weighted by (plan 0027).

final class MembersByIdProvider
    extends
        $FunctionalProvider<
          Map<String, Member>,
          Map<String, Member>,
          Map<String, Member>
        >
    with $Provider<Map<String, Member>> {
  /// The roster keyed by id — the portion factors every demand and lens share
  /// is weighted by (plan 0027).
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

String _$weekMacrosHash() => r'18ccac97520f365e7e725a1bd80a2bc7db7a290c';

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

String _$dayMacrosHash() => r'946b030b15db540aad00e8cefa2c90748b90d469';

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
