/// Per-line validity for the import review screen — PURE DART (invariant 2).
///
/// A reviewed line is "done" (its needs-attention flag cleared, and it stops
/// blocking Save) exactly when it is MATCHED to an ingredient, any printed
/// range has a picked number, and its unit is one the matched ingredient
/// actually admits (ADR-0008 `allowed_units` + the ingredient's measures + the
/// always-admitted imprecise units). Anything else is surfaced, never hidden
/// (0014) — and Save stays disabled until every line clears.
library;

import 'package:meta/meta.dart';

import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import 'line_resolution.dart';

/// Why a line still wants the user. An empty issue list == done/clean.
enum LineIssue {
  /// No ingredient chosen yet.
  unmatched,

  /// The source printed a range and no single number has been picked.
  rangeUnpicked,

  /// The line's unit isn't one the matched ingredient can carry.
  unitNotAllowed,

  /// A line LINKED to a household recipe (8.6 / D6) carries no amount. That is
  /// its only gate: it wants no ingredient match and faces no admission check.
  amountMissing,
}

/// The imprecise word a LINE actually printed, when it printed one — the
/// source's own vocabulary, resolved to a catalog unit. Null for a mass,
/// volume or count unit, a measure label, or no unit at all.
Unit? printedImpreciseUnit(String? unit) {
  if (unit == null || unit.isEmpty) return null;
  final resolved = unitById(unit);
  return resolved != null && resolved.family == UnitFamily.imprecise
      ? resolved
      : null;
}

/// The imprecise units the import surface admits for [ingredient] on a line
/// whose source printed [parsedUnit]. Three legs:
///
/// - `to taste` unconditionally: a "plus more, to serve" use is legitimately
///   imprecise whatever the food, and an import line is exactly where that
///   phrasing arrives;
/// - the ingredient's own category gate ([impreciseUnitsFor]) — J3's ruling,
///   which is what stops the editor OFFERING "a dash of kale";
/// - **the line's own printed word** ([printedImpreciseUnit]), whatever the
///   category, uncategorised rows included.
///
/// That third leg is never-invent, read the other way round. J3 gated what the
/// editor may SUGGEST; it must not gate what the source SAID. Without it a
/// canned "a pinch of chilli flakes" landing on a freshly created row — which
/// has no category until the form gives it one — validated as
/// `unitNotAllowed` and locked the Save gate on a unit nobody could have
/// picked, because it was never offered.
/// Exactly one word is admitted: the one that was printed. A row still earns
/// no other imprecise chip it has not earned.
Set<Unit> importImpreciseUnitsFor(Ingredient ingredient, {String? parsedUnit}) {
  final printed = printedImpreciseUnit(parsedUnit);
  return {
    toTaste,
    ...impreciseUnitsFor(ingredient),
    if (printed != null) printed,
  };
}

/// The unit tokens acceptable for a matched line: the ingredient's allowed
/// catalog units (by id) + its [measures] (by label) + the imprecise words it
/// earns, [parsedUnit]'s own printed word included (J3b). Mirrors exactly what
/// the amount sheet offers for this line (see [amountSheetIngredient]), so a
/// unit is "allowed" iff the picker could have produced it — which is why the
/// line's printed unit has to be threaded through both: a word the editor
/// never offers is a word the user can never clear the flag with.
Set<String> acceptableUnitTokens(
  Ingredient ingredient,
  List<Measure> measures, {
  String? parsedUnit,
}) {
  final offer = allowedUnitChoicesFor(
    amountSheetIngredient(ingredient, parsedUnit: parsedUnit),
    measures,
  );
  return {
    for (final c in offer.choices)
      switch (c) {
        UnitOption(:final unit) => unit.id,
        MeasureOption(:final measure) => measure.label,
      },
  };
}

/// One inline unit-suggestion chip: [token] is what gets stored on the
/// resolution's unit (a catalog unit id, or a measure label); [label] is the
/// chip text. Parallel to the ingredient "did you mean" chips (round-3 #2).
@immutable
class UnitSuggestion {
  const UnitSuggestion({required this.token, required this.label});

  final String token;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is UnitSuggestion && other.token == token && other.label == label;

  @override
  int get hashCode => Object.hash(token, label);
}

