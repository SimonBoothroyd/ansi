/// One pass of keeping Health Connect in step, against a fake phone.
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/features/health/domain/health_meal.dart';
import 'package:ansi/features/health/presentation/health_sync.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_health.dart';

HealthMeal _meal(String id, {double kcal = 400}) => HealthMeal(
  id: id,
  name: 'Curry',
  day: DateTime(2026, 10, 21),
  at: DateTime(2026, 10, 21, 19),
  mealType: HealthMealType.dinner,
  macros: Macros(kcal: kcal, protein: 30, carb: 40, fat: 10),
);

void main() {
  final window = DateTime.utc(2026, 10, 12);

  test('writes, takes back, and remembers what is now there', () async {
    final gateway = FakeHealthGateway();
    final log = FakeHealthSendLog()..log = {'gone': _meal('gone').contentKey};
    await reconcileHealth(
      [_meal('a')],
      windowStart: window,
      gateway: gateway,
      log: log,
    );
    expect(gateway.deleted, ['gone']);
    expect(gateway.written.map((m) => m.id), ['a']);
    expect(log.log.keys, ['a']);
  });

  test('a second pass with nothing changed writes nothing', () async {
    final gateway = FakeHealthGateway();
    final log = FakeHealthSendLog();
    await reconcileHealth(
      [_meal('a')],
      windowStart: window,
      gateway: gateway,
      log: log,
    );
    gateway.written.clear();
    await reconcileHealth(
      [_meal('a')],
      windowStart: window,
      gateway: gateway,
      log: log,
    );
    expect(gateway.written, isEmpty);
  });

  test('without permission it touches nothing, forgets nothing, and says '
      'so', () async {
    final gateway = FakeHealthGateway()..granted = false;
    final log = FakeHealthSendLog()..log = {'x': _meal('x').contentKey};
    await expectLater(
      reconcileHealth(
        const [],
        windowStart: window,
        gateway: gateway,
        log: log,
      ),
      throwsA(isA<HealthNotAllowed>()),
    );
    expect(gateway.deleted, isEmpty);
    expect(log.log.keys, ['x']);
  });

  test('a record Health Connect refuses never holds back the rest', () async {
    final gateway = FakeHealthGateway()..refuses.add('bad');
    final log = FakeHealthSendLog();
    final refused = await reconcileHealth(
      [_meal('a'), _meal('bad'), _meal('b')],
      windowStart: window,
      gateway: gateway,
      log: log,
    );
    expect(refused, ['bad']);
    expect(gateway.records.keys, unorderedEquals(['a', 'b']));
    // Not remembered as sent, so the next pass tries it again.
    expect(log.log.keys, unorderedEquals(['a', 'b']));
  });

  group('a tick, the switch and an untick, in any order', () {
    const members = {'ada': Member(id: 'ada', displayName: 'Ada')};
    const curry = RecipeMacroSummary(
      perServing: Macros(kcal: 400, protein: 30, carb: 40, fat: 10),
    );
    final weekStart = DateTime.utc(2026, 10, 19);

    /// Ada's meals as the phone would send them, with Wednesday's dinner
    /// ticked at [ticked] (or not), and what she had instead.
    List<HealthMeal> wanted({DateTime? ticked, PlanEntry? had}) =>
        healthMealsIn(
          WeekPlan(
            id: 'w',
            weekStart: weekStart,
            entries: [
              PlanEntry(
                id: 'e1',
                dayOfWeek: 2,
                mealSlot: 'Dinner',
                recipeId: 'curry',
                recipeTitle: 'Curry',
                eaterIds: const ['ada'],
                eatenAt: {'ada': ?ticked},
                had: {'ada': ?had},
              ),
            ],
          ),
          memberId: 'ada',
          membersById: members,
          summaryFor: (id) => id == 'curry' ? curry : null,
        ).meals;

    final gateway = FakeHealthGateway();
    final log = FakeHealthSendLog();
    Future<void> pass(List<HealthMeal> meals) =>
        reconcileHealth(meals, windowStart: window, gateway: gateway, log: log);

    setUp(() {
      gateway.records.clear();
      log.log = {};
    });

    test('ticked before the switch, sent once on; an untick takes it '
        'back, and nothing is ever sent as less than nothing', () async {
      final tick = DateTime(2026, 10, 21, 19, 42);
      // Ticked while off: nothing runs. Switched on: the first pass.
      await pass(wanted(ticked: tick));
      expect(gateway.records.keys, ['ansi:e1:ada']);
      expect(gateway.records.values.single.macros.kcal, 400);

      await pass(wanted());
      expect(gateway.records, isEmpty);
      expect(log.log, isEmpty);
      expect(gateway.written.every((m) => m.macros.kcal >= 0), isTrue);
    });

    test('a changed tick time replaces the record, never adds one', () async {
      await pass(wanted(ticked: DateTime(2026, 10, 21, 19, 42)));
      await pass(wanted(ticked: DateTime(2026, 10, 21, 21)));
      expect(gateway.records.keys, ['ansi:e1:ada']);
      expect(gateway.records.values.single.at, DateTime(2026, 10, 21, 21));
    });

    test(
      'unticked while switched off, it goes once switched back on',
      () async {
        await pass(wanted(ticked: DateTime(2026, 10, 21, 19, 42)));
        // Switched off, then unticked: nothing runs, the record stays.
        expect(gateway.records, hasLength(1));
        // Switched back on.
        await pass(wanted());
        expect(gateway.records, isEmpty);
      },
    );

    test(
      'something else instead of a tick replaces the meal in place',
      () async {
        await pass(wanted(ticked: DateTime(2026, 10, 21, 19, 42)));
        await pass(
          wanted(
            had: PlanEntry(
              id: 'h1',
              dayOfWeek: 2,
              mealSlot: 'Dinner',
              label: 'Pizza',
              macros: const Macros(kcal: 900, protein: 30, carb: 100, fat: 40),
              eaterIds: const ['ada'],
              insteadOf: 'e1',
              createdAt: DateTime(2026, 10, 21, 20),
            ),
          ),
        );
        expect(gateway.records.keys, ['ansi:e1:ada']);
        final record = gateway.records.values.single;
        expect(record.name, 'Pizza');
        expect(record.macros.kcal, 900);
        expect(record.at, DateTime(2026, 10, 21, 20));
      },
    );
  });
}
