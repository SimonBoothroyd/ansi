/// Recipe macro summation — PURE DART (invariant 2). Pulled forward from
/// step 9 (plan 0011) to feed the recipe picker's honest per-serving row;
/// the recipe-page macro panel remains step 9.
///
/// Sums a recipe's line items against the vocab's per-100 macros, honouring
/// each ingredient's stored basis (`macros_basis`, migration 0011):
///
/// - a line whose unit family matches the basis computes directly (ml lines
///   × per-100 ml — the common liquid case, no density needed);
/// - a cross-basis line bridges via the ingredient's density when present;
/// - a measure line converts through its gram weight, then needs basis 'g'
///   or a density to reach a per-100 ml basis;
/// - anything else — a stub ingredient, a count line without a measure, an
///   imprecise-only line, a numberless line, a missing density — makes the
///   whole summary honestly **incomplete**: no partial total is ever shown
///   as if it were the recipe's macros (invariant 3, never zeros).
library;

import 'package:meta/meta.dart';

import '../../../core/result/result.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import 'recipe.dart';

/// What the summation needs to know about one vocab ingredient. `macros` is
/// null for a stub (which excludes the line — invariant 3).
typedef IngredientNutrition = ({
  Macros? macros,
  MacrosBasis basis,
  double? densityGPerMl,
});

/// The honest per-serving summary of a recipe's macros.
///
/// [perServing] is set only when EVERY line joined the total (and the
/// serving count is positive); otherwise the summary is [incomplete] and
/// carries why — [stubLines] lines of stub/unknown ingredients, and
/// [unconvertibleLines] lines the unit system cannot bridge (count without a
/// measure, imprecise-only, cross-basis without density, no quantity).
@immutable
class RecipeMacroSummary {
  const RecipeMacroSummary({
    this.perServing,
    this.stubLines = 0,
    this.unconvertibleLines = 0,
  });

  final Macros? perServing;
  final int stubLines;
  final int unconvertibleLines;

  bool get incomplete => perServing == null;

  @override
  bool operator ==(Object other) =>
      other is RecipeMacroSummary &&
      other.perServing == perServing &&
      other.stubLines == stubLines &&
      other.unconvertibleLines == unconvertibleLines;

  @override
  int get hashCode => Object.hash(perServing, stubLines, unconvertibleLines);

  @override
  String toString() => incomplete
      ? 'RecipeMacroSummary(incomplete: $stubLines stub, '
            '$unconvertibleLines unconvertible)'
      : 'RecipeMacroSummary($perServing /serving)';
}

/// Sums [lines] (a recipe's items across all groups) into a per-serving
/// [RecipeMacroSummary]. [nutritionOf] resolves a line's ingredient id to its
/// vocab nutrition, or null when the row is unknown locally (treated as a
/// stub — an unknown ingredient must never silently drop out of the total).
///
/// [servingsBase] at or below zero yields an incomplete summary rather than
/// an Infinity per-serving figure (the DB check makes this unreachable from
/// stored rows; the guard keeps the function total).
RecipeMacroSummary summarizeRecipeMacros({
  required double servingsBase,
  required Iterable<LineItem> lines,
  required IngredientNutrition? Function(String ingredientId) nutritionOf,
}) {
  var total = const Macros(kcal: 0, protein: 0, carb: 0, fat: 0);
  var stubs = 0;
  var unconvertible = 0;

  for (final line in lines) {
    final nutrition = nutritionOf(line.ingredientId);
    final macros = nutrition?.macros;
    if (nutrition == null || macros == null) {
      stubs++;
      continue;
    }
    final per100 = _amountInBasis(line, nutrition);
    if (per100 == null) {
      unconvertible++;
      continue;
    }
    total += macros.scaledBy(per100 / 100);
  }

  final incomplete = stubs > 0 || unconvertible > 0 || !(servingsBase > 0);
  return RecipeMacroSummary(
    perServing: incomplete ? null : total.scaledBy(1 / servingsBase),
    stubLines: stubs,
    unconvertibleLines: unconvertible,
  );
}

/// The line's amount expressed in the ingredient's basis unit (g or ml), or
/// null when the unit system cannot bridge it honestly. Delegates to
/// [convert]/[convertMeasure], which already encode the whole matrix: a
/// same-family pair converts directly, mass↔volume needs the density, and
/// count/imprecise pairs (or invalid measure grams) are typed failures.
double? _amountInBasis(LineItem line, IngredientNutrition nutrition) {
  final quantity = line.quantity;
  if (quantity == null) return null;

  final to = nutrition.basis.baseUnit;
  final measure = line.measure;
  final Result<Quantity> converted;
  if (measure != null) {
    converted = convertMeasure(
      quantity,
      measure,
      to: to,
      densityGPerMl: nutrition.densityGPerMl,
    );
  } else if (line.measureId != null) {
    // An unresolved measure reads as its honest count fallback — a count
    // can't join a mass/volume total, so the line is unbridgeable until the
    // measure row syncs in.
    return null;
  } else {
    converted = convert(
      Quantity(quantity, line.unit),
      to: to,
      densityGPerMl: nutrition.densityGPerMl,
    );
  }
  return switch (converted) {
    Ok(:final value) => value.amount,
    Err() => null,
  };
}