/// A matched line's acceptable units as ordered suggestion chips — exactly the
/// amount sheet's offer for this line (allowed set + measures + the imprecise
/// words it earns, including [parsedUnit]'s printed one), so tapping a chip
/// always yields a valid unit.
List<UnitSuggestion> acceptableUnitChips(
  Ingredient ingredient,
  List<Measure> measures, {
  String? parsedUnit,
}) {
  final offer = allowedUnitChoicesFor(
    amountSheetIngredient(ingredient, parsedUnit: parsedUnit),
    measures,
  );
  return [
    for (final c in offer.choices)
      switch (c) {
        UnitOption(:final unit) => UnitSuggestion(
          token: unit.id,
          label: unit.label,
        ),
        MeasureOption(:final measure) => UnitSuggestion(
          token: measure.label,
          label: measure.label,
        ),
      },
  ];
}

/// How many unit chips a review line shows before the fold (owner call): five,
/// with the rest one "more" tap away. The full admission set for a common
/// ingredient runs to a dozen-plus chips, which reads as a wall rather than a
/// choice — but every chip stays reachable, so nothing honest is hidden.
const kVisibleUnitChips = 5;

/// [chips] reordered so the five most likely land in front of the fold.
///
/// **With a parsed unit** — the line printed one — the owner's relevance
/// ranking: the line's own [parsedUnit] first, then the rest of that unit's
/// family, then the ingredient's named measures (in the order they were given
/// — most likely first), then the generic mass/volume unit (g/ml), then
/// everything else, with the imprecise words last.
///
/// The imprecise tail folds UNLESS the parsed amount is itself imprecise ("a
/// good pinch"), in which case its family leads by the same rule that fronts
/// any other parsed unit — a pinch line should not have to expand to say pinch.
///
/// **With no parsed unit the incoming order is preserved as given**, imprecise
/// still sinking to the back. A line that printed no unit offers no evidence
/// to rank on, so the only honest order is the ingredient's own — and the
/// caller already built it: [allowedUnitChoicesFor] hands these chips over in
/// ADR-0008 kitchen order (the row's DEFAULT unit fronted, the rest of its
/// family in kitchen order, then the measures, then the demoted other family,
/// imprecise last).
///
/// The g/ml boost below is relevance only NEXT TO a parsed unit; with none it
/// just outranks the row's own default, which is how the vocab audit came to
/// offer `ml` before flour's `cup`, `g` before black pepper's `tsp`, and
/// `ml g` ahead of kale's own `cup`. Owner ruling (batch 6): spices lead
/// `tsp`, and "in general we use american recipes, so cup / spoon is preferred
/// over ml / L" — which is the ADR kitchen order, so this leg ranks nothing
/// and defers to it. One source of chip order for a line that said nothing.
///
/// The sort is stable within each rank, so the ADR-0008 chip order the caller
/// built survives inside every group.
///
/// **A parsed `piece` the row refuses ranks nothing** (ADR-0010). The chips
/// come from the offer, so a refused `piece` is not among them and cannot take
/// rank 0; and `piece` is the whole count family, so the same-family leg has
/// nothing to lift either. What is left in front is the row's measures at rank
/// 2 — a clove, an avocado, three potato sizes — which is exactly the offer the
/// user has to choose from. Nothing here reads the line's words to guess which
/// measure it meant.
List<UnitSuggestion> rankedUnitChips(
  List<UnitSuggestion> chips, {
  required String? parsedUnit,
}) {
  final noParsedUnit = parsedUnit == null || parsedUnit.isEmpty;
  final parsed = noParsedUnit ? null : unitById(parsedUnit);
  int rankOf(UnitSuggestion c) {
    final unit = unitById(c.token); // null ⇒ the token is a measure label
    // Defer: every chip keeps its offer position, bar the imprecise tail.
    if (noParsedUnit) {
      return unit != null && unit.family == UnitFamily.imprecise ? 1 : 0;
    }
    if (c.token == parsedUnit) return 0;
    if (unit != null && parsed != null && unit.family == parsed.family) {
      return 1;
    }
    if (unit == null) return 2;
    if (unit == g || unit == ml) return 3;
    if (unit.family == UnitFamily.imprecise) return 5;
    return 4;
  }

  final indexed = [
    for (var i = 0; i < chips.length; i++) (rank: rankOf(chips[i]), at: i),
  ]..sort((a, b) => a.rank == b.rank ? a.at - b.at : a.rank - b.rank);
  return [for (final e in indexed) chips[e.at]];
}

