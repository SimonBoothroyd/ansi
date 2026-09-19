/// The week variant over a REAL PowerSync database — the local tables are
/// SQLite views, so a save that reached for `ON CONFLICT` would fail here the
/// way it fails on a phone.
library;

import 'dart:async';
import 'dart:io';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/planning/data/week_variant_repository_impl.dart';
import 'package:ansi/features/planning/domain/week_variant_repository.dart';
import 'package:ansi/features/recipes/data/recipe_repository_impl.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

final _thisWeek = DateTime.utc(2026, 9, 14);
final _nextWeek = DateTime.utc(2026, 9, 21);

String get _now => DateTime.now().toUtc().toIso8601String();

Future<void> _insertWeek(PowerSyncDatabase db, String id, String key) =>
    db.execute(
      'INSERT INTO week_plan (id, household_id, week_start_date, created_at, '
      'updated_at) VALUES (?, ?, ?, ?, ?)',
      [id, 'h', key, _now, _now],
    );

Future<void> _insertRecipe(
  PowerSyncDatabase db,
  String id,
  String title, {
  double servings = 4,
}) => db.execute(
  'INSERT INTO recipe (id, household_id, title, servings_base, created_at, '
  'updated_at) VALUES (?, ?, ?, ?, ?, ?)',
  [id, 'h', title, servings, _now, _now],
);

Future<void> _insertIngredient(
  PowerSyncDatabase db,
  String id,
  String name, {
  String? macros,
}) => db.execute(
  'INSERT INTO ingredient (id, household_id, canonical_name, default_unit, '
  'match_text, macros, macros_basis, status, created_at, updated_at) '
  "VALUES (?, ?, ?, 'g', ?, ?, 'per_g', ?, ?, ?)",
  [
    id,
    'h',
    name,
    name.toLowerCase(),
    macros,
    if (macros == null) 'stub' else 'complete',
    _now,
    _now,
  ],
);

/// Coins one of [recipeId]'s own words — *a [label] is [amount] [unit]*
/// (ADR-0018). The ONE place this file states what a measure IS.
Future<void> _insertMeasure(
  PowerSyncDatabase db,
  String recipeId, {
  String id = 'm-blob',
  String label = 'blob',
  double amount = 0.05,
  Unit unit = cup,
}) => db.execute(
  'INSERT INTO recipe_measure (id, household_id, recipe_id, label, amount, '
  'unit, sort_order, created_at, updated_at) '
  'VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)',
  [id, 'h', recipeId, label, amount, unit.id, _now, _now],
);

Future<void> _insertGroup(PowerSyncDatabase db, String id, String recipeId) =>
    db.execute(
      'INSERT INTO ingredient_group (id, household_id, recipe_id, sort_order, '
      'created_at, updated_at) VALUES (?, ?, ?, 0, ?, ?)',
      [id, 'h', recipeId, _now, _now],
    );

