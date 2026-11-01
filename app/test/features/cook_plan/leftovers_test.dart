import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/cook_plan/domain/leftovers.dart';
import 'package:flutter_test/flutter_test.dart';

/// The week of Sunday 25 October 2026.
final _week = DateTime(2026, 10, 25);

CoveredMeal _meal(int day, double portions, {double eaten = 0, String? id}) =>
    CoveredMeal(
      dayOfWeek: day,
      mealSlot: 'Dinner',
      portions: portions,
      entryId: id ?? 'e$day',
      eatenPortions: eaten,
    );

CookPlan _plan(List<CoveredMeal> meals, {int? keeps = 4}) => buildCookPlan([
  PlannedRecipe(
    recipeId: 'curry',
    title: 'Chickpea Curry',
    servingsBase: 4,
    keepsForDays: keeps,
    meals: meals,
  ),
]);

void main() {
  group('batchLeftovers', () {
    test('a batch nobody ticked was never cooked, so leaves nothing', () {
      final plan = _plan([_meal(1, 2), _meal(2, 2)]);
      expect(
        batchLeftovers(plan, weekStart: _week, today: DateTime(2026, 10, 30)),
        isEmpty,
      );
    });

    test('a cooked batch leaves its uneaten past meals, good until the cook '
        'day plus its fridge life', () {
      // Cooked Monday, ticked; Tuesday's meal nobody ate.
      final plan = _plan([_meal(1, 2, eaten: 2), _meal(2, 1.75)]);
      final left = batchLeftovers(
        plan,
        weekStart: _week,
        today: DateTime(2026, 10, 28),
      );
      expect(left, hasLength(1));
      expect(left.single.key, 'e1');
      expect(left.single.portions, 1.75);
      expect(left.single.cookDate, DateTime(2026, 10, 26));
      expect(left.single.useBy, DateTime(2026, 10, 30));
      expect(left.single.isGoodOn(DateTime(2026, 10, 30)), isTrue);
      expect(left.single.isGoodOn(DateTime(2026, 10, 31)), isFalse);
      expect(left.single.isDueOn(DateTime(2026, 10, 31)), isTrue);
    });

    test('a meal today or later is still to be eaten, not left', () {
      final plan = _plan([_meal(1, 2, eaten: 2), _meal(3, 2)]);
      // Wednesday is today.
      expect(
        batchLeftovers(plan, weekStart: _week, today: DateTime(2026, 10, 28)),
        isEmpty,
      );
    });

    test('two batches of one dish keep two dates', () {
      // A two-day fridge life splits Monday from Thursday.
      final plan = _plan([
        _meal(1, 2, eaten: 1),
        _meal(4, 2, eaten: 1, id: 'thu'),
      ], keeps: 2);
      final left = batchLeftovers(
        plan,
        weekStart: _week,
        today: DateTime(2026, 10, 31),
      );
      expect(
        [for (final l in left) l.useBy],
        [DateTime(2026, 10, 28), DateTime(2026, 10, 31)],
      );
      final saturday = DateTime(2026, 10, 31);
      expect([for (final l in left) l.isGoodOn(saturday)], [false, true]);
    });

    test('binned, eaten and planned-from portions come off; kept does not', () {
      final plan = _plan([_meal(1, 4, eaten: 1)]);
      List<BatchLeftover> left(
        Map<String, LeftoverAnswer> answers,
        Map<String, double> plannedFrom,
      ) => batchLeftovers(
        plan,
        weekStart: _week,
        today: DateTime(2026, 10, 27),
        answers: answers,
        plannedFrom: plannedFrom,
      );

      expect(left(const {}, const {}).single.portions, 3);
      expect(
        left(const {
          'e1': (kept: 3.0, binned: 0.0, eaten: 0.0),
        }, const {}).single.portions,
        3,
      );
      expect(
        left(const {}, const {'e1': 1.75}).single.portions,
        closeTo(1.25, 1e-9),
      );
      expect(
        left(
          const {'e1': (kept: 0.0, binned: 1.0, eaten: 0.25)},
          const {'e1': 1.75},
        ),
        isEmpty,
      );
    });

    test('an unknown fridge life is good only until its last meal', () {
      final plan = _plan([_meal(1, 2, eaten: 1)], keeps: null);
      final left = batchLeftovers(
        plan,
        weekStart: _week,
        today: DateTime(2026, 10, 27),
      ).single;
      expect(left.useBy, DateTime(2026, 10, 26));
      expect(left.isDueOn(DateTime(2026, 10, 27)), isTrue);
    });
  });

  test('a freezer share stretches the use-by to the last meal', () {
    final session = CookSession(
      recipeId: 'r',
      recipeTitle: 'Dal',
      servingsBase: 4,
      cookDay: 0,
      keepsForDays: 2,
      freezable: true,
      covers: [_meal(0, 2), _meal(6, 2)],
    );
    expect(useByOf(session, _week), DateTime(2026, 10, 31));
  });
}
