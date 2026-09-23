/// The label-and-amount form every measure is stated in, shared by the
/// ingredient's and the recipe's measure lists.
///
/// Its three controls sit on one run at [kInlineControlHeight]. Save stops the
/// slots' caret scrollers first: the host may remove the form on that tap, and
/// a scroll still running over a removed subtree trips a framework assertion.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';
import '../core/units/units.dart';
import 'amount_and_unit.dart';
import 'inline_amount_field.dart';

class MeasureForm extends HookWidget {
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

  /// Names this form's fields (`add` / `edit`), since both can be on screen.
  /// The keys are `<slot>-measure-label`, `-amount` and `-unit`.
  final String slot;

  /// What the amount may be said in; the caller decides.
  final List<Unit> units;
  final Unit unit;
  final String? error;
  final bool autofocus;

  /// The two slots' controllers. The host owns the text because it empties
  /// it; rebuilding a field to change its text would drop focus.
  final TextEditingController label;
  final TextEditingController amount;

  /// Focused when the host wants the keyboard back in the first slot.
  final FocusNode? labelFocus;

  /// The empty label slot's hint.
  final String hint;

  final ValueChanged<Unit> onUnit;
  final VoidCallback onSave;

  /// The line under the fields when nothing is wrong.
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final labelScroll = useScrollController();
    final amountScroll = useScrollController();

    // The host may remove this form on the tap; see the library note.
    void save() {
      for (final scroll in [labelScroll, amountScroll]) {
        if (scroll.hasClients) scroll.position.jumpTo(scroll.position.pixels);
      }
      onSave();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Icon + text: the "＋" glyph is missing from the bundled fonts.
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
              // The small variant, trimmed to the run's height.
              child: FTextField(
                key: ValueKey('$slot-measure-label'),
                autofocus: autofocus,
                focusNode: labelFocus,
                scrollController: labelScroll,
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
              amountWidth: kInlineWeightWidth,
              controller: amount,
              scrollController: amountScroll,
              unit: unit,
              units: units,
              onUnit: onUnit,
              onSubmit: save,
            ),
            const SizedBox(width: 8),
            // `xs`: `sm` floors at 40 pt on a touch platform.
            FButton(
              size: FButtonSizeVariant.xs,
              style: const FButtonStyleDelta.delta(
                contentStyle: FButtonContentStyleDelta.delta(
                  padding: EdgeInsetsGeometryDelta.value(
                    EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                  ),
                ),
              ),
              onPress: save,
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
