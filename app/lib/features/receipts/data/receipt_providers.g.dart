// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'receipt_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The reader behind the scan door.
///
/// With Supabase configured it is the real `import-receipt` edge function.
/// Unconfigured it FAILS LOUDLY rather than falling through to the replay
/// payload, which would have a misconfigured build answer "read this receipt"
/// with somebody else's groceries. Tests and a walkthrough build reach
/// `ReplayReceiptRepository` by naming it, never by accident.

@ProviderFor(receiptImportRepository)
const receiptImportRepositoryProvider = ReceiptImportRepositoryProvider._();

/// The reader behind the scan door.
///
/// With Supabase configured it is the real `import-receipt` edge function.
/// Unconfigured it FAILS LOUDLY rather than falling through to the replay
/// payload, which would have a misconfigured build answer "read this receipt"
/// with somebody else's groceries. Tests and a walkthrough build reach
/// `ReplayReceiptRepository` by naming it, never by accident.

final class ReceiptImportRepositoryProvider
    extends
        $FunctionalProvider<
          ReceiptImportRepository,
          ReceiptImportRepository,
          ReceiptImportRepository
        >
    with $Provider<ReceiptImportRepository> {
  /// The reader behind the scan door.
  ///
  /// With Supabase configured it is the real `import-receipt` edge function.
  /// Unconfigured it FAILS LOUDLY rather than falling through to the replay
  /// payload, which would have a misconfigured build answer "read this receipt"
  /// with somebody else's groceries. Tests and a walkthrough build reach
  /// `ReplayReceiptRepository` by naming it, never by accident.
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

/// Every receipt the household has kept, newest first, as the ledger reads
/// them.
///
/// The row's printed total is what it cost where the paper printed one, and
/// the sum of its own lines where it did not — a hand-typed price prints
/// neither a tax nor a total, and reading `$0` for it would be a lie about a
/// shop that happened.

@ProviderFor(receiptSummaries)
const receiptSummariesProvider = ReceiptSummariesProvider._();

/// Every receipt the household has kept, newest first, as the ledger reads
/// them.
///
/// The row's printed total is what it cost where the paper printed one, and
/// the sum of its own lines where it did not — a hand-typed price prints
/// neither a tax nor a total, and reading `$0` for it would be a lie about a
/// shop that happened.

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
  /// Every receipt the household has kept, newest first, as the ledger reads
  /// them.
  ///
  /// The row's printed total is what it cost where the paper printed one, and
  /// the sum of its own lines where it did not — a hand-typed price prints
  /// neither a tax nor a total, and reading `$0` for it would be a lie about a
  /// shop that happened.
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

String _$receiptSummariesHash() => r'5b0c42a996eabc34ec71f4e42ef67beb3ecccb84';

/// One stored receipt, for the ledger's read-only review.

@ProviderFor(storedReceipt)
const storedReceiptProvider = StoredReceiptFamily._();

/// One stored receipt, for the ledger's read-only review.

final class StoredReceiptProvider
    extends
        $FunctionalProvider<
          AsyncValue<StoredReceipt?>,
          StoredReceipt?,
          Stream<StoredReceipt?>
        >
    with $FutureModifier<StoredReceipt?>, $StreamProvider<StoredReceipt?> {
  /// One stored receipt, for the ledger's read-only review.
  const StoredReceiptProvider._({
    required StoredReceiptFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'storedReceiptProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$storedReceiptHash();

  @override
  String toString() {
    return r'storedReceiptProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<StoredReceipt?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<StoredReceipt?> create(Ref ref) {
    final argument = this.argument as String;
    return storedReceipt(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is StoredReceiptProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$storedReceiptHash() => r'e7cff08d430510207ea85f8cc8a7f7a054ff709e';

/// One stored receipt, for the ledger's read-only review.

final class StoredReceiptFamily extends $Family
    with $FunctionalFamilyOverride<Stream<StoredReceipt?>, String> {
  const StoredReceiptFamily._()
    : super(
        retry: null,
        name: r'storedReceiptProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One stored receipt, for the ledger's read-only review.

  StoredReceiptProvider call(String receiptId) =>
      StoredReceiptProvider._(argument: receiptId, from: this);

  @override
  String toString() => r'storedReceiptProvider';
}

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

/// Whether the household has kept any receipt at all — what decides whether
/// the Shop offers the ledger a door, because a door onto an empty page is
/// furniture.

@ProviderFor(hasAnyReceipt)
const hasAnyReceiptProvider = HasAnyReceiptProvider._();

/// Whether the household has kept any receipt at all — what decides whether
/// the Shop offers the ledger a door, because a door onto an empty page is
/// furniture.

final class HasAnyReceiptProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether the household has kept any receipt at all — what decides whether
  /// the Shop offers the ledger a door, because a door onto an empty page is
  /// furniture.
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
