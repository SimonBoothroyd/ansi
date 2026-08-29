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
