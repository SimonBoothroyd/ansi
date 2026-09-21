// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'receipt_view_models.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ReceiptScanController)
const receiptScanControllerProvider = ReceiptScanControllerProvider._();

final class ReceiptScanControllerProvider
    extends $NotifierProvider<ReceiptScanController, ReceiptScanState> {
  const ReceiptScanControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'receiptScanControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$receiptScanControllerHash();

  @$internal
  @override
  ReceiptScanController create() => ReceiptScanController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReceiptScanState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReceiptScanState>(value),
    );
  }
}

String _$receiptScanControllerHash() =>
    r'2c942eacc8d80bb7cd413761632dc1a31555b913';

abstract class _$ReceiptScanController extends $Notifier<ReceiptScanState> {
  ReceiptScanState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ReceiptScanState, ReceiptScanState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ReceiptScanState, ReceiptScanState>,
              ReceiptScanState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
