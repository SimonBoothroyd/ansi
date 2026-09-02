// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'week_view_models.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The Monday of the week containing today.
///
/// Known wart, pre-existing: `DateTime.now()` in a provider doesn't re-fire at
/// midnight, so "today" is stale until the next rebuild (tracker debt).

@ProviderFor(currentWeekStart)
const currentWeekStartProvider = CurrentWeekStartProvider._();

/// The Monday of the week containing today.
///
/// Known wart, pre-existing: `DateTime.now()` in a provider doesn't re-fire at
/// midnight, so "today" is stale until the next rebuild (tracker debt).

final class CurrentWeekStartProvider
    extends $FunctionalProvider<DateTime, DateTime, DateTime>
    with $Provider<DateTime> {
  /// The Monday of the week containing today.
  ///
  /// Known wart, pre-existing: `DateTime.now()` in a provider doesn't re-fire at
  /// midnight, so "today" is stale until the next rebuild (tracker debt).
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

String _$currentWeekStartHash() => r'fdfd04e6f844526dc22fbdfdeaa0ef12609dfe24';

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

/// The household eater roster.

@ProviderFor(members)
const membersProvider = MembersProvider._();

/// The household eater roster.

final class MembersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Member>>,
          List<Member>,
          FutureOr<List<Member>>
        >
    with $FutureModifier<List<Member>>, $FutureProvider<List<Member>> {
  /// The household eater roster.
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
  $FutureProviderElement<List<Member>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Member>> create(Ref ref) {
    return members(ref);
  }
}

String _$membersHash() => r'3a22c0d4097b2b89991990cc72bdac5780eb4baf';

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
