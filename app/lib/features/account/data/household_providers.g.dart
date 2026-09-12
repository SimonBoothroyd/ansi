// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'household_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(householdRepository)
const householdRepositoryProvider = HouseholdRepositoryProvider._();

final class HouseholdRepositoryProvider
    extends
        $FunctionalProvider<
          HouseholdRepository,
          HouseholdRepository,
          HouseholdRepository
        >
    with $Provider<HouseholdRepository> {
  const HouseholdRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'householdRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$householdRepositoryHash();

  @$internal
  @override
  $ProviderElement<HouseholdRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  HouseholdRepository create(Ref ref) {
    return householdRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HouseholdRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HouseholdRepository>(value),
    );
  }
}

String _$householdRepositoryHash() =>
    r'78786ca51b6473541db5aad9eae4e2aabf16f2d5';

/// The `set_household_week_start` RPC (migration 0043) as a function, so the
/// widget that offers the flip can be tested without a Supabase client.

@ProviderFor(flipWeekStart)
const flipWeekStartProvider = FlipWeekStartProvider._();

/// The `set_household_week_start` RPC (migration 0043) as a function, so the
/// widget that offers the flip can be tested without a Supabase client.

final class FlipWeekStartProvider
    extends $FunctionalProvider<FlipWeekStart, FlipWeekStart, FlipWeekStart>
    with $Provider<FlipWeekStart> {
  /// The `set_household_week_start` RPC (migration 0043) as a function, so the
  /// widget that offers the flip can be tested without a Supabase client.
  const FlipWeekStartProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'flipWeekStartProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$flipWeekStartHash();

  @$internal
  @override
  $ProviderElement<FlipWeekStart> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  FlipWeekStart create(Ref ref) {
    return flipWeekStart(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FlipWeekStart value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FlipWeekStart>(value),
    );
  }
}

String _$flipWeekStartHash() => r'466213b8eb799384e5ee8dce86180a1a3ab2098e';

@ProviderFor(weekShapeStream)
const weekShapeStreamProvider = WeekShapeStreamProvider._();

final class WeekShapeStreamProvider
    extends
        $FunctionalProvider<AsyncValue<WeekShape>, WeekShape, Stream<WeekShape>>
    with $FutureModifier<WeekShape>, $StreamProvider<WeekShape> {
  const WeekShapeStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'weekShapeStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$weekShapeStreamHash();

  @$internal
  @override
  $StreamProviderElement<WeekShape> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<WeekShape> create(Ref ref) {
    return weekShapeStream(ref);
  }
}

String _$weekShapeStreamHash() => r'56784cfaf9e44624687be6c0311b04c55ba699a6';

/// The household's week shape, as a plain value.
///
/// Monday until the row arrives — and equally for a device that cannot reach
/// its own database yet. That is not a swallowed error: the shape has exactly
/// one honest default, the surfaces that read it have no loading state, and a
/// database that never opens has a louder failure than a Monday-first grid.

@ProviderFor(weekShape)
const weekShapeProvider = WeekShapeProvider._();

/// The household's week shape, as a plain value.
///
/// Monday until the row arrives — and equally for a device that cannot reach
/// its own database yet. That is not a swallowed error: the shape has exactly
/// one honest default, the surfaces that read it have no loading state, and a
/// database that never opens has a louder failure than a Monday-first grid.

final class WeekShapeProvider
    extends $FunctionalProvider<WeekShape, WeekShape, WeekShape>
    with $Provider<WeekShape> {
  /// The household's week shape, as a plain value.
  ///
  /// Monday until the row arrives — and equally for a device that cannot reach
  /// its own database yet. That is not a swallowed error: the shape has exactly
  /// one honest default, the surfaces that read it have no loading state, and a
  /// database that never opens has a louder failure than a Monday-first grid.
  const WeekShapeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'weekShapeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$weekShapeHash();

  @$internal
  @override
  $ProviderElement<WeekShape> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  WeekShape create(Ref ref) {
    return weekShape(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WeekShape value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WeekShape>(value),
    );
  }
}

String _$weekShapeHash() => r'859c52bcd409af23cd6e091143c439bb385c513d';
