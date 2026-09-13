/// The macro line where it is DENSE — `197 🔥 · 2P 3C 20F · 1.5 🌾`.
///
/// A picker row, a recipe line under its name, a day's foot, the week's band:
/// lines that are already one number after another, where `kcal` and `fibre`
/// spelled out are the two longest things on them and the only two that never
/// change. Drawn as a flame and a sheaf of wheat after their figures, they
/// cost a glyph each and the numbers get the width.
///
/// **The words stay where there is room**: [formatMacroLine] itself, which is
/// what a test, a log and a scan card read; the recipe panel's cells; and the
/// form's own field labels, where a person is typing into the slot the word
/// names.
///
/// **A glyph is not a unit to a screen reader.** Each icon carries the word
/// it replaced as its semantic label, so the line is still read out as
/// "kcal" and "fibre".
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/units/macros.dart';
import 'macros_format.dart';

/// Energy. Lucide's `flame` — the one glyph on a kitchen screen that reads as
/// heat rather than as a warning.
const kMacroEnergyIcon = FLucideIcons.flame;

/// Fibre. Lucide's `wheat`: a sheaf, which is what the figure is about.
const kMacroFibreIcon = FLucideIcons.wheat;

/// A unit glyph after its number, sized to the line and painted in the line's
/// own colour so it sits ON the line rather than beside it.
///
/// **It is centred on the digits, by construction.** The box sits on the
/// baseline ([PlaceholderAlignment.aboveBaseline]) and is then dropped, in
/// paint only, by half of what it overshoots the cap height
/// ([kMonoCapHeight]) — so the glyph's middle lands on the middle of a
/// figure's ink, which runs from the baseline to the cap.
/// [PlaceholderAlignment.middle] cannot do that: it centres on the font's
/// ascent/descent midpoint, which is higher than the digits and moves with
/// the line's [TextStyle.height], so one glyph rides at a different altitude
/// on every surface that draws it.
///
/// The box is a whole number of logical pixels because Flutter centres an
/// [Icon]'s glyph inside a box of its own, and a box that lands between
/// pixels lets that centring drift by up to half of one.
InlineSpan macroUnitSpan(
  IconData icon, {
  required String label,
  required TextStyle style,
}) {
  final fontSize = style.fontSize ?? 12;
  final box = (fontSize * 0.95).roundToDouble();
  return WidgetSpan(
    alignment: PlaceholderAlignment.aboveBaseline,
    baseline: TextBaseline.alphabetic,
    child: Transform.translate(
      offset: Offset(0, (box - fontSize * kMonoCapHeight) / 2),
      child: Icon(icon, size: box, color: style.color, semanticLabel: label),
    ),
  );
}

/// The spans of `197 🔥 · 2P 3C 20F · 1.5 🌾`, in [style].
///
/// The order and the separators are [formatMacroLine]'s exactly — the two
/// renderings of one line must not drift into two — and so is the rule that
/// an unstated fibre prints nothing at all rather than a zero (invariant 3).
///
/// [kcal] and [grams] are the two number formatters, so a surface that adds
/// up whole days can pass figures with a thousands separator
/// (`week_macro_widgets.dart`) and still be THIS line rather than a second
/// one. They print the figure; they never decide which figures appear.
List<InlineSpan> macroLineSpans(
  Macros m, {
  required TextStyle style,
  String Function(double) kcal = formatKcal,
  String Function(double) grams = formatGrams,
}) {
  final fiber = m.fiber;
  return [
    TextSpan(text: '${kcal(m.kcal)} ', style: style),
    macroUnitSpan(kMacroEnergyIcon, label: 'kcal', style: style),
    TextSpan(
      text: ' \u00b7 ${grams(m.protein)}P ${grams(m.carb)}C ${grams(m.fat)}F',
      style: style,
    ),
    if (fiber != null) ...[
      TextSpan(text: ' \u00b7 ${grams(fiber)} ', style: style),
      macroUnitSpan(kMacroFibreIcon, label: 'fibre', style: style),
    ],
  ];
}

/// One dense macro line as a widget, with an optional muted [suffix] after it
/// — the basis (`/100 g`) on a picker row, `per 2 tbsp` on a read row.
class MacroLineText extends StatelessWidget {
  const MacroLineText(
    this.macros, {
    required this.style,
    this.suffix,
    this.suffixStyle,
    this.overflow,
    super.key,
  });

  final Macros macros;
  final TextStyle style;

  /// What the figures are per. Printed in [suffixStyle], or in [style] when
  /// the surface draws the whole line in one colour.
  final String? suffix;
  final TextStyle? suffixStyle;

  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final suffix = this.suffix;
    return Text.rich(
      TextSpan(
        children: [
          ...macroLineSpans(macros, style: style),
          if (suffix != null)
            TextSpan(text: ' $suffix', style: suffixStyle ?? style),
        ],
      ),
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}
