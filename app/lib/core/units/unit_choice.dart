/// What a unit picker may offer — PURE DART.
///
/// A picker's entry is a catalog [Unit] (`g`, `cup` — offered on everything)
/// or a named [Measure] of one ingredient (`clove`, `can (400 g)` — a word for
/// that row alone). Sealed, so a picker switches exhaustively and a new kind of
/// word cannot be silently rendered as a stale `else`.
///
/// It lives under the units rather than in a feature because three features
/// now offer the same row: an ingredient's quantity dock, a receipt's pack,
/// and a sub-recipe component's amount. A type owned by one of them would
/// make the other two import it, which is the import the layering rule exists
/// to stop.
///
/// Which entries a given surface offers, and in what order, is NOT decided
/// here: `features/ingredients/domain/allowed_units.dart` answers it for an
/// ingredient. This file is the vocabulary those answers are written in.
library;

import 'package:meta/meta.dart';

import 'measure.dart';
import 'number_format.dart';
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

/// A unit picker's full offer: the filtered `choices`, plus `offFilter` when
/// the stored selection had to be admitted from outside the filter (it is
/// also the last element of `choices`) so the UI can style it subtly
/// ("not in filter") rather than hide it.
typedef UnitChoiceOffer = ({List<UnitChoice> choices, UnitChoice? offFilter});
