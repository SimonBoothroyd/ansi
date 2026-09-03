// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'crash_sink.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Where the zone handler and `guardedWrite` speak.
///
/// Overridden in `bootstrap.dart` with a [ToastCrashSink] anchored under the
/// app's toaster. The default is [NoopCrashSink], which is also what a test
/// wanting silence gets for free.

@ProviderFor(crashSink)
const crashSinkProvider = CrashSinkProvider._();

/// Where the zone handler and `guardedWrite` speak.
///
/// Overridden in `bootstrap.dart` with a [ToastCrashSink] anchored under the
/// app's toaster. The default is [NoopCrashSink], which is also what a test
/// wanting silence gets for free.

final class CrashSinkProvider
    extends $FunctionalProvider<CrashSink, CrashSink, CrashSink>
    with $Provider<CrashSink> {
  /// Where the zone handler and `guardedWrite` speak.
  ///
  /// Overridden in `bootstrap.dart` with a [ToastCrashSink] anchored under the
  /// app's toaster. The default is [NoopCrashSink], which is also what a test
  /// wanting silence gets for free.
  const CrashSinkProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'crashSinkProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$crashSinkHash();

  @$internal
  @override
  $ProviderElement<CrashSink> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CrashSink create(Ref ref) {
    return crashSink(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CrashSink value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CrashSink>(value),
    );
  }
}

String _$crashSinkHash() => r'137f461db3a5201b34871cc51327133fcf948783';
