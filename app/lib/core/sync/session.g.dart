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

@ProviderFor(SessionController)
const sessionControllerProvider = SessionControllerProvider._();

final class SessionControllerProvider
    extends $NotifierProvider<SessionController, AppSession?> {
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
  Override overrideWithValue(AppSession? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppSession?>(value),
    );
  }
}

String _$sessionControllerHash() => r'6f7cb1643aa211f4bc7c257da00e25eb6f1af99d';

abstract class _$SessionController extends $Notifier<AppSession?> {
  AppSession? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AppSession?, AppSession?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AppSession?, AppSession?>,
              AppSession?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// The household every repository write is scoped to. Read only behind the auth
/// gate — throws before a session exists.

@ProviderFor(currentHouseholdId)
const currentHouseholdIdProvider = CurrentHouseholdIdProvider._();

/// The household every repository write is scoped to. Read only behind the auth
/// gate — throws before a session exists.

final class CurrentHouseholdIdProvider
    extends $FunctionalProvider<String, String, String>
    with $Provider<String> {
  /// The household every repository write is scoped to. Read only behind the auth
  /// gate — throws before a session exists.
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
    r'923bfdf41313b3a2b8132e3ff4f01245c8120f46';
