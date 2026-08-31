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

/// The imprecise units the import amount editor ALWAYS admits — a "plus more,
/// to serve" use is legitimately imprecise regardless of the ingredient's
/// category, so `to taste`/`pinch`/`dash`/`handful` are always selectable and
/// always valid here.
const List<Unit> kImportImpreciseUnits = [pinch, dash, handful, toTaste];

/// The unit tokens acceptable for a matched line: the ingredient's allowed
/// catalog units (by id) + its [measures] (by label) + the always-admitted
/// imprecise units. Mirrors exactly what the amount sheet offers for this
/// ingredient (see [amountSheetIngredient]), so a unit is "allowed" iff the
/// picker could have produced it.
Set<String> acceptableUnitTokens(
  Ingredient ingredient,
  List<Measure> measures,
) {
  final offer = allowedUnitChoicesFor(
    amountSheetIngredient(ingredient),
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
/// amount sheet's offer (allowed set + measures + imprecise), so tapping a chip
/// always yields a valid unit.
List<UnitSuggestion> acceptableUnitChips(
  Ingredient ingredient,
  List<Measure> measures,
) {
  final offer = allowedUnitChoicesFor(
    amountSheetIngredient(ingredient),
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

/// [chips] reordered so the five most likely land in front of the fold, in the
/// owner's ranking: the line's own parsed [parsedUnit] first, then the rest of
/// that unit's family, then the ingredient's named measures (in the order they
/// were given — most likely first), then the generic mass/volume unit (g/ml),
/// then everything else, with the imprecise words last.
///
/// The imprecise tail folds UNLESS the parsed amount is itself imprecise ("a
/// good pinch"), in which case its family leads by the same rule that fronts
/// any other parsed unit — a pinch line should not have to expand to say pinch.
///
/// The sort is stable within each rank, so the ADR-0008 chip order the caller
/// built survives inside every group.
List<UnitSuggestion> rankedUnitChips(
  List<UnitSuggestion> chips, {
  required String? parsedUnit,
}) {
  final parsed = parsedUnit == null || parsedUnit.isEmpty
      ? null
      : unitById(parsedUnit);
  int rankOf(UnitSuggestion c) {
    if (parsedUnit != null && c.token == parsedUnit) return 0;
    final unit = unitById(c.token); // null ⇒ the token is a measure label
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
  if (acceptableUnitTokens(ingredient, measures).contains(unit)) return null;
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
/// about: the real ingredient with the always-admitted imprecise units unioned
/// into its allowed set, so imprecise chips are offered (and accepted) on every
/// line without touching the stored vocab row.
Ingredient amountSheetIngredient(Ingredient ingredient) {
  final base = ingredient.allowedUnits ?? defaultAllowedUnitSet(ingredient);
  return ingredient.copyWith(
    allowedUnits: {...base, ...kImportImpreciseUnits}.toList(),
  );
}

/// The outstanding issues for [resolution]. Pass the matched [ingredient] (and
/// its [measures]) to check the unit against the allowed set; without an
/// ingredient only the structural issues (unmatched / range) are reported.
///
/// A DROPPED line has no issues by construction: it is leaving the recipe, so
/// it can neither be flagged nor hold up Save (owner call).
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
    if (!acceptableUnitTokens(ingredient, measures).contains(unit)) {
      issues.add(LineIssue.unitNotAllowed);
    }
  }
  return issues;
}

/// Whether every line is done — the Save gate. [issuesByLine] is the per-line
/// result of [lineIssues] across the whole import.
bool allLinesValid(Map<int, List<LineIssue>> issuesByLine) =>
    issuesByLine.values.every((i) => i.isEmpty);
