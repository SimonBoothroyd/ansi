// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(supabaseClient)
const supabaseClientProvider = SupabaseClientProvider._();

final class SupabaseClientProvider
    extends $FunctionalProvider<SupabaseClient, SupabaseClient, SupabaseClient>
    with $Provider<SupabaseClient> {
  const SupabaseClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'supabaseClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$supabaseClientHash();

  @$internal
  @override
  $ProviderElement<SupabaseClient> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SupabaseClient create(Ref ref) {
    return supabaseClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SupabaseClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SupabaseClient>(value),
    );
  }
}

String _$supabaseClientHash() => r'3db2a4c212c7f24cea9810e376225aa1a6cab012';

/// Calls the idempotent `ensure_onboarded` RPC (migration 0007) and returns
/// the household id. A provider so [SessionController] tests can fake the
/// network boundary.

@ProviderFor(ensureOnboarded)
const ensureOnboardedProvider = EnsureOnboardedProvider._();

/// Calls the idempotent `ensure_onboarded` RPC (migration 0007) and returns
/// the household id. A provider so [SessionController] tests can fake the
/// network boundary.

final class EnsureOnboardedProvider
    extends
        $FunctionalProvider<
          Future<String> Function(),
          Future<String> Function(),
          Future<String> Function()
        >
    with $Provider<Future<String> Function()> {
  /// Calls the idempotent `ensure_onboarded` RPC (migration 0007) and returns
  /// the household id. A provider so [SessionController] tests can fake the
  /// network boundary.
  const EnsureOnboardedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ensureOnboardedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ensureOnboardedHash();

  @$internal
  @override
  $ProviderElement<Future<String> Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Future<String> Function() create(Ref ref) {
    return ensureOnboarded(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Future<String> Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Future<String> Function()>(value),
    );
  }
}

String _$ensureOnboardedHash() => r'80e8a8971134fd0ce35e1caa057e12c23aee438e';

@ProviderFor(householdCache)
const householdCacheProvider = HouseholdCacheProvider._();

final class HouseholdCacheProvider
    extends $FunctionalProvider<HouseholdCache, HouseholdCache, HouseholdCache>
    with $Provider<HouseholdCache> {
  const HouseholdCacheProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'householdCacheProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$householdCacheHash();

  @$internal
  @override
  $ProviderElement<HouseholdCache> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  HouseholdCache create(Ref ref) {
    return householdCache(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HouseholdCache value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HouseholdCache>(value),
    );
  }
}

String _$householdCacheHash() => r'2e24f43025c30067c2c90a8104d8e5ce353e755b';

@ProviderFor(SessionController)
const sessionControllerProvider = SessionControllerProvider._();

final class SessionControllerProvider
    extends $NotifierProvider<SessionController, SessionState> {
  const SessionControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionControllerHash();

  @$internal
  @override
  SessionController create() => SessionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SessionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SessionState>(value),
    );
  }
}

String _$sessionControllerHash() => r'3a10832edc67ecf886fe7f5c5aa333041d3a3db2';

abstract class _$SessionController extends $Notifier<SessionState> {
  SessionState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<SessionState, SessionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SessionState, SessionState>,
              SessionState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// The household every repository write is scoped to. Read only behind the auth
/// gate — throws before a session is ready.

@ProviderFor(currentHouseholdId)
const currentHouseholdIdProvider = CurrentHouseholdIdProvider._();

/// The household every repository write is scoped to. Read only behind the auth
/// gate — throws before a session is ready.

final class CurrentHouseholdIdProvider
    extends $FunctionalProvider<String, String, String>
    with $Provider<String> {
  /// The household every repository write is scoped to. Read only behind the auth
  /// gate — throws before a session is ready.
  const CurrentHouseholdIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentHouseholdIdProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentHouseholdIdHash();

  @$internal
  @override
  $ProviderElement<String> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String create(Ref ref) {
    return currentHouseholdId(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$currentHouseholdIdHash() =>
    r'7087d03830015ee18da598f5f169a8d41ebb0f56';
