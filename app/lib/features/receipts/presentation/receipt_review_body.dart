/// The receipt review: what the paper says about itself, then every line.
///
/// The header is the receipt's own facts — the store as a **chip word** with
/// the paper's printed header under it, the date it was bought, the printed
/// totals, and the join card holding the lines' sum against the printed
/// subtotal. Below them the lines, money first, with the two kinds that are
/// not food folded under the list.
///
/// **The join card is a flag, not a refusal.** A receipt whose lines do not
/// add up to its printed subtotal is still a receipt and still saves — the
/// total is the paper's and stands — but it is counted in the header exactly
/// as a line's flag is, because a sum that does not close means a line is
/// missing or doubled and somebody should look.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/money.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_micro_label.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_scroll.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/unit_chip.dart';
import '../../account/data/household_providers.dart';
import '../../books/presentation/text_prompt.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../domain/receipt_payload.dart';
import '../domain/receipt_review.dart';
import 'receipt_date_sheet.dart';
import 'receipt_line_card.dart';
import 'receipt_view_models.dart';

/// The review's Save, so a test names it rather than matching prose.
const kReceiptSaveKey = ValueKey('receipt-save');

/// The join card, likewise.
const kReceiptJoinKey = ValueKey('receipt-join');

/// *Delete this receipt*, on a saved one.
const kReceiptDeleteKey = ValueKey('receipt-delete');

/// The Bought line — the date's door.
const kReceiptBoughtKey = ValueKey('receipt-bought');

class ReceiptReviewBody extends ConsumerWidget {
  const ReceiptReviewBody({required this.state, super.key});

  final ReceiptReviewing state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final map = state.map;
    final kept = [
      for (final d in state.drafts)
        if (d.kind.isFood || d.dropped) d,
    ];
    final folded = [
      for (final d in state.drafts)
        if (!d.dropped && d.kind == ReceiptKind.notFood) d,
    ];
    return ListView(
      padding: ansiScrollPadding(
        context,
        const EdgeInsets.fromLTRB(20, 4, 20, 28),
      ),
      children: [
        if (state.payload.notes.isNotEmpty) _Notes(notes: state.payload.notes),
        const SizedBox(height: 10),
        const AnsiMicroLabel('STORE'),
        const SizedBox(height: 6),
        _StoreChips(state: state),
        if (state.source == 'manual')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'typed by hand, on the ingredient’s page',
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          ),
        if (state.payload.storePrinted case final printed?)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'from receipt:  $printed'
              '${state.payload.purchasedAtPrinted == null ? '' : ' · '
                        '${state.payload.purchasedAtPrinted}'}',
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          ),

        const SizedBox(height: 16),
        const AnsiMicroLabel('BOUGHT'),
        const SizedBox(height: 6),
        _Bought(state: state),

        const SizedBox(height: 16),
        const AnsiMicroLabel('PRINTED TOTALS'),
        const SizedBox(height: 6),
        _PrintedTotals(payload: state.payload),

        const SizedBox(height: 12),
        _JoinCard(map: map),

        const SizedBox(height: 14),
        _SectionRule(label: 'Lines', count: kept.length),
        for (final draft in kept)
          ReceiptLineCard(
            key: ValueKey('receipt-line-${draft.index}'),
            draft: draft,
            issues: map.issuesByIndex[draft.index] ?? const [],
            row: state.rows[draft.ingredientId],
          ),

        if (foldedHeading(map) case final heading?) ...[
          const SizedBox(height: 14),
          _FoldHeading(label: heading),
          for (final draft in folded) _FoldedRow(draft: draft),
        ],
        if (taxHeading(map) case final heading?) ...[
          const SizedBox(height: 10),
          _FoldHeading(label: heading),
        ],

        const SizedBox(height: 18),
        _SaveBar(state: state),
      ],
    );
  }
}

/// What the reader could not read, in its own words — above everything, so it
/// is read as being about the whole receipt.
class _Notes extends StatelessWidget {
  const _Notes({required this.notes});

