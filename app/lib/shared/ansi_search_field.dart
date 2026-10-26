/// The app's one search field: an [FTextField] with a magnifier prefix.
///
/// It sets the text size and the icon inset here because Forui's defaults
/// draw the text at 16 and hang the prefix icon at the border.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_theme.dart';

/// The size interface sans reads at in a row.
const _kSearchTextSize = 14.0;

class AnsiSearchField extends StatelessWidget {
  const AnsiSearchField({
    required this.hint,
    this.controller,
    this.onChanged,
    this.focusNode,
    this.autofocus = false,
    this.clearable = false,
    super.key,
  });

  final String hint;

  /// For a screen that branches on what the field says rather than on a
  /// query stored elsewhere, or clears it itself.
  final TextEditingController? controller;

  final ValueChanged<String>? onChanged;

  /// For a host that acts on the field gaining or losing focus.
  final FocusNode? focusNode;

  final bool autofocus;

  /// Whether a clear mark stands at the end while the field holds text.
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    return FTextField(
      autofocus: autofocus,
      focusNode: focusNode,
      hint: hint,
      clearable: clearable
          ? (value) => value.text.isNotEmpty
          : FTextField.defaultClearable,
      style: _style(),
      // With a controller too, [onChanged] hears every change to it — a
      // selection move as well as an edit, so a host compares the text.
      control: FTextFieldControl.managed(
        controller: controller,
        onChange: (v) => onChanged?.call(v.text),
      ),
      prefixBuilder: (context, style, variants) => Padding(
        // The field's content padding, so the icon starts where the text
        // would. Only the start is set; Material keeps a gap after a prefix.
        padding: EdgeInsetsDirectional.only(
          start: style.contentPadding.resolve(Directionality.of(context)).left,
        ),
        child: IconTheme(
          data: style.iconStyle.resolve(variants),
          child: const Icon(FLucideIcons.search),
        ),
      ),
    );
  }
}

/// The app's sans at the row size, for the content and the hint. A delta, so
/// Forui's own inks stay.
FTextFieldStyleDelta _style() {
  final sans = ansiSans(size: _kSearchTextSize);
  final text = TextStyleDelta.delta(
    fontSize: sans.fontSize,
    height: sans.height,
    fontFamilyFallback: sans.fontFamilyFallback,
  );
  return FTextFieldStyleDelta.delta(
    contentTextStyle: FVariantsDelta.delta([FVariantOperation.all(text)]),
    hintTextStyle: FVariantsDelta.delta([FVariantOperation.all(text)]),
    iconStyle: FVariantsDelta.delta([
      FVariantOperation.all(IconThemeDataDelta.delta(size: sans.fontSize)),
    ]),
  );
}
