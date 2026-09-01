// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'off_lookup_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app's Open Food Facts client.
///
/// `keepAlive` because it wraps one long-lived `http.Client`: rebuilding it
/// per sheet would open and drop a connection pool on every scan. It is closed
/// with the container rather than with any one surface, which is also why the
/// scan sheet must not close what it did not make — see `BarcodeScanSheet`'s
/// ownership rule.

@ProviderFor(offLookup)
const offLookupProvider = OffLookupProvider._();

/// The app's Open Food Facts client.
///
/// `keepAlive` because it wraps one long-lived `http.Client`: rebuilding it
/// per sheet would open and drop a connection pool on every scan. It is closed
/// with the container rather than with any one surface, which is also why the
/// scan sheet must not close what it did not make — see `BarcodeScanSheet`'s
/// ownership rule.

final class OffLookupProvider
    extends $FunctionalProvider<OffLookup, OffLookup, OffLookup>
    with $Provider<OffLookup> {
  /// The app's Open Food Facts client.
  ///
  /// `keepAlive` because it wraps one long-lived `http.Client`: rebuilding it
  /// per sheet would open and drop a connection pool on every scan. It is closed
  /// with the container rather than with any one surface, which is also why the
  /// scan sheet must not close what it did not make — see `BarcodeScanSheet`'s
  /// ownership rule.
  const OffLookupProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'offLookupProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$offLookupHash();

  @$internal
  @override
  $ProviderElement<OffLookup> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  OffLookup create(Ref ref) {
    return offLookup(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OffLookup value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OffLookup>(value),
    );
  }
}

String _$offLookupHash() => r'ef246978242b9d3cb1d2d622418985c6a4cff0c6';
