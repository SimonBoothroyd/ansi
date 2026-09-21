/// Display formatting for macro lines (`197 kcal · 2P 3C 20F /100 g`). Pure
/// functions. Only complete rows get a macro line; a stub shows its badge,
/// never zeros.
///
/// One rounding rule, display only: energy prints whole, and so does a gram
/// figure of a gram or more; below a gram it keeps one decimal. Stored values
/// are untouched.
library;

import '../../../core/units/macros.dart';

/// `285`, `0`: energy, whole.
String formatKcal(double v) => v.round().toString();

/// `21`, `0.4`, `7`: a gram figure whole from a gram up, one decimal below. The
/// decimal stays below a gram so 0.42 g of protein does not print as `0P`.
String formatGrams(double v) {
  if (v.abs() >= 1) return v.round().toString();
  final rounded = (v * 10).roundToDouble() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
}

/// `197 kcal · 2P 3C 20F`, with ` · 3 fibre` on a row that states fibre.
/// Protein, carb, fat: the panel's order. Fibre is spelled out because `F` is
/// fat; an unstated fibre prints nothing. Dense surfaces draw glyphs instead
/// (`MacroLineText`).
String formatMacroLine(Macros m) =>
    '${formatKcal(m.kcal)} kcal · ${formatGrams(m.protein)}P '
    '${formatGrams(m.carb)}C ${formatGrams(m.fat)}F'
    '${_fibre(m.fiber)}';

/// The muted basis suffix: `/100 g` or `/100 ml`.
String macroBasisSuffix(MacrosBasis basis) => '/100 ${basis.dbValue}';

/// A macro field's text as the field shows it: the draft's figure through the
/// rounding rule, with anything that is not a number left as it stands. The
/// draft keeps the full value, so an untouched field saves what it was seeded
/// with.
String macroFieldText(String text, {required bool energy}) {
  final v = double.tryParse(text.trim());
  if (v == null || !v.isFinite) return text;
  return energy ? formatKcal(v) : formatGrams(v);
}

/// A stored macro figure as editable text: `60` not `60.0`, every other digit
/// kept. Lossless, unlike [macroFieldText], so opening a row and saving it
/// untouched does not edit its macros.
String macroFieldSeed(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

/// ` · 1.5 fibre`, or nothing at all when the source never stated it.
String _fibre(double? fiber) =>
    fiber == null ? '' : ' · ${formatGrams(fiber)} fibre';
