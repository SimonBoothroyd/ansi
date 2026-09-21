// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_view_models.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The import session controller. It is `autoDispose`, so the user can leave
/// mid-flight, and Riverpod 3 throws on writing `state` to a disposed notifier:
/// every post-await assignment, `catch` blocks included, is guarded by
/// [Ref.mounted].

@ProviderFor(ImportController)
const importControllerProvider = ImportControllerProvider._();

/// The import session controller. It is `autoDispose`, so the user can leave
/// mid-flight, and Riverpod 3 throws on writing `state` to a disposed notifier:
/// every post-await assignment, `catch` blocks included, is guarded by
/// [Ref.mounted].
final class ImportControllerProvider
    extends $NotifierProvider<ImportController, ImportState> {
  /// The import session controller. It is `autoDispose`, so the user can leave
  /// mid-flight, and Riverpod 3 throws on writing `state` to a disposed notifier:
  /// every post-await assignment, `catch` blocks included, is guarded by
  /// [Ref.mounted].
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

String _$importControllerHash() => r'098019f86eca506798208394d24e4b6d6d7b33c4';

/// The import session controller. It is `autoDispose`, so the user can leave
/// mid-flight, and Riverpod 3 throws on writing `state` to a disposed notifier:
/// every post-await assignment, `catch` blocks included, is guarded by
/// [Ref.mounted].

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

/// The slice of the controller [importValidation] depends on (see
/// [ImportReconciling.validationKey]), so a note keystroke does not re-run it.

@ProviderFor(importValidationKey)
const importValidationKeyProvider = ImportValidationKeyProvider._();

/// The slice of the controller [importValidation] depends on (see
/// [ImportReconciling.validationKey]), so a note keystroke does not re-run it.

final class ImportValidationKeyProvider
    extends $FunctionalProvider<String, String, String>
    with $Provider<String> {
  /// The slice of the controller [importValidation] depends on (see
  /// [ImportReconciling.validationKey]), so a note keystroke does not re-run it.
  const ImportValidationKeyProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'importValidationKeyProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$importValidationKeyHash();

  @$internal
  @override
  $ProviderElement<String> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String create(Ref ref) {
    return importValidationKey(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$importValidationKeyHash() =>
    r'04873386dafd09f83ea6a2cb9387c725d2432e7d';

/// Per-line validity for the current reconciliation, keyed by flat line index:
/// checks each matched line's unit against its ingredient's allowed set
/// (ADR-0008) and offers valid units as chips. Drives the per-line flag, the
/// unit chips and the Save gate.
///
/// [againstLiveVocabulary] runs here, so a line matched to a since-retired row
/// reads as unmatched. Depends only on [importValidationKey]; read it with
/// `AsyncValue.value`, which keeps the last data across a refresh.
///
/// Vocab and measures are each one plain repository query. Never use the
/// per-ingredient autoDispose stream providers' `.future` here: an element
/// disposed before its first emission completes with a [StateError].

@ProviderFor(importValidation)
const importValidationProvider = ImportValidationProvider._();

/// Per-line validity for the current reconciliation, keyed by flat line index:
/// checks each matched line's unit against its ingredient's allowed set
/// (ADR-0008) and offers valid units as chips. Drives the per-line flag, the
/// unit chips and the Save gate.
///
/// [againstLiveVocabulary] runs here, so a line matched to a since-retired row
/// reads as unmatched. Depends only on [importValidationKey]; read it with
/// `AsyncValue.value`, which keeps the last data across a refresh.
///
/// Vocab and measures are each one plain repository query. Never use the
/// per-ingredient autoDispose stream providers' `.future` here: an element
/// disposed before its first emission completes with a [StateError].

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
  /// Per-line validity for the current reconciliation, keyed by flat line index:
  /// checks each matched line's unit against its ingredient's allowed set
  /// (ADR-0008) and offers valid units as chips. Drives the per-line flag, the
  /// unit chips and the Save gate.
  ///
  /// [againstLiveVocabulary] runs here, so a line matched to a since-retired row
  /// reads as unmatched. Depends only on [importValidationKey]; read it with
  /// `AsyncValue.value`, which keeps the last data across a refresh.
  ///
  /// Vocab and measures are each one plain repository query. Never use the
  /// per-ingredient autoDispose stream providers' `.future` here: an element
  /// disposed before its first emission completes with a [StateError].
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

String _$importValidationHash() => r'4e7e1a384b47bdad0fe7b09dc4ba1b0eaa5e5f5e';

/// The one count of lines still needing attention, shared by the header and the
/// Save button. Falls back to the structural unresolved count until the first
/// validation lands.

@ProviderFor(importOutstandingLines)
const importOutstandingLinesProvider = ImportOutstandingLinesProvider._();

/// The one count of lines still needing attention, shared by the header and the
/// Save button. Falls back to the structural unresolved count until the first
/// validation lands.

final class ImportOutstandingLinesProvider
    extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  /// The one count of lines still needing attention, shared by the header and the
  /// Save button. Falls back to the structural unresolved count until the first
  /// validation lands.
  const ImportOutstandingLinesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'importOutstandingLinesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$importOutstandingLinesHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return importOutstandingLines(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$importOutstandingLinesHash() =>
    r'cfe5496b87213da8d218916a996f8c988b221220';
