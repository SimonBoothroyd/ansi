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
///   category, uncategorised rows included (plan 0020 **J3b**).
///
/// That third leg is never-invent, read the other way round. J3 gated what the
/// editor may SUGGEST; it must not gate what the source SAID. Without it a
/// canned "a pinch of chilli flakes" landing on a freshly created stub — which
/// has no category at all — validated as `unitNotAllowed` and locked the Save
/// gate on a unit nobody could have picked, because it was never offered.
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
/// ([LineIssue.unitNotAllowed]) and the ingredient names its own measures, the
/// most likely of them ("clove", "can") is almost always what the line meant.
/// Pre-selecting it turns resolving into one confirm tap instead of a
/// scroll-and-choose — the flag stays up until the user actually confirms.
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
  for (final m in measures) {
    if (!isVolumeUnitLabel(m.label)) return m;
  }
  return null;
}

/// One line's review state: its outstanding [issues] and, for a matched line,
/// the valid units to offer as inline chips when the unit needs a fix.
class LineValidation {
  const LineValidation({required this.issues, this.unitChoices = const []});

  final List<LineIssue> issues;
  final List<UnitSuggestion> unitChoices;

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
  final matched =
      resolution.chosenIngredientId != null ||
      resolution.createStubName != null;
  if (!matched) return const [LineIssue.unmatched];

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
