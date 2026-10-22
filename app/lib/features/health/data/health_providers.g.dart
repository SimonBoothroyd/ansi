// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(healthGateway)
const healthGatewayProvider = HealthGatewayProvider._();

final class HealthGatewayProvider
    extends $FunctionalProvider<HealthGateway, HealthGateway, HealthGateway>
    with $Provider<HealthGateway> {
  const HealthGatewayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'healthGatewayProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$healthGatewayHash();

  @$internal
  @override
  $ProviderElement<HealthGateway> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  HealthGateway create(Ref ref) {
    return healthGateway(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HealthGateway value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HealthGateway>(value),
    );
  }
}

String _$healthGatewayHash() => r'5606a1d6de1436f050656487ccfae2672e17459c';

@ProviderFor(healthSendLog)
const healthSendLogProvider = HealthSendLogProvider._();

final class HealthSendLogProvider
    extends $FunctionalProvider<HealthSendLog, HealthSendLog, HealthSendLog>
    with $Provider<HealthSendLog> {
  const HealthSendLogProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'healthSendLogProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$healthSendLogHash();

  @$internal
  @override
  $ProviderElement<HealthSendLog> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  HealthSendLog create(Ref ref) {
    return healthSendLog(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HealthSendLog value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HealthSendLog>(value),
    );
  }
}

String _$healthSendLogHash() => r'8bfc7d4c7e4aadbc335682f4f274ba39350ba53a';

/// Whether this build can talk to Health Connect. Tests pin it.

@ProviderFor(healthIsSupported)
const healthIsSupportedProvider = HealthIsSupportedProvider._();

/// Whether this build can talk to Health Connect. Tests pin it.

final class HealthIsSupportedProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether this build can talk to Health Connect. Tests pin it.
  const HealthIsSupportedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'healthIsSupportedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$healthIsSupportedHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return healthIsSupported(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$healthIsSupportedHash() => r'5dd5948fd687643457f32d77655b8c3d4849d057';
