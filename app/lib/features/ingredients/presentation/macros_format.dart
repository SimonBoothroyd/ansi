/// Display formatting for macro lines (design board: `197 kcal · 2P 3C 20F
/// /100 g`). Pure functions, kept apart from widgets so they're trivially
/// testable. Only COMPLETE rows get a macro line — a stub shows its badge,
/// never zeros (invariant 3).
///
/// **One rounding rule, and it is display only.** Energy prints whole, and so
/// does a gram figure of a gram or more; below a gram it keeps one decimal.
/// That is everywhere a macro figure is printed: the field a form seeds, the
/// derivation under it, a picker row, the recipe panel's cells, the week's
/// strip. What is STORED is untouched by it — a row seeded from a serving
/// reverses to the figures the label printed, and it could not if the
/// rounding reached the value.
library;

import '../../../core/units/macros.dart';

/// `285`, `0` — energy, whole. A tenth of a calorie is not a reading anybody
/// takes off a pack, and printing the tail of a division nobody asked for is
/// how a derived figure starts looking like a measured one.
String formatKcal(double v) => v.round().toString();

/// `21`, `0.4`, `7` — a gram figure whole from a gram up, one decimal below.
///
/// Whole where the number is one a kitchen can hold: nobody weighs the tenth
/// of a gram of protein in a portion, and a panel of `21.4 / 3.1 / 11.7`
/// reads as a measurement that was never taken.
///
/// **Below a gram the decimal stays**, which is the reason this rule exists
/// at all: an oat milk's 0.42 g of protein would round to `0P`, and a line
/// that says a row stores no protein when it stores some is the dishonest
/// number invariant 3 is about.
String formatGrams(double v) {
  if (v.abs() >= 1) return v.round().toString();
  final rounded = (v * 10).roundToDouble() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
}

/// `197 kcal · 2P 3C 20F`, and ` · 3 fibre` after it on a row that states
/// fibre.
///
/// **Protein, carb, fat — the panel's order**, because the panel's cells and
/// this line are two renderings of one fact and a reader should not have to
/// notice which one they are looking at.
///
/// Fibre is spelled out because the initials are taken: `F` is fat, and a
/// second `F` on the same line would be read as one. Its absence prints
/// nothing at all — an unstated fibre is not a zero (invariant 3).
///
/// **The words are here.** A dense surface draws energy and fibre as glyphs
/// instead (`MacroLineText`); this string is what a test, a log and a line
/// with room for the words read.
String formatMacroLine(Macros m) =>
    '${formatKcal(m.kcal)} kcal · ${formatGrams(m.protein)}P '
    '${formatGrams(m.carb)}C ${formatGrams(m.fat)}F'
    '${_fibre(m.fiber)}';

/// The muted basis suffix: `/100 g` or `/100 ml`.
String macroBasisSuffix(MacrosBasis basis) => '/100 ${basis.dbValue}';

/// A macro field's text as the field SHOWS it — the draft's figure through
/// the rule above, and anything that is not a number ("", a half-typed `1.`)
/// left exactly as it stands.
///
/// The draft goes on holding the full value: a field nobody touched saves
/// what it was seeded with rather than what it was showing, so opening a row
/// derived from a serving and saving it untouched reverses to the label's own
/// figures. A field somebody types in holds what they typed, and this stops
/// applying to it.
String macroFieldText(String text, {required bool energy}) {
  final v = double.tryParse(text.trim());
  if (v == null || !v.isFinite) return text;
  return energy ? formatKcal(v) : formatGrams(v);
}

/// A stored macro figure as EDITABLE text: `60` not `60.0`, and every other
/// digit kept exactly as stored.
///
/// **Lossless, deliberately** — the opposite of [macroFieldText], which is
/// what the field shows. A USDA-derived `285.7142857` must seed as itself, so
/// opening a row and saving it untouched is not a silent edit of its macros.
String macroFieldSeed(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

/// ` · 1.5 fibre`, or nothing at all when the source never stated it.
String _fibre(double? fiber) =>
    fiber == null ? '' : ' · ${formatGrams(fiber)} fibre';
