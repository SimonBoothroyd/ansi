/// One line of a receipt, as a card — the recipe review's own component,
/// carrying **money where a recipe line carries an amount**.
///
/// Collapsed, a settled line is one sentence with the sum first: `$3.49 ·
/// Bananas, organic · bag (454 g) · 77¢ / 100 g`. The note under the name is
/// the pack and what the two come to per basis, which is the whole chain a
/// reader needs to check the figure. A discount printed under the item is
/// folded into that sum and shown as a deduction on the same line, because
/// what you paid is the price.
///
/// Two flags a recipe line never raises, each with its own door:
///
/// * **Say what the pack is** — a matched row that neither sold by weight
///   here nor has a pack yet. The door is the price sheet's *for* field
///   ([showReceiptPackSheet]), with *keep as a measure* under it.
/// * **Match an ingredient** — the did-you-mean chips, the picker, and **Not
///   food**, which folds the line under the list where it still counts toward
///   the total and never toward a price.
///
/// **The match is the server's, each time.** Confirming one teaches the
/// vocabulary nothing, so there is no alias-learning path anywhere on this
/// screen. What carries over is the pack, on the row.
///
/// **An answer answers every line that is this line again.** A receipt prints
/// one item six times when six were bought, so the open card says
/// `×6 on this receipt` before the doors rather than after them
/// ([sameLineAgainNote]) — apply-and-tell, so six cards settling at once is
/// what the person was told would happen. The drop and the PRICE chip are
/// corrections to the paper and stay on their own line.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/money.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../shared/ansi_tap.dart';
import '../../books/presentation/text_prompt.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/ingredient_picker.dart';
import '../../recipes/presentation/line_card.dart';
import '../domain/receipt_review.dart';
import 'receipt_pack_sheet.dart';
import 'receipt_view_models.dart';

/// One review line. [readOnly] is the ledger's posture: a saved receipt is
/// read back as matched, with no doors and no flags.
class ReceiptLineCard extends ConsumerWidget {
  const ReceiptLineCard({
    required this.draft,
    required this.issues,
    this.row,
    this.storedBasis,
    this.readOnly = false,
    super.key,
  });

  final ReceiptLineDraft draft;
  final List<ReceiptLineIssue> issues;

  /// The matched vocabulary row, or null where the line names none.
  final Ingredient? row;

  /// The basis a STORED line's figures are denominated in, read off the join
  /// rather than off a row this screen never loads. Null while reviewing,
  /// where [row] answers instead.
  final MacrosBasis? storedBasis;

  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (draft.dropped) {
      return _DroppedLine(
        draft: draft,
        onUndo: () => ref
            .read(receiptScanControllerProvider.notifier)
            .undrop(draft.index),
      );
    }
    final label = receiptAttentionLabel(issues);
    return LineCard(
      attention: label != null,
      collapsed: (expand) => _Collapsed(
        draft: draft,
        basis: row?.macrosBasis ?? storedBasis,
        label: label,
        onExpand: readOnly ? null : expand,
      ),
      expanded: (collapse) =>
          _Expanded(draft: draft, row: row, label: label, onCollapse: collapse),
    );
  }
}

/// The row at rest: money, name, and the chain under it — or the flag.
class _Collapsed extends StatelessWidget {
  const _Collapsed({
    required this.draft,
    required this.basis,
    required this.label,
    this.onExpand,
  });

  final ReceiptLineDraft draft;
  final MacrosBasis? basis;
  final String? label;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    final basis = this.basis;
    final note = basis == null ? null : packAndUnitPrice(draft, basis: basis);
    final discount = discountWords(draft);
    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 62,
          child: Text(formatMoney(draft.paidCents), style: ansiMono(size: 13)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                draft.displayName,
                style: ansiSerif(size: AnsiType.row),
                overflow: TextOverflow.ellipsis,
              ),
              if (note != null || discount != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    [
                      if (discount != null) discount,
                      if (note != null) note,
                    ].join(' · '),
                    style: ansiMono(size: 10.5, color: AnsiColors.muted),
                  ),
                ),
              if (label != null)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: ReceiptAttentionTag(label: label!),
                ),
              ReceiptSourceLine(draft: draft),
            ],
          ),
        ),
        if (onExpand != null) ...[
          const SizedBox(width: 6),
          const Icon(FLucideIcons.pencil, size: 12, color: AnsiColors.herb),
        ],
      ],
    );
    if (onExpand == null) return body;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onExpand,
      child: body,
    );
  }
}

/// The open card: the paper's words, what the line is, and the door its flag
/// names.
class _Expanded extends ConsumerWidget {
  const _Expanded({
    required this.draft,
    required this.row,
    required this.label,
    required this.onCollapse,
  });