  final List<String> notes;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AnsiColors.paper,
      border: Border.all(color: AnsiColors.line),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              FLucideIcons.triangleAlert,
              size: 12,
              color: AnsiColors.aging,
            ),
            const SizedBox(width: 6),
            Text(
              'What we could not read',
              style: ansiMono(size: 10.5, color: AnsiColors.aging),
            ),
          ],
        ),
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '· $note',
              style: ansiSans(size: 12, color: AnsiColors.muted, height: 1.35),
            ),
          ),
      ],
    ),
  );
}

/// The household's words for its shops, with `＋` to name a new one. It is
/// the price sheet's own chip row: a store is a word, not a row, and there is
/// one control for picking one.
class _StoreChips extends ConsumerWidget {
  const _StoreChips({required this.state});

  final ReceiptReviewing state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remembered =
        ref.watch(priceStoresProvider).asData?.value ?? const <String>[];
    final stores = <String>[
      ...state.coinedStores,
      for (final word in remembered)
        if (!state.coinedStores.contains(word)) word,
    ];
    return SizedBox(
      height: kUnitChipHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final word in stores)
              UnitChip(
                label: word,
                selected: word == state.store,
                onTap: () => ref
                    .read(receiptScanControllerProvider.notifier)
                    .pickStore(word),
              ),
            // A real icon, never a `＋` glyph — the bundled fonts carry no
            // U+FF0B and it would render as tofu.
            UnitChip(
              icon: const Icon(
                FLucideIcons.plus,
                size: 13,
                color: AnsiColors.herb,
              ),
              accent: true,
              onTap: () async {
                final container = ProviderScope.containerOf(
                  context,
                  listen: false,
                );
                final typed = await promptForText(
                  context,
                  title: 'Where',
                  hint: 'e.g. Whole Foods',
                  confirm: 'Use it',
                );
                if (typed == null || typed.trim().isEmpty) return;
                container
                    .read(receiptScanControllerProvider.notifier)
                    .pickStore(typed);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The receipt's own moment, and the door to correct it.
///
/// What is drawn is what was read, with the header's own line above to check
/// it against — and a tap opens the calendar ([showReceiptDateSheet]), because
/// the date decides which week the receipt files under and a reader that
/// missed it must not get the last word. A receipt the reader could not date
/// opens on the day of the scan, and says so until somebody says otherwise.
class _Bought extends ConsumerWidget {
  const _Bought({required this.state});

  final ReceiptReviewing state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = ref.watch(weekShapeProvider);
    final at = state.purchasedAt;
    final day = shape.labelFull(shape.offsetOf(at));
    final clock =
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    final moved = state.purchasedAt != state.openedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnsiTap(
          key: kReceiptBoughtKey,
          onTap: () async {
            // Captured BEFORE the await: a `ref` used after the sheet closes
            // can belong to an unmounted row (Riverpod 3 throws).
            final container = ProviderScope.containerOf(context, listen: false);
            final picked = await showReceiptDateSheet(context, current: at);
            if (picked == null) return;
            container
                .read(receiptScanControllerProvider.notifier)
                .setPurchasedAt(picked);
          },
          semanticsLabel: 'Change the date',
          minTarget: false,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$day ${formatDayMonth(at)} · $clock',
                style: ansiMono(size: 13),
              ),
              const SizedBox(width: 8),
              const Icon(FLucideIcons.pencil, size: 12, color: AnsiColors.herb),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            moved
                ? 'the day you said — it files under the week it falls in'
                : state.payload.purchasedAt == null
                ? 'the paper printed no date we could read — this is the day '
                      'it was scanned. Tap to say when the shop happened'
                : 'the receipt’s own date, not the scan’s — it files under '
                      'the week it falls in',
            style: ansiMono(size: 10, color: AnsiColors.muted),
          ),
        ),
      ],
    );
  }
}

class _PrintedTotals extends StatelessWidget {
  const _PrintedTotals({required this.payload});

  final ReceiptPayload payload;

