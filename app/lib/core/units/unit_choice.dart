/// What a unit picker may offer. Pure Dart.
///
/// Sealed over a catalog [Unit], a named [Measure] of one ingredient and a
/// [RecipeMeasure] of one recipe, so pickers switch exhaustively. Which entries
/// a surface offers is decided by `allowed_units.dart` (ingredients) and
/// `component_units.dart` (component lines).
library;

import 'package:meta/meta.dart';

import 'measure.dart';
import 'recipe_measure.dart';
import 'units.dart';

/// One entry of a unit picker. Sealed so a picker can switch exhaustively.
@immutable
sealed class UnitChoice {
  const UnitChoice();

  /// The dropdown label.
  String get label;
}

final class UnitOption extends UnitChoice {
  const UnitOption(this.unit);

  final Unit unit;

  @override
  String get label => unit.label;

  @override
  bool operator ==(Object other) => other is UnitOption && other.unit == unit;

  @override
  int get hashCode => unit.hashCode;
}

final class MeasureOption extends UnitChoice {
  const MeasureOption(this.measure);

  final Measure measure;

  /// The word with what one of it comes to behind it, or the word alone where
  /// it already states its size ([measureWordWithSize]).
  @override
  String get label => measureWordWithSize(
    measure.label,
    measure.amount,
    measure.basis.baseUnit,
  );

  @override
  bool operator ==(Object other) =>
      other is MeasureOption && other.measure.id == measure.id;

  @override
  int get hashCode => measure.id.hashCode;
}

/// One of the target recipe's own words for a share of a batch. The [label] is
/// the bare word; what one comes to is said once on the conversion line.
final class RecipeMeasureOption extends UnitChoice {
  const RecipeMeasureOption(this.measure);

  final RecipeMeasure measure;

  @override
  String get label => measure.label;

  @override
  bool operator ==(Object other) =>
      other is RecipeMeasureOption && other.measure.id == measure.id;

  @override
  int get hashCode => measure.id.hashCode;
}

/// What an ingredient surface does when handed a [RecipeMeasureOption]: throw.
/// `allowedUnitChoicesFor` cannot produce one, and any fallback would fabricate
/// an amount.
Never notAWordForAnIngredient(RecipeMeasure measure) => throw StateError(
  'a recipe measure (“${measure.label}”) is not a word for an ingredient',
);

/// What a recipe surface does when handed a [MeasureOption]: throw, for the
/// same reason as [notAWordForAnIngredient]. `componentUnitChoices` cannot
/// produce one.
Never notAWordForARecipe(Measure measure) => throw StateError(
  'an ingredient measure (“${measure.label}”) is not a word for a recipe',
);

/// A unit picker's full offer: the filtered `choices`, plus `offFilter` when
/// the stored selection was admitted from outside the filter (it is also the
/// last of `choices`) so the UI can mark it.
typedef UnitChoiceOffer = ({List<UnitChoice> choices, UnitChoice? offFilter});
