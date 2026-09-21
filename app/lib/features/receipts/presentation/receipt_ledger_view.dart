/// The receipts ledger (`/receipts`) and one saved receipt (`/receipts/:id`).
///
/// Receipts file under the household week their date falls in. Each week shows
/// what was spent beside what it plans to cook, never reconciled (ADR-0017),
/// and a month line sums the receipts by store. A saved receipt opens on the
/// same review a scan does.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/money.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
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
import 'receipt_review_body.dart';
import 'receipt_view_models.dart';

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
          'ingredient',
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

/// The week's pair: spent, beside what that week plans to cook. The planned
/// figure shows only for the week the app is currently costing; a past week
/// would be re-costed at today's prices (ADR-0017).
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

/// One saved receipt: the review itself, opened on the stored rows. The scan
/// controller holds the sitting, so nothing is written until Save.
class StoredReceiptView extends ConsumerStatefulWidget {
  const StoredReceiptView({required this.receiptId, super.key});

  final String receiptId;

  @override
  ConsumerState<StoredReceiptView> createState() => _StoredReceiptViewState();
}

class _StoredReceiptViewState extends ConsumerState<StoredReceiptView> {
  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(StoredReceiptView old) {
    super.didUpdateWidget(old);
    if (old.receiptId != widget.receiptId) _open();
  }

  /// After the frame: a provider may not be written while the tree builds.
  void _open() {
    final id = widget.receiptId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(receiptScanControllerProvider.notifier).open(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(receiptScanControllerProvider);
    // A receipt taken back has no page to stay on.
    ref.listen(receiptScanControllerProvider, (previous, next) {
      if (previous is ReceiptSaving && next is ReceiptGone) {
        ansiBack(context, home: '/receipts');
      }
    });
    final reviewing =
        state is ReceiptReviewing && state.receiptId == widget.receiptId
        ? state
        : null;
    final count = reviewing?.map.headerCount ?? 0;
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
        suffixes: [
          if (count > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  '$count to review',
                  style: ansiMono(size: 11, color: AnsiColors.muted),
                ),
              ),
            ),
        ],
      ),
      child: switch (state) {
        _ when reviewing != null => ReceiptReviewBody(state: reviewing),
        ReceiptGone() => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Text(
            'this receipt is gone',
            style: ansiMono(size: 11.5, color: AnsiColors.muted),
          ),
        ),
        ReceiptScanFailed(:final message) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Text(
            message,
            style: ansiSans(size: 13, color: AnsiColors.gone),
          ),
        ),
        _ => const Center(child: FCircularProgress()),
      },
    );
  }
}
