import 'dart:convert';
import 'dart:io';

import 'package:ansi/core/sync/connector.dart' show insertOnceTables;
import 'package:ansi/features/cook_plan/data/cook_plan_repository_impl.dart'
    show loadCookPlan;
import 'package:ansi/features/cook_plan/data/cooking_store.dart';
import 'package:ansi/features/cook_plan/data/leftover_repository_impl.dart';
import 'package:ansi/features/cook_plan/domain/leftovers.dart';
import 'package:ansi/features/planning/data/planning_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/leftover_rows.dart';
import '../../helpers/test_db.dart';

/// The week of Monday 24 August 2026; today is its Wednesday.
final _week = DateTime(2026, 8, 24);
final _wednesday = DateTime(2026, 8, 26);

/// The curry, keeps 3 days, freezes for 90; Ada eats 1, Jun ¾.
Future<void> _household(PowerSyncDatabase db) async {
  await db.execute(
    'INSERT INTO recipe (id, household_id, title, servings_base, '
    'keeps_for_days, freezable, freezer_days, created_at, updated_at) '
    "VALUES ('curry', 'h', 'Curry', 2, 3, 1, 90, '2026-01-01', "
    "'2026-01-01')",
  );
  await db.execute(
    'INSERT INTO household_member (id, household_id, display_name, '
    'sort_order, portion_factor, created_at, updated_at) VALUES '
    "('a', 'h', 'Ada', 0, 1, '2026-01-01', '2026-01-01'), "
    "('b', 'h', 'Jun', 1, 0.75, '2026-01-01', '2026-01-01')",
  );
}

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteLeftoverRepository repo;
  late SqlitePlanningRepository planning;

  Future<LeftoverShelves> read({DateTime? today}) =>
      repo.watchHouseholdLeftovers(today: today ?? _wednesday).first;

  Future<List<Leftover>> shelves({DateTime? today}) async =>
      (await read(today: today)).rows;

  Future<String> curry(int day, {DateTime? week}) => planning.addEntry(
    weekStart: week ?? _week,
    dayOfWeek: day,
    mealSlot: 'Dinner',
    recipeId: 'curry',
    eaterIds: const ['a', 'b'],
  );

  Future<void> tick(String entry, String member, {bool ate = true}) =>
      planning.setMealEaten(
        entry,
        memberId: member,
        eatenAt: ate ? DateTime.utc(2026, 8, 24, 19) : null,
      );

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqliteLeftoverRepository(
      db,
      householdId: 'h',
      clock: () => _wednesday,
    );
    planning = SqlitePlanningRepository(
      db,
      householdId: 'h',
      clock: () => _wednesday,
    );
    await _household(db);
  });

  tearDown(() => closeTestDb(db, dir));

  group('pots not born yet', () {
    test('are this week’s and later meals no cooking holds, grouped as a '
        'birth would group them; a pick from one births it', () async {
      // Monday is behind Wednesday; Thursday and Friday are ahead.
      await curry(0);
      final thu = await curry(3);
      await curry(4);
      final next = await curry(3, week: DateTime(2026, 8, 31));
      final pots = (await read()).pots;
      expect(pots.map((p) => (p.id, p.since, p.cooked)), [
        (thu, DateTime(2026, 8, 27), false),
        (next, DateTime(2026, 9, 3), false),
      ]);
      expect(pots.first.plannedIn, _week);

      // Next Thursday picked from this week's pot: it is born and linked.
      final picked = await planning.addEntry(
        weekStart: DateTime(2026, 8, 31),
        dayOfWeek: 5,
        mealSlot: 'Dinner',
        recipeId: 'curry',
        eaterIds: const ['a'],
        cooking: thu,
      );
      final cooking = (await db.get(
        'SELECT cooking FROM plan_entry WHERE id = ?',
        [picked],
      ))['cooking'];
      expect(cooking, isNotNull);
      final after = await read();
      // This week's pot is a cooking now, not cooked yet; next week's is
      // still a pot.
      expect(after.pots.map((p) => p.id), [next]);
      final row = after.rows.singleWhere((r) => r.id == cooking);
      expect(row.cooked, isFalse);
    });
  });

  group('the tick path', () {
    test('a first tick births the group’s cooking and links the '
        'group; the page reads it', () async {
      final mon = await curry(0);
      final tue = await curry(1);
      await tick(tue, 'b');
      final cooking = await db.get('SELECT * FROM cooking');
      expect(cooking['id'], mon);
      expect(cooking['made'], 3.5);
      final row = (await shelves()).single;
      // Tue cooked; Jun's ¾ eaten of 3½ made, Monday skipped.
      expect(
        (row.id, row.since, row.inBox),
        (mon, DateTime(2026, 8, 25), 2.75),
      );
    });

    test('an untick writes nothing to the cooking; with every meal behind '
        'us it reads never cooked', () async {
      final mon = await curry(0);
      await tick(mon, 'b');
      await drainCrudQueue(db);
      await tick(mon, 'b', ate: false);
      final ops = await queuedCrudOps(db);
      expect(ops.map((o) => o['type']).toSet(), {'meal_eaten'});
      expect((await db.get('SELECT made FROM cooking'))['made'], 1.75);
      expect(await shelves(), isEmpty);
    });

    test('a birth checks for its id first: a cooking the other phone born '
        'and synced is linked, never inserted again', () async {
      final mon = await curry(0);
      await insertCooking(db, id: mon, recipeId: 'curry', made: 1.75);
      await drainCrudQueue(db);
      await tick(mon, 'a');
      final ops = await queuedCrudOps(db);
      expect(ops.where((o) => o['type'] == 'cooking'), isEmpty);
      expect(
        (await db.get('SELECT cooking FROM plan_entry WHERE id = ?', [
          mon,
        ]))['cooking'],
        mon,
      );
    });

    test('a tick counts for a member taken off the meal since', () async {
      final mon = await curry(0);
      await tick(mon, 'b');
      await planning.setEaters(mon, const ['a']);
      // Made 1¾ at the tick; Jun's usual ¾ still came out of it.
      expect((await shelves()).single.inBox, 1);
    });

    test('the read is one flat query: a cooking weeks old is still read, '
        'past its date', () async {
      final old = await curry(0, week: DateTime(2026, 7, 6));
      await tick(old, 'b');
      final row = (await shelves()).single;
      expect(row.pastItsDate(_wednesday), isTrue);
    });
  });

  group('the shelves’ writes', () {
    late String mon;

    setUp(() async {
      mon = await curry(0);
      await tick(mon, 'b');
    });

    test('the stepper writes the difference, and later ticks still move '
        'it', () async {
      final row = (await shelves()).single;
      expect(row.inBox, 1);
      await repo.setLeftoverPortions(row, 0.5);
      final change = await db.get('SELECT fridge, freezer FROM cooking_change');
      expect((change['fridge'], change['freezer']), (-0.5, 0.0));
      expect((await shelves()).single.inBox, 0.5);
      // Ada's tick takes her 1: nothing left to show.
      await tick(mon, 'a');
      expect(await shelves(), isEmpty);
      await tick(mon, 'a', ate: false);
      expect((await shelves()).single.inBox, 0.5);
    });

    test('Freeze moves the fridge box; Undo soft-deletes the change', () async {
      final undo = await repo.freezeLeftover((await shelves()).single);
      final frozen = await shelves();
      expect(frozen.single.place, LeftoverPlace.freezer);
      expect(frozen.single.inBox, 1);
      await repo.undoLeftovers(undo);
      expect((await shelves()).single.place, LeftoverPlace.fridge);
      expect(
        (await db.get('SELECT deleted_at FROM cooking_change'))['deleted_at'],
        isNotNull,
      );
    });

    test('Remove gone off says the cooking gone, for good: a late untick '
        'does not bring it back; Undo does', () async {
      final saturday = DateTime(2026, 8, 29);
      final undo = await repo.markLeftoversGone([
        (await shelves(today: saturday)).single,
      ]);
      expect(undo.gone, {mon: null});
      await tick(mon, 'b', ate: false);
      await tick(mon, 'b');
      expect(await shelves(today: saturday), isEmpty);
      await repo.undoLeftovers(undo);
      expect(await shelves(today: saturday), hasLength(1));
    });

    test('Remove gone off on a fridge part leaves the freezer’s, and is '
        'final: a late untick brings neither part back', () async {
      final saturday = DateTime(2026, 8, 29);
      // Said on Saturday, when the fridge part is past its date.
      final onSaturday = SqliteLeftoverRepository(
        db,
        householdId: 'h',
        clock: () => saturday,
      );
      // Two said into the freezer, and one more in the fridge; Ada ate
      // hers too.
      await insertCookingChangeFor(db, mon, fridge: 1, freezer: 2);
      await tick(mon, 'a');
      final rows = await shelves(today: saturday);
      final fridge = rows.singleWhere((l) => l.place == LeftoverPlace.fridge);
      expect(fridge.pastItsDate(saturday), isTrue);
      final undo = await onSaturday.markLeftoversGone([fridge]);
      expect(undo.gone, {mon: null});
      expect(undo.changes, isEmpty);
      Future<List<(LeftoverPlace, double)>> left() async => [
        for (final l in await shelves(today: saturday)) (l.place, l.inBox),
      ];
      expect(await left(), [(LeftoverPlace.freezer, 2.0)]);
      // Ada did not eat Monday's after all: her portion stays gone with the
      // fridge part, and the freezer keeps what it had.
      await tick(mon, 'a', ate: false);
      expect(await left(), [(LeftoverPlace.freezer, 2.0)]);
      // Undo puts the fridge part back, unticks and all.
      await onSaturday.undoLeftovers(undo);
      expect(
        (await left()).map((r) => r.$1),
        containsAll([LeftoverPlace.fridge, LeftoverPlace.freezer]),
      );
    });

    test('Remove gone off a second time, when the freezer part has gone off '
        'too, takes it all; its Undo puts back only the second', () async {
      await insertCookingChangeFor(db, mon, freezer: 1);
      final saturday = DateTime(2026, 8, 29);
      final first =
          await SqliteLeftoverRepository(
            db,
            householdId: 'h',
            clock: () => saturday,
          ).markLeftoversGone([
            (await shelves(
              today: saturday,
            )).singleWhere((l) => l.place == LeftoverPlace.fridge),
          ]);
      final saidFirst = (await db.get(
        'SELECT gone_at FROM cooking',
      ))['gone_at'];
      expect(first.gone, {mon: null});
      // Freezer life is 90 days: by December it has gone off too.
      final december = DateTime(2026, 12, 2);
      final later = SqliteLeftoverRepository(
        db,
        householdId: 'h',
        clock: () => december,
      );
      final freezer = (await shelves(today: december)).single;
      expect(freezer.place, LeftoverPlace.freezer);
      expect(freezer.pastItsDate(december), isTrue);
      final second = await later.markLeftoversGone([freezer]);
      expect(second.gone, {mon: saidFirst});
      expect(await shelves(today: december), isEmpty);
      await later.undoLeftovers(second);
      expect(
        (await db.get('SELECT gone_at FROM cooking'))['gone_at'],
        saidFirst,
      );
      expect((await shelves(today: december)).single.place, freezer.place);
    });
  });

  test('Add a leftover is food said by hand, on its shelf, dated', () async {
    final id = await repo.addLeftover(
      place: LeftoverPlace.freezer,
      portions: 2,
      since: DateTime(2026, 8, 12),
      label: ' Mum’s lasagne ',
    );
    final row = await db.get('SELECT * FROM cooking WHERE id = ?', [id]);
    expect(
      (row['label'], row['made'], row['place'], row['since']),
      ('Mum’s lasagne', 2.0, 'freezer', '2026-08-12'),
    );
    final shelf = (await shelves()).single;
    expect(
      (shelf.place, shelf.inBox, shelf.goodUntil),
      (LeftoverPlace.freezer, 2.0, null),
    );
  });

  group('the carry-over', () {
    Future<void> carry() =>
        carryOverCookings(db, householdId: 'h', today: _wednesday);

    test('births a cooking for every group ticked in the last 28 days, '
        'once', () async {
      final mon = await curry(0);
      // Ticked before this release: no cooking yet.
      await db.execute(
        'INSERT INTO meal_eaten (id, household_id, plan_entry_id, member_id, '
        "eaten_at, created_at, updated_at) VALUES ('t', 'h', ?, 'b', "
        "'2026-08-24T19:00:00Z', '2026-08-24T19:00:00Z', "
        "'2026-08-24T19:00:00Z')",
        [mon],
      );
      final old = await curry(0, week: DateTime(2026, 7, 6));
      await db.execute(
        'INSERT INTO meal_eaten (id, household_id, plan_entry_id, member_id, '
        "eaten_at, created_at, updated_at) VALUES ('t2', 'h', ?, 'b', "
        "'2026-07-06T19:00:00Z', '2026-07-06T19:00:00Z', "
        "'2026-07-06T19:00:00Z')",
        [old],
      );
      await carry();
      final cookings = await db.getAll('SELECT id, made FROM cooking');
      expect([for (final c in cookings) (c['id'], c['made'])], [(mon, 1.75)]);
      await drainCrudQueue(db);
      await carry();
      expect(await queuedCrudOps(db), isEmpty);
    });

    test('a group an old fridge row names joins the cooking that row '
        'became, at the count the row said', () async {
      final mon = await curry(0);
      final tue = await curry(1);
      await db.execute(
        'INSERT INTO meal_eaten (id, household_id, plan_entry_id, member_id, '
        "eaten_at, created_at, updated_at) VALUES ('t', 'h', ?, 'a', "
        "'2026-08-24T19:00:00Z', '2026-08-24T19:00:00Z', "
        "'2026-08-24T19:00:00Z')",
        [mon],
      );
      // 0060's row and the cooking 0061 made of it: 2 said, in the fridge.
      await db.execute(
        'INSERT INTO leftover (id, household_id, place, recipe_id, portions, '
        'since, batch, created_at, updated_at) VALUES '
        "('lo', 'h', 'fridge', 'curry', 2, '2026-08-24', ?, "
        "'2026-08-24T20:00:00Z', '2026-08-24T20:00:00Z')",
        [mon],
      );
      await insertCooking(
        db,
        id: 'lo',
        recipeId: 'curry',
        made: 2,
        since: '2026-08-24',
      );
      expect((await shelves()).single.inBox, 2);
      await carry();
      final linked = await db.getAll(
        'SELECT cooking FROM plan_entry ORDER BY day_of_week',
      );
      expect([for (final r in linked) r['cooking']], ['lo', 'lo']);
      // Still what the row said, though Monday's tick now comes off it; a
      // tick after it moves it.
      expect((await shelves()).single.inBox, 2);
      await tick(tue, 'a');
      expect((await shelves()).single.inBox, 1);
      await carry();
      expect(await db.getAll('SELECT id FROM cooking_change'), hasLength(1));
    });

    test('a batch some meal was planned from joins its cooking, ticked or '
        'not', () async {
      final mon = await curry(0);
      final tue = await curry(1);
      await insertCooking(db, id: mon, recipeId: 'curry');
      final thu = await curry(3);
      await linkToCooking(db, thu, mon);
      await carry();
      final linked = await db.getAll(
        'SELECT id, cooking FROM plan_entry ORDER BY day_of_week',
      );
      expect(
        {for (final r in linked) r['id']: r['cooking']},
        {mon: mon, tue: mon, thu: mon},
      );
    });

    test('an old answer that a batch was binned takes it to nothing, '
        'once', () async {
      final mon = await curry(0);
      await db.execute(
        'INSERT INTO meal_eaten (id, household_id, plan_entry_id, member_id, '
        "eaten_at, created_at, updated_at) VALUES ('t', 'h', ?, 'b', "
        "'2026-08-24T19:00:00Z', '2026-08-24T19:00:00Z', "
        "'2026-08-24T19:00:00Z')",
        [mon],
      );
      await db.execute(
        'INSERT INTO batch_leftover (id, household_id, plan_entry_id, binned, '
        "created_at, updated_at) VALUES ('bl', 'h', ?, 1, "
        "'2026-08-25T09:00:00Z', '2026-08-25T09:00:00Z')",
        [mon],
      );
      await carry();
      expect(await shelves(), isEmpty);
      await carry();
      expect(await db.getAll('SELECT id FROM cooking_change'), hasLength(1));
    });
  });

  test('two phones offline — a tick, a correction and an untick on each — '
      'converge whatever order they upload in', () async {
    final (phoneB, dirB) = await openTestDb();
    addTearDown(() => closeTestDb(phoneB, dirB));
    await _household(phoneB);
    // The same plan on both, synced before going offline.
    final mon = await curry(0);
    final tue = await curry(1);
    for (final r in await db.getAll('SELECT * FROM week_plan')) {
      await _apply(phoneB, 'week_plan', r['id'] as String, {...r});
    }
    for (final r in await db.getAll('SELECT * FROM plan_entry')) {
      await _apply(phoneB, 'plan_entry', r['id'] as String, {...r});
    }
    await drainCrudQueue(db);
    await drainCrudQueue(phoneB);

    final planningB = SqlitePlanningRepository(
      phoneB,
      householdId: 'h',
      clock: () => _wednesday,
    );
    final repoB = SqliteLeftoverRepository(
      phoneB,
      householdId: 'h',
      clock: () => _wednesday,
    );
    // Phone A: Ada ticks Monday, sets the count to 2, unticks Tuesday's
    // mistaken tick.
    await tick(mon, 'a');
    await tick(tue, 'a');
    await repo.setLeftoverPortions((await shelves()).single, 2);
    await tick(tue, 'a', ate: false);
    // Phone B: Jun ticks Monday, sets the count to 1, and unticks Monday.
    await planningB.setMealEaten(
      mon,
      memberId: 'b',
      eatenAt: DateTime.utc(2026, 8, 24, 19),
    );
    await repoB.setLeftoverPortions(
      (await repoB.watchHouseholdLeftovers(today: _wednesday).first)
          .rows
          .single,
      1,
    );
    await planningB.setMealEaten(mon, memberId: 'b', eatenAt: null);

    final opsA = await queuedCrudOps(db);
    final opsB = await queuedCrudOps(phoneB);
    Future<List<(String, String, double)>> serverAfter(
      List<List<Map<String, dynamic>>> uploads,
    ) async {
      final (server, serverDir) = await openTestDb();
      addTearDown(() => closeTestDb(server, serverDir));
      await _household(server);
      for (final r in await db.getAll('SELECT * FROM week_plan')) {
        await _apply(server, 'week_plan', r['id'] as String, {...r});
      }
      for (final r in await db.getAll('SELECT * FROM plan_entry')) {
        await _apply(server, 'plan_entry', r['id'] as String, {
          ...r,
          'cooking': null,
        });
      }
      for (final ops in uploads) {
        for (final op in ops) {
          await _upload(server, op);
        }
      }
      final shelves = await SqliteLeftoverRepository(
        server,
        householdId: 'h',
        clock: () => _wednesday,
      ).watchHouseholdLeftovers(today: _wednesday).first;
      return [for (final r in shelves.rows) (r.id, r.place.name, r.box)];
    }

    final aFirst = await serverAfter([opsA, opsB]);
    final bFirst = await serverAfter([opsB, opsA]);
    expect(aFirst, bFirst);
    // One cooking under one id. Made 3½; Ada's Monday is out, Jun's untick
    // and Ada's Tuesday untick stand; A's +½ (1½ said 2) and B's −1¾ (2¾
    // said 1) both apply: 1¼.
    expect(aFirst, [(mon, 'fridge', 1.25)]);
  });

  group('what the third sim review found', () {
    /// Ragù, serves 4, keeps 3 days, freezes for 90.
    Future<void> ragu() => db.execute(
      'INSERT INTO recipe (id, household_id, title, servings_base, '
      'keeps_for_days, freezable, freezer_days, created_at, updated_at) '
      "VALUES ('ragu', 'h', 'Ragù', 4, 3, 1, 90, '2026-01-01', "
      "'2026-01-01')",
    );

    Future<String> plan(
      String recipe,
      int day, {
      DateTime? week,
      int? portions,
      String? cooking,
    }) => planning.addEntry(
      weekStart: week ?? _week,
      dayOfWeek: day,
      mealSlot: 'Dinner',
      recipeId: recipe,
      eaterIds: const ['a', 'b'],
      portions: portions,
      cooking: cooking,
    );

    Future<String?> linkOf(String entry) async =>
        (await db.get('SELECT cooking FROM plan_entry WHERE id = ?', [
              entry,
            ]))['cooking']
            as String?;

    test('a meal added beside a pot not cooked yet joins it: one cook, '
        'and its first tick links it', () async {
      await ragu();
      final nextWeek = DateTime(2026, 8, 31);
      // Saturday's ragù, picked for next Thursday: a cooking not cooked.
      final sat = await plan('ragu', 5, portions: 2);
      final thu = await plan(
        'ragu',
        3,
        week: nextWeek,
        portions: 2,
        cooking: sat,
      );
      expect(await linkOf(thu), sat);
      // Then Friday of the same week, planned plain.
      final fri = await plan('ragu', 4, portions: 2);
      expect(await linkOf(fri), isNull);

      // Cook: one pot, cooked Friday, covering Fri, Sat and next Thu.
      final cook = await loadCookPlan(db, '2026-08-24');
      final sessions = cook.recipes.single.mealSessions;
      expect(sessions, hasLength(1));
      expect(sessions.single.cookingId, sat);
      expect(sessions.single.coveredDays, [4, 5, 10]);
      expect(sessions.single.totalPortions, 6);

      // Leftovers: the pot cooks Friday, and Friday is no pot of its own.
      final shelves = await read();
      expect(shelves.pots, isEmpty);
      expect(shelves.rows.single.id, sat);
      expect(shelves.rows.single.since, DateTime(2026, 8, 28));
      expect(shelves.meals.keys, containsAll([fri, sat, thu]));

      // Friday's first tick links it and fixes what was made: all six.
      await tick(fri, 'a');
      expect(await linkOf(fri), sat);
      expect(await db.getAll('SELECT id FROM cooking'), hasLength(1));
      expect(
        (await db.get('SELECT made FROM cooking WHERE id = ?', [sat]))['made'],
        6,
      );
    });

    test(
      'after the first tick a meal added to the week is its own cook',
      () async {
        await ragu();
        final sat = await plan('ragu', 5, portions: 2);
        await tick(sat, 'a');
        final fri = await plan('ragu', 4, portions: 2);
        final cook = await loadCookPlan(db, '2026-08-24');
        expect(cook.recipes.single.mealSessions, hasLength(2));
        await tick(fri, 'a');
        expect(await linkOf(fri), isNot(sat));
      },
    );

    test('removing a meal someone ate keeps its leftovers, and Undo keeps '
        'them too', () async {
      // Monday's curry for two, both ate; Tuesday's cooked fresh instead.
      final mon = await plan('curry', 0, portions: 2);
      final tue = await plan('curry', 1, portions: 2);
      await tick(mon, 'a');
      await tick(mon, 'b');
      await planning.cookFreshInstead(tue);
      Future<double> left() async => (await shelves()).single.inBox;
      expect(await left(), 2);

      await planning.removeEntry(mon);
      expect(await left(), 2, reason: 'what was eaten was eaten');
      expect((await shelves()).single.since, DateTime(2026, 8, 24));

      await planning.restoreEntry(mon);
      expect(await left(), 2);
    });

    test('a whole batch is made, bought and left over: serves 4, planned '
        'for 2, both ate, 2 left', () async {
      await ragu();
      final wed = await plan('ragu', 2, portions: 2);
      await repo.setWholeBatch(wed, whole: true);
      final cook = await loadCookPlan(db, '2026-08-24');
      final session = cook.recipes.single.mealSessions.single;
      expect((session.wholeBatch, session.totalPortions), (true, 4.0));
      expect(session.scaleFactor, 1);

      await tick(wed, 'a');
      await tick(wed, 'b');
      final row = (await shelves(today: DateTime(2026, 8, 27))).single;
      expect(row.inBox, 2);

      // Back to the exact amount: one change row, soft-deleted.
      await repo.setWholeBatch(wed, whole: false);
      expect(await shelves(today: DateTime(2026, 8, 27)), isEmpty);
      final flags = await db.getAll('SELECT deleted_at FROM cooking_change');
      expect(flags, hasLength(1));
      expect(flags.single['deleted_at'], isNotNull);
    });
  });
}

