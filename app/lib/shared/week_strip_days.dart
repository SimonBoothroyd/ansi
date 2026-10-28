/// The seven days a [WeekStripDay] row describes: what a batch is doing on each
/// day of the household's week, which days a meal eats from it, and which day
/// the screen is about. Pure Dart, so the geometry is unit-tested apart from
/// the widget that draws it (`week_strip.dart`).
///
/// Day `i` is offset `i` from the week's own first day, as everywhere else.
library;

import 'package:meta/meta.dart';

/// What a batch is doing on one day.
enum WeekStripFill {
  /// Nothing: before the cook, or no batch reaches it.
  none,

  /// The day it is cooked.
  cooked,

  /// Inside the fridge window after the cook.
  keeps,

  /// A meal reaches it from the freezer.
  frozen,

  /// Past the fridge window, with nothing frozen to reach it.
  gone,
}

/// One day of the strip.
@immutable
class WeekStripDay {
  const WeekStripDay({
    this.fill = WeekStripFill.none,
    this.eats = false,
    this.thisMeal = false,
  });

  final WeekStripFill fill;

  /// A meal eats from the batch this day: the dot.
  final bool eats;

  /// The meal the screen is about: the outline.
  final bool thisMeal;

  @override
  bool operator ==(Object other) =>
      other is WeekStripDay &&
      other.fill == fill &&
      other.eats == eats &&
      other.thisMeal == thisMeal;

  @override
  int get hashCode => Object.hash(fill, eats, thisMeal);

  @override
  String toString() =>
      'WeekStripDay(${fill.name}${eats ? ', eats' : ''}'
      '${thisMeal ? ', this meal' : ''})';
}

/// Which fill wins when two batches land on one day: the cook, then the
/// freezer, then the fridge, then the hatch.
const _strength = {
  WeekStripFill.cooked: 4,
  WeekStripFill.frozen: 3,
  WeekStripFill.keeps: 2,
  WeekStripFill.gone: 1,
  WeekStripFill.none: 0,
};

/// Several batches of one dish as one row of seven: per day the strongest fill
/// ([WeekStripFill.cooked] over [WeekStripFill.frozen] over
/// [WeekStripFill.keeps] over [WeekStripFill.gone]), and a dot or an outline
/// from any of them. No rows is seven empty days.
List<WeekStripDay> mergeStripDays(Iterable<List<WeekStripDay>> rows) => [
  for (var day = 0; day < 7; day++)
    rows.fold(const WeekStripDay(), (merged, row) {
      final other = day < row.length ? row[day] : const WeekStripDay();
      return WeekStripDay(
        fill: _strength[other.fill]! > _strength[merged.fill]!
            ? other.fill
            : merged.fill,
        eats: merged.eats || other.eats,
        thisMeal: merged.thisMeal || other.thisMeal,
      );
    }),
];

/// [days] with the fridge and the hatch taken off: only the days a batch is
/// cooked or comes out of the freezer keep their fill. Dots and the outline
/// stay.
List<WeekStripDay> cookDaysOnly(List<WeekStripDay> days) => [
  for (final d in days)
    WeekStripDay(
      fill: d.fill == WeekStripFill.cooked || d.fill == WeekStripFill.frozen
          ? d.fill
          : WeekStripFill.none,
      eats: d.eats,
      thisMeal: d.thisMeal,
    ),
];
