/// A number slot inside a line of prose: an [FTextField] with its padding
/// trimmed to one line of digits and its width to a plausible value, so the
/// sentence around it stays on one run at phone width.
library;

import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// The height of one control inside a line of prose: this slot, the unit chip
/// beside it, and every neighbour a host puts on the same run.
const double kInlineControlHeight = 32;

/// The width of a slot holding a kitchen amount — `⅔`, `1½`, `250` — at the
/// field's own text size.
const double kInlineAmountWidth = 52;

/// The width of a slot holding a scale reading — up to `1234.5` — at the
/// field's own text size. What something weighs is typed off a scale or a
/// pack, so it gets the digits a scale shows.
const double kInlineWeightWidth = 76;

class InlineAmountField extends StatelessWidget {
  const InlineAmountField({
    required this.onSubmit,
    this.onChange,
    this.controller,
    this.initial,
    this.width = 46,
    this.fieldKey,
    this.fractions = false,
    this.scrollController,
    super.key,
  }) : assert(
         controller == null || initial == null,
         'the controller already carries the text this would seed',
       );

  /// The slot's text, exactly as typed; the parse belongs to the caller, so a
  /// draft can tell blank from `0` and `60` from `60.0`. Null where the host
  /// holds a [controller].
  final ValueChanged<String>? onChange;
  final VoidCallback onSubmit;

  /// The slot's controller, for a host that must empty the slot after an
  /// entry lands. Seeding is then the host's business.
  final TextEditingController? controller;

  /// Seeds the controller once, when this widget is built. Give the widget a
  /// key that moves with the text to re-seed it.
  final String? initial;

  final double width;

  /// Keys the [FTextField] itself, so a test can target one slot.
  final Key? fieldKey;

  /// Whether this slot holds a kitchen amount, which may be typed as a
  /// fraction (`1/2`). It brings the text keyboard, because iOS's numeric
  /// pads carry no `/`.
  final bool fractions;

  /// The field's caret scroller, for a host that must stop it before the
  /// field leaves the tree (`shared/measure_form.dart`).
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: FTextField(
      key: fieldKey,
      scrollController: scrollController,
      textAlign: TextAlign.center,
      textInputAction: TextInputAction.done,
      onSubmit: (_) => onSubmit(),
      style: const FTextFieldStyleDelta.delta(
        // Forui's touch sizing floors a field at 44 pt; too tall for a
        // sentence.
        constraints: BoxConstraints(minHeight: kInlineControlHeight),
        contentPadding: EdgeInsetsGeometryDelta.value(
          EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        ),
      ),
      keyboardType: fractions
          ? TextInputType.text
          : const TextInputType.numberWithOptions(decimal: true),
      control: FTextFieldControl.managed(
        controller: controller,
        initial: initial == null ? null : TextEditingValue(text: initial!),
        onChange: onChange == null ? null : (v) => onChange!(v.text),
      ),
    ),
  );
}