/// The measure a line should open PRE-SELECTED on in the amount editor: when
/// the source's [unit] is one the matched [ingredient] cannot carry
/// ([LineIssue.unitNotAllowed]) and the ingredient names **exactly one**
/// measure, that measure is what the line meant — there is nothing else it
/// could have meant. Pre-selecting it turns resolving into one confirm tap
/// instead of a scroll-and-choose.
///
/// **It pre-selects the SHEET, not the LINE** (seam D3, named). Nothing in the
/// validation path has ever called this: [lineIssues] checks the resolution's
/// own unit, which this function does not write, so a sole-measure cucumber
/// line stayed flagged until somebody opened the sheet and confirmed — while
/// ADR-0010 consequence 4's "one measure pre-selects" read to everyone as "is
/// not flagged". [arrivalMeasure] is the function that writes the LINE, and
/// under it a bare count on a row with a default (or a sole count measure)
/// arrives clean. This one keeps its original, narrower job: seeding the
/// amount sheet for the cases the arrival rule deliberately does not answer —
/// a printed `bunch`, a printed `ml`.
///
/// **Two or more measures pre-select nothing** (ADR-0010, owner). A potato line
/// arriving as `piece` could be small, medium or large, and picking the first
/// in `sort_order` — or reading "large" out of the raw text, or defaulting to
/// medium — is the machine deciding what a piece meant. The chips are right
/// there; the user picks, and Save stays gated until they do.
///
/// Null when the unit is already fine, when the line printed none, or when the
/// ingredient has no measure to offer. Volume-labelled measures are skipped for
/// the same reason the chip row skips them: density owns volume (ADR-0008 §2).
Measure? preselectedMeasure(
  Ingredient ingredient,
  List<Measure> measures, {
  required String? unit,
}) {
  if (unit == null || unit.isEmpty) return null;
  if (acceptableUnitTokens(
    ingredient,
    measures,
    parsedUnit: unit,
  ).contains(unit)) {
    return null;
  }
  final offered = measures.where((m) => !isVolumeUnitLabel(m.label));
  return offered.length == 1 ? offered.first : null;
}

/// The measure a line should ARRIVE on — the ingredient's curated default,
/// spent at the one moment it is worth spending (seam **D2**).
///
/// **The scope rule, in one sentence: the default answers a line that named a
/// number and no thing; it never overrules a line that named a thing.**
/// Concretely it fires when the line printed no unit at all, or printed a
/// `count`-family unit the row refuses (i.e. `piece` on a measured row —
/// ADR-0010's own case). A line that printed `bunch`, `head` or `can` keeps
/// today's flag, because replacing the source's own word with our default is
/// exactly the guess ADR-0010 forbids: cilantro's default IS `sprig` (2.22 g)
/// and "1 bunch cilantro" is about twenty-five of them.
///
/// The caller writes the returned measure's LABEL onto the resolution — the
/// same token a tapped chip writes ([sheetChoiceUnit]) — so [lineIssues] then
/// finds an acceptable unit and the card is clean **for the ordinary reason**.
/// There is no new [LineIssue], no "flagged but allowed" state, and the commit
/// path is byte-for-byte what a tapped chip produces.
///
/// Null when the row has no default, when the default's measure row has not
/// synced in yet (flag, never guess a different one), and when the unit is
/// already fine. Volume-labelled measures are skipped for the same reason the
/// chip row skips them: density owns volume (ADR-0008 §2).
Measure? arrivalMeasure(
  Ingredient ingredient,
  List<Measure> measures, {
  required String? unit,
}) {
  if (unit != null && unit.isNotEmpty) {
    final parsed = unitById(unit);
    // A measure label, or a word the catalog has never heard of. Either way
    // the source named a THING, and the default stands aside.
    if (parsed == null) return null;
    if (parsed.family != UnitFamily.count) return null;
    if (acceptableUnitTokens(
      ingredient,
      measures,
      parsedUnit: unit,
    ).contains(unit)) {
      return null; // the row carries this count word; nothing to answer
    }
  }
  final offered = [
    for (final m in measures)
      if (!isVolumeUnitLabel(m.label)) m,
  ];
  final id = ingredient.defaultMeasureId;
  if (id != null) {
    for (final m in offered) {
      if (m.id == id) return m;
    }
    // The row states a default whose measure this device has not synced yet.
    // Falling through to the sole-measure leg would be picking a DIFFERENT
    // measure than the one the household named, so the line keeps its flag.
    return null;
  }
  // No stated default, but exactly one measure: there is nothing else the
  // line could have meant, which is ADR-0010 consequence 4's own sentence.
  // This is [preselectedMeasure]'s promise, finally kept on the LINE (D3).
  return offered.length == 1 ? offered.single : null;
}

