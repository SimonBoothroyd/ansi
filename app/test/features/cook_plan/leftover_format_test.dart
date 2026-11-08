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
}) => Leftover(
  place: place,
  title: 'Chili',
  since: since ?? DateTime(2026, 11, 9),
  goodUntil: until,
  portions: portions,
  planned: planned,
);

void main() {
  const shape = WeekShape.monday;

  test('a fridge row says the day it is good until', () {
    expect(
      leftoverLine(
        _row(portions: 1.75, until: DateTime(2026, 11, 16)),
        _today,
        shape,
      ),
      '1¾ · until Mon',
    );
    expect(leftoverUntil(_today, _today, shape), 'until today');
    expect(
      leftoverUntil(DateTime(2026, 11, 21), _today, shape),
      'until 21 Nov',
    );
  });

  test('a freezer row, or one with no date, says its age', () {
    final frozen = _row(
      place: LeftoverPlace.freezer,
      since: DateTime(2026, 10, 28),
    );
    expect(leftoverLine(frozen, _today, shape), '2 · 2 wk');
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
      '2 · past its date',
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

  test('the count names the meals still planned from it', () {
    expect(leftoverCount(_row()), '2');
    expect(leftoverCount(_row(planned: 2)), '2 · 2 planned');
  });
}
