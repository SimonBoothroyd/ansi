/// One line of a receipt as a card, sum first: `$23.92 · Tofu · 8 × block (16
/// oz) · 66¢ / 100 g`.
///
/// Two flags have their own doors: "say what the pack is"
/// ([showReceiptPackSheet]) and "match an ingredient" (chips, the picker, or
/// Not food). Confirming a match writes no alias; a match the server recalled
/// says `as you matched it last time`. An answer applies to every identical
/// line on the receipt ([sameLineAgainNote]); the drop and the price chip stay
/// per line.
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

/// One review line.
class ReceiptLineCard extends ConsumerWidget {
  const ReceiptLineCard({
    required this.draft,
    required this.issues,
    this.row,
    this.manual = false,
    super.key,
  });

  final ReceiptLineDraft draft;
  final List<ReceiptLineIssue> issues;

  /// The matched vocabulary row, or null where the line names none.
  final Ingredient? row;

  /// Whether the receipt was typed by hand on an ingredient's page. The header
  /// already says so, so lines omit `added by hand`.
  final bool manual;

  /// Whether a person added this line in the review rather than the reader
  /// reading it off the paper.
  bool get _byHand => draft.saidByHand && !manual;

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
      // A line just added arrives as a form: its pack and its count are the
      // next things to say, and a closed row would hide both.
      initiallyOpen: _byHand && draft.lineId == null,
      collapsed: (expand) => _Collapsed(
        draft: draft,
        basis: row?.macrosBasis,
        label: label,
        byHand: _byHand,
        onExpand: expand,
      ),
      expanded: (collapse) => _Expanded(
        draft: draft,
        issues: issues,
        row: row,
        label: label,
        byHand: _byHand,
        onCollapse: collapse,
      ),
    );
  }
}

/// The row at rest: money, name, and the chain under it — or the flag.
class _Collapsed extends StatelessWidget {
  const _Collapsed({
    required this.draft,
    required this.basis,
    required this.label,
    required this.byHand,
    required this.onExpand,
  });

  final ReceiptLineDraft draft;
  final MacrosBasis? basis;
  final String? label;
  final bool byHand;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final basis = this.basis;
    final note = basis == null ? null : packAndUnitPrice(draft, basis: basis);
    final discount = discountWords(draft);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onExpand,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              formatMoney(draft.paidCents),
              style: ansiMono(size: 13),
            ),
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
                ReceiptSourceLine(draft: draft, byHand: byHand),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Icon(FLucideIcons.pencil, size: 12, color: AnsiColors.herb),
        ],
      ),
    );
  }
}

/// The open card: the paper's words, what the line is, and the door its flag
/// names.
class _Expanded extends ConsumerWidget {
  const _Expanded({
    required this.draft,
    required this.issues,
    required this.row,
    required this.label,
    required this.byHand,
    required this.onCollapse,
  });

