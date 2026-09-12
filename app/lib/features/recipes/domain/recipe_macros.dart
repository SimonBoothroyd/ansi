/// Recipe macro summation — PURE DART (invariant 2). It feeds the recipe
/// picker's honest per-serving row and the recipe page's macro panel.
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
/// - an **imprecise** line — `to taste`, `pinch`, `dash`, `handful` — is
///   excluded **by rule** and does NOT make the summary incomplete (seam
///   **D6**). It is unweighable by nature: no measure and no density turn a
///   handful into grams, so marking it "fixable" would mark a line that can
///   never be cleared. Nothing is invented (it contributes zero because zero
///   grams of it were claimed, not because a number was guessed) and nothing
///   is silent (every one is named under the total, by name, every time) —
///   which is a stronger reading of invariant 3 than hiding a figure that is
///   knowable to within a pinch of salt. The one guard: a recipe whose lines
///   are ALL imprecise summed nothing and still refuses
///   ([RecipeMacroSummary.nothingWeighable]);
/// - an **optional** line is excluded by rule too, through the one
///   [effectiveLines] seam every derivation shares, and composes with the
///   imprecise exclusion under the total: `not counted · 2 optional lines:
///   Lime, Coriander`. It runs before every other test, so an optional line
///   that is also imprecise, or a stub, is named once — as optional. Like the
///   imprecise case it does NOT make the summary incomplete, and shares its one
///   guard: a recipe whose lines are ALL optional (or optional and imprecise)
///   summed nothing and still refuses;
/// - anything else — a stub ingredient, a count line without a measure, a
///   numberless line, a missing density — makes the whole summary honestly
///   **incomplete**: no partial total is ever shown as if it were the
///   recipe's macros (invariant 3, never zeros);
/// - a recipe with **no lines at all** is likewise incomplete
///   ([RecipeMacroSummary.noLines]): an empty sum is an absence, not a
///   ~0 kcal recipe.
///
/// Every excluded line is also NAMED, in line order, in
/// [RecipeMacroSummary.notes] (seam **D5**) — the refusal says which lines it
/// is waiting on, which is strictly more honest, not less.
///
/// **Fibre is the one optional figure** ([Macros.fiber]). It never decides
/// whether a line joins the total or whether the summary is complete; what it
/// decides is whether the TOTAL states fibre, and the rule is the same
/// honesty: only when every counted line stated it. The lines that did not are
/// named in [RecipeMacroSummary.linesWithoutFiber], so a surface says which
/// rows a missing fibre figure is waiting on rather than dropping it in
/// silence.
///
/// The walk keeps BOTH halves of what it worked out: every line that joined is
/// recorded in [RecipeMacroSummary.lineMacros] with the macros it contributed,
/// and every line that did not is named in the notes. A surface that prints a
/// figure per line reads the first and the second — it never re-derives a
/// conversion, so a line can never read one way beside its total and another
/// way inside it.
library;

import 'package:meta/meta.dart';

import '../../../core/result/result.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import 'component_math.dart';
import 'effective_lines.dart';
import 'recipe.dart';

/// What the summation needs to know about one vocab ingredient. `macros` is
/// null for a stub (which excludes the line — invariant 3).
typedef IngredientNutrition = ({
  Macros? macros,
  MacrosBasis basis,
  double? densityGPerMl,

  /// What one of the ingredient weighs, in [basis] (ADR-0015) — the number a
  /// bare `piece` line converts through, the way a cross-basis line converts
  /// through [densityGPerMl]. Null when the row has none, and a `piece` line
  /// is then [MacroLineReason.needsWeight].
  double? pieceBasisAmount,
});

/// [IngredientNutrition]'s piece weight as the [Measure] the converter already
/// understands: `n piece` is `n × amount` of the basis unit, exactly like a
/// named measure. Nothing is invented — the amount is the row's own stated
/// fact — so the count joins the total through the same [convertMeasure] a
/// clove or a can does.
Measure? pieceMeasureOf(IngredientNutrition nutrition) {
  final amount = nutrition.pieceBasisAmount;
  if (amount == null) return null;
  return Measure(
    id: 'piece',
    label: 'piece',
    amount: amount,
    basis: nutrition.basis,
  );
}

