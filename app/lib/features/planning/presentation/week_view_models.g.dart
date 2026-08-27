// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'week_view_models.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The Monday of the active week (the week containing today).

@ProviderFor(currentWeekStart)
const currentWeekStartProvider = CurrentWeekStartProvider._();

/// The Monday of the active week (the week containing today).

final class CurrentWeekStartProvider
    extends $FunctionalProvider<DateTime, DateTime, DateTime>
    with $Provider<DateTime> {
  /// The Monday of the active week (the week containing today).
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

/// The active week with its meals, or null until its first meal (empty state).

@ProviderFor(currentWeek)
const currentWeekProvider = CurrentWeekProvider._();

/// The active week with its meals, or null until its first meal (empty state).

final class CurrentWeekProvider
    extends
        $FunctionalProvider<AsyncValue<WeekPlan?>, WeekPlan?, Stream<WeekPlan?>>
    with $FutureModifier<WeekPlan?>, $StreamProvider<WeekPlan?> {
  /// The active week with its meals, or null until its first meal (empty state).
  const CurrentWeekProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentWeekProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentWeekHash();

  @$internal
  @override
  $StreamProviderElement<WeekPlan?> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<WeekPlan?> create(Ref ref) {
    return currentWeek(ref);
  }
}

String _$currentWeekHash() => r'dc5cac2ec3ac2e9ef85857c294212d196cf95fa0';

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

/// The most recent earlier week with meals, for the empty-week reference list
/// and the "copy last week" affordance.

@ProviderFor(lastWeek)
const lastWeekProvider = LastWeekProvider._();

/// The most recent earlier week with meals, for the empty-week reference list
/// and the "copy last week" affordance.

final class LastWeekProvider
    extends
        $FunctionalProvider<
          AsyncValue<WeekPlan?>,
          WeekPlan?,
          FutureOr<WeekPlan?>
        >
    with $FutureModifier<WeekPlan?>, $FutureProvider<WeekPlan?> {
  /// The most recent earlier week with meals, for the empty-week reference list
  /// and the "copy last week" affordance.
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

String _$lastWeekHash() => r'0200b9013085db4bb45918d92a6d02b909e0b6d3';
