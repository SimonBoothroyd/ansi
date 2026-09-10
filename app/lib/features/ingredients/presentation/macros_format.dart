/// Display formatting for macro lines (design board: `197 kcal · 2P 20F 3C
/// /100 g`). Pure functions, kept apart from widgets so they're trivially
/// testable. Only COMPLETE rows get a macro line — a stub shows its badge,
/// never zeros (invariant 3).
library;

import '../../../core/units/macros.dart';

/// `197 kcal · 2P 20F 3C` — values rounded for the dense picker row.
String formatMacroLine(Macros m) =>
    '${m.kcal.round()} kcal · ${m.protein.round()}P ${m.fat.round()}F '
    '${m.carb.round()}C';

/// The muted basis suffix: `/100 g` or `/100 ml`.
String macroBasisSuffix(MacrosBasis basis) => '/100 ${basis.dbValue}';

/// `46.5 kcal · 0.4P 2.1F 7.2C` — the same line to one decimal, for a
/// **derivation**: the per-100 figures a per-serving label implies, and the
/// per-100 line under a read row's own.
///
/// [formatMacroLine]'s whole numbers are right for a dense picker row, where a
/// tenth of a gram of protein is noise. They are wrong where the number is the
/// receipt for the arithmetic the app just did: an oat milk's 0.42 g of
/// protein rounds to `0P`, and a line that says a row stores no protein when
/// it stores some is the dishonest number invariant 3 is about.
String formatMacroLineFine(Macros m) =>
    '${_fine(m.kcal)} kcal · ${_fine(m.protein)}P ${_fine(m.fat)}F '
    '${_fine(m.carb)}C';

/// One decimal, trailing zero trimmed — `46.5`, `7`, `0.4`.
String _fine(double v) {
  final rounded = (v * 10).roundToDouble() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
}