/// A change row on [cookingId], as a phone's Freeze writes one.
Future<void> insertCookingChangeFor(
  PowerSyncDatabase db,
  String cookingId, {
  double fridge = 0,
  double freezer = 0,
}) => db.writeTransaction(
  (tx) => insertCookingChange(
    tx,
    householdId: 'h',
    cookingId: cookingId,
    fridge: fridge,
    freezer: freezer,
  ),
);

/// Writes [data] as the row [id] of [table]: an UPDATE when it is there, an
/// INSERT when not (local tables are views: no UPSERT).
Future<void> _apply(
  PowerSyncDatabase db,
  String table,
  String id,
  Map<String, Object?> data,
) async {
  final columns = [
    for (final k in data.keys)
      if (k != 'id') k,
  ];
  final exists = await db.getOptional('SELECT id FROM $table WHERE id = ?', [
    id,
  ]);
  if (exists != null) {
    if (columns.isEmpty) return;
    await db.execute(
      'UPDATE $table SET ${columns.map((c) => '$c = ?').join(', ')} '
      'WHERE id = ?',
      [for (final c in columns) _sqlValue(data[c]), id],
    );
  } else {
    await db.execute(
      'INSERT INTO $table (id, ${columns.join(', ')}) '
      'VALUES (?, ${List.filled(columns.length, '?').join(', ')})',
      [id, for (final c in columns) _sqlValue(data[c])],
    );
  }
}

Object? _sqlValue(Object? v) => v is List || v is Map ? jsonEncode(v) : v;

/// One queued op as the server takes it: a PUT of a table a phone only
/// births ([insertOnceTables]) leaves a row already there alone; any other
/// PUT writes the whole row; a PATCH writes its columns.
Future<void> _upload(PowerSyncDatabase server, Map<String, dynamic> op) async {
  final table = op['type'] as String;
  final id = op['id'] as String;
  final data = Map<String, Object?>.from(op['data'] as Map? ?? const {});
  switch (op['op']) {
    case 'PUT':
      final there = await server.getOptional(
        'SELECT id FROM $table WHERE id = ?',
        [id],
      );
      if (there != null && insertOnceTables.contains(table)) return;
      await _apply(server, table, id, data);
    case 'PATCH':
      await _apply(server, table, id, data);
  }
}