Future<void> _insertLine(
  PowerSyncDatabase db,
  String id,
  String groupId,
  String ingredientId, {
  double quantity = 100,
  String unit = 'g',
  bool optional = false,
  int sortOrder = 0,
}) => db.execute(
  'INSERT INTO recipe_line_item (id, household_id, group_id, ingredient_id, '
  'quantity, unit, optional, sort_order, created_at, updated_at) '
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
  [
    id,
    'h',
    groupId,
    ingredientId,
    quantity,
    unit,
    if (optional) 1 else 0,
    sortOrder,
    _now,
    _now,
  ],
);

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteWeekVariantRepository repo;

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqliteWeekVariantRepository(db, householdId: 'h');
    await _insertWeek(db, 'wp-1', '2026-09-14');
    await _insertWeek(db, 'wp-2', '2026-09-21');
    await _insertRecipe(db, 'r1', 'Slow-Cooker Beef Ragù');
    await _insertRecipe(db, 'r2', 'Weeknight Chicken Curry');
    await _insertIngredient(
      db,
      'i-sausage',
      'Pork sausage',
      macros: '{"kcal":300,"protein":14,"carb":2,"fat":26}',
    );
    await _insertIngredient(
      db,
      'i-mince',
      'Beef mince',
      macros: '{"kcal":137,"protein":21,"carb":0,"fat":5}',
    );
    await _insertGroup(db, 'g1', 'r1');
    await _insertLine(db, 'l1', 'g1', 'i-sausage', quantity: 400);
    await _insertLine(db, 'l2', 'g1', 'i-mince', quantity: 500, sortOrder: 1);
  });

  tearDown(() => closeTestDb(db, dir));

  group('one tap ticks a line in for the week', () {
    Future<List<LineOverride>> set() => repo.loadOverrides(_thisWeek, 'r1');

    test('an include row appears for the line, and nothing else', () async {
      await repo.setLineIncluded(_thisWeek, 'r1', 'l2', included: true);
      final stored = set();
      expect((await stored).single.action, LineOverrideAction.include);
      expect((await stored).single.recipeLineItemId, 'l2');
      expect(await repo.loadOverrides(_nextWeek, 'r1'), isEmpty);
    });

    test('asking twice is one row, and the same row', () async {
      await repo.setLineIncluded(_thisWeek, 'r1', 'l2', included: true);
      final first = (await set()).single.id;
      await repo.setLineIncluded(_thisWeek, 'r1', 'l2', included: true);
      expect((await set()).single.id, first);
      final live = await db.get(
        'SELECT COUNT(*) AS n FROM week_recipe_line_override '
        "WHERE recipe_id = 'r1' AND deleted_at IS NULL",
      );
      expect(live['n'], 1);
    });

    test(
      'taking it back out drops the row — and asking twice is quiet',
      () async {
        await repo.setLineIncluded(_thisWeek, 'r1', 'l2', included: true);
        await repo.setLineIncluded(_thisWeek, 'r1', 'l2', included: false);
        expect(await set(), isEmpty);
        await repo.setLineIncluded(_thisWeek, 'r1', 'l2', included: false);
        expect(await set(), isEmpty);
      },
    );

    test('it composes with what the week already says', () async {
      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.exclude,
            recipeLineItemId: 'l1',
          ),
        ],
      );
      await repo.setLineIncluded(_thisWeek, 'r1', 'l2', included: true);
      final stored = await set();
      expect(stored, hasLength(2));
      expect(
        stored.firstWhere((o) => o.recipeLineItemId == 'l1').action,
        LineOverrideAction.exclude,
      );
      expect(
        stored.firstWhere((o) => o.recipeLineItemId == 'l2').action,
        LineOverrideAction.include,
      );
    });

    test('the same tap on a line the week left out puts it back', () async {
      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.exclude,
            recipeLineItemId: 'l2',
          ),
        ],
      );
      await repo.setLineIncluded(_thisWeek, 'r1', 'l2', included: true);
      expect((await set()).single.action, LineOverrideAction.include);
    });

    test(
      'a line the week states its own amount for keeps that amount',
      () async {
        await repo.saveOverrides(
          _thisWeek,
          'r1',
          overrides: const [
            LineOverride(
              action: LineOverrideAction.replace,
              recipeLineItemId: 'l1',
              ingredientId: 'i-mince',
              quantity: 400,
              unit: g,
            ),
          ],
        );
        await repo.setLineIncluded(_thisWeek, 'r1', 'l1', included: true);
        final stored = (await set()).single;
        expect(stored.action, LineOverrideAction.replace);
        expect(stored.quantity, 400);
      },
    );
  });

  group('the set is written whole', () {
    test('nothing stored means no variant at all', () async {
      expect(await repo.loadOverrides(_thisWeek, 'r1'), isEmpty);
      expect(await repo.watchWeekOverrides(_thisWeek).first, isEmpty);
    });

    test('a set saves and reads back by week and recipe', () async {
      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.replace,
            recipeLineItemId: 'l1',
            ingredientId: 'i-mince',
            quantity: 400,
            unit: g,
            note: 'browned',
          ),
          LineOverride(
            action: LineOverrideAction.exclude,
            recipeLineItemId: 'l2',
          ),
        ],
      );

      final set = await repo.loadOverrides(_thisWeek, 'r1');
      expect(set, hasLength(2));
      final replace = set.firstWhere(
        (o) => o.action == LineOverrideAction.replace,
      );
      expect(replace.recipeLineItemId, 'l1');
      expect(replace.ingredientId, 'i-mince');
      // The name comes off the live vocab row, not off the stored delta.
      expect(replace.ingredientName, 'Beef mince');
      expect(replace.quantity, 400);
      expect(replace.unit, g);
      expect(replace.note, 'browned');
      expect(replace.id, isNotEmpty);
    });

    test(
      're-saving keeps one row per line rather than racing tombstones',
      () async {
        await repo.saveOverrides(
          _thisWeek,
          'r1',
          overrides: const [
            LineOverride(
              action: LineOverrideAction.replace,
              recipeLineItemId: 'l1',
              ingredientId: 'i-mince',
              quantity: 400,
              unit: g,
            ),
          ],
        );
        final first = (await repo.loadOverrides(_thisWeek, 'r1')).single.id;

        await repo.saveOverrides(
          _thisWeek,
          'r1',
          overrides: const [
            LineOverride(
              action: LineOverrideAction.replace,
              recipeLineItemId: 'l1',
              ingredientId: 'i-mince',
              quantity: 600,
              unit: g,
            ),
          ],
        );
        final second = (await repo.loadOverrides(_thisWeek, 'r1')).single;
        expect(second.id, first);
        expect(second.quantity, 600);

        final live = await db.get(
          'SELECT COUNT(*) AS n FROM week_recipe_line_override '
          "WHERE recipe_id = 'r1' AND deleted_at IS NULL",
        );
        expect(live['n'], 1);
      },
    );

    test('an empty set is back to the recipe — every row tombstoned', () async {
      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.exclude,
            recipeLineItemId: 'l2',
          ),
        ],
      );
      await repo.saveOverrides(_thisWeek, 'r1', overrides: const []);
      expect(await repo.loadOverrides(_thisWeek, 'r1'), isEmpty);
      final row = await db.get(
        'SELECT deleted_at FROM week_recipe_line_override '
        "WHERE recipe_line_item_id = 'l2'",
      );
      expect(row['deleted_at'], isNotNull);
    });

    test('an added line keeps the id it was drafted with', () async {
      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            id: 'ov-basil',
            action: LineOverrideAction.add,
            ingredientId: 'i-mince',
            quantity: 1,
            unit: pieces,
            sortOrder: 0,
          ),
        ],
      );
      var set = await repo.loadOverrides(_thisWeek, 'r1');
      expect(set.single.id, 'ov-basil');

      // Re-saving the same addition updates it in place.
      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            id: 'ov-basil',
            action: LineOverrideAction.add,
            ingredientId: 'i-mince',
            quantity: 2,
            unit: pieces,
            sortOrder: 0,
          ),
        ],
      );
      set = await repo.loadOverrides(_thisWeek, 'r1');
      expect(set, hasLength(1));
      expect(set.single.quantity, 2);
    });

    test('the week plan is created lazily by the first change', () async {
      final unplanned = DateTime.utc(2026, 10, 5);
      await repo.saveOverrides(
        unplanned,
        'r1',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.exclude,
            recipeLineItemId: 'l2',
          ),
        ],
      );
      final row = await db.get(
        "SELECT id FROM week_plan WHERE week_start_date = '2026-10-05'",
      );
      expect(row['id'], isNotNull);
      expect(await repo.loadOverrides(unplanned, 'r1'), hasLength(1));
    });
  });

  group('a variant never leaks', () {
    test('into another week', () async {
      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.exclude,
            recipeLineItemId: 'l2',
          ),
        ],
      );
      expect(await repo.loadOverrides(_nextWeek, 'r1'), isEmpty);
      expect(await repo.watchWeekOverrides(_nextWeek).first, isEmpty);
    });

    test('into another recipe', () async {
      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.exclude,
            recipeLineItemId: 'l2',
          ),
        ],
      );
      final byRecipe = await repo.watchWeekOverrides(_thisWeek).first;
      expect(byRecipe.keys, ['r1']);
      expect(await repo.loadOverrides(_thisWeek, 'r2'), isEmpty);
    });

    test("and saving one recipe leaves another recipe's set alone", () async {
      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.exclude,
            recipeLineItemId: 'l2',
          ),
        ],
      );
      await repo.saveOverrides(_thisWeek, 'r2', overrides: const []);
      expect(await repo.loadOverrides(_thisWeek, 'r1'), hasLength(1));
    });
  });

  group("the week's own macro summaries", () {
    /// The Library's per-recipe figure — what the week keeps borrowing for
    /// every recipe it does not vary.
    Future<Macros?> libraryFigure() async {
      final summaries = await SqliteRecipeRepository(
        db,
        householdId: 'h',
      ).watchRecipes().first;
      return summaries.firstWhere((s) => s.id == 'r1').macros?.perServing;
    }

    test(
      'a recipe with no variant is absent — the Library figure stands',
      () async {
        expect(await repo.watchVariantRecipeMacros(_thisWeek).first, isEmpty);
      },
    );

    test(
      "an exclusion moves this week's figure, and no other week's",
      () async {
        final library = await libraryFigure();
        expect(library, isNotNull);

        await repo.saveOverrides(
          _thisWeek,
          'r1',
          overrides: const [
            LineOverride(
              action: LineOverrideAction.exclude,
              recipeLineItemId: 'l2',
            ),
          ],
        );
        final varied = await repo.watchVariantRecipeMacros(_thisWeek).first;
        expect(varied.keys, ['r1']);
        expect(varied['r1']!.perServing, isNot(library));
        // And the Library's own figure has not moved: the recipe is untouched.
        expect(await libraryFigure(), library);
        expect(await repo.watchVariantRecipeMacros(_nextWeek).first, isEmpty);
      },
    );
  });

  /// This week's amount for a component line, said in the target's own word.
  /// No screen on this build writes one; the week must round-trip every one it
  /// reads, and refuse the shapes the server would refuse.
  group("this week's amount, in the recipe's own word", () {
    setUp(() async {
      await _insertRecipe(db, 'aioli', 'Romesco Aioli');
      await _insertMeasure(db, 'aioli');
      // The line the delta is about: `¼ cup` of the aioli, on r1.
      await db.execute(
        'INSERT INTO recipe_line_item (id, household_id, group_id, '
        'sub_recipe_id, quantity, unit, sort_order, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        ['l3', 'h', 'g1', 'aioli', 0.25, 'cup', 2, _now, _now],
      );
    });

    test('round-trips the pointer with unit NULL, on the INSERT and again on '
        'the UPDATE', () async {
      const measured = LineOverride(
        action: LineOverrideAction.replace,
        recipeLineItemId: 'l3',
        subRecipeId: 'aioli',
        quantity: 3,
        recipeMeasureId: 'm-blob',
      );
      await repo.saveOverrides(_thisWeek, 'r1', overrides: const [measured]);

      var stored = (await repo.loadOverrides(_thisWeek, 'r1')).single;
      expect(stored.recipeMeasureId, 'm-blob');
      expect(stored.quantity, 3);
      expect(stored.unit, isNull, reason: 'the word IS the denomination');
      var row = await db.get(
        'SELECT unit, recipe_measure_id FROM week_recipe_line_override '
        'WHERE deleted_at IS NULL',
      );
      expect(row['unit'], isNull);
      expect(row['recipe_measure_id'], 'm-blob');

      // The same delta saved again takes the UPDATE branch — the one the
      // column was missing from — and must still carry the word.
      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: [measured.copyWith(quantity: 5)],
      );
      stored = (await repo.loadOverrides(_thisWeek, 'r1')).single;
      expect(stored.recipeMeasureId, 'm-blob');
      expect(stored.quantity, 5);
      row = await db.get(
        'SELECT unit, recipe_measure_id FROM week_recipe_line_override '
        'WHERE deleted_at IS NULL',
      );
      expect(row['unit'], isNull);
      expect(row['recipe_measure_id'], 'm-blob');
    });

    test(
      'a word with no number is refused before anything is written',
      () async {
        await expectLater(
          repo.saveOverrides(
            _thisWeek,
            'r1',
            overrides: const [
              LineOverride(
                id: 'wro-bad',
                action: LineOverrideAction.replace,
                recipeLineItemId: 'l3',
                subRecipeId: 'aioli',
                recipeMeasureId: 'm-blob',
              ),
            ],
          ),
          throwsA(isA<WordlessOverrideError>()),
        );
        expect(await repo.loadOverrides(_thisWeek, 'r1'), isEmpty);
      },
    );

    test(
      'a word on a delta about an INGREDIENT is dropped, not stored',
      () async {
        await repo.saveOverrides(
          _thisWeek,
          'r1',
          overrides: const [
            LineOverride(
              action: LineOverrideAction.replace,
              recipeLineItemId: 'l1',
              ingredientId: 'i-sausage',
              quantity: 3,
              unit: g,
              recipeMeasureId: 'm-blob',
            ),
          ],
        );
        final stored = (await repo.loadOverrides(_thisWeek, 'r1')).single;
        expect(stored.recipeMeasureId, isNull);
        expect(stored.unit, g, reason: 'the unit is what is honest here');
      },
    );

    test('the week watch re-fires when the word is re-stated', () async {
      await repo.saveOverrides(
        _thisWeek,
        'r1',
        overrides: const [
          LineOverride(
            action: LineOverrideAction.replace,
            recipeLineItemId: 'l3',
            subRecipeId: 'aioli',
            quantity: 3,
            recipeMeasureId: 'm-blob',
          ),
        ],
      );
      final stream = StreamIterator(repo.watchWeekOverrides(_thisWeek));
      addTearDown(stream.cancel);
      expect(await stream.moveNext(), isTrue);
      expect(stream.current['r1'], hasLength(1));

      await db.execute('UPDATE recipe_measure SET amount = ? WHERE id = ?', [
        1 / 24,
        'm-blob',
      ]);
      // The re-statement moves nothing about the STORED delta — an amount here
      // is absolute — but the stream must fire, because what the delta comes
      // to has changed for every surface reading it.
      expect(await stream.moveNext(), isTrue);
      expect(stream.current['r1']!.single.quantity, 3);
    });
  });
}
