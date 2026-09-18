/// The receipts ledger (`/receipts`) and one saved receipt (`/receipts/:id`).
///
/// **The week is the unit, because the shop is.** Receipts file under the
/// week their own date falls in — the household's week start, so a Sunday
/// shop sits inside the week it feeds — and each week closes with the pair
/// the band shows: what was spent, beside what the same week plans to cook.
/// A month line on top sums the receipts by store.
///
/// The two figures are never reconciled (ADR-0017). The gap between them is
/// the pantry filling or emptying, and nothing here tries to explain it.
///
/// A receipt opens **read-only**, with its lines as matched. A price on one
/// of them is still editable, through the ingredient page's own price sheet —
/// there is one door for a price, and it is not duplicated here.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/money.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
import '../../../core/week_shape.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_back.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_scroll.dart';
import '../../../shared/cost_words.dart';
import '../../../shared/guarded_navigation.dart';
import '../../account/data/household_providers.dart';
import '../../planning/presentation/week_view_models.dart';
import '../data/receipt_providers.dart';
import '../domain/receipt_ledger.dart';
import '../domain/receipt_payload.dart';
import '../domain/receipt_repository.dart';
import '../domain/receipt_review.dart';
import 'receipt_line_card.dart';

/// The ledger's list root, so the tests name it rather than a title.
const kReceiptLedgerKey = ValueKey('receipts-ledger');

class ReceiptLedgerView extends ConsumerWidget {
  const ReceiptLedgerView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipts = ref.watch(receiptSummariesProvider);
    final shape = ref.watch(weekShapeProvider);
    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text('Receipts', style: ansiHeaderTitle()),
        // The ledger belongs to the Shop, which is where its door stands, so
        // a cold link to it goes home there rather than to the Library.
        prefixes: [
          FHeaderAction.back(onPress: () => ansiBack(context, home: '/shop')),
        ],
      ),
      child: receipts.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (e, st) => AnsiErrorState(
          what: 'the receipts',
          error: e,
          stackTrace: st,
          onRetry: () => ref.invalidate(receiptSummariesProvider),
        ),
        data: (all) => _Ledger(receipts: all, shape: shape),
      ),
    );
  }
}

class _Ledger extends ConsumerWidget {
  const _Ledger({required this.receipts, required this.shape});

  final List<ReceiptSummary> receipts;
  final WeekShape shape;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (receipts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: Text(
          'no receipts yet — scan one from the Shop, or type a price on an '
          'ingredient and it lands here as a one-line receipt',
          style: ansiMono(size: 11.5, color: AnsiColors.muted),
        ),
      );
    }
    final weeks = fileByWeek(receipts, shape);
    final month = newestMonth(receipts);
    return ListView(
      key: kReceiptLedgerKey,
      padding: ansiScrollPadding(
        context,
        const EdgeInsets.fromLTRB(20, 8, 20, 28),
      ),
      children: [
        if (month != null) _MonthBand(month: month),
        for (final week in weeks) ...[
          const SizedBox(height: 16),
          Text(
            'Week of ${formatDayMonth(week.weekStart)}',
            style: ansiSerif(size: AnsiType.small),
          ),
          const SizedBox(height: 6),
          for (final receipt in week.receipts)
            _ReceiptRow(receipt: receipt, shape: shape),
          _WeekFoot(week: week),
        ],
      ],
    );
  }
}

/// The month at the top — what has been spent so far, and where.
class _MonthBand extends ConsumerWidget {
  const _MonthBand({required this.month});

  final ReceiptMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: AnsiColors.surface,
      border: Border.all(color: AnsiColors.line),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          monthHeading(month, today: DateTime.now()).toUpperCase(),
          style: ansiMono(size: 9.5, color: AnsiColors.muted, letterSpacing: 1),
        ),
        const SizedBox(height: 8),
        Text(monthLine(month), style: ansiMono(size: 11.5)),
      ],
    ),
  );
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.receipt, required this.shape});

  final ReceiptSummary receipt;
  final WeekShape shape;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => context.pushOnce('/receipts/${receipt.id}'),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  receipt.store,
                  style: ansiSerif(size: AnsiType.row),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                formatMoney(receipt.totalCents),
                style: ansiMono(size: 12.5),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              receipt.subLine(shape),
              style: ansiMono(size: 10.5, color: AnsiColors.muted),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The week's own pair — spent, beside what that week plans to cook.
///
/// The planned figure is only ever shown for the week the app is currently
/// costing: costing an arbitrary past week would mean re-deriving a plan at
/// today's prices and calling it that week's, which is a figure nobody could
/// stand behind (ADR-0017).
class _WeekFoot extends ConsumerWidget {
  const _WeekFoot({required this.week});

