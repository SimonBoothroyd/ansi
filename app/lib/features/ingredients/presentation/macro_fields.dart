/// The macro keypad: the five-slot sentence a person reads a label into. Shared
/// by the ingredient form (per 100 of a basis) and the meal-out confirm sheet
/// (per portion); what the numbers mean belongs to the host.
library;

import 'package:flutter/widgets.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../shared/inline_amount_field.dart';
import 'ingredient_view_models.dart';
import 'macros_format.dart';

/// The macro inputs as one sentence: `[285.7] kcal · [0] protein · [21.4] carb
/// · [21.4] fat · [ ] fibre`. The slots are [InlineAmountField]s with the name
/// after the number, so the five sit on one or two runs.
///
/// The first four are all-or-none; fibre is optional ([Macros.fiber]).
class MacroFields extends StatelessWidget {
  const MacroFields({required this.draft, required this.onChanged, super.key});

  /// Seeds the controllers when this widget is built under a new key. The form
  /// re-keys whenever it puts something new in the draft, from the row or from
  /// a scan.
  final MacroDraft draft;
  final ValueChanged<MacroDraft> onChanged;

  /// Wide enough for four digits and a decimal of kcal (`1234.5`); the gram
  /// slots take three and a decimal (`21.4`, `100`).
  static const _kcalWidth = 60.0;
  static const _gramsWidth = 46.0;

  @override
  Widget build(BuildContext context) {
    Widget slot(
      String label,
      String seed,
      MacroDraft Function(String) put, {
      required bool last,
    }) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InlineAmountField(
          // Keyed: they read alike, and a test that targets them by
          // position breaks the moment a slot moves.
          fieldKey: ValueKey('macro-$label'),
          width: label == 'kcal' ? _kcalWidth : _gramsWidth,
          // Seeded through the display rule. The draft keeps the full figure,
          // so an untouched field saves what it was given.
          initial: macroFieldText(seed, energy: label == 'kcal'),
          onChange: (t) => onChanged(put(t)),
          onSubmit: () {},
        ),
        const SizedBox(width: 4),
        Text(label, style: ansiMono(size: 9, color: AnsiColors.muted)),
        // The separator travels with the slot it follows, so a run that breaks
        // can never leave a number on one line and its name on the next.
        if (!last) ...[
          const SizedBox(width: 5),
          Text('·', style: ansiMono(size: 10, color: AnsiColors.muted)),
        ],
      ],
    );

    // One Wrap, exactly as the density sentence is: the five read as a list and
    // fold onto a second run at 402 pt rather than shrinking to fit.
    return Wrap(
      key: const ValueKey('macro-sentence'),
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 5,
      runSpacing: 6,
      children: [
        slot('kcal', draft.kcal, (t) => draft.copyWith(kcal: t), last: false),
        slot(
          'protein',
          draft.protein,
          (t) => draft.copyWith(protein: t),
          last: false,
        ),
        slot('carb', draft.carb, (t) => draft.copyWith(carb: t), last: false),
        slot('fat', draft.fat, (t) => draft.copyWith(fat: t), last: false),
        slot('fibre', draft.fiber, (t) => draft.copyWith(fiber: t), last: true),
      ],
    );
  }
}