  @override
  Widget build(BuildContext context) {
    final rows = <({String label, int? cents, bool bold})>[
      (label: 'Subtotal', cents: payload.subtotalCents, bold: false),
      (label: 'Tax', cents: payload.taxCents, bold: false),
      (label: 'Total', cents: payload.totalCents, bold: true),
    ];
    return Column(
      children: [
        for (final row in rows)
          if (row.cents != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.label,
                      style: ansiSans(
                        size: 12.5,
                        color: AnsiColors.muted,
                        weight: row.bold ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  Text(
                    formatMoney(row.cents!),
                    style: ansiMono(
                      size: 12,
                      weight: row.bold ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// The lines' sum held against the printed subtotal — closed, or apart.
class _JoinCard extends StatelessWidget {
  const _JoinCard({required this.map});

  final ReceiptReviewMap map;

  @override
  Widget build(BuildContext context) {
    final closes = map.joinCloses;
    return Container(
      key: kReceiptJoinKey,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: closes ? AnsiColors.herbSoft : AnsiColors.surface,
        border: Border.all(color: closes ? AnsiColors.herb : AnsiColors.aging),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            closes ? FLucideIcons.check : FLucideIcons.triangleAlert,
            size: 14,
            color: closes ? AnsiColors.herb : AnsiColors.aging,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(joinSumLine(map), style: ansiSans(size: 13)),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    joinNote(map),
                    style: ansiMono(
                      size: 10.5,
                      color: closes ? AnsiColors.muted : AnsiColors.aging,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionRule extends StatelessWidget {
  const _SectionRule({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(label, style: ansiSerif(size: AnsiType.small)),
      const SizedBox(width: 8),
      Text('$count', style: ansiMono(size: 11, color: AnsiColors.muted)),
      const SizedBox(width: 10),
      Expanded(child: Container(height: 1, color: AnsiColors.line)),
    ],
  );
}

class _FoldHeading extends StatelessWidget {
  const _FoldHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      label,
      style: ansiMono(size: 10, color: AnsiColors.muted, letterSpacing: 0.5),
    ),
  );
}

/// A folded line: what it was and what it cost, and the way back. It counts
/// toward the total and toward no price.
class _FoldedRow extends ConsumerWidget {
  const _FoldedRow({required this.draft});

  final ReceiptLineDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            draft.printedText.isEmpty ? draft.displayName : draft.printedText,
            style: ansiMono(size: 11, color: AnsiColors.muted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          formatMoney(draft.paidCents),
          style: ansiMono(size: 11, color: AnsiColors.muted),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref
              .read(receiptScanControllerProvider.notifier)
              .unfold(draft.index),
          child: Text(
            'it is food',
            style: ansiMono(size: 10.5, color: AnsiColors.herbDeep),
          ),
        ),
      ],
    ),
  );
}

/// Save, and the one sentence that says why it is shut. It reads the same map
/// the header count and every card flag read.
class _SaveBar extends ConsumerWidget {
  const _SaveBar({required this.state});

  final ReceiptReviewing state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final map = state.map;
    final named = state.store.trim().isNotEmpty;
    // A kept receipt has nothing to save until something has moved.
    final open = map.canSave && named && (!state.isSaved || state.edited);
    return Column(
      children: [
        FButton(
          key: kReceiptSaveKey,
          onPress: open
              ? () => ref.read(receiptScanControllerProvider.notifier).save()
              : null,
          child: Text(
            !named
                ? 'Say which shop this was'
                : receiptSaveLabel(map, saved: state.isSaved),
          ),
        ),
        if (!map.joinCloses)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'The receipt saves either way — the printed total is the '
              'paper’s, and it stands.',
              textAlign: TextAlign.center,
              style: ansiSans(
                size: 11.5,
                color: AnsiColors.muted,
                height: 1.35,
              ),
            ),
          ),
        if (state.isSaved) ...[
          const SizedBox(height: 14),
          AnsiTap(
            key: kReceiptDeleteKey,
            onTap: () async {
              final container = ProviderScope.containerOf(
                context,
                listen: false,
              );
              final sure = await askAnsi(
                context,
                title: 'Delete this receipt?',
                body:
                    'It leaves the ledger, and every price it stated stops '
                    'being one.',
                confirm: 'Delete',
                cancel: 'Keep it',
              );
              if (!sure) return;
              await container
                  .read(receiptScanControllerProvider.notifier)
                  .delete();
            },
            semanticsLabel: 'Delete this receipt',
            child: Text(
              'delete this receipt',
              style: ansiMono(size: 11.5, color: AnsiColors.gone),
            ),
          ),
        ],
      ],
    );
  }
}
