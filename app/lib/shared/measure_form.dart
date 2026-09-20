/// The one label-and-amount form every measure is stated in — an ingredient's
/// own count words, and a recipe's own words for one of what it makes.
///
/// It lives here rather than beside either list because the two are the same
/// fact one level apart (a word, and what one of it comes to), and a second
/// copy is how two forms that must read identically drift: the ingredient's
/// `can (400 g)` and the recipe's `blob` are typed into the same run, in the
/// same order, with the button in the same place.
///
/// Its three controls sit on one run at [kInlineControlHeight]: the label field
/// is the small variant trimmed to it, the amount and its unit are
/// [AmountAndUnitField], and the button is the `xs` the density sentence ends
/// with.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';
import '../core/units/units.dart';
import 'amount_and_unit.dart';
import 'inline_amount_field.dart';

class MeasureForm extends StatelessWidget {
  const MeasureForm({
    required this.icon,
    required this.headline,
    required this.saveLabel,
    required this.slot,
    required this.units,
    required this.unit,
    required this.error,
    required this.autofocus,
    required this.label,
    required this.amount,
    required this.onUnit,
    required this.onSave,
    required this.footer,
    this.hint = 'label — “half can”',
    this.labelFocus,
    super.key,
  });

  final IconData icon;
  final String headline;
  final String saveLabel;

  /// Names this form's own fields (`add` / `edit`), because two of them are on
  /// screen together — the row being edited sits in the list, above the add
  /// form — and a test has to be able to say which one it means. The keys are
  /// `<slot>-measure-label`, `-amount` and `-unit`.
  final String slot;

  /// What the amount may be said in. The caller decides: an ingredient's
  /// measure is weighed in something its basis can reach, and a recipe's word
  /// only in a family its `makes` states.
  final List<Unit> units;
  final Unit unit;
  final String? error;
  final bool autofocus;

  /// The two slots, as the controllers the host holds. The host owns the text
  /// because it is the one that has to **empty** it — a field rebuilt to say
  /// something new drags its focus, its keyboard and any scroll-into-view it
  /// had in flight out of the tree with it.
  final TextEditingController label;
  final TextEditingController amount;

  /// Focused when the host wants the keyboard back in the first slot.
  final FocusNode? labelFocus;

  /// What the empty label slot suggests — the host's own example word.
  final String hint;

  final ValueChanged<Unit> onUnit;
  final VoidCallback onSave;

  /// The line under the fields when nothing is wrong — the add form's
  /// provenance note, the edit form's way back out.
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Icon + text, never the raw "＋" glyph (missing from the bundled
        // fonts — renders as tofu).
        Row(
          children: [
            Icon(icon, size: 12, color: AnsiColors.herb),
            const SizedBox(width: 5),
            Text(headline, style: ansiLabel(color: AnsiColors.herb)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              // The small variant, trimmed to the run's height: a full-height
              // field beside a 32 pt control is what made this row read as
              // two rows stacked rather than as one line.
              child: FTextField(
                key: ValueKey('$slot-measure-label'),
                autofocus: autofocus,
                focusNode: labelFocus,
                hint: hint,
                size: FTextFieldSizeVariant.sm,
                style: const FTextFieldStyleDelta.delta(
                  constraints: BoxConstraints(minHeight: kInlineControlHeight),
                  contentPadding: EdgeInsetsGeometryDelta.value(
                    EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
                control: FTextFieldControl.managed(controller: label),
              ),
            ),
            const SizedBox(width: 8),
            AmountAndUnitField(
              amountKey: ValueKey('$slot-measure-amount'),
              unitKey: ValueKey('$slot-measure-unit'),
              amountWidth: 40,
              controller: amount,
              unit: unit,
              units: units,
              onUnit: onUnit,
              onSubmit: onSave,
            ),
            const SizedBox(width: 8),
            // The density sentence's button, to the point: `sm` floors at
            // 40 pt on a touch platform, which is a row of its own.
            FButton(
              size: FButtonSizeVariant.xs,
              style: const FButtonStyleDelta.delta(
                contentStyle: FButtonContentStyleDelta.delta(
                  padding: EdgeInsetsGeometryDelta.value(
                    EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                  ),
                ),
              ),
              onPress: onSave,
              child: Text(saveLabel),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (error != null)
          Text(error!, style: ansiMono(size: 10, color: AnsiColors.gone))
        else
          footer,
      ],
    );
  }
}
