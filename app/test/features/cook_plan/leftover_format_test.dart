import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
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
  id: 'left-1',
  place: place,
  title: 'Chili',
  since: since ?? DateTime(2026, 11, 9),
  goodUntil: until,
  planned: planned,
  freezeBy: freezeBy,
  meals: meals,
  box: portions + planned,
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
    // A weekday within the coming six days, else its date.
    expect(leftoverTill(DateTime(2026, 11, 17), _today, shape), 'till Tue');
    expect(leftoverTill(DateTime(2026, 11, 18), _today, shape), 'till 18 Nov');
    expect(leftoverTill(DateTime(2027, 1, 26), _today, shape), 'till 26 Jan');
  });

  test('the freezer says its month past the coming six days', () {
    String till(DateTime until) =>
        leftoverTill(until, _today, shape, frozen: true);
    expect(till(DateTime(2026, 11, 17)), 'till Tue');
    expect(till(DateTime(2026, 11, 21)), 'till Nov');
    expect(till(DateTime(2027, 1, 26)), 'till Jan');
  });

  test('cooked names the week when it is not this one', () {
    // Wednesday 11 November, in a week from Monday the 9th.
    expect(cookedOn(_today, _today, shape), 'cooked today');
    expect(cookedOn(DateTime(2026, 11, 9), _today, shape), 'cooked Mon');
    expect(cookedOn(DateTime(2026, 11, 7), _today, shape), 'cooked last Sat');
    expect(cookedOn(DateTime(2026, 11, 2), _today, shape), 'cooked last Mon');
    expect(cookedOn(DateTime(2026, 10, 31), _today, shape), 'cooked 31 Oct');
    // A Sunday week puts Saturday the 7th in last week, Sunday the 8th in
    // this one.
    expect(
      cookedOn(DateTime(2026, 11, 8), _today, WeekShape.sunday),
      'cooked Sun',
    );
  });

  test('a pot not cooked yet says when it cooks, and has no count', () {
    final pot = Leftover(
      id: 'sat',
      place: LeftoverPlace.fridge,
      recipeId: 'ragu',
      title: 'Beef Ragù',
      since: DateTime(2026, 11, 14),
      goodUntil: DateTime(2026, 11, 17),
      box: 0,
      freezable: true,
      cooked: false,
    );
    expect(leftoverWhen(pot, _today, shape), 'cooks Sat');
    expect(leftoverLine(pot, _today, shape), 'cooks Sat');
    expect(
      leftoverLine(pot.frozenForLater(), _today, shape),
      'cooks Sat · freeze by Tue',
    );
    expect(potCookedLine(pot, _today, shape), 'cooks Sat');
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

  test('a meal that wants more than is there is said, not listed', () {
    final row = _row(
      meals: [
        LeftoverMeal(
          entryId: 'wed',
          day: DateTime(2026, 11, 11),
          portions: 2,
          place: LeftoverPlace.fridge,
          warning: LeftoverWarning.notEnoughLeft,
        ),
        _meal(13, portions: 1),
      ],
    );
    expect(leftoverShortFor(row, _today, shape), 'today needs 2');
    expect(leftoverFor(row, _today, shape), 'for Fri');
    final later = _row(
      meals: [
        LeftoverMeal(
          entryId: 'fri',
          day: DateTime(2026, 11, 13),
          portions: 2,
          place: LeftoverPlace.fridge,
          warning: LeftoverWarning.notEnoughLeft,
        ),
      ],
    );
    expect(leftoverShortFor(later, _today, shape), 'Fri needs 2');
    expect(leftoverFor(later, _today, shape), isNull);
    expect(leftoverShortFor(_row(), _today, shape), isNull);
  });

  test('the meal that cooks for next week says so', () {
    // Sunday weeks: Saturday 14 Nov cooks it all, next Thursday frozen.
    const host = CookSession(
      recipeId: 'r',
      recipeTitle: 'Beef Ragù',
      servingsBase: 4,
      cookDay: 6,
      keepsForDays: 3,
      freezable: true,
      covers: [
        CoveredMeal(dayOfWeek: 6, mealSlot: 'Dinner', portions: 2),
        CoveredMeal(dayOfWeek: 11, mealSlot: 'Dinner', portions: 2),
      ],
    );
    final week = DateTime(2026, 11, 8);
    expect(
      nextWeekShareLine(host, week, DateTime(2026, 11, 9), WeekShape.sunday),
      'cook it all · freeze 2 for next Thu',
    );
    // A next-week meal inside the fridge life is kept, not frozen.
    final soon = host.copyWith(
      covers: const [
        CoveredMeal(dayOfWeek: 6, mealSlot: 'Dinner', portions: 2),
        CoveredMeal(dayOfWeek: 8, mealSlot: 'Dinner', portions: 1),
      ],
    );
    expect(
      nextWeekShareLine(soon, week, DateTime(2026, 11, 9), WeekShape.sunday),
      'cook it all · keep 1 for next Mon',
    );
    expect(
      nextWeekShareLine(
        host.copyWith(covers: [host.covers.first]),
        week,
        DateTime(2026, 11, 9),
        WeekShape.sunday,
      ),
      isNull,
    );
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
      // Weekdays, never dates: the batch's week began Mon 9 Nov, so Mon 16
      // is next Mon.
      final week = DateTime(2026, 11, 9);
      expect(
        freezeShareLine(share, week, shape),
        'freeze 2 by Sat for next Mon',
      );
      expect(freezeShareFor(share, week, shape), 'freeze by Sat for next Mon');
      // As ruled: Saturday cooks for next Thursday, to freeze by Tuesday.
      final far = (
        portions: 2.0,
        freezeBy: DateTime(2026, 11, 17),
        forDays: [DateTime(2026, 11, 19)],
      );
      expect(
        freezeShareLine(far, DateTime(2026, 11, 8), WeekShape.sunday),
        'freeze 2 by Tue for next Thu',
      );
    },
  );
}
