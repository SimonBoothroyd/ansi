import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/cook_plan/domain/leftovers.dart';
import 'package:flutter_test/flutter_test.dart';

/// The week of Sunday 25 October 2026: Wed 28, Fri 30, Sat 31, Mon 2 Nov.
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

/// Hamburger Helper for two, planned Wed, Fri and Sat: 6 portions, keeps 3
/// days, freezes for 30. [eaten] is each day's ticked portions.
CookSession _helper(
  Map<int, double> eaten, {
  bool freezable = true,
  int? keeps = 3,
}) => CookSession(
  recipeId: 'hh',
  recipeTitle: 'Hamburger Helper',
  servingsBase: 6,
  cookDay: 3,
  keepsForDays: keeps,
  freezable: freezable,
  freezerDays: 30,
  covers: [
    for (final day in [3, 5, 6]) _meal(day, 2, eaten: eaten[day] ?? 0),
  ],
);

CookPlan _planOf(CookSession session) => CookPlan(
  recipes: [
    RecipeCookPlan(
      recipeId: session.recipeId,
      title: session.recipeTitle,
      servingsBase: session.servingsBase,
      keepsForDays: session.keepsForDays,
      freezable: session.freezable,
      freezerDays: session.freezerDays,
      sessions: [session],
    ),
  ],
);

DateTime _nov(int day) => DateTime(2026, 11, day);
DateTime _oct(int day) => DateTime(2026, 10, day);

