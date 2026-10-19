/// The amount an ingredient is offered at when nobody has said one. Pure Dart.
///
/// One order, read by every door that asks for one portion or one top-up — the
/// Week's snack sheet, the Shop's top-up sheet and Ask Ansi's cards:
///
/// 1. **What was used last time** at the same door ([LastAmount]): the last
///    meal of it for a meal, the last top-up of it for a top-up. It is the
///    household's own choice, said once.
/// 2. **One of its word for one**: the row's whole measure, `1 pot (150 g)`
///    ([wholeMeasureOf], ADR-0016).
/// 3. **One piece**, on a row that admits `piece` (ADR-0015).
///
/// Otherwise there is no default: a sheet opens empty and Ansi asks. A
/// remembered amount whose unit or measure the row no longer offers is passed
/// over rather than revived.
library;

import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import 'allowed_units.dart';
import 'ingredient.dart';

/// An amount used before: a number with a catalog unit, or a count of a
/// measure (whose `unit` is then the count fallback).
typedef LastAmount = ({double quantity, Unit? unit, String? measureId});

/// Where a default came from, so a surface can say so.
enum DefaultAmountSource {
  lastTime,
  wholeMeasure,
  piece;

  /// The card's words for it.
  String get said => switch (this) {
    lastTime => 'as last time',
    wholeMeasure || piece => 'one each',
  };
}

typedef DefaultAmount = ({
  double quantity,
  UnitChoice choice,
  DefaultAmountSource source,
});

/// The default for [ingredient] with its live [measures], or null.
DefaultAmount? defaultAmountFor(
  Ingredient ingredient,
  List<Measure> measures, {
  LastAmount? last,
}) {
  if (last != null && last.quantity > 0) {
    final measureId = last.measureId;
    if (measureId != null) {
      for (final m in measures) {
        if (m.id == measureId) {
          return (
            quantity: last.quantity,
            choice: MeasureOption(m),
            source: DefaultAmountSource.lastTime,
          );
        }
      }
    } else if (last.unit case final unit?
        when allowedUnitsFor(ingredient).contains(unit)) {
      return (
        quantity: last.quantity,
        choice: UnitOption(unit),
        source: DefaultAmountSource.lastTime,
      );
    }
  }
  final whole = wholeMeasureOf(ingredient, measures);
  if (whole != null) {
    return (
      quantity: 1,
      choice: MeasureOption(whole),
      source: DefaultAmountSource.wholeMeasure,
    );
  }
  if (allowedUnitsFor(ingredient).contains(pieces) &&
      (ingredient.pieceBasisAmount ?? 0) > 0) {
    return (
      quantity: 1,
      choice: const UnitOption(pieces),
      source: DefaultAmountSource.piece,
    );
  }
  return null;
}
