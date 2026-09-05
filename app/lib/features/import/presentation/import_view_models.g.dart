// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_view_models.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The import session controller.
///
/// It is `autoDispose` (the default), so the user can back out of `/import`
/// while an extraction or a commit is still in flight — and in Riverpod 3
/// writing `state` on a disposed notifier THROWS (in release too). Every
/// post-await assignment here, the `catch` blocks included, is therefore
/// guarded by [Ref.mounted]. Guards rather than `keepAlive`: an abandoned
/// import should be collected, not kept warm for a flow the user left.

@ProviderFor(ImportController)
const importControllerProvider = ImportControllerProvider._();

/// The import session controller.
///
/// It is `autoDispose` (the default), so the user can back out of `/import`
/// while an extraction or a commit is still in flight — and in Riverpod 3
/// writing `state` on a disposed notifier THROWS (in release too). Every
/// post-await assignment here, the `catch` blocks included, is therefore
/// guarded by [Ref.mounted]. Guards rather than `keepAlive`: an abandoned
/// import should be collected, not kept warm for a flow the user left.
final class ImportControllerProvider
    extends $NotifierProvider<ImportController, ImportState> {
  /// The import session controller.
  ///
  /// It is `autoDispose` (the default), so the user can back out of `/import`
  /// while an extraction or a commit is still in flight — and in Riverpod 3
  /// writing `state` on a disposed notifier THROWS (in release too). Every
  /// post-await assignment here, the `catch` blocks included, is therefore
  /// guarded by [Ref.mounted]. Guards rather than `keepAlive`: an abandoned
  /// import should be collected, not kept warm for a flow the user left.
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

String _$importControllerHash() => r'bcb3a428008d07f3fcf703fcc3aa46bc52db855e';

/// The import session controller.
///
/// It is `autoDispose` (the default), so the user can back out of `/import`
/// while an extraction or a commit is still in flight — and in Riverpod 3
/// writing `state` on a disposed notifier THROWS (in release too). Every
/// post-await assignment here, the `catch` blocks included, is therefore
/// guarded by [Ref.mounted]. Guards rather than `keepAlive`: an abandoned
/// import should be collected, not kept warm for a flow the user left.

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

/// The narrow slice of the controller [importValidation] actually depends on
/// (see [ImportReconciling.validationKey]). Watching THIS rather than the whole
/// state is what keeps a note keystroke or a servings tap from re-running a
/// vocab query per line.

@ProviderFor(importValidationKey)
const importValidationKeyProvider = ImportValidationKeyProvider._();

/// The narrow slice of the controller [importValidation] actually depends on
/// (see [ImportReconciling.validationKey]). Watching THIS rather than the whole
/// state is what keeps a note keystroke or a servings tap from re-running a
/// vocab query per line.

final class ImportValidationKeyProvider
    extends $FunctionalProvider<String, String, String>
    with $Provider<String> {
  /// The narrow slice of the controller [importValidation] actually depends on
  /// (see [ImportReconciling.validationKey]). Watching THIS rather than the whole
  /// state is what keeps a note keystroke or a servings tap from re-running a
  /// vocab query per line.
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

/// Per-line validity for the current reconciliation, keyed by flat line index —
/// resolves each matched line's ingredient + measures and checks its unit
/// against the ingredient's allowed set (ADR-0008), offering that ingredient's
/// valid units as inline suggestion chips. The review screen reads it for the
/// per-line needs-attention flag, the unit chips, AND the Save gate. Empty
/// until reconciling.
///
/// It is deliberately NOT recomputed on every controller change: it depends on
/// [importValidationKey], so editing a note or the servings leaves the cached
/// map alone. Views must read it with `AsyncValue.value` (which keeps the last
/// data across a refresh), never a data-only view that goes null mid-recompute.
///
/// The whole import's vocab and the whole import's measures are each fetched in
/// ONE repository query — never N round-trips down the line list, and never
/// through the per-ingredient measure STREAM providers. Those are autoDispose,
/// PowerSync's `watch` does not emit synchronously, and an element disposed
/// before its first emission completes `.future` with a [StateError] — which
/// this loader caught and turned into "no measures", so "1 clove" of a garlic
/// row that carries a `clove` measure validated against an empty list and was
/// flagged "Pick a supported unit". A plain read has no element to lose.
/// Nothing is swallowed now either: a query that genuinely fails surfaces as
/// the provider's error rather than as a screen full of wrongly-flagged lines.

@ProviderFor(importValidation)
const importValidationProvider = ImportValidationProvider._();

/// Per-line validity for the current reconciliation, keyed by flat line index —
/// resolves each matched line's ingredient + measures and checks its unit
/// against the ingredient's allowed set (ADR-0008), offering that ingredient's
/// valid units as inline suggestion chips. The review screen reads it for the
/// per-line needs-attention flag, the unit chips, AND the Save gate. Empty
/// until reconciling.
///
/// It is deliberately NOT recomputed on every controller change: it depends on
/// [importValidationKey], so editing a note or the servings leaves the cached
/// map alone. Views must read it with `AsyncValue.value` (which keeps the last
/// data across a refresh), never a data-only view that goes null mid-recompute.
///
/// The whole import's vocab and the whole import's measures are each fetched in
/// ONE repository query — never N round-trips down the line list, and never
/// through the per-ingredient measure STREAM providers. Those are autoDispose,
/// PowerSync's `watch` does not emit synchronously, and an element disposed
/// before its first emission completes `.future` with a [StateError] — which
/// this loader caught and turned into "no measures", so "1 clove" of a garlic
/// row that carries a `clove` measure validated against an empty list and was
/// flagged "Pick a supported unit". A plain read has no element to lose.
/// Nothing is swallowed now either: a query that genuinely fails surfaces as
/// the provider's error rather than as a screen full of wrongly-flagged lines.

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
  /// resolves each matched line's ingredient + measures and checks its unit
  /// against the ingredient's allowed set (ADR-0008), offering that ingredient's
  /// valid units as inline suggestion chips. The review screen reads it for the
  /// per-line needs-attention flag, the unit chips, AND the Save gate. Empty
  /// until reconciling.
  ///
  /// It is deliberately NOT recomputed on every controller change: it depends on
  /// [importValidationKey], so editing a note or the servings leaves the cached
  /// map alone. Views must read it with `AsyncValue.value` (which keeps the last
  /// data across a refresh), never a data-only view that goes null mid-recompute.
  ///
  /// The whole import's vocab and the whole import's measures are each fetched in
  /// ONE repository query — never N round-trips down the line list, and never
  /// through the per-ingredient measure STREAM providers. Those are autoDispose,
  /// PowerSync's `watch` does not emit synchronously, and an element disposed
  /// before its first emission completes `.future` with a [StateError] — which
  /// this loader caught and turned into "no measures", so "1 clove" of a garlic
  /// row that carries a `clove` measure validated against an empty list and was
  /// flagged "Pick a supported unit". A plain read has no element to lose.
  /// Nothing is swallowed now either: a query that genuinely fails surfaces as
  /// the provider's error rather than as a screen full of wrongly-flagged lines.
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

String _$importValidationHash() => r'2251f1864079a254c0cfbd68cdf98c69585ed88e';

/// The ONE "how many lines still want you" count — the header's "N to review"
/// and the Save button's "N line(s) need you" are the same number, read from
/// the same place — two rules would let the header stop decrementing while the
/// button kept counting. Until the first validation lands it falls back to the
/// structural unresolved count, so the header is never blank or wrong-by-zero.

@ProviderFor(importOutstandingLines)
const importOutstandingLinesProvider = ImportOutstandingLinesProvider._();

/// The ONE "how many lines still want you" count — the header's "N to review"
/// and the Save button's "N line(s) need you" are the same number, read from
/// the same place — two rules would let the header stop decrementing while the
/// button kept counting. Until the first validation lands it falls back to the
/// structural unresolved count, so the header is never blank or wrong-by-zero.

final class ImportOutstandingLinesProvider
    extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  /// The ONE "how many lines still want you" count — the header's "N to review"
  /// and the Save button's "N line(s) need you" are the same number, read from
  /// the same place — two rules would let the header stop decrementing while the
  /// button kept counting. Until the first validation lands it falls back to the
  /// structural unresolved count, so the header is never blank or wrong-by-zero.
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
