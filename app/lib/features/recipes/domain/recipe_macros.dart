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
/// - a **sub-recipe component** line (step 8.6 / D8) contributes the target
///   recipe's WHOLE-recipe macros × the batches it asks for — but only when
///   both halves are honest: the batch math resolves (D2) *and* the target's
///   own summary is complete. Anything else is a named reason on the parent
///   ([RecipeMacroSummary.subRecipesUnresolved] /
///   [RecipeMacroSummary.subRecipesIncomplete]), never a dropped line;
/// - anything else — a stub ingredient, a count line without a measure, an
///   imprecise-only line, a numberless line, a missing density — makes the
///   whole summary honestly **incomplete**: no partial total is ever shown
///   as if it were the recipe's macros (invariant 3, never zeros);
/// - a recipe with **no lines at all** is likewise incomplete
///   ([RecipeMacroSummary.noLines]): an empty sum is an absence, not a
///   ~0 kcal recipe.
library;

import 'package:meta/meta.dart';

import '../../../core/result/result.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import 'component_math.dart';
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
/// [perServing] is set only when EVERY line joined the total (and there is at
/// least one line, and the serving count is positive); otherwise the summary
/// is [incomplete] and carries why — [noLines] for a recipe with no line
/// items at all (nothing was summed, so "~0 kcal" would be fabricated, not
/// computed — invariant 3), [stubLines] lines of stub/unknown ingredients,
/// [countLinesWithoutMeasure] bare counts ("2 pieces") with no weight behind
/// them, [unconvertibleLines] everything else the unit system cannot bridge
/// (imprecise-only, cross-basis without density, no quantity), and the two
/// sub-recipe reasons (step 8.6 / D8).
///
/// The reason WORDING lives in one place — `shared/incomplete_macros.dart`'s
/// `incompleteNote` — so the picker row, the macro panel and the review card
/// cannot drift apart.
///
/// The bare-count reason is split out because it is the ONE incomplete cause
/// a household can fix in two taps — pick a measure on that line — and under
/// plan 0022's admission model those taps are unambiguous: the row's chip row
/// holds its measures and (mostly) not `piece`. Folding it into
/// "unconvertible" told them a conversion had failed, which is not what
/// happened: nothing was ever weighed.
@immutable
class RecipeMacroSummary {
  const RecipeMacroSummary({
    this.perServing,
    this.stubLines = 0,
    this.unconvertibleLines = 0,
    this.subRecipesUnresolved = 0,
    this.subRecipesIncomplete = 0,
    this.countLinesWithoutMeasure = 0,
    this.noLines = false,
  });

  final Macros? perServing;
  final int stubLines;
  final int unconvertibleLines;

  /// Component lines whose batch math does not resolve (step 8.6 / D8): no
  /// yield on the target, a unit in no yield's family, no amount, or a cycle.
  /// The share cannot be computed at all, so nothing is assumed for it.
  final int subRecipesUnresolved;

  /// Component lines whose batch math resolved but whose TARGET's own summary
  /// is incomplete — the share is knowable, the macros behind it are not.
  final int subRecipesIncomplete;

  /// Lines saying a bare count ("2 pieces") with no measure linked, so there
  /// is no weight to sum — plan 0022 **D6**.
  final int countLinesWithoutMeasure;

  /// The recipe has no line items yet — incomplete by absence, not by any
  /// per-line failure.
  final bool noLines;

  bool get incomplete => perServing == null;

  @override
  bool operator ==(Object other) =>
      other is RecipeMacroSummary &&
      other.perServing == perServing &&
      other.stubLines == stubLines &&
      other.unconvertibleLines == unconvertibleLines &&
      other.subRecipesUnresolved == subRecipesUnresolved &&
      other.subRecipesIncomplete == subRecipesIncomplete &&
      other.countLinesWithoutMeasure == countLinesWithoutMeasure &&
      other.noLines == noLines;

  @override
  int get hashCode => Object.hash(
    perServing,
    stubLines,
    unconvertibleLines,
    subRecipesUnresolved,
    subRecipesIncomplete,
    countLinesWithoutMeasure,
    noLines,
  );

  @override
  String toString() => incomplete
      ? 'RecipeMacroSummary(incomplete: '
            '${noLines ? 'no lines' : '$stubLines stub, '
                      '$countLinesWithoutMeasure bare count, '
                      '$unconvertibleLines unconvertible, '
                      '$subRecipesUnresolved sub unresolved, '
                      '$subRecipesIncomplete sub incomplete'})'
      : 'RecipeMacroSummary($perServing /serving)';
}

/// What the summation needs about one sub-recipe it walks into (step 8.6 /
/// D8): its own lines and serving count, plus the yields the component line's
/// amount is resolved against.
///
/// The caller supplies these by id; the walk is depth-first with a visited
/// set, so a cycle raced past both guards renders the parent incomplete
/// instead of recursing forever.
typedef SubRecipeNode = ({
  double servingsBase,
  List<LineItem> lines,
  List<YieldDenomination> yields,
});

/// Sums [lines] (a recipe's items across all groups) into a per-serving
/// [RecipeMacroSummary]. [nutritionOf] resolves a line's ingredient id to its
/// vocab nutrition, or null when the row is unknown locally (treated as a
/// stub — an unknown ingredient must never silently drop out of the total).
///
/// [subRecipeOf] resolves a component line's target (step 8.6 / D8); leaving
/// it null means components cannot be walked at all, and every component line
/// counts as unresolved. A component whose target is *missing* (a dangling
/// link, D5) is likewise unresolved — nothing is derived from a link whose
/// other end isn't there.
///
/// [servingsBase] at or below zero yields an incomplete summary rather than
/// an Infinity per-serving figure (the DB check makes this unreachable from
/// stored rows; the guard keeps the function total).
RecipeMacroSummary summarizeRecipeMacros({
  required double servingsBase,
  required Iterable<LineItem> lines,
  required IngredientNutrition? Function(String ingredientId) nutritionOf,
  SubRecipeNode? Function(String subRecipeId)? subRecipeOf,
}) => _summarize(
  servingsBase: servingsBase,
  lines: lines,
  nutritionOf: nutritionOf,
  subRecipeOf: subRecipeOf,
  visited: const <String>{},
);

