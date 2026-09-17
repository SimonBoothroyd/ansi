/// The macro keypad — the five-slot sentence a person reads a label into.
///
/// It lives apart from the ingredient form because a second door types the
/// same five figures into it: the confirm sheet of a meal eaten OUT, whose
/// optional fold asks what the canteen printed per portion. The two doors mean
/// different things by the numbers — the form stores per 100 of a basis, the
/// sheet stores what one plate was worth — and that difference belongs to the
/// hosts. What must not differ is the control: one keypad, one set of widths,
/// one rule about the fifth slot.
library;

import 'package:flutter/widgets.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../shared/inline_amount_field.dart';
import 'ingredient_view_models.dart';
import 'macros_format.dart';

/// The macro inputs, as one **sentence**: `[285.7] kcal · [0] protein ·
/// [21.4] carb · [21.4] fat · [ ] fibre`.
///
/// They were five tall boxes with a caption under each, which is a form's
/// height for a line a person reads off a label in one breath. The slots are
/// the density sentence's own [InlineAmountField] — stripped chrome, a width
/// that fits the widest plausible reading — with the name after the number the
/// way a panel prints it, so the five sit on one or two runs instead of five.
///
/// The first four are all-or-none — a partial panel would compute totals out
/// of numbers nobody supplied (invariant 3). **Fibre is optional**
/// ([Macros.fiber]): a label that prints it fills the fifth slot, one that
/// does not leaves it blank and the row is complete regardless.
class MacroFields extends StatelessWidget {
  const MacroFields({required this.draft, required this.onChanged, super.key});

  /// Seeds the controllers when this widget is (re)built under a new key —
  /// so it is the DRAFT, not the row: the form re-keys exactly when it has put
  /// something new in the draft, whether that came from the row (G1) or from a
  /// barcode scan.
  final MacroDraft draft;
  final ValueChanged<MacroDraft> onChanged;

  /// Wide enough for a kcal reading of four digits and a decimal (`1234.5`,
  /// `285.7`); the gram slots take three and a decimal (`21.4`, `100`), which
  /// is the density sentence's own slot width. A slot sized for a number
  /// somebody types into it rather than for one they leave alone — a field
  /// scrolls, and a run lost to a width nobody fills is a run lost.
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
          // Seeded through the display rule, and only seeded: the draft goes
          // on holding the full figure, so a field nobody touches saves what
          // it was given rather than what it was showing.
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