  final ReceiptLineDraft draft;
  final List<ReceiptLineIssue> issues;
  final Ingredient? row;
  final String? label;
  final bool byHand;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(receiptScanControllerProvider.notifier);
    final basis = row?.macrosBasis;
    final amountMissing = issues.contains(ReceiptLineIssue.amountMissing);
    final unmatched = issues.contains(ReceiptLineIssue.unmatched);
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
          // An unsaved hand-added line has no row behind it, so removing it
          // takes it off the list. Every other line is dropped: greyed,
          // undoable, tombstoned at Save.
          onRemove: byHand && draft.lineId == null
              ? () => controller.removeLine(draft.index)
              : () => controller.drop(draft.index),
          onCollapse: onCollapse,
        ),
        ReceiptSourceLine(draft: draft, byHand: byHand),
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
        // The figure is editable on every line: a `$4.99` read as `$4.49` is
        // wrong without being zero. A line with no figure gets the louder door
        // below.
        if (!amountMissing) ...[
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
        // A match at a row this device cannot find still names itself, so the
        // way to re-match it is here.
        if (draft.ingredientId != null) ...[
          const SizedBox(height: 8),
          _ChosenRow(
            name: row?.canonicalName ?? draft.displayName,
            remembered: draft.remembered,
            onChange: () => _pick(context, draft.index),
          ),
        ],
        if (label != null) ...[
          const SizedBox(height: 8),
          ReceiptAttentionTag(label: label!),
        ],
        if (amountMissing) ...[
          const SizedBox(height: 10),
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => _setCents(context, draft),
            child: const Text('Set the amount'),
          ),
          const SizedBox(height: 6),
          Text(
            'read it off the paper, or drop the line',
            style: ansiMono(size: 10.5, color: AnsiColors.muted),
          ),
        ],
        if (unmatched) ...[
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
        ] else if (row != null && basis != null) ...[
          const SizedBox(height: 10),
          LineCardRow(
            label: 'PACK',
            child: LineCardAmountChip(
              label: packWords(draft, basis: basis) ?? '',
              // This chip asks for the pack. "set amount" would name the
              // money door standing beside it on the same card.
              emptyLabel: 'say the pack',
              semanticsLabel: 'Pack',
              onTap: () => _setPack(context, draft, row!),
            ),
          ),
          const SizedBox(height: 8),
          // Beside the pack: the pack is what one comes in, this is how many. A
          // correction to the paper, so it never rides to the line's twins.
          LineCardRow(
            label: 'COUNT',
            child: LineCardAmountChip(
              key: ValueKey('receipt-line-count-${draft.index}'),
              label: countChipLabel(draft.count),
              semanticsLabel: 'How many',
              onTap: () => _setCount(context, draft),
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
        ],
        const SizedBox(height: 8),
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => controller.fold(draft.index),
          child: const Text('Not food'),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, int index) async {
    // The container and host are captured before the sheet's await: the
    // keyboard can unmount this card, and a `ref` used after unmount throws.
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

  /// The money door, for a figure the reader missed or misread. A prompt rather
  /// than a sheet, since there is one number to type.
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

  /// The count door — the same small prompt the money door uses, because it
  /// is the same act: one number read off the paper.
  Future<void> _setCount(BuildContext context, ReceiptLineDraft draft) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final typed = await promptForText(
      context,
      title: 'How many of this rang up?',
      hint: 'e.g. 8',
      confirm: 'Use it',
      initial: '${draft.count}',
    );
    final count = typed == null ? null : int.tryParse(typed.trim());
    if (count == null || count < 1) return;
    container
        .read(receiptScanControllerProvider.notifier)
        .setCount(draft.index, count);
  }

  Future<void> _setPack(
    BuildContext context,
    ReceiptLineDraft draft,
    Ingredient row,
  ) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final state = container.read(receiptScanControllerProvider);
    final reviewing = state is ReceiptReviewing ? state : null;
    final measures = reviewing?.measuresById[row.id] ?? const <Measure>[];
    final answer = await showReceiptPackSheet(
      context,
      ingredient: row,
      paidCents: draft.paidCents,
      count: draft.count,
      amount: draft.packAmount,
      choice: _choiceOf(draft, measures),
      pendingMeasures: reviewing == null
          ? const []
          : _pendingMeasures(reviewing.drafts, draft, row),
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

/// The measures other lines of the receipt will mint for [row] at Save. The
/// lines this answer reaches are left out, since it replaces theirs.
List<Measure> _pendingMeasures(
  List<ReceiptLineDraft> drafts,
  ReceiptLineDraft draft,
  Ingredient row,
) {
  final answered = linesAnsweredWith(drafts, draft.index);
  return [
    for (final d in drafts)
      if (!d.dropped &&
          !answered.contains(d.index) &&
          d.ingredientId == row.id &&
          d.keepAsMeasure != null &&
          d.packBasisAmount != null)
        Measure(
          id: '',
          label: d.keepAsMeasure!,
          amount: d.packBasisAmount!,
          basis: row.macrosBasis,
        ),
  ];
}

/// The chip the pack was entered on, resolved against the row's measures, for
/// reopening the pack sheet. Null when the line has no pack yet.
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

/// The matched row, with the way to change it. A [remembered] row says where
/// the answer came from, beside `tap to change`: changing it becomes the most
/// recent answer.
class _ChosenRow extends StatelessWidget {
  const _ChosenRow({
    required this.name,
    required this.onChange,
    this.remembered = false,
  });

  final String name;
  final bool remembered;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) => AnsiTap(
    onTap: onChange,
    semanticsLabel: 'Change the match',
    minTarget: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
        if (remembered)
          Padding(
            padding: const EdgeInsets.only(left: 19, top: 3),
            child: Text(
              'as you matched it last time',
              style: ansiMono(size: 10.5, color: AnsiColors.herbDeep),
            ),
          ),
      ],
    ),
  );
}

/// `from receipt:  TJ ORG BANANAS  3.49`: the paper's own words, always
/// visible. A line nobody read off paper says `added by hand` in the same
/// place.
class ReceiptSourceLine extends StatelessWidget {
  const ReceiptSourceLine({
    required this.draft,
    this.byHand = false,
    super.key,
  });

  final ReceiptLineDraft draft;

  /// Whether a person added this line in the review. See
  /// [ReceiptLineDraft.saidByHand].
  final bool byHand;

  @override
  Widget build(BuildContext context) {
    if (draft.printedText.isEmpty && !byHand) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(
        draft.printedText.isEmpty
            ? 'added by hand'
            : 'from receipt:  ${draft.printedText}',
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

/// The dropped card: greyed and labelled, with undo beside it. Nothing is
/// written until Save.
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