/// One line's review state: its outstanding [issues] and, for a matched line,
/// the valid units to offer as inline chips when the unit needs a fix.
class LineValidation {
  const LineValidation({
    required this.issues,
    this.unitChoices = const [],
    this.unitMeasure,
  });

  final List<LineIssue> issues;
  final List<UnitSuggestion> unitChoices;

  /// The measure the line's current unit NAMES, when it names one — so the
  /// card can print the weight beside it ("counts as pepper, medium · 119 g",
  /// seam D2) without a second measure read per line. Null when the unit is a
  /// catalog unit, a word nothing carries, or absent.
  final Measure? unitMeasure;

  bool get isClean => issues.isEmpty;
}

/// The ingredient the import amount editor and the validity check both reason
/// about: the real ingredient with the imprecise units it earns
/// ([importImpreciseUnitsFor]) unioned into its allowed set, so those chips are
/// offered (and accepted) on a line without touching the stored vocab row.
///
/// [parsedUnit] is the line's own printed unit, so a source-printed imprecise
/// word is admitted on this line alone (J3b) — the sheet must always be able
/// to render the unit the line is already carrying.
Ingredient amountSheetIngredient(Ingredient ingredient, {String? parsedUnit}) {
  final base = ingredient.allowedUnits ?? defaultAllowedUnitSet(ingredient);
  return ingredient.copyWith(
    allowedUnits: {
      ...base,
      ...importImpreciseUnitsFor(ingredient, parsedUnit: parsedUnit),
    }.toList(),
  );
}

/// The outstanding issues for [resolution]. Pass the matched [ingredient] (and
/// its [measures]) to check the unit against the allowed set; without an
/// ingredient only the structural issues (unmatched / range) are reported.
///
/// A DROPPED line has no issues by construction: it is leaving the recipe, so
/// it can neither be flagged nor hold up Save (owner call).
///
/// The line's own unit is passed to [acceptableUnitTokens] as the parsed unit:
/// a source-printed imprecise word validates whatever the ingredient's
/// category (J3b). A printed mass/volume unit gets no such pass — D4c flags
/// "1 cup" on a density-less row exactly as before, because that one the
/// converter genuinely cannot resolve.
List<LineIssue> lineIssues(
  LineResolution resolution, {
  Ingredient? ingredient,
  List<Measure> measures = const [],
}) {
  if (resolution.isDropped) return const [];
  // A LINKED line answers to D6's rule alone: valid when its amount is set.
  // No ingredient match is wanted (it has the other identity), and no
  // `allowed_units` gate applies — admission is an ingredient concept, and
  // this unit meets the target recipe's yield family later, at derive time
  // (D2). Which is why "¼ cup of a yield-less aioli" surfaces on the cook
  // plan, not here.
  if (resolution.isComponent) {
    return resolution.quantity == null
        ? const [LineIssue.amountMissing]
        : const [];
  }
  if (resolution.chosenIngredientId == null) {
    return const [LineIssue.unmatched];
  }

  final issues = <LineIssue>[];
  if (resolution.isRange && resolution.quantity == null) {
    issues.add(LineIssue.rangeUnpicked);
  }
  final unit = resolution.unit;
  if (ingredient != null && unit != null && unit.isNotEmpty) {
    if (!acceptableUnitTokens(
      ingredient,
      measures,
      parsedUnit: unit,
    ).contains(unit)) {
      issues.add(LineIssue.unitNotAllowed);
    }
  }
  return issues;
}

/// Whether every line is done — the Save gate. [issuesByLine] is the per-line
/// result of [lineIssues] across the whole import.
bool allLinesValid(Map<int, List<LineIssue>> issuesByLine) =>
    issuesByLine.values.every((i) => i.isEmpty);

/// The printed CROSS-REFERENCE a line carries — `"(page 38)"` — or null.
///
/// One more honest-import flag: the server strips it before matching (the way
/// parentheticals already are), so saying so on the card is what keeps the
/// stripping from looking like a misreading — the identity text still says
/// "(page 38)" and the chip below says which recipe that turned out to be.
/// The pattern mirrors the server's stripping, so the two agree about what
/// counts as a reference rather than as an ordinary parenthetical.
String? crossReferenceFlag(String ingredientText) {
  final match = RegExp(
    r'\((?:see\s+)?p(?:age|g)?\.?\s*\d+\)',
    caseSensitive: false,
  ).firstMatch(ingredientText);
  return match?.group(0);
}