  final ReceiptLineDraft draft;
  final Ingredient? row;
  final String? label;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(receiptScanControllerProvider.notifier);
    final basis = row?.macrosBasis;
    final again = switch (ref.watch(receiptScanControllerProvider)) {
      ReceiptReviewing(:final drafts) => sameLineAgainNote(drafts, draft.index),
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LineCardHead(
          identity: Row(
            children: [
              Text(formatMoney(draft.paidCents), style: ansiMono(size: 13)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  draft.displayName,
                  style: ansiSerif(size: AnsiType.row),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          onRemove: () => controller.drop(draft.index),
          onCollapse: onCollapse,
        ),
        ReceiptSourceLine(draft: draft),
        if (again != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              again,
              style: ansiMono(size: 10.5, color: AnsiColors.herbDeep),
            ),
          ),
        if (draft.lowConfidence)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'low confidence — check this one against the paper',
              style: ansiMono(size: 10.5, color: AnsiColors.muted),
            ),
          ),
        // The figure is a door on EVERY line, not only on one the reader gave
        // up on: a `$4.99` read as `$4.49` is wrong without being zero, and
        // the join card can only say that something is — this is where it is
        // put right. A line with no figure gets the louder door below.
        if (!issuesInclude(draft, ReceiptLineIssue.amountMissing)) ...[
          const SizedBox(height: 10),
          LineCardRow(
            label: 'PRICE',
            child: LineCardAmountChip(
              key: ValueKey('receipt-line-price-${draft.index}'),
              label: formatMoney(draft.cents),
              onTap: () => _setCents(context, draft),
            ),
          ),
        ],
        if (row != null) ...[
          const SizedBox(height: 8),
          _ChosenRow(
            name: row!.canonicalName,
            onChange: () => _pick(context, draft.index),
          ),
        ],
        if (label != null) ...[
          const SizedBox(height: 8),
          ReceiptAttentionTag(label: label!),
        ],
        if (issuesInclude(draft, ReceiptLineIssue.amountMissing)) ...[
          const SizedBox(height: 10),
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => _setCents(context, draft),
            child: const Text('Set the amount'),
          ),
          const SizedBox(height: 6),
          Text(
            'the reader could not make this figure out — read it off the '
            'paper, or drop the line',
            style: ansiMono(size: 10.5, color: AnsiColors.muted),
          ),
        ],
        if (issuesInclude(draft, ReceiptLineIssue.unmatched)) ...[
          if (draft.suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('DID YOU MEAN', style: ansiLabel()),
            const SizedBox(height: 6),
            _Suggestions(draft: draft),
          ],
          const SizedBox(height: 10),
          FButton(
            variant: FButtonVariant.outline,
            prefix: const Icon(FLucideIcons.search),
            onPress: () => _pick(context, draft.index),
            child: const Text('Something else'),
          ),
          const SizedBox(height: 8),
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => controller.fold(draft.index),
            child: const Text('Not food'),
          ),
        ] else if (row != null && basis != null) ...[
          const SizedBox(height: 10),
          LineCardRow(
            label: 'PACK',
            child: LineCardAmountChip(
              label: packWords(draft, basis: basis) ?? '',
              onTap: () => _setPack(context, draft, row!),
            ),
          ),
          if (draft.keepAsMeasure case final word?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'kept as a measure on save: $word',
                style: ansiMono(size: 10.5, color: AnsiColors.herbDeep),
              ),
            ),
          const SizedBox(height: 8),
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => controller.fold(draft.index),
            child: const Text('Not food'),
          ),
        ],
      ],
    );
  }

  Future<void> _pick(BuildContext context, int index) async {
    // The container and the host are captured BEFORE the sheet's await: this
    // card is a row of a viewport, the sheet's keyboard shrinks it, and a
    // `ref` used after the row is unmounted throws (Riverpod 3).
    final container = ProviderScope.containerOf(context, listen: false);
    final picked = await showIngredientPicker(
      context,
      title: 'What is this line?',
    );
    if (picked == null) return;
    await container
        .read(receiptScanControllerProvider.notifier)
        .matchLine(index, picked);
  }

  /// The money door — for a figure the reader could not make out, and for
  /// one it made out wrong. It is a prompt rather than a sheet: there is one
  /// number to read off the paper, and the pack sheet's whole apparatus would
  /// be furniture around it.
  Future<void> _setCents(BuildContext context, ReceiptLineDraft draft) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final typed = await promptForText(
      context,
      title: 'What did this line cost?',
      hint: 'e.g. 3.49',
      confirm: 'Use it',
      // Opens on what was read, so fixing one digit is fixing one digit.
      initial: draft.cents > 0 ? dollarsTyped(draft.cents) : '',
    );
    final cents = typed == null ? null : parseMoney(typed);
    if (cents == null || cents <= 0) return;
    container
        .read(receiptScanControllerProvider.notifier)
        .setCents(draft.index, cents);
  }

  Future<void> _setPack(
    BuildContext context,
    ReceiptLineDraft draft,
    Ingredient row,
  ) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final measures = switch (container.read(receiptScanControllerProvider)) {
      ReceiptReviewing(:final measuresById) =>
        measuresById[row.id] ?? const <Measure>[],
      _ => const <Measure>[],
    };
    final answer = await showReceiptPackSheet(
      context,
      ingredient: row,
      paidCents: draft.paidCents,
      amount: draft.packAmount,
      choice: _choiceOf(draft, measures),
    );
    if (answer == null) return;
    container
        .read(receiptScanControllerProvider.notifier)
        .setPack(
          draft.index,
          amount: answer.amount,
          choice: answer.choice,
          basisAmount: answer.basisAmount,
          keepAsMeasure: answer.keepAsMeasure,
        );
  }
}

