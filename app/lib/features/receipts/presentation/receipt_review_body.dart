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

import 'dart:async';

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
import '../../../shared/dashed_border_box.dart';
import '../../../shared/write.dart';
import '../../account/data/household_providers.dart';
import '../../books/presentation/text_prompt.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/presentation/ingredient_picker.dart';
import '../../ingredients/presentation/price_fields.dart';
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

/// Why the last write did not happen, over Save.
const kReceiptErrorKey = ValueKey('receipt-error');

/// The Bought line — the date's door.
const kReceiptBoughtKey = ValueKey('receipt-bought');

/// *add a line* — the door for a line the reader missed.
const kReceiptAddLineKey = ValueKey('receipt-add-line');

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
        if (state.isManual)
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

        // A hand-typed price has no paper to print totals or to join against.
        if (!state.isManual) ...[
          const SizedBox(height: 16),
          const AnsiMicroLabel('PRINTED TOTALS'),
          const SizedBox(height: 6),
          _PrintedTotals(payload: state.payload),

          const SizedBox(height: 12),
          _JoinCard(map: map),
        ],

        const SizedBox(height: 14),
        _SectionRule(label: 'Lines', count: kept.length),
        for (final draft in kept)
          ReceiptLineCard(
            key: ValueKey('receipt-line-${draft.index}'),
            draft: draft,
            issues: map.issuesByIndex[draft.index] ?? const [],
            row: state.rows[draft.ingredientId],
            manual: state.isManual,
          ),
        const SizedBox(height: 8),
        const _AddLineDoor(),

        if (foldedHeading(map) case final heading?) ...[
          const SizedBox(height: 14),
          _FoldHeading(label: heading),
          for (final draft in folded)
            _FoldedRow(
              draft: draft,
              count: linesAnsweredWith(state.drafts, draft.index).length,
            ),
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

/// The household's store words, on the price sheet's own chip row.
class _StoreChips extends ConsumerWidget {
  const _StoreChips({required this.state});

  final ReceiptReviewing state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remembered =
        ref.watch(priceStoresProvider).asData?.value ?? const <String>[];
    // Held from the build: the prompt can outlive this row, and a `ref` used
    // after unmount throws.
    final container = ProviderScope.containerOf(context, listen: false);
    void pick(String word) =>
        container.read(receiptScanControllerProvider.notifier).pickStore(word);
    return StoreChipRow(
      stores: [
        ...state.coinedStores,
        for (final word in remembered)
          if (!state.coinedStores.contains(word)) word,
      ],
      selected: state.store,
      onSelect: pick,
      onCoined: pick,
    );
  }
}

/// When the shop happened, and the door to correct it: the date decides which
/// week the receipt files under. An undated receipt opens on the scan day and
/// says so.
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
    final caption = state.purchasedAt != state.openedAt
        ? 'the day you said'
        // A saved receipt's date was confirmed when it was saved.
        : state.isSaved
        ? null
        : state.payload.purchasedAt == null
        ? 'the paper printed no date — this is the scan day'
        : 'the receipt’s own date, not the scan’s';
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
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              caption,
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

/// *add a line* — for the row the reader missed.
///
/// The reader loses a line to a fold in the paper or a torn strip, and the join
/// card is what says so; this is where the line is put back. Two questions,
/// each on the door the screen already uses for it: the ingredient picker (the
/// card's *Something else*) and the money prompt (the card's PRICE chip).
/// Backing out of either adds nothing, so the door itself writes nothing.
class _AddLineDoor extends StatelessWidget {
  const _AddLineDoor();

  @override
  Widget build(BuildContext context) => DashedAction(
    key: kReceiptAddLineKey,
    icon: FLucideIcons.plus,
    label: 'add a line',
    onTap: () => unawaited(_addLine(context)),
  );

  /// The picker, then the money, then the line.
  ///
  /// The container and the host are captured BEFORE the first await: the
  /// picker's keyboard shrinks this viewport, so the door itself can be
  /// unmounted by the time either answer arrives, and the second door is
  /// opened on the overlay that outlives it.
  static Future<void> _addLine(BuildContext context) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final host = hostContextOf(context);
    final picked = await showIngredientPicker(
      context,
      title: 'What is this line?',
    );
    if (picked == null) return;
    final typed = await promptForText(
      // The host outlives the row — see [hostContextOf].
      // ignore: use_build_context_synchronously
      host.context,
      title: 'What did this line cost?',
      hint: 'e.g. 3.49',
      confirm: 'Use it',
    );
    final cents = typed == null ? null : parseMoney(typed);
    if (cents == null || cents <= 0) return;
    await container
        .read(receiptScanControllerProvider.notifier)
        .addLine(picked, cents);
  }
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
  const _FoldedRow({required this.draft, required this.count});

  final ReceiptLineDraft draft;

  /// How many lines *it is food* answers: this one and its twins.
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            [
              if (draft.printedText.isEmpty)
                draft.displayName
              else
                draft.printedText,
              if (count > 1) '×$count',
            ].join(' · '),
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
        AnsiTap(
          onTap: () => ref
              .read(receiptScanControllerProvider.notifier)
              .unfold(draft.index),
          minTarget: false,
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
    // Every line dropped writes no receipt at all — the ledger refuses one,
    // and `canSave` is where that is decided, so the button reads the map
    // rather than counting the drafts a second time.
    final empty = map.keptCount == 0;
    // A kept receipt has nothing to save until something has moved.
    final open = map.canSave && named && (!state.isSaved || state.edited);
    return Column(
      children: [
        // Why the last write did not happen. The review is untouched under
        // it, so this is a line to read and try again, not a state to leave.
        if (state.error case final message?)
          Padding(
            key: kReceiptErrorKey,
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: ansiSans(size: 12.5, color: AnsiColors.gone, height: 1.35),
            ),
          ),
        FButton(
          key: kReceiptSaveKey,
          onPress: open
              ? () => ref.read(receiptScanControllerProvider.notifier).save()
              : null,
          child: Text(
            !named && !empty
                ? 'Say which shop this was'
                : receiptSaveLabel(map, saved: state.isSaved),
          ),
        ),
        if (empty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              state.isSaved
                  ? 'Every line is dropped. Delete the receipt below.'
                  : 'Every line is dropped. Bring one back to save.',
              textAlign: TextAlign.center,
              style: ansiSans(size: 11.5, color: AnsiColors.muted),
            ),
          ),
        if (!map.joinCloses)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'The receipt saves either way.',
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
                body: 'Its prices go with it.',
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