/// Why one line is not in the total — the per-line half of the refusal
/// (seam **D5**: *"this message makes it impossible to know what ingredients
/// need fixing"*).
///
/// The wording for each lives in `shared/incomplete_macros.dart`, beside the
/// summary-level [RecipeMacroSummary] note, so the panel's list, a row's
/// marker and the picker row are one vocabulary.
enum MacroLineReason {
  /// The vocab row has no macros yet — the flesh-out form is the fix.
  stubIngredient,

  /// The line names an ingredient this device has never synced.
  unknownIngredient,

  /// The line names an ingredient the household has RETIRED — a row that was
  /// here and was removed, which is a different thing to say than "not in
  /// your ingredients yet" and a different fix: re-point the line, in the
  /// editor. Nothing about a retired row is summed, so the total honestly
  /// refuses the same way a stub makes it refuse.
  removedIngredient,

  /// A bare count on a row with no piece weight ("2 pieces", nothing
  /// weighing one) — the row's fact is missing, so the row's form is the fix
  /// (ADR-0015).
  needsWeight,

  /// A cross-basis line on a row with no density.
  needsDensity,

  /// No quantity at all.
  noAmount,

  /// A component line whose batch math does not resolve.
  subRecipeUnresolved,

  /// A component line whose target's own summary is incomplete.
  subRecipeIncomplete,

  /// `to taste`, `pinch`, `dash`, `handful` — unweighable BY NATURE, so
  /// excluded by rule rather than by failure (seam **D6**). With [optional],
  /// one of the two reasons that do NOT make a summary
  /// [RecipeMacroSummary.incomplete].
  imprecise,

  /// The recipe marks the line optional: left out by the [effectiveLines] seam,
  /// by rule, and named under the total. The other reason that does NOT make a
  /// summary incomplete.
  optional,
}

