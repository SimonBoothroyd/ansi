/// Recipe macro summation. Pure Dart.
///
/// Sums lines against the vocab's per-100 macros in each ingredient's basis; a
/// sub-recipe component contributes its target's macros × the batches asked
/// for. Imprecise and optional lines ([effectiveLines]) are excluded by rule.
/// Any other unsummable line, or no lines, makes the summary incomplete; a
/// partial total is never shown. Excluded lines are named in
/// [RecipeMacroSummary.notes]; fibre is stated only when every counted line
/// states it.
library;

import 'package:meta/meta.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import 'component_math.dart';
import 'effective_lines.dart';
import 'line_basis.dart';
import 'recipe.dart';

export 'line_basis.dart' show SubRecipeNode;

/// What the summation needs to know about one vocab ingredient. `macros` is
/// null for a stub (which excludes the line — invariant 3).
typedef IngredientNutrition = ({
  Macros? macros,
  MacrosBasis basis,
  double? densityGPerMl,

  /// What one of the ingredient weighs, in [basis] (ADR-0015). Null makes a
  /// bare `piece` line [MacroLineReason.needsWeight].
  double? pieceBasisAmount,
});

/// [IngredientNutrition]'s piece weight as a [Measure], so a bare count
/// converts through [convertMeasure] like any named measure.
Measure? pieceMeasureOf(IngredientNutrition nutrition) =>
    pieceMeasureIn(basisOf(nutrition));

/// [nutrition] as the dimension facts alone — what [lineAmountInBasis] needs,
/// with the macros left behind.
IngredientBasis basisOf(IngredientNutrition nutrition) => (
  basis: nutrition.basis,
  densityGPerMl: nutrition.densityGPerMl,
  pieceBasisAmount: nutrition.pieceBasisAmount,
);

/// Why one line is not in the total. The wording for each lives in
/// `shared/incomplete_macros.dart`.
enum MacroLineReason {
  /// The vocab row has no macros yet — the flesh-out form is the fix.
  stubIngredient,

  /// The line names an ingredient this device has never synced.
  unknownIngredient,

  /// The line names an ingredient the household has retired; the fix is to
  /// re-point the line in the editor.
  removedIngredient,

  /// A bare count on a row with no piece weight; the fix is on the ingredient's
  /// form (ADR-0015).
  needsWeight,

  /// A cross-basis line on a row with no density.
  needsDensity,

  /// No quantity at all.
  noAmount,

  /// A component line whose batch math does not resolve.
  subRecipeUnresolved,

  /// A component line whose target's own summary is incomplete.
  subRecipeIncomplete,

  /// `to taste`, `pinch`, `dash`, `handful`: unweighable, so excluded by rule.
  /// With [optional], one of the two reasons that do not make a summary
  /// [RecipeMacroSummary.incomplete].
  imprecise,

  /// The recipe marks the line optional, so [effectiveLines] leaves it out.
  /// Does not make a summary incomplete.
  optional,
}

/// One line left out of the total. `lineId` is the `recipe_line_item` id (null
/// only where a caller built lines without one); `unit` is the printed
/// imprecise word for [MacroLineReason.imprecise], null otherwise.
typedef MacroLineNote = ({
  String? lineId,
  String name,
  MacroLineReason reason,
  String? unit,
});

/// A recipe's per-serving macros. [perServing] is set only when every line
/// joined the total, at least one line counts and the serving count is
/// positive; otherwise the summary is [incomplete] and the counters say why.
/// Reason wording lives in `shared/incomplete_macros.dart`.
@immutable
class RecipeMacroSummary {
  const RecipeMacroSummary({
    this.perServing,
    this.stubLines = 0,
    this.unconvertibleLines = 0,
    this.subRecipesUnresolved = 0,
    this.subRecipesIncomplete = 0,
    this.countLinesWithoutMeasure = 0,
    this.impreciseLines = 0,
    this.optionalLines = 0,
    this.notes = const [],
    this.lineMacros = const {},
    this.linesWithoutFiber = const [],
    this.noLines = false,
    this.nothingWeighable = false,
  });

  final Macros? perServing;
  final int stubLines;
  final int unconvertibleLines;

  /// Lines excluded by rule because their unit is unweighable. Does not make
  /// the summary [incomplete]; see [nothingWeighable].
  final int impreciseLines;

  /// Lines excluded by rule because the recipe marks them optional. Does not
  /// make the summary [incomplete]; see [nothingWeighable].
  final int optionalLines;