/// The chip the pack was entered on, resolved against the row's measures —
/// what the pack sheet reopens on. Null where the line has no pack yet, and
/// the sheet then opens on its own default.
UnitChoice? _choiceOf(ReceiptLineDraft draft, List<Measure> measures) {
  final unit = draft.packUnit;
  if (unit != null) return UnitOption(unit);
  final id = draft.measureId;
  if (id == null) return null;
  for (final m in measures) {
    if (m.id == id) return MeasureOption(m);
  }
  return null;
}

bool issuesInclude(ReceiptLineDraft draft, ReceiptLineIssue issue) =>
    receiptLineIssues(draft).contains(issue);

/// The did-you-mean chips. Tapping one resolves the line to that row — the
/// person's act, never the cascade's (ADR-0004).
class _Suggestions extends ConsumerWidget {
  const _Suggestions({required this.draft});

  final ReceiptLineDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final suggestion in draft.suggestions)
        AnsiTap(
          onTap: () async {
            final container = ProviderScope.containerOf(context, listen: false);
            final row = await container
                .read(receiptScanControllerProvider.notifier)
                .rowFor(suggestion.ingredientId);
            if (row == null) return;
            await container
                .read(receiptScanControllerProvider.notifier)
                .matchLine(draft.index, row);
          },
          semanticsLabel: 'Match ${suggestion.name}',
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AnsiColors.paper,
              border: Border.all(color: AnsiColors.line),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(suggestion.name, style: ansiMono(size: 11)),
            ),
          ),
        ),
    ],
  );
}

/// The matched row, with the way to change it — the recipe review's own
/// chosen-row line.
class _ChosenRow extends StatelessWidget {
  const _ChosenRow({required this.name, required this.onChange});

  final String name;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onChange,
    child: Row(
      children: [
        const Icon(FLucideIcons.check, size: 13, color: AnsiColors.herb),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            name,
            style: ansiSans(size: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          'tap to change',
          style: ansiMono(size: 10.5, color: AnsiColors.muted),
        ),
        const SizedBox(width: 4),
        const Icon(
          FLucideIcons.chevronRight,
          size: 13,
          color: AnsiColors.muted,
        ),
      ],
    ),
  );
}

/// `from receipt:  TJ ORG BANANAS  3.49` — the paper's own words, always
/// visible. From a photograph there is no other way to check what was read.
class ReceiptSourceLine extends StatelessWidget {
  const ReceiptSourceLine({required this.draft, super.key});

  final ReceiptLineDraft draft;

  @override
  Widget build(BuildContext context) {
    if (draft.printedText.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(
        'from receipt:  ${draft.printedText}',
        style: ansiMono(size: 10, color: AnsiColors.muted),
      ),
    );
  }
}

/// The amber `⚠ label` a flagged card wears.
class ReceiptAttentionTag extends StatelessWidget {
  const ReceiptAttentionTag({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(FLucideIcons.triangleAlert, size: 11, color: AnsiColors.aging),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          label,
          style: ansiMono(size: 10.5, color: AnsiColors.aging),
        ),
      ),
    ],
  );
}

/// The "as deleted" card: the line stays on screen, greyed and plainly
/// labelled, with the undo beside it. Nothing is written until Save, so this
/// state IS the whole deletion — reversible, visible, and out of the count.
class _DroppedLine extends StatelessWidget {
  const _DroppedLine({required this.draft, required this.onUndo});

  final ReceiptLineDraft draft;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) => LineCardSurface(
    dropped: true,
    child: Row(
      children: [
        Expanded(
          child: Text(
            '${draft.displayName} — dropped',
            style: ansiMono(size: 11.5, color: AnsiColors.muted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        AnsiTap(
          onTap: onUndo,
          semanticsLabel: 'Keep the line',
          child: Text(
            'undo',
            style: ansiMono(size: 11.5, color: AnsiColors.herbDeep),
          ),
        ),
      ],
    ),
  );
}
