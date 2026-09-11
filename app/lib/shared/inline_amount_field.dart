/// A number slot INSIDE a line of prose, not a form field with a line of its
/// own.
///
/// The full [FTextField] chrome (its content padding and minimum height) is
/// what pushes such a line onto three rows: at 44 pt tall and 72 pt wide a
/// field cannot share a run with the words around it. Here the padding is
/// trimmed to what a single line of digits needs and the width to what a
/// plausible value is, so the sentence stays a sentence at 402 pt.
///
/// Three sentences are built out of it — the density's `2 tbsp weighs 32 g`,
/// the piece weight's `1 piece weighs 200 g`, and the macros' `285.7 kcal ·
/// 0 protein · …` — which is why it lives here rather than beside any one of
/// them.
library;

import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// The height of one control inside a line of prose — this slot, the unit
/// chip beside it, and every neighbour a host puts on the same run.
///
/// Forui's touch sizing floors a field at 44 pt and a button at 32; a
/// sentence needs one number, so there is one height and it is stated here
/// rather than trimmed to taste at five call sites.
const double kInlineControlHeight = 32;

class InlineAmountField extends StatelessWidget {
  const InlineAmountField({
    required this.onChange,
    required this.onSubmit,
    this.initial,
    this.width = 46,
    this.fieldKey,
    this.fractions = false,
    super.key,
  });

  /// The slot's TEXT, exactly as typed — the parse belongs to the caller.
  ///
  /// A draft that holds numbers as text can tell "blank" from "0" and opens a
  /// stored `60` as `60` rather than as `60.0`; a slot that handed back a
  /// `double` would have thrown both of those away before its host ever saw
  /// them.
  final ValueChanged<String> onChange;
  final VoidCallback onSubmit;

  /// Seeds the controller once, when this widget is built. Give the widget a
  /// key that moves with the text to re-seed it.
  final String? initial;

  final double width;

  /// Keyed on the [FTextField] itself, so a test targets one slot of a
  /// sentence that has several.
  final Key? fieldKey;

  /// Whether this slot holds a kitchen AMOUNT, which may be typed as a
  /// fraction (`1/2`). It brings the text keyboard, because iOS's numeric
  /// pads carry no `/`. A macro figure is not one of these: it is a number
  /// off a label, and the decimal pad is the right keyboard for it.
  final bool fractions;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: FTextField(
      key: fieldKey,
      textAlign: TextAlign.center,
      textInputAction: TextInputAction.done,
      onSubmit: (_) => onSubmit(),
      style: const FTextFieldStyleDelta.delta(
        // Forui's touch sizing floors a field at 44 pt tall with 10 pt of
        // vertical padding — right for a form field, and a whole row's worth
        // of height for a slot inside a sentence.
        constraints: BoxConstraints(minHeight: kInlineControlHeight),
        contentPadding: EdgeInsetsGeometryDelta.value(
          EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        ),
      ),
      keyboardType: fractions
          ? TextInputType.text
          : const TextInputType.numberWithOptions(decimal: true),
      control: FTextFieldControl.managed(
        initial: initial == null ? null : TextEditingValue(text: initial!),
        onChange: (v) => onChange(v.text),
      ),
    ),
  );
}