  final ReceiptWeek week;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewed = ref.watch(viewedWeekStartProvider);
    final planned = viewed == week.weekStart
        ? ref.watch(weekCostProvider(null)).cents
        : null;
    final count = week.receipts.length;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            [
              weekSpentTotal(week),
              if (planned != null) '${approxMoneyWhole(planned)} to cook',
            ].join(' · '),
            style: ansiMono(size: 11.5),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '$count ${plural(count, 'receipt')}',
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// One saved receipt, read back.
class StoredReceiptView extends ConsumerWidget {
  const StoredReceiptView({required this.receiptId, super.key});

  final String receiptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt = ref.watch(storedReceiptProvider(receiptId));
    final shape = ref.watch(weekShapeProvider);
    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text('Receipt', style: ansiHeaderTitle()),
        // A receipt is a detail OF the ledger, so it goes back to it.
        prefixes: [
          FHeaderAction.back(
            onPress: () => ansiBack(context, home: '/receipts'),
          ),
        ],
      ),
      child: receipt.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (e, st) => AnsiErrorState(
          what: 'this receipt',
          error: e,
          stackTrace: st,
          onRetry: () => ref.invalidate(storedReceiptProvider(receiptId)),
        ),
        data: (stored) => stored == null
            ? Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Text(
                  'this receipt is gone',
                  style: ansiMono(size: 11.5, color: AnsiColors.muted),
                ),
              )
            : _StoredBody(stored: stored, shape: shape),
      ),
    );
  }
}

class _StoredBody extends StatelessWidget {
  const _StoredBody({required this.stored, required this.shape});

  final StoredReceipt stored;
  final WeekShape shape;

  @override
  Widget build(BuildContext context) {
    final read = [
      for (final (index, line) in stored.lines.indexed)
        (
          draft: storedLineDraft(line, index: index),
          basis: MacrosBasis.fromDb(line.macrosBasis),
        ),
    ];
    final drafts = [for (final r in read) r.draft];
    final food = [
      for (final r in read)
        if (r.draft.kind.isFood) r,
    ];
    final folded = [
      for (final r in read)
        if (r.draft.kind == ReceiptKind.notFood) r.draft,
    ];
    final map = receiptReviewMap(
      drafts,
      printedSubtotalCents: stored.subtotalCents,
      printedTaxCents: stored.taxCents,
      printedTotalCents: stored.totalCents,
    );
    final day = shape.labelFull(shape.offsetOf(stored.purchasedAt));
    return ListView(
      padding: ansiScrollPadding(
        context,
        const EdgeInsets.fromLTRB(20, 10, 20, 28),
      ),
      children: [
        Text(stored.store, style: ansiSerif(size: AnsiType.heading)),
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            '$day ${formatDayMonth(stored.purchasedAt)} · '
            '${formatMoney(map.totalCents)}'
            '${stored.source == 'manual' ? ' · typed by hand' : ''}',
            style: ansiMono(size: 11, color: AnsiColors.muted),
          ),
        ),
        const SizedBox(height: 14),
        for (final line in food)
          ReceiptLineCard(
            key: ValueKey('stored-line-${line.draft.index}'),
            draft: line.draft,
            issues: const [],
            storedBasis: line.basis,
            readOnly: true,
          ),
        if (foldedHeading(map) case final heading?) ...[
          const SizedBox(height: 12),
          Text(
            heading,
            style: ansiMono(
              size: 10,
              color: AnsiColors.muted,
              letterSpacing: 0.5,
            ),
          ),
          for (final draft in folded)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      draft.printedText.isEmpty
                          ? draft.displayName
                          : draft.printedText,
                      style: ansiMono(size: 11, color: AnsiColors.muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    formatMoney(draft.paidCents),
                    style: ansiMono(size: 11, color: AnsiColors.muted),
                  ),
                ],
              ),
            ),
        ],
        if (taxHeading(map) case final heading?) ...[
          const SizedBox(height: 10),
          Text(
            heading,
            style: ansiMono(
              size: 10,
              color: AnsiColors.muted,
              letterSpacing: 0.5,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'A price on one of these lines is edited on the ingredient’s own '
          'page — there is one door for a price, and this is not a second '
          'one.',
          style: ansiSans(size: 11.5, color: AnsiColors.muted, height: 1.35),
        ),
      ],
    );
  }
}

/// A stored line as the review's own draft, so the ledger draws it with the
/// card the scan drew it with — one shape for a receipt line, read or
/// written.
ReceiptLineDraft storedLineDraft(
  StoredReceiptLine line, {
  required int index,
}) => ReceiptLineDraft(
  index: index,
  printedText: line.printedText,
  cents: line.cents,
  discountCents: line.discountCents,
  kind: ReceiptKind.fromWire(line.kind),
  ingredientId: line.ingredientId,
  ingredientName: line.ingredientName,
  packBasisAmount: line.packBasisAmount,
  packAmount: line.packAmount,
  packUnit: unitById(line.packUnit ?? ''),
  measureId: line.measureId,
  packLabel: line.measureLabel,
);
