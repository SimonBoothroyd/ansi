// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'receipt_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The reader behind the scan door: the `import-receipt` edge function when
/// Supabase is configured. Unconfigured, it fails loudly rather than serving
/// the replay payload. Tests reach `ReplayReceiptRepository` by naming it.

@ProviderFor(receiptImportRepository)
const receiptImportRepositoryProvider = ReceiptImportRepositoryProvider._();

/// The reader behind the scan door: the `import-receipt` edge function when
/// Supabase is configured. Unconfigured, it fails loudly rather than serving
/// the replay payload. Tests reach `ReplayReceiptRepository` by naming it.

final class ReceiptImportRepositoryProvider
    extends
        $FunctionalProvider<
          ReceiptImportRepository,
          ReceiptImportRepository,
          ReceiptImportRepository
        >
    with $Provider<ReceiptImportRepository> {
  /// The reader behind the scan door: the `import-receipt` edge function when
  /// Supabase is configured. Unconfigured, it fails loudly rather than serving
  /// the replay payload. Tests reach `ReplayReceiptRepository` by naming it.
  const ReceiptImportRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'receiptImportRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$receiptImportRepositoryHash();

  @$internal
  @override
  $ProviderElement<ReceiptImportRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReceiptImportRepository create(Ref ref) {
    return receiptImportRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReceiptImportRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReceiptImportRepository>(value),
    );
  }
}

String _$receiptImportRepositoryHash() =>
    r'bf0563988f48528a962e9ba57d08438b40e73069';

/// The ledger itself — always local, like every other read.

@ProviderFor(receiptRepository)
const receiptRepositoryProvider = ReceiptRepositoryProvider._();

/// The ledger itself — always local, like every other read.

final class ReceiptRepositoryProvider
    extends
        $FunctionalProvider<
          ReceiptRepository,
          ReceiptRepository,
          ReceiptRepository
        >
    with $Provider<ReceiptRepository> {
  /// The ledger itself — always local, like every other read.
  const ReceiptRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'receiptRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$receiptRepositoryHash();

  @$internal
  @override
  $ProviderElement<ReceiptRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReceiptRepository create(Ref ref) {
    return receiptRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReceiptRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReceiptRepository>(value),
    );
  }
}

String _$receiptRepositoryHash() => r'3d02dc4f1309eef88d2eb1b7f7e66b4a21ba64c4';

/// Every receipt the household has kept, newest first. A row costs the printed
/// total, else its lines plus tax (the printed tax, else the tax lines).

@ProviderFor(receiptSummaries)
const receiptSummariesProvider = ReceiptSummariesProvider._();

/// Every receipt the household has kept, newest first. A row costs the printed
/// total, else its lines plus tax (the printed tax, else the tax lines).

final class ReceiptSummariesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ReceiptSummary>>,
          List<ReceiptSummary>,
          Stream<List<ReceiptSummary>>
        >
    with
        $FutureModifier<List<ReceiptSummary>>,
        $StreamProvider<List<ReceiptSummary>> {
  /// Every receipt the household has kept, newest first. A row costs the printed
  /// total, else its lines plus tax (the printed tax, else the tax lines).
  const ReceiptSummariesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'receiptSummariesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$receiptSummariesHash();

  @$internal
  @override
  $StreamProviderElement<List<ReceiptSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ReceiptSummary>> create(Ref ref) {
    return receiptSummaries(ref);
  }
}

String _$receiptSummariesHash() => r'3434b831f7b15e2d91c5ae843efbb3cb6f40c8eb';

/// The receipts dated inside the week beginning [weekStart] — the band's
/// second figure, and nothing else.

@ProviderFor(receiptsForWeek)
const receiptsForWeekProvider = ReceiptsForWeekFamily._();

/// The receipts dated inside the week beginning [weekStart] — the band's
/// second figure, and nothing else.

final class ReceiptsForWeekProvider
    extends
        $FunctionalProvider<
          List<ReceiptSummary>,
          List<ReceiptSummary>,
          List<ReceiptSummary>
        >
    with $Provider<List<ReceiptSummary>> {
  /// The receipts dated inside the week beginning [weekStart] — the band's
  /// second figure, and nothing else.
  const ReceiptsForWeekProvider._({
    required ReceiptsForWeekFamily super.from,
    required DateTime super.argument,
  }) : super(
         retry: null,
         name: r'receiptsForWeekProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$receiptsForWeekHash();

  @override
  String toString() {
    return r'receiptsForWeekProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<ReceiptSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<ReceiptSummary> create(Ref ref) {
    final argument = this.argument as DateTime;
    return receiptsForWeek(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<ReceiptSummary> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<ReceiptSummary>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReceiptsForWeekProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$receiptsForWeekHash() => r'628c75a39d9e6f62e3c1dc2b9c9feeb95c58a507';

/// The receipts dated inside the week beginning [weekStart] — the band's
/// second figure, and nothing else.

final class ReceiptsForWeekFamily extends $Family
    with $FunctionalFamilyOverride<List<ReceiptSummary>, DateTime> {
  const ReceiptsForWeekFamily._()
    : super(
        retry: null,
        name: r'receiptsForWeekProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The receipts dated inside the week beginning [weekStart] — the band's
  /// second figure, and nothing else.

  ReceiptsForWeekProvider call(DateTime weekStart) =>
      ReceiptsForWeekProvider._(argument: weekStart, from: this);

  @override
  String toString() => r'receiptsForWeekProvider';
}

/// Whether the household has kept any receipt, which decides whether the Shop
/// shows the ledger door.

@ProviderFor(hasAnyReceipt)
const hasAnyReceiptProvider = HasAnyReceiptProvider._();

/// Whether the household has kept any receipt, which decides whether the Shop
/// shows the ledger door.

final class HasAnyReceiptProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether the household has kept any receipt, which decides whether the Shop
  /// shows the ledger door.
  const HasAnyReceiptProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hasAnyReceiptProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hasAnyReceiptHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return hasAnyReceipt(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$hasAnyReceiptHash() => r'834490de4750794e87a71cf10a321aa757db1a7a';