RecipeMacroSummary _summarize({
  required double servingsBase,
  required Iterable<LineItem> lines,
  required IngredientNutrition? Function(String ingredientId) nutritionOf,
  required SubRecipeNode? Function(String subRecipeId)? subRecipeOf,
  required Set<String> visited,
}) {
  var total = const Macros(kcal: 0, protein: 0, carb: 0, fat: 0);
  var stubs = 0;
  var unconvertible = 0;
  var subUnresolved = 0;
  var subIncomplete = 0;
  var bareCounts = 0;
  var lineCount = 0;

  for (final line in lines) {
    lineCount++;
    final subRecipeId = line.subRecipeId;
    if (subRecipeId != null) {
      switch (_componentMacros(
        subRecipeId: subRecipeId,
        line: line,
        nutritionOf: nutritionOf,
        subRecipeOf: subRecipeOf,
        visited: visited,
      )) {
        case _ComponentUnresolved():
          subUnresolved++;
        case _ComponentIncomplete():
          subIncomplete++;
        case _ComponentMacros(:final macros):
          total += macros;
      }
      continue;
    }
    final ingredientId = line.ingredientId;
    // Neither identity set is foreign data (the DB's XOR check forbids it) —
    // it reads as a stub, the same as an ingredient the vocab doesn't know.
    final nutrition = ingredientId == null ? null : nutritionOf(ingredientId);
    final macros = nutrition?.macros;
    if (nutrition == null || macros == null) {
      stubs++;
      continue;
    }
    final per100 = _amountInBasis(line, nutrition);
    if (per100 == null) {
      if (_isBareCount(line)) {
        bareCounts++;
      } else {
        unconvertible++;
      }
      continue;
    }
    total += macros.scaledBy(per100 / 100);
  }

  // No lines summed nothing: rendering that as "~0 kcal /serving" would
  // present an absence as a computed number (invariant 3, never zeros).
  final noLines = lineCount == 0;
  final incomplete =
      noLines ||
      stubs > 0 ||
      unconvertible > 0 ||
      subUnresolved > 0 ||
      subIncomplete > 0 ||
      bareCounts > 0 ||
      !(servingsBase > 0);
  return RecipeMacroSummary(
    perServing: incomplete ? null : total.scaledBy(1 / servingsBase),
    stubLines: stubs,
    unconvertibleLines: unconvertible,
    subRecipesUnresolved: subUnresolved,
    subRecipesIncomplete: subIncomplete,
    countLinesWithoutMeasure: bareCounts,
    noLines: noLines,
  );
}

/// What one component line contributes, or which reason it costs.
sealed class _ComponentResult {
  const _ComponentResult();
}

final class _ComponentMacros extends _ComponentResult {
  const _ComponentMacros(this.macros);
  final Macros macros;
}

/// The batch math didn't resolve (no yield, wrong family, no amount, a cycle,
/// or a target that isn't there).
final class _ComponentUnresolved extends _ComponentResult {
  const _ComponentUnresolved();
}

/// The share is known; the target's own macros are not.
final class _ComponentIncomplete extends _ComponentResult {
  const _ComponentIncomplete();
}

/// The target's WHOLE-recipe macros × the batches this line asks for.
///
/// Whole-recipe, not per-serving: a component takes a share of the *batch*,
/// and the target's summary is per-serving, so it is multiplied back up by the
/// target's own serving count before the share is taken.
_ComponentResult _componentMacros({
  required String subRecipeId,
  required LineItem line,
  required IngredientNutrition? Function(String ingredientId) nutritionOf,
  required SubRecipeNode? Function(String subRecipeId)? subRecipeOf,
  required Set<String> visited,
}) {
  // A cycle stops the walk here rather than recursing (D3's guard, D8's
  // "renders incomplete, never loops").
  if (visited.contains(subRecipeId)) return const _ComponentUnresolved();
  final node = subRecipeOf?.call(subRecipeId);
  if (node == null) return const _ComponentUnresolved();

  final amount = resolveComponentAmount(
    quantity: line.quantity,
    unit: line.unit,
    yields: node.yields,
  );
  if (amount is! ResolvedComponentAmount) return const _ComponentUnresolved();

  final summary = _summarize(
    servingsBase: node.servingsBase,
    lines: node.lines,
    nutritionOf: nutritionOf,
    subRecipeOf: subRecipeOf,
    visited: {...visited, subRecipeId},
  );
  final perServing = summary.perServing;
  if (perServing == null) return const _ComponentIncomplete();
  return _ComponentMacros(
    perServing.scaledBy(node.servingsBase * amount.batches),
  );
}

/// Whether [line] is a bare count with a number and nothing weighing it — the
/// D6 reason. A line pointing at a measure that has not synced in yet is NOT
/// one: something does weigh it, this device just cannot see it, and telling
/// the household to add a weight would send them to fix what is not broken.
bool _isBareCount(LineItem line) =>
    line.quantity != null &&
    line.unit.family == UnitFamily.count &&
    line.measure == null &&
    line.measureId == null;

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
