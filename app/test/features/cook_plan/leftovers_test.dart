import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/cook_plan/domain/cooking.dart';
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

  test('a Saturday never ticked: next Thursday, picked from it, becomes the '
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

  group('readCooking — the plan’s edge cases', () {
    test('1. the only tick on a past meal unticked: never cooked, nothing '
        'left, and its meals warn', () {
      final read = _read(
        _cooking([_m('wed', _oct(28)), _m('thu', _oct(29))], made: 4),
        _nov(1),
      );
      expect(read.rows, isEmpty);
      expect(read.meals.map((m) => m.warning).toSet(), {
        LeftoverWarning.notEnoughLeft,
      });
    });

    test('2. the only tick unticked with a meal still to come: it cooks '
        'then, and made keeps its snapshot', () {
      final read = _read(
        _cooking([_m('wed', _oct(28)), _m('sat', _oct(31))], made: 6),
        _oct(30),
      );
      final row = _fridge(read)!;
      expect(row.since, _oct(31));
      expect(row.isCookedBy(_oct(30)), isFalse);
      // Six made, Saturday's two spoken for.
      expect(row.box, 6);
      expect(row.portions, 4);
    });

    test('3. the earliest tick unticked: the cook day and dates move '
        'later', () {
      final both = _read(
        _cooking([
          _m('wed', _oct(28), eaten: 2),
          _m('fri', _oct(30), eaten: 2),
        ], made: 6),
        _oct(30),
      );
      expect(_fridge(both)!.since, _oct(28));
      expect(_fridge(both)!.goodUntil, _oct(31));
      final friday = _read(
        _cooking([_m('wed', _oct(28)), _m('fri', _oct(30), eaten: 2)], made: 6),
        _oct(30),
      );
      expect(_fridge(friday)!.since, _oct(30));
      expect(_fridge(friday)!.goodUntil, _nov(2));
    });

    test('4. ticks backfilled Sat, Fri, Wed: the cook day walks earlier, and '
        'the end state does not hang on their order', () {
      CookingRead after(Map<String, double> eaten, {bool reversed = false}) {
        final meals = [
          _m('wed', _oct(28), eaten: eaten['wed'] ?? 0),
          _m('fri', _oct(30), eaten: eaten['fri'] ?? 0),
          _m('sat', _oct(31), eaten: eaten['sat'] ?? 0),
        ];
        return _read(
          _cooking(reversed ? meals.reversed.toList() : meals, made: 6),
          _nov(1),
        );
      }

      expect(_fridge(after({'sat': 2}))!.since, _oct(31));
      expect(_fridge(after({'sat': 2, 'fri': 2}))!.since, _oct(30));
      final all = after({'sat': 2, 'fri': 2, 'wed': 2});
      final flipped = after({'sat': 2, 'fri': 2, 'wed': 2}, reversed: true);
      expect(all.rows, isEmpty);
      expect((flipped.fridge, flipped.freezer), (all.fridge, all.freezer));
    });

    test('5. set to 1, untick Fri, tick it again: 1, 3, 1', () {
      double box({required bool friday}) => _fridge(
        _read(
          _cooking(
            [
              _m('wed', _oct(28), eaten: 2),
              _m('fri', _oct(30), eaten: friday ? 2 : 0),
            ],
            made: 6,
            changes: (fridge: -1, freezer: 0),
          ),
          _oct(31),
        ),
      )!.inBox;
      expect(box(friday: true), 1);
      expect(box(friday: false), 3);
      expect(box(friday: true), 1);
    });

    test('6. both phones tick offline: one cooking, the same id', () {
      const unlinked = [
        (entryId: 'wed', dayOfWeek: 3),
        (entryId: 'fri', dayOfWeek: 5),
      ];
      final phoneA = cookingGroupOf('wed', unlinked: unlinked, keepsForDays: 3);
      final phoneB = cookingGroupOf('fri', unlinked: unlinked, keepsForDays: 3);
      expect(birthIdFor(phoneA), birthIdFor(phoneB));
      expect(birthIdFor(phoneA), 'wed');
    });

    test('7. both phones correct offline: both apply, and it reads 0', () {
      // Three left; each phone sets it to 1.
      final read = _read(
        _cooking(
          [_m('wed', _oct(28), eaten: 2), _m('fri', _oct(30), eaten: 1)],
          made: 6,
          changes: (fridge: -4, freezer: 0),
        ),
        _oct(31),
      );
      expect(read.fridge, -1);
      expect(read.rows, isEmpty);
    });

    test('8. one phone unticks while the other corrects: both stand', () {
      final read = _read(
        _cooking(
          [_m('wed', _oct(28), eaten: 2), _m('fri', _oct(30))],
          made: 6,
          changes: (fridge: -1, freezer: 0),
        ),
        _oct(31),
      );
      // 6 − Wed's 2 − the 1 said; Friday unticked takes nothing.
      expect(_fridge(read)!.inBox, 3);
    });

    test('9. two phones with different plans: at worst two cookings, a '
        'visible over-count the stepper fixes', () {
      final a = birthIdFor(
        cookingGroupOf(
          'fri',
          unlinked: const [
            (entryId: 'wed', dayOfWeek: 3),
            (entryId: 'fri', dayOfWeek: 5),
          ],
          keepsForDays: 3,
        ),
      );
      // Phone B no longer had Wednesday.
      final b = birthIdFor(
        cookingGroupOf(
          'fri',
          unlinked: const [(entryId: 'fri', dayOfWeek: 5)],
          keepsForDays: 3,
        ),
      );
      expect(a, isNot(b));
      final shelves = readCookings([
        _cooking([_m('wed', _oct(28), eaten: 2)], id: a, made: 4),
        _cooking([_m('fri', _oct(30), eaten: 2)], id: b, made: 2),
      ], _oct(31));
      expect(shelves.rows, hasLength(1));
      expect(shelves.rows.single.inBox, 2);
    });

    test('10. a meal moved or removed before cooking regroups, and nothing '
        'points at it', () {
      const week = [
        (entryId: 'mon', dayOfWeek: 1),
        (entryId: 'wed', dayOfWeek: 3),
      ];
      expect(cookingGroupOf('mon', unlinked: week, keepsForDays: 3), [
        'mon',
        'wed',
      ]);
      // Wednesday moved to Saturday, past Monday's fridge life.
      expect(
        cookingGroupOf(
          'mon',
          unlinked: const [
            (entryId: 'mon', dayOfWeek: 1),
            (entryId: 'wed', dayOfWeek: 6),
          ],
          keepsForDays: 3,
        ),
        ['mon'],
      );
    });

    test('11. an own meal removed after cooking: made stands, so its '
        'portions are in the fridge', () {
      final all = _read(
        _cooking([
          _m('wed', _oct(28), eaten: 2),
          _m('fri', _oct(30)),
          _m('sat', _oct(31)),
        ], made: 6),
        _oct(29),
      );
      expect(_fridge(all)!.portions, 0);
      final removed = _read(
        _cooking([_m('wed', _oct(28), eaten: 2), _m('fri', _oct(30))], made: 6),
        _oct(29),
      );
      expect(_fridge(removed)!.inBox, 4);
      expect(_fridge(removed)!.portions, 2);
    });

    test('12. an own meal moved after cooking, into another week: still '
        'linked; past the fridge date a freezer meal, or a warning', () {
      final moved = [_m('wed', _oct(28), eaten: 2), _m('thu', _nov(5))];
      final freezes = _read(_cooking(moved, made: 4), _oct(29));
      expect(freezes.meals.last.place, LeftoverPlace.freezer);
      expect(freezes.meals.last.freezeBy, _oct(31));
      final keeps = _read(
        _cooking(moved, made: 4, life: _fridgeOnly),
        _oct(29),
      );
      expect(keeps.meals.last.warning, LeftoverWarning.pastItsDate);
    });

    test('13. the anchor removed before cooking, with a pick on it: the '
        'cooking keeps its id, makes the pick, and the pick cooks it', () {
      final pick = _m('thu', _nov(5), week: _nov(1));
      final cooking = _cooking([pick], id: 'sat');
      expect(madeOf(cooking.cooking, cooking.meals), 2);
      expect(boughtIn(cooking.cooking, cooking.meals), _nov(1));
      final row = _fridge(_read(cooking, _nov(2)))!;
      expect(row.id, 'sat');
      expect(row.since, _nov(5));
    });

    test('14. a later meal raised after cooking warns, and the pot does not '
        'grow', () {
      final read = _read(
        _cooking([
          _m('wed', _oct(28), eaten: 2),
          _m('fri', _oct(30), eaten: 2),
          _m('sat', _oct(31), portions: 3),
        ], made: 6),
        _oct(31),
      );
      final row = _fridge(read)!;
      expect(row.inBox, 2);
      expect(read.meals.last.warning, LeftoverWarning.notEnoughLeft);
    });

    test('15. a later meal lowered after cooking frees its portions', () {
      final row = _fridge(
        _read(
          _cooking([
            _m('wed', _oct(28), eaten: 2),
            _m('fri', _oct(30), eaten: 2),
            _m('sat', _oct(31), portions: 1),
          ], made: 6),
          _oct(31),
        ),
      )!;
      expect((row.inBox, row.planned, row.portions), (2.0, 1.0, 1.0));
    });

    test('16. a tick counts what was eaten, never more than the meal', () {
      // An eater taken off after ticking: the reader still hands in their
      // share; a meal behind us takes it, capped at the meal.
      expect(_m('wed', _oct(28), portions: 1, eaten: 2).takeOn(_nov(1)), 1);
      expect(_m('wed', _oct(28), eaten: 1.5).takeOn(_nov(1)), 1.5);
    });

    test('17. a skipped first meal: cooked on the next ticked day, and the '
        'skipped portions are left', () {
      final row = _fridge(
        _read(
          _cooking([
            _m('wed', _oct(28)),
            _m('fri', _oct(30), eaten: 2),
            _m('sat', _oct(31)),
          ], made: 6),
          _oct(31),
        ),
      )!;
      expect(row.since, _oct(30));
      expect(row.goodUntil, _nov(2));
      expect((row.inBox, row.portions), (4.0, 2.0));
    });

    test('18. a pick from Saturday before it is cooked makes Thursday’s '
        'portions too, bought once in Saturday’s week', () {
      final cooking = _cooking([
        _m('sat', _oct(31)),
        _m('thu', _nov(5), week: _nov(1)),
      ]);
      expect(madeOf(cooking.cooking, cooking.meals), 4);
      expect(boughtIn(cooking.cooking, cooking.meals), _week);
    });

    test('19. a pick after Saturday’s first tick takes from the spare, '
        'or warns', () {
      CookingRead withPick(double portions) => _read(
        _cooking([
          _m('sat', _oct(31), eaten: 2),
          _m('mon', _nov(2), week: _nov(1), portions: portions),
        ], made: 4),
        _nov(1),
      );
      expect(withPick(2).meals.last.warning, isNull);
      expect(withPick(3).meals.last.warning, LeftoverWarning.notEnoughLeft);
    });

    test('20. the source unticked into nothing after a pick: cook Thu, made '
        'still Saturday’s', () {
      final read = _read(
        _cooking([
          _m('sat', _oct(31)),
          _m('thu', _nov(5), week: _nov(1)),
        ], made: 6),
        _nov(2),
      );
      final row = _fridge(read)!;
      expect(row.since, _nov(5));
      expect(row.box, 6);
    });

    test('21. cook fresh instead frees the portions it took', () {
      final linked = _fridge(
        _read(
          _cooking([
            _m('sat', _oct(31), eaten: 2),
            _m('mon', _nov(2), week: _nov(1)),
          ], made: 4),
          _nov(1),
        ),
      )!;
      expect(linked.portions, 0);
      final fresh = _fridge(
        _read(_cooking([_m('sat', _oct(31), eaten: 2)], made: 4), _nov(1)),
      )!;
      expect(fresh.portions, 2);
    });

    test('22. freeze 2, then untick Friday: the freezer keeps 2, the fridge '
        'gains Friday’s', () {
      CookingRead read({required bool friday}) => _read(
        _cooking(
          [
            _m('wed', _oct(28), eaten: 2),
            _m('fri', _oct(30), eaten: friday ? 2 : 0),
          ],
          made: 6,
          changes: (fridge: -2, freezer: 2),
        ),
        _oct(31),
      );
      expect((read(friday: true).fridge, read(friday: true).freezer), (0, 2));
      expect((read(friday: false).fridge, read(friday: false).freezer), (2, 2));
    });

    test('23. freeze by: `freeze by Mon for Wed` until Mon, then Wednesday '
        'is a freezer meal, with no write', () {
      final cooking = _cooking([
        _m('fri', _oct(30), eaten: 2),
        _m('sat', _oct(31), eaten: 2),
        _m('wed', _nov(4), week: _nov(1)),
      ], made: 6);
      final sunday = _read(cooking, _nov(1));
      final fridge = _fridge(sunday)!;
      expect(fridge.freezeBy, _nov(2));
      expect((fridge.inBox, fridge.portions), (2.0, 0.0));
      expect(sunday.meals.last.freezeBy, _nov(2));
      expect(_freezer(sunday), isNull);

      final tuesday = _read(cooking, _nov(3));
      expect(_fridge(tuesday), isNull);
      final freezer = _freezer(tuesday)!;
      expect(freezer.since, _oct(30));
      expect(freezer.goodUntil, _nov(29));
      expect((freezer.inBox, freezer.planned), (2.0, 2.0));
      expect(tuesday.meals.last.freezeBy, isNull);
    });

    test('24. undo takes the change or the gone back: it reads as before', () {
      final meals = [_m('wed', _oct(28), eaten: 2)];
      final before = _read(_cooking(meals, made: 4), _oct(29));
      final frozen = _read(
        _cooking(meals, made: 4, changes: (fridge: -2, freezer: 2)),
        _oct(29),
      );
      expect(_freezer(frozen)!.inBox, 2);
      final gone = _read(_cooking(meals, made: 4, goneAt: _oct(29)), _oct(29));
      expect(gone.rows, isEmpty);
      // Undone: no change, no gone.
      expect(_fridge(before)!.inBox, 2);
      expect(_freezer(before), isNull);
    });

    test('25. removed as gone off, a late untick does not bring it back', () {
      final read = _read(
        _cooking([_m('wed', _oct(28))], made: 4, goneAt: _nov(4)),
        _nov(5),
      );
      expect(read.rows, isEmpty);
    });

    test('26. typed leftovers: a week in the fridge, an age in the freezer, '
        'never offered', () {
      final fridge = _fridge(
        _read(
          _said(label: 'Soup', place: LeftoverPlace.fridge, since: _oct(28)),
          _oct(29),
        ),
      )!;
      expect(fridge.goodUntil, _nov(4));
      expect(leftoverOfferOn(fridge, _oct(30), _oct(29)), isNull);
      final freezer = _freezer(
        _read(
          _said(label: 'Soup', place: LeftoverPlace.freezer, since: _oct(1)),
          _oct(29),
        ),
      )!;
      expect(freezer.goodUntil, isNull);
      expect(freezer.pastItsDate(_dec(30)), isFalse);
    });

    test('27. the same dish every week: one cooking a week, no chain', () {
      // Each week groups its own meals; next week's Monday is not this
      // week's, whatever it keeps.
      final thisWeek = cookingGroupOf(
        'mon',
        unlinked: const [(entryId: 'mon', dayOfWeek: 1)],
        keepsForDays: 30,
        freezable: true,
      );
      final nextWeek = cookingGroupOf(
        'mon2',
        unlinked: const [(entryId: 'mon2', dayOfWeek: 1)],
        keepsForDays: 30,
        freezable: true,
      );
      expect(birthIdFor(thisWeek), isNot(birthIdFor(nextWeek)));
    });

    test('28. a dish twice in a week beyond its fridge life: two groups', () {
      const week = [
        (entryId: 'mon', dayOfWeek: 1),
        (entryId: 'sat', dayOfWeek: 6),
      ];
      expect(cookingGroupOf('mon', unlinked: week, keepsForDays: 2), ['mon']);
      expect(cookingGroupOf('sat', unlinked: week, keepsForDays: 2), ['sat']);
    });

    test('29. the week start changed: the buy week follows the meals', () {
      final cooking = _cooking([_m('sat', _oct(31), week: _oct(26))]);
      expect(boughtIn(cooking.cooking, cooking.meals), _oct(26));
    });

    test('30. a recipe’s fridge or freezer days edited: dates read '
        'live', () {
      final meals = [_m('wed', _oct(28), eaten: 2)];
      expect(
        _fridge(_read(_cooking(meals, made: 4), _oct(29)))!.goodUntil,
        _oct(31),
      );
      final longer = _read(
        _cooking(
          meals,
          made: 4,
          life: (
            title: 'Hamburger Helper',
            keepsForDays: 5,
            freezable: true,
            freezerDays: 60,
          ),
        ),
        _oct(29),
      );
      expect(_fridge(longer)!.goodUntil, _nov(2));
      expect(_fridge(longer)!.freezerUntil, _dec(27));
    });
  });

  group('readCooking', () {
    test('a fridge meal takes the freezer’s spare once the fridge has '
        'not got it, as after a Freeze', () {
      final read = _read(
        _cooking(
          [_m('wed', _oct(28), eaten: 2), _m('fri', _oct(30))],
          made: 4,
          changes: (fridge: -2, freezer: 2),
        ),
        _oct(29),
      );
      final fri = read.meals.last;
      expect(fri.place, LeftoverPlace.freezer);
      expect(fri.warning, isNull);
      expect((read.fridge, read.freezer), (0, 2));
    });

    test('food said by hand is dated by its day, on its shelf', () {
      final read = _read(
        _said(recipe: true, place: LeftoverPlace.freezer, since: _oct(20)),
        _oct(29),
      );
      expect(_fridge(read), isNull);
      final row = _freezer(read)!;
      expect((row.since, row.goodUntil, row.inBox), (_oct(20), _nov(19), 3.0));
    });

    test('a meal of food said by hand before its day warns', () {
      final read = _read(
        _said(
          recipe: true,
          place: LeftoverPlace.fridge,
          since: _oct(28),
          meals: [_m('mon', _oct(26), eaten: 1)],
        ),
        _oct(29),
      );
      expect(read.meals.single.warning, LeftoverWarning.notEnoughLeft);
    });

    test('a recipe since deleted takes its cooking with it', () {
      final read = _read(
        _cooking([_m('wed', _oct(28), eaten: 2)], made: 4, life: null),
        _oct(29),
      );
      expect(read.rows, isEmpty);
    });

    test('a meal past every date is from the fridge, past its date', () {
      final read = _read(
        _cooking(
          [_m('wed', _oct(28), eaten: 2), _m('tue', _nov(3), week: _nov(1))],
          made: 4,
          life: _fridgeOnly,
        ),
        _oct(29),
      );
      expect(read.meals.last.place, LeftoverPlace.fridge);
      expect(read.meals.last.warning, LeftoverWarning.pastItsDate);
    });

    test('rows go fridge first, soonest to go off first, past its date '
        'last', () {
      final shelves = readCookings([
        _cooking([_m('a', _oct(20), eaten: 2)], id: 'old', made: 4),
        _cooking([_m('b', _oct(28), eaten: 2)], id: 'new', made: 4),
        _cooking([_m('c', _oct(26), eaten: 2)], id: 'mid', made: 4),
        _said(recipe: true, place: LeftoverPlace.freezer, since: _oct(20)),
      ], _oct(29));
      expect(
        [for (final r in shelves.rows) '${r.id}:${r.place.name}'],
        ['mid:fridge', 'new:fridge', 'old:fridge', 'said:freezer'],
      );
    });
  });

  group('leftoverOfferOn', () {
    final cooked = _cooking([
      _m('fri', _oct(30), eaten: 2),
      _m('sat', _oct(31), eaten: 2),
    ], made: 6);

    test('planning next Wed on Saturday offers it under Freezer, to be '
        'frozen by Mon', () {
      final left = _fridge(_read(cooked, _oct(31)))!;
      expect(
        leftoverOfferOn(left, _nov(1), _oct(31))!.place,
        LeftoverPlace.fridge,
      );
      final offer = leftoverOfferOn(left, _nov(4), _oct(31))!;
      expect(offer.place, LeftoverPlace.freezer);
      expect(offer.freezeBy, _nov(2));
      expect(offer.goodUntil, _nov(29));
      final fridgeOnly = _fridge(
        _read(_cooking(cooked.meals, made: 6, life: _fridgeOnly), _oct(31)),
      )!;
      expect(leftoverOfferOn(fridgeOnly, _nov(4), _oct(31)), isNull);
    });

    test('a row past its date is never offered, from either shelf', () {
      final left = _fridge(_read(cooked, _nov(3)))!;
      expect(left.pastItsDate(_nov(3)), isTrue);
      expect(leftoverOfferOn(left, _nov(4), _nov(3)), isNull);

      final frozen = Leftover(
        id: 'f',
        place: LeftoverPlace.freezer,
        recipeId: 'hh',
        title: 'Hamburger Helper',
        since: _oct(1),
        goodUntil: _nov(1),
        box: 2,
      );
      expect(leftoverOfferOn(frozen, _oct(31), _oct(30)), same(frozen));
      expect(leftoverOfferOn(frozen, _nov(2), _oct(30)), isNull);
    });
  });

  group('Remove gone off is final', () {
    // Cooked Wed 28 Oct, good in the fridge till Sat 31, frozen till 27 Nov.
    final wed = _m('wed', _oct(28), eaten: 1);
    final thu = _m('thu', _oct(29), eaten: 1);

    test('a fridge part said gone stays gone, untick or no; the freezer part '
        'in date that day stays', () {
      CookingInput said({required double thuEaten}) => _cooking(
        [wed, _m('thu', _oct(29), eaten: thuEaten)],
        made: 6,
        changes: (fridge: -2, freezer: 2),
        goneAt: _nov(2),
      );
      final ticked = _read(said(thuEaten: 1), _nov(3));
      expect(_fridge(ticked), isNull);
      expect(_freezer(ticked)!.inBox, 2);
      expect(ticked.fridge, 0);
      // Thursday unticked after: its portion is not brought back.
      final unticked = _read(said(thuEaten: 0), _nov(3));
      expect(_fridge(unticked), isNull);
      expect(_freezer(unticked)!.inBox, 2);
    });

    test('said gone once the freezer part is past its date too, it all '
        'goes', () {
      final read = _read(
        _cooking(
          [wed, thu],
          made: 6,
          changes: (fridge: -2, freezer: 2),
          goneAt: _dec(1),
        ),
        _dec(2),
      );
      expect(read.rows, isEmpty);
    });

    test('a dish that does not freeze goes whole', () {
      final read = _read(
        _cooking([wed, thu], made: 6, goneAt: _nov(2), life: _fridgeOnly),
        _nov(3),
      );
      expect(read.rows, isEmpty);
    });
  });

  group('pots not cooked yet', () {
    const ragu = (
      title: 'Beef Ragù',
      keepsForDays: 3,
      freezable: true,
      freezerDays: 60,
    );
    UnbornMeal meal(String id, int day, {String recipe = 'ragu'}) => (
      entryId: id,
      recipeId: recipe,
      weekStart: _week,
      dayOfWeek: day,
      life: ragu,
    );

    test('planned meals no cooking holds group as a birth would, one pot '
        'per group under its first meal', () {
      final pots = plannedPots([
        meal('sat', 6),
        meal('sun-next', 7),
        // Past the fridge date but freezable: the same pot.
        meal('later', 6 + 10),
      ]);
      expect(pots, hasLength(1));
      final pot = pots.single;
      expect(
        (pot.id, pot.since, pot.goodUntil, pot.cooked, pot.plannedIn),
        ('sat', _oct(31), _nov(3), false, _week),
      );
      expect(pot.freezerUntil, _dec(30));
    });

    test('a week and a recipe each make their own pot', () {
      final pots = plannedPots([meal('a', 1), meal('b', 2, recipe: 'curry')]);
      expect(pots.map((p) => p.id), ['a', 'b']);
    });

    test('a pot not cooked yet is offered with nothing free, from its cook '
        'day, and from the freezer past its fridge date', () {
      final pot = plannedPots([meal('sat', 6)]).single;
      expect(pot.portions, 0);
      // Before its cook day it holds nothing to eat.
      expect(leftoverOfferOn(pot, _oct(30), _oct(28)), isNull);
      final soon = leftoverOfferOn(pot, _nov(2), _oct(28))!;
      expect((soon.place, soon.cooked), (LeftoverPlace.fridge, false));
      final later = leftoverOfferOn(pot, _nov(5), _oct(28))!;
      expect((later.place, later.freezeBy), (LeftoverPlace.freezer, _nov(3)));
      // Past its freezer life: not offered.
      expect(leftoverOfferOn(pot, _dec(31), _oct(28)), isNull);
    });

    test('a cooking nobody ticked yet reads not cooked; a tick cooks it', () {
      final ahead = _cooking([_m('sat', _oct(31))]);
      final before = _fridge(_read(ahead, _oct(29)))!;
      expect((before.cooked, before.since), (false, _oct(31)));
      expect(leftoverOfferOn(before, _nov(2), _oct(29))?.id, 'c');
      final ticked = _cooking([_m('sat', _oct(31), eaten: 1)], made: 2);
      expect(_fridge(_read(ticked, _nov(1)))!.cooked, isTrue);
    });
  });
}