  /// Every excluded line, named, in line order. A nested recipe's own
  /// exclusions never appear: the parent names its component line.
  final List<MacroLineNote> notes;

  /// What each counted line contributed, by [LineItem.id]. A line is either
  /// here or in [notes], never both, and an excluded line is never here as a
  /// zero.
  ///
  /// Figures are at the recipe's stored amounts; a surface showing a scaled
  /// list multiplies by its own factor. A component line's entry is its whole
  /// share.
  final Map<String, Macros> lineMacros;

  /// The counted lines that state no fibre, by name in line order. They are in
  /// the total and never make the summary [incomplete]. Non-empty exactly when
  /// a complete summary's `perServing.fiber` is null.
  final List<String> linesWithoutFiber;

  /// Component lines whose batch math does not resolve: no yield on the target,
  /// a unit in no yield's family, no amount, or a cycle.
  final int subRecipesUnresolved;

  /// Component lines whose batch math resolved but whose TARGET's own summary
  /// is incomplete — the share is knowable, the macros behind it are not.
  final int subRecipesIncomplete;

  /// Lines saying a bare count ("2 pieces") with no measure linked, so there is
  /// no weight to sum.
  final int countLinesWithoutMeasure;

  /// The recipe has no line items yet — incomplete by absence, not by any
  /// per-line failure.
  final bool noLines;

  /// Every line was imprecise or optional, so nothing was weighed and the
  /// summary refuses, like [noLines].
  final bool nothingWeighable;

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
      other.impreciseLines == impreciseLines &&
      other.optionalLines == optionalLines &&
      _sameNotes(other.notes, notes) &&
      _sameLineMacros(other.lineMacros, lineMacros) &&
      _sameStrings(other.linesWithoutFiber, linesWithoutFiber) &&
      other.noLines == noLines &&
      other.nothingWeighable == nothingWeighable;

