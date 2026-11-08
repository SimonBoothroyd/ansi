import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/cook_plan/domain/leftovers.dart';
import 'package:ansi/features/cook_plan/presentation/leftover_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Wednesday.
final _today = DateTime(2026, 11, 11);

Leftover _row({
  LeftoverPlace place = LeftoverPlace.fridge,
  DateTime? since,
  DateTime? until,
  double portions = 2,
  double planned = 0,
  DateTime? freezeBy,
  List<LeftoverMeal> meals = const [],
}) => Leftover(
  place: place,
  title: 'Chili',
  since: since ?? DateTime(2026, 11, 9),
  goodUntil: until,
  portions: portions,
  planned: planned,
  freezeBy: freezeBy,
  meals: meals,
);

LeftoverMeal _meal(int day, {DateTime? freezeBy, double portions = 2}) =>
    LeftoverMeal(
      day: DateTime(2026, 11, day),
      portions: portions,
      place: freezeBy == null ? LeftoverPlace.fridge : LeftoverPlace.freezer,
      freezeBy: freezeBy,
    );

void main() {
  const shape = WeekShape.monday;

  test('a row says what can be planned from it and till when', () {
    expect(
      leftoverLine(
        _row(portions: 1.75, until: DateTime(2026, 11, 16)),
        _today,
        shape,
      ),
      '1¾ left · till Mon',
    );
    expect(leftoverTill(_today, _today, shape), 'till today');
    expect(leftoverTill(DateTime(2026, 11, 21), _today, shape), 'till 21 Nov');
    expect(leftoverTill(DateTime(2027, 1, 26), _today, shape), 'till Jan');
  });

  test('a freezer row says its date; one with no date says its age', () {
    final frozen = _row(
      place: LeftoverPlace.freezer,
      since: DateTime(2026, 10, 28),
      until: DateTime(2027, 1, 26),
    );
    expect(leftoverLine(frozen, _today, shape), '2 left · till Jan');
    expect(
      leftoverWhen(_row(since: DateTime(2026, 11, 7)), _today, shape),
      '4 days',
    );
    expect(leftoverAge(DateTime(2026, 11, 10), _today), '1 day');
    expect(leftoverAge(_today, _today), 'today');
  });

  test('a row behind its date says so, in either place', () {
    expect(
      leftoverLine(_row(until: DateTime(2026, 11, 8)), _today, shape),
      '2 left · past its date',
    );
    expect(
      leftoverWhen(
        _row(place: LeftoverPlace.freezer, until: DateTime(2026, 11, 2)),
        _today,
        shape,
      ),
      'past its date',
    );
  });

  test('a row names the days planned from it, and what goes in the freezer '
      'by when', () {
    final row = _row(
      until: DateTime(2026, 11, 15),
      freezeBy: DateTime(2026, 11, 15),
      meals: [
        _meal(10),
        _meal(13),
        _meal(14, portions: 0),
        _meal(17, freezeBy: DateTime(2026, 11, 15)),
      ],
    );
    expect(leftoverFor(row, _today, shape), 'for Fri');
    expect(leftoverFreezeFor(row, _today, shape), 'freeze by Sun for Tue');
    expect(leftoverFor(_row(), _today, shape), isNull);
    expect(leftoverFreezeFor(_row(), _today, shape), isNull);
  });

  test('the count is what is left', () {
    expect(leftCount(2), '2 left');
    expect(leftCount(1.75), '1¾ left');
  });

  test(
    'a batch not cooked yet says what it will freeze, by when, for when',
    () {
      final share = (
        portions: 2.0,
        freezeBy: DateTime(2026, 11, 14),
        forDays: [DateTime(2026, 11, 16)],
      );
      expect(freezeShareLine(share, _today, shape), 'freeze 2 by Sat for Mon');
      expect(freezeShareFor(share, _today, shape), 'freeze by Sat for Mon');
    },
  );
}