const CookingShelfLife _helperLife = (
  title: 'Hamburger Helper',
  keepsForDays: 3,
  freezable: true,
  freezerDays: 30,
);

const CookingShelfLife _fridgeOnly = (
  title: 'Hamburger Helper',
  keepsForDays: 3,
  freezable: false,
  freezerDays: null,
);

DateTime _dec(int day) => DateTime(2026, 12, day);

/// A meal of a cooking, two portions unless said, in the week of [week].
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

/// Hamburger Helper's cooking with [meals].
CookingInput _cooking(
  List<CookingMeal> meals, {
  String id = 'c',
  double? made,
  CookingChanges changes = (fridge: 0, freezer: 0),
  DateTime? goneAt,
  CookingShelfLife? life = _helperLife,
}) => (
  cooking: Cooking(id: id, recipeId: 'hh', made: made, goneAt: goneAt),
  life: life,
  meals: meals,
  changes: changes,
);

/// Food said by hand: three portions of Hamburger Helper or of [label].
CookingInput _said({
  required LeftoverPlace place,
  required DateTime since,
  bool recipe = false,
  String? label,
  List<CookingMeal> meals = const [],
}) => (
  cooking: Cooking(
    id: 'said',
    recipeId: recipe ? 'hh' : null,
    label: recipe ? null : label,
    made: 3,
    place: place,
    since: since,
  ),
  life: recipe ? _helperLife : null,
  meals: meals,
  changes: (fridge: 0, freezer: 0),
);

CookingRead _read(CookingInput input, DateTime today) =>
    readCooking(input, today);

Leftover? _fridge(CookingRead read) =>
    read.rows.where((r) => r.place == LeftoverPlace.fridge).firstOrNull;

Leftover? _freezer(CookingRead read) =>
    read.rows.where((r) => r.place == LeftoverPlace.freezer).firstOrNull;
