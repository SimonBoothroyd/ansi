/// What a unit picker may offer — PURE DART.
///
/// A picker's entry is one of three things, and they are not the same kind of
/// fact: a catalog [Unit] (`g`, `cup` — offered on everything), a named
/// [Measure] of one ingredient (`clove`, `can (400 g)` — a word for that row
/// alone), or a [RecipeMeasure] of one recipe (`blob`, `loaf` — a word for
/// that recipe alone). Sealed, so a picker switches exhaustively and a new
/// kind of word cannot be silently rendered as a stale `else`.
///
/// It lives under the units rather than in a feature because three features
/// now offer the same row: an ingredient's quantity dock, a receipt's pack,
/// and a sub-recipe component's amount. A type owned by one of them would
/// make the other two import it, which is the import the layering rule exists
/// to stop.
///
/// Which entries a given surface offers, and in what order, is NOT decided
/// here: `features/ingredients/domain/allowed_units.dart` answers it for an
/// ingredient and `features/recipes/domain/component_units.dart` for a
/// component line. This file is the vocabulary those answers are written in.
library;

import 'package:meta/meta.dart';

import 'measure.dart';
import 'number_format.dart';
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

  @override
  String get label {
    final basis = measure.basis.baseUnit;
    return '${measure.label} (${formatAmountIn(measure.amount, basis)} '
        '${basis.label})';
  }

  @override
  bool operator ==(Object other) =>
      other is MeasureOption && other.measure.id == measure.id;

  @override
  int get hashCode => measure.id.hashCode;
}

/// One of the target recipe's own words for a share of a batch — the chip a
/// component line says `3 blob` with.
///
/// The [label] is the **bare word**, where a [MeasureOption] carries its weight
/// in brackets. An ingredient measure explains itself against a catalog unit
/// the reader already knows (`clove (3 g)`); a recipe measure has no such unit
/// to be said in — what one comes to is a share of a batch, and that is said
/// once on the conversion line above the row rather than nine times inside it.
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

/// What a surface **about an ingredient** does when handed a
/// [RecipeMeasureOption]: nothing, loudly.
///
/// `blob` is a word for a recipe. An ingredient's doors — its quantity dock, a
/// receipt's pack, a top-up, an import line — are never offered one
/// (`allowedUnitChoicesFor` cannot produce one), so a branch reaching here is
/// a wiring mistake in this app, not a shape the data can take. It throws
/// rather than falling back, because every fallback available would be a
/// fabricated amount: the alternative to this line is a silent `piece`.
Never notAWordForAnIngredient(RecipeMeasure measure) => throw StateError(
  'a recipe measure (“${measure.label}”) is not a word for an ingredient',
);

/// A unit picker's full offer: the filtered `choices`, plus `offFilter` when
/// the stored selection had to be admitted from outside the filter (it is
/// also the last element of `choices`) so the UI can style it subtly
/// ("not in filter") rather than hide it.
typedef UnitChoiceOffer = ({List<UnitChoice> choices, UnitChoice? offFilter});