  static bool _sameStrings(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameNotes(List<MacroLineNote> a, List<MacroLineNote> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameLineMacros(Map<String, Macros> a, Map<String, Macros> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    perServing,
    stubLines,
    unconvertibleLines,
    subRecipesUnresolved,
    subRecipesIncomplete,
    countLinesWithoutMeasure,
    impreciseLines,
    optionalLines,
    Object.hashAll(notes),
    Object.hashAllUnordered([
      for (final e in lineMacros.entries) Object.hash(e.key, e.value),
    ]),
    Object.hashAll(linesWithoutFiber),
    noLines,
    nothingWeighable,
  );

  @override
  String toString() {
    if (!incomplete) {
      return 'RecipeMacroSummary($perServing /serving'
          '${impreciseLines > 0 ? ', $impreciseLines imprecise' : ''}'
          '${optionalLines > 0 ? ', $optionalLines optional' : ''})';
    }
    final why = noLines
        ? 'no lines'
        : nothingWeighable
        ? 'nothing weighable'
        : '$stubLines stub, '
              '$countLinesWithoutMeasure bare count, '
              '$unconvertibleLines unconvertible, '
              '$subRecipesUnresolved sub unresolved, '
              '$subRecipesIncomplete sub incomplete';
    return 'RecipeMacroSummary(incomplete: $why)';
  }
}

/// Sums [lines] into a per-serving [RecipeMacroSummary].
///
/// [nutritionOf] resolves a line's ingredient id to its nutrition; null is
/// treated as a stub. [subRecipeOf] resolves a component line's target; a null
/// resolver or a missing target counts the line as unresolved. A [servingsBase]
/// at or below zero yields an incomplete summary.
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
  // `fiber: 0` is the additive identity, so the empty sum does not strip fibre
  // from every total ([Macros.fiber]).
  var total = const Macros(kcal: 0, protein: 0, carb: 0, fat: 0, fiber: 0);
  var stubs = 0;
  var unconvertible = 0;
  var subUnresolved = 0;
  var subIncomplete = 0;
  var bareCounts = 0;
  var imprecise = 0;
  var optional = 0;
  var lineCount = 0;
  final notes = <MacroLineNote>[];
  final lineMacros = <String, Macros>{};
  final withoutFiber = <String>[];

  /// Adds one line's contribution to the total AND records it against the
  /// line, so the two can never disagree.
  void add(LineItem line, Macros macros) {
    total += macros;
    lineMacros[line.id] = macros;
    // The line is counted either way; a missing fibre only costs the fibre
    // total.
    if (macros.fiber == null) {
      withoutFiber.add(line.subRecipe?.title ?? line.ingredientName);
    }
  }

  void note(LineItem line, MacroLineReason reason, {String? unit}) =>
      notes.add((
        lineId: line.id,
        name: line.subRecipe?.title ?? line.ingredientName,
        reason: reason,
        unit: unit,
      ));

  // The walk runs in stored order and asks the seam's answer first, so an
  // optional line is named once, as optional, and still counts for the
  // nothing-weighable guard.
  final dropped = {for (final d in effectiveLines(lines).dropped) d.line};

  for (final line in lines) {
    lineCount++;
    if (dropped.contains(line)) {
      optional++;
      note(line, MacroLineReason.optional);
      continue;
    }
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
          note(line, MacroLineReason.subRecipeUnresolved);
        case _ComponentIncomplete():
          subIncomplete++;
          note(line, MacroLineReason.subRecipeIncomplete);
        case _ComponentMacros(:final macros):
          add(line, macros);
      }
      continue;
    }
    // Runs before the quantity and stub tests: a `to taste` line usually has no
    // quantity and would otherwise read as unconvertible.
    if (line.measure == null && line.unit?.family == UnitFamily.imprecise) {
      imprecise++;
      note(line, MacroLineReason.imprecise, unit: line.unit?.label);
      continue;
    }
    final ingredientId = line.ingredientId;
    // Neither identity set is foreign data (the DB's XOR check forbids it) —
    // it reads as a stub, the same as an ingredient the vocab doesn't know.
    final nutrition = ingredientId == null ? null : nutritionOf(ingredientId);
    final macros = nutrition?.macros;
    if (nutrition == null || macros == null) {
      stubs++;
      // Three ways to have no nutrition share a counter but get different
      // reasons, because the fixes differ.
      note(
        line,
        line.ingredientDeleted
            ? MacroLineReason.removedIngredient
            : nutrition == null
            ? MacroLineReason.unknownIngredient
            : MacroLineReason.stubIngredient,
      );
      continue;
    }
    final per100 = lineAmountInBasis(line, basisOf(nutrition));
    if (per100 == null) {
      if (isBareCount(line)) {
        bareCounts++;
        note(line, MacroLineReason.needsWeight);
      } else {
        unconvertible++;
        note(
          line,
          line.quantity == null
              ? MacroLineReason.noAmount
              : MacroLineReason.needsDensity,
        );
      }
      continue;
    }
    add(line, macros.scaledBy(per100 / 100));
  }

  // An empty sum is refused rather than shown as `0 kcal`, and so is a recipe
  // whose every line is imprecise or optional.
  final noLines = lineCount == 0;
  final nothingWeighable = !noLines && imprecise + optional == lineCount;
  final incomplete =
      noLines ||
      nothingWeighable ||
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
    impreciseLines: imprecise,
    optionalLines: optional,
    notes: notes,
    lineMacros: lineMacros,
    linesWithoutFiber: List.unmodifiable(withoutFiber),
    noLines: noLines,
    nothingWeighable: nothingWeighable,
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

/// The batch math didn't resolve (no yield, wrong family, a word the target no
/// longer has, no amount, a cycle, or a target that isn't there).
final class _ComponentUnresolved extends _ComponentResult {
  const _ComponentUnresolved();
}

/// The share is known; the target's own macros are not.
final class _ComponentIncomplete extends _ComponentResult {
  const _ComponentIncomplete();
}

/// The target's whole-recipe macros × the batches this line asks for. The
/// target's per-serving summary is multiplied back up by its serving count
/// first.
_ComponentResult _componentMacros({
  required String subRecipeId,
  required LineItem line,
  required IngredientNutrition? Function(String ingredientId) nutritionOf,
  required SubRecipeNode? Function(String subRecipeId)? subRecipeOf,
  required Set<String> visited,
}) {
  // A cycle stops the walk here: the recipe renders incomplete, never loops.
  if (visited.contains(subRecipeId)) return const _ComponentUnresolved();
  final node = subRecipeOf?.call(subRecipeId);
  if (node == null) return const _ComponentUnresolved();

  final amount = resolveComponentAmount(
    quantity: line.quantity,
    unit: line.unit,
    yields: node.yields,
    recipeMeasureId: line.recipeMeasureId,
    measures: node.measures,
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
