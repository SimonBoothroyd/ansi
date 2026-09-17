/// How a recipe line reaches an ingredient's basis unit — PURE DART
/// (invariant 2), and the ONE answer every summation over a recipe's lines
/// asks for.
///
/// The macro summation and the cost summation are the same walk over the same
/// lines with a different fact multiplied in at the end: grams of a line
/// against per-100 macros, or grams of a line against a per-100 price. What
/// they must never differ about is the **grams** — a line that weighs 213 g
/// for the macros and 210 g for the cost would be two readings of one recipe,
/// and no reader could tell which was wrong. So the conversion lives here,
/// once, and both call it.
///
/// It is the unit system's own matrix and adds nothing to it: a same-family
/// pair converts directly, a measure converts through its stored weight,
/// mass↔volume crosses only through the row's density, and a bare `piece`
/// crosses through the row's piece weight (ADR-0015). Every other pair is a
/// typed failure down there and a null here — never a number invented to make
/// a total render (invariant 3).
library;

import '../../../core/result/result.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import 'component_math.dart';
import 'recipe.dart';

/// What a vocabulary row states about the DIMENSION its amounts live in —
/// everything [lineAmountInBasis] needs, and deliberately nothing about what
/// the food is worth: no macros, no money.
typedef IngredientBasis = ({
  /// The unit a stored per-100 figure is denominated in (g or ml).
  MacrosBasis basis,

  /// What one millilitre weighs, when the row says — the only bridge between
  /// the mass and volume families (ADR-0009).
  double? densityGPerMl,

  /// What one of the ingredient weighs, in [basis] — the bridge a bare count
  /// crosses (ADR-0015). Null when the row has none.
  double? pieceBasisAmount,
});

/// A row's piece weight as the [Measure] the converter already understands:
/// `n piece` is `n × amount` of the basis unit, exactly like a named measure.
/// Nothing is invented — the amount is the row's own stated fact — so a count
/// converts through the same [convertMeasure] a clove or a can does.
Measure? pieceMeasureIn(IngredientBasis row) {
  final amount = row.pieceBasisAmount;
  if (amount == null) return null;
  return Measure(id: 'piece', label: 'piece', amount: amount, basis: row.basis);
}

/// Whether [line] is a bare count with a number and nothing weighing it.
///
/// A line pointing at a measure that has not synced in yet is NOT one:
/// something does weigh it, this device just cannot see it, and telling the
/// household to add a weight would send them to fix what is not broken.
bool isBareCount(LineItem line) =>
    line.quantity != null &&
    line.unit.family == UnitFamily.count &&
    line.measure == null &&
    line.measureId == null;

/// [amount] of [unit] expressed in [row]'s basis unit, or null when the unit
/// system cannot bridge it honestly.
///
/// The measure-free half of [lineAmountInBasis], for a caller holding a bare
/// [Quantity] rather than a recipe line — a shopping row's rolled-up total.
double? quantityInBasis(double amount, Unit unit, IngredientBasis row) {
  final to = row.basis.baseUnit;
  final piece = pieceMeasureIn(row);
  // A bare `piece` converts through the row's piece weight (ADR-0015) — the
  // count fact the way the density is the volume fact.
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

/// [line]'s amount expressed in [row]'s basis unit, or null when the unit
/// system cannot bridge it honestly.
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
    // An unresolved measure reads as its honest count fallback — a count
    // can't join a mass/volume total, so the line is unbridgeable until the
    // measure row syncs in.
    return null;
  }
  return quantityInBasis(quantity, line.unit, row);
}

/// What a summation needs about one sub-recipe it walks into: its own lines
/// and serving count, plus the yields a component line's amount is resolved
/// against.
///
/// The caller supplies these by id; a walk is depth-first with a visited set,
/// so a cycle raced past both guards renders the parent unresolved instead of
/// recursing forever.
typedef SubRecipeNode = ({
  double servingsBase,
  List<LineItem> lines,
  List<YieldDenomination> yields,
});
