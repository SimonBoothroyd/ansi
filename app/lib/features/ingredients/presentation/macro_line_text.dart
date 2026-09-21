/// The macro line where it is dense: `197 🔥 · 2P 3C 20F · 1.5 🌾`.
///
/// On picker rows, recipe lines and the week's band, `kcal` and `fibre` are
/// drawn as a flame and a sheaf of wheat after their figures. The words stay
/// where there is room: [formatMacroLine], the recipe panel's cells and the
/// form's field labels. Each icon carries the word it replaced as its semantic
/// label.
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
/// colour.
///
/// It is centred on the digits: the box sits on the baseline
/// ([PlaceholderAlignment.aboveBaseline]) and is dropped, in paint only, by
/// half of what it overshoots the cap height ([kMonoCapHeight]).
/// [PlaceholderAlignment.middle] centres on the ascent/descent midpoint
/// instead, which is higher than the digits and moves with [TextStyle.height].
/// The box is a whole number of logical pixels so the [Icon]'s own centring
/// cannot drift by half a pixel.
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

/// The spans of `197 🔥 · 2P 3C 20F · 1.5 🌾`, in [style]. Order, separators
/// and the unstated-fibre rule are [formatMacroLine]'s. [kcal] and [grams] are
/// the number formatters, so a surface summing whole days can add a thousands
/// separator (`week_macro_widgets.dart`).
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