void main() {
  group('cookDayOf', () {
    test('is the earliest day anybody ticked, in whatever order', () {
      // Saturday ticked first, then Friday.
      expect(cookDayOf(_helper({6: 2}), _week, _nov(1)), 6);
      expect(cookDayOf(_helper({6: 2, 5: 2}), _week, _nov(1)), 5);
      // Friday unticked again: back to Saturday.
      expect(cookDayOf(_helper({6: 2}), _week, _nov(1)), 6);
    });

    test('a skipped first meal moves it to the first ticked day', () {
      expect(cookDayOf(_helper({5: 2, 6: 2}), _week, _nov(1)), 5);
    });

    test('a batch nobody ticked cooks on its next meal, and once its days '
        'are over was never cooked', () {
      final untouched = _helper(const {});
      expect(cookDayOf(untouched, _week, _oct(27)), 3);
      expect(cookDayOf(untouched, _week, _oct(28)), 3);
      // Wednesday behind us, unticked: Friday is next.
      expect(cookDayOf(untouched, _week, _oct(29)), 5);
      expect(cookDayOf(untouched, _week, _nov(1)), isNull);
      expect(useByOf(untouched, _week, _nov(1)), isNull);
    });
  });

  test('a Saturday never ticked: next Thursday, folded in, becomes the '
      'cook day', () {
    final session = CookSession(
      recipeId: 'hh',
      recipeTitle: 'Hamburger Helper',
      servingsBase: 4,
      cookDay: 6,
      keepsForDays: 3,
      freezable: true,
      covers: [_meal(6, 2), _meal(11, 2)],
    );
    expect(cookDayOf(session, _week, _oct(31)), 6);
    expect(cookDayOf(session, _week, _nov(1)), 11);
    // Cooked on the day, nothing goes in the freezer.
    expect(freezeShareOf(session, _week, _nov(1)), isNull);
  });

  group('useByOf', () {
    test('is the cook day plus its fridge life, never stretched to a '
        'later meal', () {
      // Cooked Fri, keeps 3: till Mon, though nothing is planned past Sat.
      expect(useByOf(_helper({5: 2}), _week, _nov(1)), _nov(2));
      // A freezer share on the next Friday does not stretch it either.
      final shared = _helper({
        3: 2,
      }).copyWith(covers: [_meal(3, 2, eaten: 2), _meal(12, 2)]);
      expect(useByOf(shared, _week, _nov(1)), _oct(31));
    });

    test('a recipe with no fridge life keeps a week', () {
      expect(useByOf(_helper({5: 2}, keeps: null), _week, _nov(1)), _nov(6));
    });
  });

  group('freezeShareOf', () {
    test('names the later meals reached from the freezer, by the fridge '
        'date', () {
      // Cooked Sat 31 Oct, keeps 3: freeze by Tue 3 Nov for Thu 5 Nov.
      final session = CookSession(
        recipeId: 'hh',
        recipeTitle: 'Hamburger Helper',
        servingsBase: 4,
        cookDay: 6,
        keepsForDays: 3,
        freezable: true,
        covers: [_meal(6, 2, eaten: 2), _meal(11, 2)],
      );
      final share = freezeShareOf(session, _week, _oct(31))!;
      expect(share.portions, 2);
      expect(share.freezeBy, _nov(3));
      expect(share.forDays, [_nov(5)]);
      expect(
        freezeShareOf(session.copyWith(freezable: false), _week, _oct(31)),
        isNull,
      );
    });
  });

  group('readLeftovers — a batch', () {
    LeftoverShelves read(
      CookSession session, {
      required DateTime today,
      Map<String, List<PlannedFromLeftover>> fromBatch = const {},
    }) => readLeftovers(
      weeks: [(weekStart: _week, plan: _planOf(session))],
      today: today,
      fromBatch: fromBatch,
    );

    test('Wednesday skipped, Friday ticked: cooked Fri, good till Mon, and '
        'Wednesday’s portions are left', () {
      final left = read(_helper({5: 2, 6: 2}), today: _nov(1)).rows.single;
      expect(left.since, _oct(30));
      expect(left.goodUntil, _nov(2));
      expect(left.portions, 2);
      expect(left.pastItsDate(_nov(2)), isFalse);
      expect(left.pastItsDate(_nov(3)), isTrue);
    });

    test('Friday night: Saturday’s portions are spoken for, not left', () {
      final left = read(_helper({5: 2}), today: _oct(31)).rows.single;
      expect(left.portions, 2);
      expect(left.planned, 2);
      final saturday = left.meals.single;
      expect(saturday.own, isTrue);
      expect(saturday.place, LeftoverPlace.fridge);
    });

    test('ticks in any order give the same counts', () {
      final a = read(_helper({6: 2, 5: 2}), today: _nov(1)).rows.single;
      final b = read(_helper({5: 2, 6: 2}), today: _nov(1)).rows.single;
      expect((a.since, a.goodUntil, a.portions), (b.since, b.goodUntil, 2.0));
    });

    test('a batch nobody ticked leaves nothing once its days are over', () {
      expect(read(_helper(const {}), today: _nov(1)).rows, isEmpty);
    });

    test('a batch not cooked yet is dated from its next meal, offered from '
        'then, and not yet in the fridge', () {
      // Thursday: Wednesday was skipped, Friday is still to come.
      final left = read(_helper(const {}), today: _oct(29)).rows.single;
      expect(left.since, _oct(30));
      expect(left.portions, 2);
      expect(left.isCookedBy(_oct(29)), isFalse);
      expect(leftoverOfferOn(left, _oct(29), _oct(29)), isNull);
      expect(leftoverOfferOn(left, _nov(2), _oct(29)), same(left));
    });

    test('a meal planned from it warns on its own day: not enough left, or '
        'past its date', () {
      final meals = read(
        _helper({5: 2, 6: 2}, freezable: false),
        today: _oct(31),
        fromBatch: {
          'e3': [
            (entryId: 'sun', day: _nov(1), portions: 1.5),
            (entryId: 'mon', day: _nov(2), portions: 1),
            (entryId: 'tue', day: _nov(3), portions: 0.25),
          ],
        },
      ).meals;
      expect(meals['sun']!.warning, isNull);
      expect(meals['mon']!.warning, LeftoverWarning.notEnoughLeft);
      expect(meals['tue']!.warning, LeftoverWarning.notEnoughLeft);

      final late = read(
        _helper({5: 2, 6: 2}, freezable: false),
        today: _oct(31),
        fromBatch: {
          'e3': [(entryId: 'tue', day: _nov(3), portions: 1)],
        },
      ).meals['tue']!;
      expect(late.warning, LeftoverWarning.pastItsDate);
      expect(late.place, isNull);
    });

    test('a meal from a batch never cooked is not enough left', () {
      final meals = read(
        _helper(const {}),
        today: _nov(1),
        fromBatch: {
          'e3': [(entryId: 'mon', day: _nov(2), portions: 1)],
        },
      ).meals;
      expect(meals['mon']!.warning, LeftoverWarning.notEnoughLeft);
    });
  });

  group('freeze by', () {
    final cooked = _helper({5: 2, 6: 2});

    test('planning next Wed on Saturday offers it under Freezer, to be '
        'frozen by Mon', () {
      final left = readLeftovers(
        weeks: [(weekStart: _week, plan: _planOf(cooked))],
        today: _oct(31),
      ).rows.single;
      // Sun: still in date in the fridge.
      expect(
        leftoverOfferOn(left, _nov(1), _oct(31))!.place,
        LeftoverPlace.fridge,
      );
      final offer = leftoverOfferOn(left, _nov(4), _oct(31))!;
      expect(offer.place, LeftoverPlace.freezer);
      expect(offer.freezeBy, _nov(2));
      // Freezer dates count from the cook day.
      expect(offer.goodUntil, _nov(29));
      // Not a dish that freezes: not offered.
      final fridgeOnly = readLeftovers(
        weeks: [
          (weekStart: _week, plan: _planOf(cooked.copyWith(freezable: false))),
        ],
        today: _oct(31),
      ).rows.single;
      expect(leftoverOfferOn(fridgeOnly, _nov(4), _oct(31)), isNull);
    });

    test('picked, the row reads freeze by Mon for Wed until Mon, then '
        'is in the freezer', () {
      LeftoverShelves on(DateTime today) => readLeftovers(
        weeks: [(weekStart: _week, plan: _planOf(cooked))],
        today: today,
        fromBatch: {
          'e3': [(entryId: 'wed', day: _nov(4), portions: 2)],
        },
      );

      final saturday = on(_oct(31));
      final row = saturday.rows.single;
      expect(row.place, LeftoverPlace.fridge);
      expect(row.portions, 0);
      expect(row.planned, 2);
      expect(row.freezeBy, _nov(2));
      final wed = saturday.meals['wed']!;
      expect(wed.place, LeftoverPlace.freezer);
      expect(wed.freezeBy, _nov(2));
      expect(wed.warning, isNull);

      final tuesday = on(_nov(3)).rows.single;
      expect(tuesday.place, LeftoverPlace.freezer);
      expect(tuesday.since, _oct(30));
      expect(tuesday.goodUntil, _nov(29));
      expect(tuesday.pastItsDate(_nov(3)), isFalse);
      expect(tuesday.freezeBy, isNull);

      // Eaten: nothing left, nothing to come.
      expect(on(_nov(5)).rows, isEmpty);
    });

    test('a row past its date is never offered, from either shelf', () {
      final left = readLeftovers(
        weeks: [(weekStart: _week, plan: _planOf(cooked))],
        today: _nov(3),
      ).rows.single;
      expect(left.pastItsDate(_nov(3)), isTrue);
      expect(leftoverOfferOn(left, _nov(4), _nov(3)), isNull);

      final frozen = Leftover(
        id: 'f',
        place: LeftoverPlace.freezer,
        recipeId: 'hh',
        title: 'Hamburger Helper',
        since: _oct(1),
        goodUntil: _nov(1),
        portions: 2,
      );
      expect(leftoverOfferOn(frozen, _oct(31), _oct(30)), same(frozen));
      // Judged on the meal's day, not today.
      expect(leftoverOfferOn(frozen, _nov(2), _oct(30)), isNull);
    });
  });

  group('householdLeftovers', () {
    // Cooked Monday 26 Oct and ticked; Tuesday's 1¾ nobody ate.
    final cooked = _plan([_meal(1, 2, eaten: 2), _meal(2, 1.75)]);
    const curry = (
      title: 'Chickpea Curry',
      keepsForDays: 4,
      freezerDays: 90,
      freezable: true,
    );

    List<Leftover> shelves({
      required DateTime today,
      CookPlan? plan,
      List<StoredLeftover> stored = const [],
      LeftoverRecipe recipe = curry,
      Map<String, LeftoverAnswer> answers = const {},
      Map<String, List<PlannedFromLeftover>> fromBatch = const {},
      Map<String, List<PlannedFromLeftover>> fromRow = const {},
    }) => householdLeftovers(
      weeks: [(weekStart: _week, plan: plan ?? cooked)],
      today: today,
      stored: stored,
      recipes: {'curry': recipe},
      answers: answers,
      fromBatch: fromBatch,
      fromRow: fromRow,
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
      since: since ?? _oct(26),
      batch: batch,
      goneAt: goneAt,
      updatedAt: updatedAt ?? DateTime.utc(2026, 10, 28, 12),
    );

    test('a cooked batch nobody spoke of is a fridge row, kept past its '
        'date', () {
      final left = shelves(today: _nov(5)).single;
      expect(left.isStored, isFalse);
      expect(left.batch, 'e1');
      expect(left.place, LeftoverPlace.fridge);
      expect(left.title, 'Chickpea Curry');
      expect(left.portions, 1.75);
      expect(left.since, _oct(26));
      expect(left.goodUntil, _oct(30));
      expect(left.pastItsDate(_oct(30)), isFalse);
      expect(left.pastItsDate(_nov(5)), isTrue);
    });

    test('meals planned from a batch come off it', () {
      expect(
        shelves(
          today: _oct(28),
          fromBatch: {
            'e1': [(entryId: 'x', day: _oct(29), portions: 0.75)],
          },
        ).single.portions,
        1,
      );
    });

    test('a correction replaces the derived count and survives later '
        'ticks', () {
      final corrected = [row('lo1')];
      final left = shelves(today: _oct(28), stored: corrected).single;
      expect((left.id, left.portions), ('lo1', 1));
      expect(left.goodUntil, _oct(30));

      // Tuesday's meal ticked after all: the batch derives nothing now, and
      // the correction still stands.
      final ticked = _plan([
        _meal(1, 2, eaten: 2),
        _meal(2, 1.75, eaten: 1.75),
      ]);
      expect(
        shelves(
          plan: ticked,
          today: _oct(28),
          stored: corrected,
        ).single.portions,
        1,
      );
    });

    test('a stored fridge row with no stated fridge life keeps a week', () {
      final left = shelves(
        today: _oct(28),
        recipe: (
          title: 'Chickpea Curry',
          keepsForDays: null,
          freezerDays: 90,
          freezable: true,
        ),
        stored: [row('lo1')],
      ).single;
      expect(left.goodUntil, _nov(2));
    });

    test('a freezer row is dated from its cook day', () {
      final left = shelves(
        today: _nov(30),
        stored: [row('lo1', place: LeftoverPlace.freezer, portions: 1.75)],
      ).single;
      expect(left.place, LeftoverPlace.freezer);
      expect(left.since, _oct(26));
      expect(left.goodUntil, DateTime(2027, 1, 24));
      expect(left.pastItsDate(_nov(30)), isFalse);
    });

    test('a freezer with no limit is never past its date', () {
      final left = shelves(
        today: DateTime(2026, 12, 20),
        recipe: (
          title: 'Chickpea Curry',
          keepsForDays: 4,
          freezerDays: null,
          freezable: true,
        ),
        stored: [row('lo1', place: LeftoverPlace.freezer, portions: 1.75)],
      ).single;
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
            since: _oct(2),
            updatedAt: DateTime.utc(2026, 10, 2),
          ),
        ],
      ).single;
      expect(left.recipeId, isNull);
      expect(left.title, 'Mum’s lasagne');
      expect(left.goodUntil, isNull);
      expect(left.pastItsDate(DateTime(2026, 11, 20)), isFalse);
      expect(leftoverOfferOn(left, _nov(21), _nov(20)), isNull);
    });

    test('two batches of one dish are two rows, and a stored row replaces '
        'only its own', () {
      // A two-day fridge life splits Monday from Thursday.
      final twice = _plan([
        _meal(1, 2, eaten: 1),
        _meal(4, 2, eaten: 1, id: 'thu'),
      ], keeps: 2);
      final saturday = _oct(31);
      expect(
        [
          for (final l in shelves(plan: twice, today: saturday))
            (l.batch, l.goodUntil),
        ],
        // Soonest to go off first, past its date last.
        [('thu', _oct(31)), ('e1', _oct(28))],
      );

      final left = shelves(
        plan: twice,
        today: saturday,
        stored: [row('lo1', place: LeftoverPlace.freezer)],
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
      final today = _oct(28);
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
        today: _oct(30),
        stored: [
          row('lo-b', portions: 2, updatedAt: DateTime.utc(2026, 10, 28)),
          row('lo-a', portions: 3, updatedAt: DateTime.utc(2026, 10, 27)),
        ],
        fromRow: {
          'lo-a': [(entryId: 'x', day: _oct(29), portions: 0.5)],
        },
      ).single;
      expect((left.id, left.portions), ('lo-b', 1.5));
    });

    test('a row with nothing left or to come, or said gone, is not shown and '
        'still hides its batch', () {
      final today = _oct(28);
      expect(
        shelves(
          today: today,
          stored: [row('lo1', portions: 2)],
          fromRow: {
            'lo1': [(entryId: 'x', day: _oct(27), portions: 2)],
          },
        ),
        isEmpty,
      );
      // The same meal still to come: shown, all of it spoken for.
      final ahead = shelves(
        today: today,
        stored: [row('lo1', portions: 2)],
        fromRow: {
          'lo1': [(entryId: 'x', day: _oct(29), portions: 2)],
        },
      ).single;
      expect((ahead.portions, ahead.planned), (0.0, 2.0));
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

  group('a count set by hand', () {
    // Hamburger Helper: Wednesday skipped, cooked Friday, Saturday to come.
    LeftoverShelves read(
      CookSession session, {
      required DateTime today,
      List<StoredLeftover> stored = const [],
      Map<String, List<PlannedFromLeftover>> fromBatch = const {},
    }) => readLeftovers(
      weeks: [(weekStart: _week, plan: _planOf(session))],
      today: today,
      stored: stored,
      recipes: const {
        'hh': (
          title: 'Hamburger Helper',
          keepsForDays: 3,
          freezerDays: 30,
          freezable: true,
        ),
      },
      fromBatch: fromBatch,
    );

    /// The count Friday evening, after dinner.
    StoredLeftover said(double portions) => StoredLeftover(
      id: 'lo1',
      place: LeftoverPlace.fridge,
      recipeId: 'hh',
      portions: portions,
      since: _oct(30),
      batch: 'e3',
      updatedAt: DateTime(2026, 10, 30, 20),
    );

    test('the box holds what is free and what is spoken for', () {
      final left = read(_helper({5: 2}), today: _oct(30)).rows.single;
      expect((left.inBox, left.portions, left.planned), (4.0, 2.0, 2.0));
      expect(left.aside, 0);
    });

    test('ticks after it still come off; no tick leaves it in the box', () {
      // Saturday ticked: its two portions came out of the three said.
      final ticked = read(
        _helper({5: 2, 6: 2}),
        today: _oct(31),
        stored: [said(3)],
      ).rows.single;
      expect((ticked.id, ticked.inBox, ticked.portions), ('lo1', 1.0, 1.0));

      // Saturday still to come: spoken for, inside the three.
      final ahead = read(
        _helper({5: 2}),
        today: _oct(31),
        stored: [said(3)],
      ).rows.single;
      expect((ahead.inBox, ahead.portions, ahead.planned), (3.0, 1.0, 2.0));

      // Saturday over and nobody ticked it: still in the box.
      final skipped = read(
        _helper({5: 2}),
        today: _nov(1),
        stored: [said(3)],
      ).rows.single;
      expect((skipped.inBox, skipped.portions), (3.0, 3.0));
    });

    test('a count never goes below nothing', () {
      expect(
        read(_helper({5: 2, 6: 2}), today: _nov(1), stored: [said(1)]).rows,
        isEmpty,
      );
    });

    test('a write stores the count plus what comes off it on read', () {
      // Saturday half ticked: one portion of it gone, one spoken for.
      final derived = read(_helper({5: 2, 6: 1}), today: _oct(31)).rows.single;
      expect((derived.inBox, derived.aside), (3.0, 1.0));
      final stored = StoredLeftover(
        id: 'lo1',
        place: LeftoverPlace.fridge,
        recipeId: 'hh',
        portions: derived.inBox + derived.aside,
        since: _oct(30),
        batch: 'e3',
        updatedAt: DateTime(2026, 10, 31, 9),
      );
      final again = read(
        _helper({5: 2, 6: 1}),
        today: _oct(31),
        stored: [stored],
      ).rows.single;
      expect((again.inBox, again.portions), (3.0, derived.portions));
    });

    test('a meal planned from the batch comes off its stored count', () {
      final left = read(
        _helper({5: 2}),
        today: _nov(1),
        stored: [said(3)],
        fromBatch: {
          'e3': [(entryId: 'x', day: _nov(2), portions: 2)],
        },
      ).rows.single;
      expect((left.inBox, left.portions, left.planned), (3.0, 1.0, 2.0));
    });
  });

  test('a row is eaten from the fridge until its date, then from the '
      'freezer if the dish freezes', () {
    final fridge = Leftover(
      place: LeftoverPlace.fridge,
      title: 'Curry',
      since: _oct(26),
      goodUntil: _oct(30),
      portions: 1,
    );
    expect(fridge.shelfOn(_oct(25)), isNull);
    expect(fridge.shelfOn(DateTime(2026, 10, 30, 19)), LeftoverPlace.fridge);
    expect(fridge.shelfOn(_oct(31)), isNull);
    final freezable = Leftover(
      place: LeftoverPlace.fridge,
      title: 'Curry',
      since: _oct(26),
      goodUntil: _oct(30),
      portions: 1,
      freezable: true,
      freezerUntil: _nov(25),
    );
    expect(freezable.shelfOn(_oct(31)), LeftoverPlace.freezer);
    expect(freezable.shelfOn(_nov(26)), isNull);
  });
}
