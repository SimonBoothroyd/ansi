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

  group('householdLeftovers', () {
    // Cooked Monday 26 Oct and ticked; Tuesday's 1¾ nobody ate.
    final cooked = _plan([_meal(1, 2, eaten: 2), _meal(2, 1.75)]);
    const curry = (title: 'Chickpea Curry', keepsForDays: 4, freezerDays: 90);

    List<Leftover> shelves({
      required DateTime today,
      CookPlan? plan,
      List<StoredLeftover> stored = const [],
      LeftoverRecipe recipe = curry,
      Map<String, LeftoverAnswer> answers = const {},
      Map<String, double> plannedFromBatch = const {},
      Map<String, double> plannedFromRow = const {},
    }) => householdLeftovers(
      weeks: [(weekStart: _week, plan: plan ?? cooked)],
      today: today,
      stored: stored,
      recipes: {'curry': recipe},
      answers: answers,
      plannedFromBatch: plannedFromBatch,
      plannedFromRow: plannedFromRow,
    );

    StoredLeftover row(
      String id, {
      LeftoverPlace place = LeftoverPlace.fridge,
      String? batch = 'e1',
      double portions = 1,
      DateTime? since,
      DateTime? updatedAt,
      DateTime? goneAt,
    }) => StoredLeftover(
      id: id,
      place: place,
      recipeId: 'curry',
      portions: portions,
      since: since ?? DateTime(2026, 10, 26),
      batch: batch,
      goneAt: goneAt,
      updatedAt: updatedAt ?? DateTime.utc(2026, 10, 28, 12),
    );

    test('a cooked batch nobody spoke of is a fridge row, kept past its '
        'date', () {
      final left = shelves(today: DateTime(2026, 11, 5)).single;
      expect(left.isStored, isFalse);
      expect(left.batch, 'e1');
      expect(left.place, LeftoverPlace.fridge);
      expect(left.title, 'Chickpea Curry');
      expect(left.portions, 1.75);
      expect(left.since, DateTime(2026, 10, 26));
      expect(left.goodUntil, DateTime(2026, 10, 30));
      expect(left.pastItsDate(DateTime(2026, 10, 30)), isFalse);
      expect(left.pastItsDate(DateTime(2026, 11, 5)), isTrue);
    });

    test('meals planned from a batch come off it', () {
      expect(
        shelves(
          today: DateTime(2026, 10, 28),
          plannedFromBatch: const {'e1': 0.75},
        ).single.portions,
        1,
      );
    });

    test('a correction replaces the derived count and survives later '
        'ticks', () {
      final corrected = [row('lo1')];
      final left = shelves(
        today: DateTime(2026, 10, 28),
        stored: corrected,
      ).single;
      expect((left.id, left.portions), ('lo1', 1));
      expect(left.goodUntil, DateTime(2026, 10, 30));

      // Tuesday's meal ticked after all: the batch derives nothing now, and
      // the correction still stands.
      final ticked = _plan([
        _meal(1, 2, eaten: 2),
        _meal(2, 1.75, eaten: 1.75),
      ]);
      expect(
        shelves(
          plan: ticked,
          today: DateTime(2026, 10, 28),
          stored: corrected,
        ).single.portions,
        1,
      );
    });

    test('a freeze moves it to the freezer, dated the day it went in', () {
      final left = shelves(
        today: DateTime(2026, 11, 30),
        stored: [
          row(
            'lo1',
            place: LeftoverPlace.freezer,
            portions: 1.75,
            since: DateTime(2026, 10, 28),
          ),
        ],
      ).single;
      expect(left.place, LeftoverPlace.freezer);
      expect(left.since, DateTime(2026, 10, 28));
      expect(left.goodUntil, DateTime(2027, 1, 26));
      expect(left.pastItsDate(DateTime(2026, 11, 30)), isFalse);
    });

    test('a late freeze is dated at the fridge use-by; a freezer with no '
        'limit is never past its date', () {
      final left = shelves(
        today: DateTime(2026, 12, 20),
        recipe: (title: 'Chickpea Curry', keepsForDays: 4, freezerDays: null),
        stored: [
          row(
            'lo1',
            place: LeftoverPlace.freezer,
            portions: 1.75,
            since: DateTime(2026, 10, 30),
          ),
        ],
      ).single;
      expect(left.since, DateTime(2026, 10, 30));
      expect(left.goodUntil, isNull);
      expect(left.pastItsDate(DateTime(2027, 6, 30)), isFalse);
    });

    test('a row in words has no date, only an age', () {
      final left = shelves(
        plan: const CookPlan(),
        today: DateTime(2026, 11, 20),
        stored: [
          StoredLeftover(
            id: 'lo-words',
            place: LeftoverPlace.fridge,
            label: 'Mum’s lasagne',
            portions: 2,
            since: DateTime(2026, 10, 2),
            updatedAt: DateTime.utc(2026, 10, 2),
          ),
        ],
      ).single;
      expect(left.recipeId, isNull);
      expect(left.title, 'Mum’s lasagne');
      expect(left.goodUntil, isNull);
      expect(left.pastItsDate(DateTime(2026, 11, 20)), isFalse);
    });

    test('two batches of one dish are two rows, and a stored row replaces '
        'only its own', () {
      // A two-day fridge life splits Monday from Thursday.
      final twice = _plan([
        _meal(1, 2, eaten: 1),
        _meal(4, 2, eaten: 1, id: 'thu'),
      ], keeps: 2);
      final saturday = DateTime(2026, 10, 31);
      expect(
        [
          for (final l in shelves(plan: twice, today: saturday))
            (l.batch, l.goodUntil),
        ],
        [('e1', DateTime(2026, 10, 28)), ('thu', DateTime(2026, 10, 31))],
      );

      final left = shelves(
        plan: twice,
        today: saturday,
        stored: [
          row(
            'lo1',
            place: LeftoverPlace.freezer,
            since: DateTime(2026, 10, 28),
          ),
        ],
      );
      expect(
        [for (final l in left) (l.place, l.batch, l.isStored)],
        [
          (LeftoverPlace.fridge, 'thu', false),
          (LeftoverPlace.freezer, 'e1', true),
        ],
      );
    });

    test('a batch Cook was told was binned or eaten reads as gone; a kept '
        'answer says nothing', () {
      final today = DateTime(2026, 10, 28);
      expect(
        shelves(
          today: today,
          answers: const {'e1': (kept: 0.0, binned: 0.25, eaten: 0.0)},
        ),
        isEmpty,
      );
      expect(
        shelves(
          today: today,
          answers: const {'e1': (kept: 1.75, binned: 0.0, eaten: 0.0)},
        ).single.portions,
        1.75,
      );
    });

    test('two stored rows for one batch read as the newest, and meals from '
        'either come off it', () {
      final left = shelves(
        today: DateTime(2026, 10, 30),
        stored: [
          row('lo-b', portions: 2, updatedAt: DateTime.utc(2026, 10, 28)),
          row('lo-a', portions: 3, updatedAt: DateTime.utc(2026, 10, 27)),
        ],
        plannedFromRow: const {'lo-a': 0.5},
      ).single;
      expect((left.id, left.portions), ('lo-b', 1.5));
    });

    test('a row with nothing left, or said gone, is not shown and still '
        'hides its batch', () {
      final today = DateTime(2026, 10, 28);
      expect(
        shelves(
          today: today,
          stored: [row('lo1', portions: 2)],
          plannedFromRow: const {'lo1': 2},
        ),
        isEmpty,
      );
      expect(
        shelves(
          today: today,
          stored: [row('lo1', goneAt: DateTime.utc(2026, 10, 28, 9))],
        ),
        isEmpty,
      );
    });

    test('a batch cooked longer ago than the horizon is not read', () {
      // Cooked Monday 26 Oct: 28 days on is the last day it is read.
      expect(shelves(today: DateTime(2026, 11, 23)), hasLength(1));
      expect(shelves(today: DateTime(2026, 11, 24)), isEmpty);
      // Sundays: the four weeks before the week of 22 Nov, and that week.
      expect(leftoverWeekStarts(DateTime(2026, 11, 22)), [
        for (final day in [25, 32, 39, 46, 53]) DateTime(2026, 10, day),
      ]);
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
