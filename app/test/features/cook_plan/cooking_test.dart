import 'package:ansi/features/cook_plan/domain/cooking.dart';
import 'package:flutter_test/flutter_test.dart';

/// The week of Sunday 25 October 2026.
final _week = DateTime(2026, 10, 25);
DateTime _oct(int day) => DateTime(2026, 10, day);
DateTime _nov(int day) => DateTime(2026, 11, day);

CookingMeal _m(
  String id,
  DateTime day, {
  double portions = 2,
  double eaten = 0,
  DateTime? week,
}) => CookingMeal(
  entryId: id,
  weekStart: week ?? _week,
  day: day,
  portions: portions,
  eaten: eaten,
);

void main() {
  group('made', () {
    test('is the live sum of its meals until it is fixed', () {
      const live = Cooking(id: 'c', recipeId: 'r');
      final meals = [_m('a', _oct(28)), _m('b', _oct(30), portions: 1.5)];
      expect(madeOf(live, meals), 3.5);
      expect(madeOf(const Cooking(id: 'c', recipeId: 'r', made: 6), meals), 6);
    });

    test('a whole batch rounds up to whole batches, live or fixed', () {
      // Serves 4, planned for 2: the whole batch makes 4.
      const whole = Cooking(id: 'c', recipeId: 'r', wholeBatchOf: 4);
      expect(madeOf(whole, [_m('a', _oct(28))]), 4);
      expect(
        madeOf(
          const Cooking(id: 'c', recipeId: 'r', made: 5, wholeBatchOf: 4),
          const [],
        ),
        8,
      );
      // Already whole: nothing spare.
      expect(madeOf(whole, [_m('a', _oct(28), portions: 4)]), 4);
      expect(roundUpToBatches(2, null), 2);
    });

    test('a meal removed after it was ticked plans nothing, and takes '
        'what was eaten', () {
      final removed = CookingMeal(
        entryId: 'r',
        weekStart: _week,
        day: _nov(1),
        portions: 2,
        eaten: 2,
        removed: true,
      );
      const live = Cooking(id: 'c', recipeId: 'r');
      expect(madeOf(live, [removed, _m('a', _nov(2))]), 2);
      // Ticked for today and then removed: it takes what was eaten only.
      expect(removed.takeOn(_nov(1)), 2);
      expect(nextCookDayOf([removed], _oct(30)), isNull);
      expect(cookDayOfCooking(live, [removed]), _nov(1));
      expect(boughtIn(live, [removed]), isNull);
    });
  });

  group('joinersOf', () {
    test('a week’s meal grouped with a pot not cooked yet joins it', () {
      // Ragù Saturday (6), keeps 3; Friday (5) added; Monday (1) is too far
      // ahead of it for a dish that does not freeze.
      final joins = joinersOf(
        unlinked: const [
          (entryId: 'mon', dayOfWeek: 1),
          (entryId: 'fri', dayOfWeek: 5),
        ],
        uncooked: const [
          (id: 'sat', days: [6]),
        ],
        keepsForDays: 3,
      );
      expect(joins, {'fri': 'sat'});
    });

    test('a dish that freezes reaches the whole week', () {
      final joins = joinersOf(
        unlinked: const [(entryId: 'mon', dayOfWeek: 1)],
        uncooked: const [
          (id: 'sat', days: [6]),
        ],
        keepsForDays: 3,
        freezable: true,
      );
      expect(joins, {'mon': 'sat'});
    });

    test('nothing joins without a pot not cooked yet', () {
      expect(
        joinersOf(
          unlinked: const [(entryId: 'fri', dayOfWeek: 5)],
          uncooked: const [],
        ),
        isEmpty,
      );
    });
  });

  group('cookDayOfCooking', () {
    test('is the earliest ticked day, whatever the order of the meals', () {
      const c = Cooking(id: 'c', recipeId: 'r');
      final meals = [
        _m('sat', _oct(31), eaten: 2),
        _m('wed', _oct(28)),
        _m('fri', _oct(30), eaten: 1),
      ];
      expect(cookDayOfCooking(c, meals), _oct(30));
      expect(cookDayOfCooking(c, meals.reversed.toList()), _oct(30));
      expect(cookDayOfCooking(c, [_m('wed', _oct(28))]), isNull);
    });

    test('food said by hand is dated by its day, ticks or not', () {
      final c = Cooking(
        id: 'c',
        label: 'Soup',
        made: 2,
        place: LeftoverPlace.fridge,
        since: _oct(20),
      );
      expect(c.saidByHand, isTrue);
      expect(cookDayOfCooking(c, [_m('a', _oct(28), eaten: 1)]), _oct(20));
    });
  });

  test('nextCookDayOf is the first meal not behind today, or none', () {
    final meals = [_m('wed', _oct(28)), _m('sat', _oct(31))];
    expect(nextCookDayOf(meals, _oct(28)), _oct(28));
    expect(nextCookDayOf(meals, _oct(29)), _oct(31));
    expect(nextCookDayOf(meals, _nov(1)), isNull);
  });

  group('takeOn', () {
    test('a meal behind today takes its ticked shares, capped', () {
      expect(_m('a', _oct(28), eaten: 1).takeOn(_oct(29)), 1);
      expect(_m('a', _oct(28), eaten: 3).takeOn(_oct(29)), 2);
      expect(_m('a', _oct(28)).takeOn(_oct(29)), 0);
    });

    test('today’s or a later meal takes its planned portions', () {
      expect(_m('a', _oct(29)).takeOn(_oct(29)), 2);
      expect(_m('a', _oct(30), eaten: 1).takeOn(_oct(29)), 2);
    });
  });

  group('boughtIn', () {
    test('is the week of the earliest linked meal', () {
      const c = Cooking(id: 'c', recipeId: 'r');
      expect(
        boughtIn(c, [_m('thu', _nov(5), week: _nov(1)), _m('sat', _oct(31))]),
        _week,
      );
    });

    test('ties on a day go to the lower id, so every reader agrees', () {
      const c = Cooking(id: 'c', recipeId: 'r');
      expect(
        boughtIn(c, [_m('b', _oct(31), week: _nov(1)), _m('a', _oct(31))]),
        _week,
      );
    });

    test('food said by hand and a cooking with no meals are bought '
        'nowhere', () {
      expect(boughtIn(const Cooking(id: 'c', recipeId: 'r'), const []), isNull);
      expect(
        boughtIn(
          Cooking(
            id: 'c',
            recipeId: 'r',
            made: 2,
            place: LeftoverPlace.fridge,
            since: _oct(20),
          ),
          [_m('a', _oct(28))],
        ),
        isNull,
      );
    });
  });

  group('cookingGroupOf', () {
    const week = [
      (entryId: 'mon', dayOfWeek: 1),
      (entryId: 'wed', dayOfWeek: 3),
      (entryId: 'sun', dayOfWeek: 6),
    ];

    test('groups the week’s unlinked meals by shelf life, the earliest '
        'first', () {
      expect(cookingGroupOf('wed', unlinked: week, keepsForDays: 3), [
        'mon',
        'wed',
      ]);
      expect(cookingGroupOf('sun', unlinked: week, keepsForDays: 3), ['sun']);
    });

    test('a freezable dish reaches its far meal from the freezer', () {
      expect(
        cookingGroupOf(
          'sun',
          unlinked: week,
          keepsForDays: 3,
          freezable: true,
          freezerDays: 30,
        ),
        ['mon', 'wed', 'sun'],
      );
    });

    test('no fridge life stated keeps a week: the whole week is one', () {
      expect(cookingGroupOf('mon', unlinked: week), ['mon', 'wed', 'sun']);
    });

    test('a meal not among them is a group of its own', () {
      expect(cookingGroupOf('x', unlinked: week), ['x']);
    });
  });

  group('birthIdFor', () {
    test('reuses a cooking a meal already links to', () {
      expect(birthIdFor(const ['a', 'b'], linkedTo: const ['c']), 'c');
    });

    test('else one whose id is a meal of the group', () {
      expect(birthIdFor(const ['a', 'b'], cookingIds: const {'b'}), 'b');
    });

    test('else the group’s anchor, its first meal', () {
      expect(birthIdFor(const ['a', 'b']), 'a');
    });
  });
}
