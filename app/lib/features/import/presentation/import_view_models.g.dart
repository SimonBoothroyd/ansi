// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_view_models.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ImportController)
const importControllerProvider = ImportControllerProvider._();

final class ImportControllerProvider
    extends $NotifierProvider<ImportController, ImportState> {
  const ImportControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'importControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$importControllerHash();

  @$internal
  @override
  ImportController create() => ImportController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ImportState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ImportState>(value),
    );
  }
}

String _$importControllerHash() => r'0bf8d099737c79137bcf039b55f147032a8aff36';

abstract class _$ImportController extends $Notifier<ImportState> {
  ImportState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ImportState, ImportState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ImportState, ImportState>,
              ImportState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Per-line validity for the current reconciliation, keyed by flat line index —
/// loads each matched line's ingredient + measures and checks its unit against
/// the ingredient's allowed set (ADR-0008), and offers that ingredient's valid
/// units as inline suggestion chips. Recomputed on every edit; the review
/// screen reads it for the per-line needs-attention flag, the unit chips, AND
/// the Save gate. Empty until reconciling.

@ProviderFor(importValidation)
const importValidationProvider = ImportValidationProvider._();

/// Per-line validity for the current reconciliation, keyed by flat line index —
/// loads each matched line's ingredient + measures and checks its unit against
/// the ingredient's allowed set (ADR-0008), and offers that ingredient's valid
/// units as inline suggestion chips. Recomputed on every edit; the review
/// screen reads it for the per-line needs-attention flag, the unit chips, AND
/// the Save gate. Empty until reconciling.

final class ImportValidationProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<int, LineValidation>>,
          Map<int, LineValidation>,
          FutureOr<Map<int, LineValidation>>
        >
    with
        $FutureModifier<Map<int, LineValidation>>,
        $FutureProvider<Map<int, LineValidation>> {
  /// Per-line validity for the current reconciliation, keyed by flat line index —
  /// loads each matched line's ingredient + measures and checks its unit against
  /// the ingredient's allowed set (ADR-0008), and offers that ingredient's valid
  /// units as inline suggestion chips. Recomputed on every edit; the review
  /// screen reads it for the per-line needs-attention flag, the unit chips, AND
  /// the Save gate. Empty until reconciling.
  const ImportValidationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'importValidationProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$importValidationHash();

  @$internal
  @override
  $FutureProviderElement<Map<int, LineValidation>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Map<int, LineValidation>> create(Ref ref) {
    return importValidation(ref);
  }
}

String _$importValidationHash() => r'470c346c4dc7fa94d41c06f1003fde52a499b1f7';