/// One line left out of the total, named. `lineId` is the `recipe_line_item`
/// id (null only where a caller built lines without one), so a surface can
/// mark the row in place; `unit` is the line's own printed imprecise word
/// ("handful"), carried for [MacroLineReason.imprecise] and null otherwise.
typedef MacroLineNote = ({
  String? lineId,
  String name,
  MacroLineReason reason,
  String? unit,
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
/// The bare-count reason is split out because it is the ONE incomplete cause a
/// household can fix in two taps — pick a measure on that line — and under
/// admission model those taps are unambiguous: the row's chip row holds its
/// measures and (mostly) not `piece`. Folding it into "unconvertible" told them
/// a conversion had failed, which is not what happened: nothing was ever
/// weighed.
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

  /// Lines excluded BY RULE because their unit is unweighable by nature
  /// (seam **D6**). **It does not make the summary [incomplete]** — the total
  /// is shown and the exclusion is named beneath it, which is a stronger form
  /// of honesty than hiding a number that is knowable to within a pinch of
  /// salt. The one guard is [noLines]'s sibling: a recipe whose lines are ALL
  /// imprecise summed nothing, and `0 kcal` there would be a fabrication.
  final int impreciseLines;

  /// Lines excluded BY RULE because the recipe marks them optional — dropped by
  /// the [effectiveLines] seam before anything else looks at them, and named
  /// under the total beside the imprecise ones. Like [impreciseLines] it never
  /// makes the summary [incomplete]; it shares the [nothingWeighable] guard.
  final int optionalLines;

  /// Every excluded line, named, in line order (seam **D5**). The panel's
  /// list, the row markers and the "not counted" line all read off this —
  /// one computation, one vocabulary.
  ///
  /// A nested recipe's own exclusions never appear here: a parent names its
  /// component line ("Romesco Aioli · sub-recipe incomplete"), not the
  /// child's lines.
  final List<MacroLineNote> notes;

  /// What each line CONTRIBUTED to the total, by [LineItem.id] — the other
  /// half of [notes], from the same walk. A line is in exactly one of the two:
  /// here with the macros it added, or there with the reason it was left out.
  /// An excluded line is never here as a zero (invariant 3), and a line whose
  /// contribution is genuinely zero is here with a zero it actually computed.
  ///
  /// The figures are at the recipe's STORED amounts, like every other input to
  /// the sum — a surface showing a scaled list multiplies by its own factor,
  /// exactly as it already scales the amount it prints beside them. (The
  /// summary's own [perServing] is scale-invariant for the opposite reason:
  /// scaling moves the lines and the servings together.)
  ///
  /// A component line's entry is the WHOLE share it contributed; the nested
  /// recipe's own lines never appear, the same way its exclusions never appear
  /// in [notes].
  final Map<String, Macros> lineMacros;

  /// The counted lines that state no fibre, by name and in line order — why
  /// [perServing] carries a fibre figure or does not.
  ///
  /// Fibre is optional per ingredient ([Macros.fiber]), so a total may be
  /// whole in every other respect and still have no honest fibre figure. These
  /// lines are IN the total: they are not exclusions and never make the
  /// summary [incomplete] — the list exists so a surface can say which rows a
  /// missing fibre total is waiting on, in the `not counted` grammar the
  /// imprecise and optional lines already use.
  ///
  /// Non-empty exactly when a complete summary's `perServing.fiber` is null.
  final List<String> linesWithoutFiber;

  /// Component lines whose batch math does not resolve (step 8.6 / D8): no
  /// yield on the target, a unit in no yield's family, no amount, or a cycle.
  /// The share cannot be computed at all, so nothing is assumed for it.
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

  /// Every line was imprecise or optional, so nothing was weighed (seam
  /// **D6**'s one guard, shared by D6b). The total would be `0 kcal`, which
  /// would be a fabrication rather than a computation — the same shape as
  /// [noLines].
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
  // `fiber: 0` is the additive identity, not a claim: the empty sum must not
  // be the one addend that strips fibre off every total ([Macros.fiber]).
  // Nothing is fabricated by it — a sum with no lines is refused outright by
  // the `noLines` guard below.
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
    // The line is counted either way — fibre is optional, so a row that never
    // stated it is not a defect. What it costs is the fibre TOTAL, and this is
    // the list that says so by name.
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

  // D6b, through the seam every derivation shares. The walk still runs in
  // stored order (the notes are named in line order, seam D5), asking the
  // seam's answer for each line FIRST — so an optional line is never also a
  // stub or a bare count in the panel's eyes: it is named once, as optional,
  // and it still counts as a line for the nothing-weighable guard.
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
    // Seam D6, and it runs FIRST: `to taste` and its family are unweighable
    // by nature, so the line is excluded BY RULE rather than by any failure —
    // before the quantity test (a `to taste` line usually has no quantity at
    // all and would otherwise read as "unconvertible") and before the stub
    // test (a pinch of a stub is still just a pinch). Nothing is invented: it
    // contributes zero because zero grams of it were claimed. Nothing is
    // silent either — every one of these is named under the total.
    if (line.measure == null && line.unit.family == UnitFamily.imprecise) {
      imprecise++;
      note(line, MacroLineReason.imprecise, unit: line.unit.label);
      continue;
    }
    final ingredientId = line.ingredientId;
    // Neither identity set is foreign data (the DB's XOR check forbids it) —
    // it reads as a stub, the same as an ingredient the vocab doesn't know.
    final nutrition = ingredientId == null ? null : nutritionOf(ingredientId);
    final macros = nutrition?.macros;
    if (nutrition == null || macros == null) {
      stubs++;
      // Three ways to have no nutrition, and the line says which — a retired
      // row is not "not synced yet" (nothing is coming) and not a stub (the
      // row is gone, not thin). Same counter, because the consequence for the
      // total is the same; different words, because the fix is not.
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
    final per100 = _amountInBasis(line, nutrition);
    if (per100 == null) {
      if (_isBareCount(line)) {
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

  // No lines summed nothing: rendering that as "~0 kcal /serving" would
  // present an absence as a computed number (invariant 3, never zeros). The
  // D6 guard is the same shape — a recipe of nothing but salt-to-taste summed
  // nothing either, so it still refuses — and D6b's optional lines share it:
  // a recipe whose every line is optional has claimed zero grams of anything.
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
  } else if (line.unit.family == UnitFamily.count &&
      pieceMeasureOf(nutrition) != null) {
    // A bare `piece` converts through the row's piece weight (ADR-0015) —
    // the count fact the way the density is the volume fact.
    converted = convertMeasure(
      quantity,
      pieceMeasureOf(nutrition)!,
      to: to,
      densityGPerMl: nutrition.densityGPerMl,
    );
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
