/// Per-line validity for the import review. Pure Dart.
///
/// A line is done, and stops blocking Save, when it is matched to an
/// ingredient, any printed range has a picked number, and its unit is one the
/// ingredient admits (ADR-0008 `allowed_units`, its measures, and the imprecise
/// words it earns).
library;

import 'package:meta/meta.dart';

import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/domain/serving_measure.dart';
import 'line_resolution.dart';

/// Why a line still wants the user. An empty issue list == done/clean.
enum LineIssue {
  /// No ingredient chosen yet.
  unmatched,

  /// The source printed a range and no single number has been picked.
  rangeUnpicked,

  /// The line's unit isn't one the matched ingredient can carry.
  unitNotAllowed,

  /// A line linked to a household recipe carries no amount. That is its only
  /// gate: it wants no ingredient match and faces no admission check.
  amountMissing,
}

/// The imprecise word a line printed, as a catalog unit. Null for any other
/// unit, a measure label, or no unit.
Unit? printedImpreciseUnit(String? unit) {
  if (unit == null || unit.isEmpty) return null;
  final resolved = unitById(unit);
  return resolved != null && resolved.family == UnitFamily.imprecise
      ? resolved
      : null;
}

/// The imprecise units the import admits for [ingredient] on a line whose
/// source printed [parsedUnit]:
///
/// - `to taste`, always;
/// - the ingredient's category gate ([impreciseUnitsFor]);
/// - the line's own printed word ([printedImpreciseUnit]), whatever the
///   category.
///
/// The category gates what the editor suggests, not what the source said: a
/// printed "pinch" on an uncategorised row would otherwise flag a unit nobody
/// could pick.
Set<Unit> importImpreciseUnitsFor(Ingredient ingredient, {String? parsedUnit}) {
  final printed = printedImpreciseUnit(parsedUnit);
  return {
    toTaste,
    ...impreciseUnitsFor(ingredient),
    if (printed != null) printed,
  };
}

/// The unit tokens acceptable for a matched line: allowed catalog units (by
/// id), [measures] (by label) and the imprecise words it earns, [parsedUnit]'s
/// included. Mirrors what the amount sheet offers ([amountSheetIngredient]), so
/// a unit is allowed iff the picker could have produced it.
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
        RecipeMeasureOption(:final measure) => notAWordForAnIngredient(measure),
      },
  };
}

/// One unit-suggestion chip. [token] is what the resolution stores (a catalog
/// unit id or a measure label); [label] is the chip text.
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

/// A matched line's acceptable units as ordered chips: the amount sheet's offer
/// for this line, so tapping a chip always yields a valid unit.
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
        // The same words the sheet's chip row uses: a weighed `piece` says
        // what one weighs, so the review never offers a bare count.
        UnitOption(:final unit) when unit == pieces => UnitSuggestion(
          token: unit.id,
          label: pieceChipLabel(ingredient),
        ),
        UnitOption(:final unit) => UnitSuggestion(
          token: unit.id,
          label: unit.label,
        ),
        MeasureOption(:final measure) => UnitSuggestion(
          token: measure.label,
          label: measureChipLabel(measure),
        ),
        RecipeMeasureOption(:final measure) => notAWordForAnIngredient(measure),
      },
  ];
}

/// How many unit chips a review line shows before the "more" fold.
const kVisibleUnitChips = 5;

/// [chips] reordered so the most likely land before the fold.
///
/// With a [parsedUnit]: that unit, the rest of its family, the ingredient's
/// measures, g/ml, everything else, imprecise words last. With none, the
/// incoming order stands ([allowedUnitChoicesFor] built it in ADR-0008 kitchen
/// order), imprecise still last. The sort is stable within each rank. A parsed
/// `piece` the row refuses is not among the chips, so the measures lead
/// (ADR-0010).
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

/// The measure the amount editor opens pre-selected on: when [unit] is one
/// [ingredient] cannot carry ([LineIssue.unitNotAllowed]) and the ingredient
/// names exactly one measure.
///
/// It pre-selects the sheet, not the line: [lineIssues] never calls this, so
/// the line stays flagged until someone confirms. Two or more measures
/// pre-select nothing (ADR-0010). Null when the unit is fine, the line printed
/// none, or no offered measure exists; volume-named measures and the serving
/// are skipped, as the chip row skips them.
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
  final offered = measures.where(
    (m) => !isVolumeUnitLabel(m.label) && !isServingMeasure(m),
  );
  return offered.length == 1 ? offered.first : null;
}

