/// Riverpod wiring for the receipts data layer.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/env.dart';
import '../../../core/sync/database.dart';
import '../../../core/sync/session.dart';
import '../../account/data/household_providers.dart';
import '../../import/data/remote_import_repository.dart';
import '../domain/receipt_ledger.dart';
import '../domain/receipt_payload.dart';
import '../domain/receipt_repository.dart';
import '../domain/receipt_stage.dart';
import 'receipt_repository_impl.dart';
import 'remote_receipt_repository.dart';

part 'receipt_providers.g.dart';

/// The reader behind the scan door: the `import-receipt` edge function when
/// Supabase is configured. Unconfigured, it fails loudly rather than serving
/// the replay payload. Tests reach `ReplayReceiptRepository` by naming it.
@Riverpod(keepAlive: true)
ReceiptImportRepository receiptImportRepository(Ref ref) {
  if (!Env.isConfigured) return const _UnconfiguredReceiptReader();
  return EdgeReceiptRepository(
    functions: ref.watch(supabaseClientProvider).functions,
  );
}

class _UnconfiguredReceiptReader implements ReceiptImportRepository {
  const _UnconfiguredReceiptReader();

  @override
  Future<ReceiptPayload> readReceipt(
    ReceiptPhotos photos, {
    void Function(ReceiptProgress)? onProgress,
  }) async {
    throw const ImportException(
      'reading a receipt needs a connection to the Ansi backend, and this '
      'build has none configured — sign in against a configured backend to '
      'scan one',
    );
  }
}

/// The ledger itself — always local, like every other read.
@Riverpod(keepAlive: true)
ReceiptRepository receiptRepository(Ref ref) => SqliteReceiptRepository(
  ref.watch(databaseProvider),
  householdId: ref.watch(currentHouseholdIdProvider),
);

/// Every receipt the household has kept, newest first. A row costs the printed
/// total, else its lines plus tax (the printed tax, else the tax lines).
@riverpod
Stream<List<ReceiptSummary>> receiptSummaries(Ref ref) => ref
    .watch(receiptRepositoryProvider)
    .watchReceipts()
    .map(
      (rows) => [
        for (final r in rows)
          ReceiptSummary(
            id: r.id,
            store: r.store,
            purchasedAt: r.purchasedAt,
            totalCents:
                r.totalCents ??
                (r.linesSumCents + (r.taxCents ?? r.taxLinesCents)),
            lineCount: r.lineCount,
            notFoodCount: r.notFoodCount,
          ),
      ],
    );

/// The receipts dated inside the week beginning [weekStart] — the band's
/// second figure, and nothing else.
@riverpod
List<ReceiptSummary> receiptsForWeek(Ref ref, DateTime weekStart) {
  final all = ref.watch(receiptSummariesProvider).asData?.value;
  if (all == null) return const [];
  return receiptsInWeek(all, weekStart, ref.watch(weekShapeProvider));
}

/// Whether the household has kept any receipt, which decides whether the Shop
/// shows the ledger door.
@riverpod
bool hasAnyReceipt(Ref ref) =>
    (ref.watch(receiptSummariesProvider).asData?.value ?? const []).isNotEmpty;
