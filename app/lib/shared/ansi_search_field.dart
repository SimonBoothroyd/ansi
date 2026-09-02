/// The app's one search field.
///
/// `PickerShell`, the ingredients manager and the Library each hand-rolled the
/// same `FTextField` + magnifier prefix; this is that anatomy, once. Reuse the
/// FIELD, not a shell — `PickerShell` stays a *sheet* shell, and the Library's
/// search is a field on a screen you are already looking at.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

class AnsiSearchField extends StatelessWidget {
  const AnsiSearchField({
    required this.hint,
    this.controller,
    this.onChanged,
    this.autofocus = false,
    super.key,
  });

  final String hint;

  /// Drive the field from a controller when the SCREEN branches on what the
  /// field says (the ingredients manager's pattern, plan 0020 J4) rather than
  /// on a query stored somewhere else.
  final TextEditingController? controller;

  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    return FTextField(
      autofocus: autofocus,
      hint: hint,
      control: controller != null
          ? FTextFieldControl.managed(controller: controller)
          : FTextFieldControl.managed(onChange: (v) => onChanged?.call(v.text)),
      prefixBuilder: (context, style, _) => const Icon(FLucideIcons.search),
    );
  }
}