/// One line's review state: its outstanding [issues] and, for a matched line,
/// the valid units to offer as inline chips when the unit needs a fix.
class LineValidation {
  const LineValidation({
    required this.issues,
    this.unitChoices = const [],
    this.unitMeasure,
    this.sourceLine,
    this.pieceWeightMissing = false,
    this.rowIsStub = false,
  });

  final List<LineIssue> issues;
  final List<UnitSuggestion> unitChoices;

  /// The matched row's provenance line ([sourceProvenanceLine]). Null on an
  /// unmatched line and on a row no lookup filled. Carried here because
  /// validation already reads the import's vocab in one query.
  final String? sourceLine;

  /// The measure the line's current unit names, so the method's step chips need
  /// no second read. Null for a catalog unit, an unknown word, or no unit.
  final Measure? unitMeasure;

  /// The line is a count on a piece-default row with no piece weight
  /// (ADR-0015). The weight is the ingredient's fact, so the card opens the row
  /// rather than taking it here.
  final bool pieceWeightMissing;

  /// The matched row is a `stub`. It gates nothing; the wide review's work
  /// queue prints the word beside a row created during this review.
  final bool rowIsStub;

  bool get isClean => issues.isEmpty;
}

/// Whether [resolution] is a plain count: a printed `piece`, or a number with
/// no unit word, which commits as `piece`.
bool resolutionIsCount(LineResolution resolution) {
  final unit = resolution.unit;
  if (unit == null || unit.isEmpty) return resolution.quantity != null;
  return unitById(unit)?.family == UnitFamily.count;
}

/// Whether a counted [resolution] on [ingredient] is waiting on the row's
/// piece weight — see [LineValidation.pieceWeightMissing].
bool countNeedsPieceWeight(LineResolution resolution, Ingredient? ingredient) =>
    ingredient != null &&
    resolutionIsCount(resolution) &&
    defaultUnitNeedsPieceWeight(ingredient);

/// The ingredient the amount editor and the validity check reason about: the
/// real row with its import imprecise units ([importImpreciseUnitsFor]) unioned
/// into the allowed set, without touching the stored row. [parsedUnit] admits
/// the line's own printed imprecise word.
Ingredient amountSheetIngredient(Ingredient ingredient, {String? parsedUnit}) {
  final base = ingredient.allowedUnits ?? defaultAllowedUnitSet(ingredient);
  return ingredient.copyWith(
    allowedUnits: {
      ...base,
      ...importImpreciseUnitsFor(ingredient, parsedUnit: parsedUnit),
    }.toList(),
  );
}

/// The outstanding issues for [resolution]. With a matched [ingredient] and its
/// [measures] the unit is checked against the allowed set; without one only
/// unmatched and range issues are reported.
///
/// A dropped line has no issues. A printed imprecise word validates whatever
/// the category; a printed mass/volume unit the row cannot convert is still
/// flagged.
List<LineIssue> lineIssues(
  LineResolution resolution, {
  Ingredient? ingredient,
  List<Measure> measures = const [],
}) {
  if (resolution.isDropped) return const [];
  // A linked line is valid when its amount is set. No ingredient match or
  // `allowed_units` gate applies; its unit meets the target recipe's yield
  // family at derive time, on the cook plan.
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
  // A number with no unit word is a count and commits as `piece`, so it is
  // validated as one (ADR-0015).
  final unit = resolution.unit;
  final effectiveUnit = (unit == null || unit.isEmpty)
      ? (resolution.quantity != null ? pieces.id : null)
      : unit;
  if (ingredient != null && effectiveUnit != null) {
    if (!acceptableUnitTokens(
      ingredient,
      measures,
      parsedUnit: effectiveUnit,
    ).contains(effectiveUnit)) {
      issues.add(LineIssue.unitNotAllowed);
    }
  }
  return issues;
}

/// Whether every line is done — the Save gate. [issuesByLine] is the per-line
/// result of [lineIssues] across the whole import.
bool allLinesValid(Map<int, List<LineIssue>> issuesByLine) =>
    issuesByLine.values.every((i) => i.isEmpty);

/// The printed cross-reference a line carries, e.g. `"(page 38)"`, or null. The
/// server strips it before matching; the pattern mirrors the server's so both
/// agree on what counts as a reference.
String? crossReferenceFlag(String ingredientText) {
  final match = RegExp(
    r'\((?:see\s+)?p(?:age|g)?\.?\s*\d+\)',
    caseSensitive: false,
  ).firstMatch(ingredientText);
  return match?.group(0);
}
