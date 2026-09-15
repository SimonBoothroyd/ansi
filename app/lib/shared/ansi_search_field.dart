/// The app's one search field.
///
/// The [FTextField] + magnifier-prefix anatomy every search surface shares,
/// once. Reuse the FIELD, not a shell — `PickerShell` stays a *sheet* shell,
/// and the Library's search is a field on a screen you are already looking at.
///
/// It carries the app's type here rather than at five call sites: Forui sizes
/// a field's text off `typography.sm`, which on the touch ramp is 16 — two
/// steps above every other sans the app draws — and hangs a prefix icon at the
/// border with no inset of its own, so the magnifier sat tight against the
/// left edge while the text began a content padding in.
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
    this.autofocus = false,
    super.key,
  });

  final String hint;

  /// Drive the field from a controller when the SCREEN branches on what the
  /// field says (the ingredients manager's pattern) rather than on a query
  /// stored somewhere else.
  final TextEditingController? controller;

  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    return FTextField(
      autofocus: autofocus,
      hint: hint,
      style: _style(),
      control: controller != null
          ? FTextFieldControl.managed(controller: controller)
          : FTextFieldControl.managed(onChange: (v) => onChanged?.call(v.text)),
      prefixBuilder: (context, style, variants) => Padding(
        // The magnifier's own inset: the field's content padding, so the icon
        // starts where the text would have started without it. Only the start
        // is set — Material keeps its own small gap after a prefix icon.
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

/// The app's sans at the row size, for the content and the hint alike.
///
/// A delta rather than a replacement: Forui's own inks stay, so the hint is
/// still `mutedForeground` and a disabled field still greys out.
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
