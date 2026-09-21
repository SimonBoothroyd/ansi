/// How a recipe line's amount reaches an ingredient's basis unit. Pure Dart;
/// shared by the macro and cost summations so both weigh a line identically.
///
/// A same-family pair converts directly, a measure through its stored weight,
/// mass↔volume only through the row's density, and a bare `piece` through the
/// row's piece weight (ADR-0015). Anything else is null, never an invented
/// number.
library;

import '../../../core/result/result.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import 'component_math.dart';
import 'recipe.dart';

/// What a vocabulary row states about the dimension its amounts live in. No
/// macros and no money.
typedef IngredientBasis = ({
  /// The unit a stored per-100 figure is denominated in (g or ml).
  MacrosBasis basis,

  /// Grams per millilitre, when the row states it — the only bridge between
  /// mass and volume (ADR-0009).
  double? densityGPerMl,

  /// What one piece weighs, in [basis] (ADR-0015). Null when the row has none.
  double? pieceBasisAmount,
});

/// A row's piece weight as a [Measure], so a count converts through
/// [convertMeasure] like a named measure.
Measure? pieceMeasureIn(IngredientBasis row) {
  final amount = row.pieceBasisAmount;
  if (amount == null) return null;
  return Measure(id: 'piece', label: 'piece', amount: amount, basis: row.basis);
}

/// Whether [line] is a bare count with a number and nothing weighing it. A line
/// pointing at an unsynced measure is not one: its weight exists, this device
/// just cannot see it.
bool isBareCount(LineItem line) =>
    line.quantity != null &&
    line.unit?.family == UnitFamily.count &&
    line.measure == null &&
    line.measureId == null;

/// [amount] of [unit] in [row]'s basis unit, or null when it cannot be bridged.
/// For a caller holding a bare [Quantity] rather than a line.
double? quantityInBasis(double amount, Unit unit, IngredientBasis row) {
  final to = row.basis.baseUnit;
  final piece = pieceMeasureIn(row);
  // A bare `piece` converts through the row's piece weight (ADR-0015).
  final converted = unit.family == UnitFamily.count && piece != null
      ? convertMeasure(amount, piece, to: to, densityGPerMl: row.densityGPerMl)
      : convert(
          Quantity(amount, unit),
          to: to,
          densityGPerMl: row.densityGPerMl,
        );
  return switch (converted) {
    Ok(:final value) => value.amount,
    Err() => null,
  };
}

/// [line]'s amount in [row]'s basis unit, or null when it cannot be bridged.
double? lineAmountInBasis(LineItem line, IngredientBasis row) {
  final quantity = line.quantity;
  if (quantity == null) return null;

  final measure = line.measure;
  if (measure != null) {
    return switch (convertMeasure(
      quantity,
      measure,
      to: row.basis.baseUnit,
      densityGPerMl: row.densityGPerMl,
    )) {
      Ok(:final value) => value.amount,
      Err() => null,
    };
  }
  if (line.measureId != null) {
    // An unresolved measure is a count, which cannot join a mass/volume total
    // until the measure row syncs.
    return null;
  }
  final unit = line.unit;
  // A component line in the target's own word has no catalog unit; it is a
  // share of a batch.
  if (unit == null) return null;
  return quantityInBasis(quantity, unit, row);
}

/// What a summation needs about one sub-recipe: its lines and serving count,
/// plus the yields and measures a component line resolves against. Walks are
/// depth-first with a visited set, so a cycle leaves the parent unresolved.
typedef SubRecipeNode = ({
  double servingsBase,
  List<LineItem> lines,
  List<YieldDenomination> yields,

  /// The node's live [RecipeMeasure]s. A word not in this list leaves the line
  /// unresolved, never re-read as a count.
  List<RecipeMeasure> measures,
});
