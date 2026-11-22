/// The amount sheet: a step's own amount of something no line holds (the
/// can of water, the pasta water). A number and the word it counts, which
/// scale with the servings and are never bought, costed or counted.
///
/// Amounts come only from the extractor, from this sheet, or from words the
/// person selected and asked to have read; prose is never pattern-matched into
/// one as it is drawn (ADR-0004).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/number_format.dart';
import '../../../shared/ansi_chip.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../domain/method_step.dart';

/// What the sheet resolved to: an amount, or the request to unmake one.
sealed class AmountSheetResult {
  const AmountSheetResult();
}

/// The figure and its word.
final class AmountSet extends AmountSheetResult {
  const AmountSet(this.qty, this.unit);

  final double qty;
  final String unit;
}

/// Remove the amount, **keeping its words**: the sentence is untouched.
final class AmountRemoved extends AmountSheetResult {
  const AmountRemoved();
}

/// The words a step most often counts water and stock in, offered beside the
/// one the selection said.
const _offered = ['cup', 'tbsp', 'tsp', 'ml'];

/// Opens the amount sheet. [words] are the step's own (`one empty can`),
/// shown as what scales; [qty] and [unit] seed the fields. [removable] draws
/// *Remove amount*.
Future<AmountSheetResult?> showMethodAmountSheet(
  BuildContext context, {
  required String words,
  double? qty,
  String unit = '',
  bool removable = false,
}) => showAnsiSheet<AmountSheetResult>(
  context: context,
  builder: (sheetContext) => _AmountSheet(
    words: words,
    qty: qty,
    unit: unit,
    removable: removable,
    onDone: (result) => Navigator.of(sheetContext).pop(result),
  ),
);

class _AmountSheet extends HookWidget {
  const _AmountSheet({
    required this.words,
    required this.qty,
    required this.unit,
    required this.removable,
    required this.onDone,
  });

  final String words;
  final double? qty;
  final String unit;
  final bool removable;
  final ValueChanged<AmountSheetResult> onDone;

  @override
  Widget build(BuildContext context) {
    final amount = useState<double?>(qty);
    final word = useTextEditingController(text: unit);
    useListenable(word);
    final figure = amount.value;
    final ok = figure != null && figure > 0 && figure.isFinite;
    final said = word.text.trim();
    final offered = [
      if (unit.trim().isNotEmpty && !_offered.contains(unit.trim()))
        unit.trim(),
      ..._offered,
    ];

    return AnsiSheetShell(
      title: 'Amount',
      centerTitle: false,
      children: [
        if (words.isNotEmpty)
          Text(
            'from “$words”',
            style: ansiMono(size: 12, color: AnsiColors.muted),
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            SizedBox(
              width: 96,
              child: FTextField(
                key: const ValueKey('amount-qty'),
                autofocus: qty == null,
                hint: 'qty',
                // A text keyboard: iOS's numeric pads have no `/`, so `1/2`
                // could not be typed.
                keyboardType: TextInputType.text,
                control: FTextFieldControl.managed(
                  initial: TextEditingValue(
                    text: qty == null ? '' : formatAmount(qty!),
                  ),
                  onChange: (v) => amount.value = parseAmount(v.text),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FTextField(
                key: const ValueKey('amount-word'),
                hint: 'can, cup, handful',
                control: FTextFieldControl.managed(controller: word),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final w in offered)
              AnsiChip(
                label: w,
                mono: true,
                selected: said == w,
                onTap: () => word.text = w,
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          ok
              ? 'Doubled, it reads '
                    '${stepAmountText(words, figure, null, said, 2)}. '
                    'Never on the Shop or in the totals.'
              : 'Scales with the servings. Never on the Shop or in the totals.',
          style: ansiSans(size: 13, color: AnsiColors.muted),
        ),
        const SizedBox(height: 16),
        FButton(
          onPress: ok ? () => onDone(AmountSet(figure, said)) : null,
          child: Text(removable ? 'Save' : 'Done'),
        ),
        if (removable) ...[
          const SizedBox(height: 8),
          FButton(
            variant: FButtonVariant.ghost,
            onPress: () => onDone(const AmountRemoved()),
            child: const Text('Remove amount · keeps the words'),
          ),
        ],
      ],
    );
  }
}
