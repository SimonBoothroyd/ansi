/// A meal from last week's pot reads the variant of the week that cooked it,
/// in every reader of a meal's figures: the Week, Health and Ask, over a real
/// PowerSync database.
library;

import 'dart:io';

import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/account/data/household_providers.dart';
import 'package:ansi/features/ask/domain/ask_tool_runner.dart';
import 'package:ansi/features/ask/presentation/ask_figures_wiring.dart';
import 'package:ansi/features/health/presentation/health_sync.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/data/planning_repository_impl.dart';
import 'package:ansi/features/planning/data/week_variant_repository_impl.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/week_view_models.dart';
import 'package:ansi/features/planning/presentation/week_widgets.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/data/recipe_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/leftover_rows.dart';
import '../../helpers/test_db.dart';

final _cookWeek = DateTime.utc(2026, 8, 24);
final _eatWeek = DateTime.utc(2026, 8, 31);
const _eatKey = '2026-08-31';

/// The dish as written, and with its optional cream ticked in.
const _plain = 100.0;
const _withCream = 400.0;

/// A one-serving curry: 100 g of rice, and 100 g of optional cream.
Future<void> _seed(PowerSyncDatabase db) async {
  const at = '2026-01-01';
  await db.execute(
    'INSERT INTO household_member (id, household_id, display_name, '
    'sort_order, portion_factor, created_at, updated_at) '
    "VALUES ('a', 'h', 'Ada', 0, 1, ?, ?)",
    [at, at],
  );
  await db.execute(
    'INSERT INTO recipe (id, household_id, title, servings_base, '
    'keeps_for_days, freezable, freezer_days, created_at, updated_at) '
    "VALUES ('curry', 'h', 'Curry', 1, 3, 1, 30, ?, ?)",
    [at, at],
  );
  await db.execute(
    'INSERT INTO ingredient_group (id, household_id, recipe_id, sort_order, '
    "created_at, updated_at) VALUES ('g', 'h', 'curry', 0, ?, ?)",
    [at, at],
  );
  for (final (id, name, kcal, optional) in [
    ('rice', 'Rice', 100, 0),
    ('cream', 'Cream', 300, 1),
  ]) {
    await db.execute(
      'INSERT INTO ingredient (id, household_id, canonical_name, '
      'default_unit, match_text, macros, macros_basis, status, created_at, '
      "updated_at) VALUES (?, 'h', ?, 'g', ?, ?, 'per_g', 'complete', ?, ?)",
      [id, name, id, '{"kcal":$kcal,"protein":1,"carb":1,"fat":1}', at, at],
    );
    await db.execute(
      'INSERT INTO recipe_line_item (id, household_id, group_id, '
      'ingredient_id, quantity, unit, optional, sort_order, created_at, '
      "updated_at) VALUES (?, 'h', 'g', ?, 100, 'g', ?, 0, ?, ?)",
      ['li-$id', id, optional, at, at],
    );
  }
}

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqlitePlanningRepository planning;
  late SqliteWeekVariantRepository variants;
  late ProviderContainer container;

  setUp(() async {
    (db, dir) = await openTestDb();
    await _seed(db);
    planning = SqlitePlanningRepository(db, householdId: 'h');
    variants = SqliteWeekVariantRepository(db, householdId: 'h');
    container = ProviderContainer(
      overrides: [
        weekShapeProvider.overrideWithValue(WeekShape.monday),
        planningRepositoryProvider.overrideWithValue(planning),
        weekVariantRepositoryProvider.overrideWithValue(variants),
        recipeRepositoryProvider.overrideWithValue(
          SqliteRecipeRepository(db, householdId: 'h'),
        ),
      ],
    );
    container.read(viewedWeekStartProvider.notifier).set(_eatWeek);
  });

  tearDown(() async {
    container.dispose();
    await closeTestDb(db, dir);
  });

  Future<String> meal(DateTime week, int day, {String? cooking}) =>
      planning.addEntry(
        weekStart: week,
        dayOfWeek: day,
        mealSlot: 'Dinner',
        recipeId: 'curry',
        eaterIds: const ['a'],
        cooking: cooking,
      );

  Future<void> cream(DateTime week) =>
      variants.setLineIncluded(week, 'curry', 'li-cream', included: true);

  /// What [value] reads once it stops moving off [expected], or at the end of
  /// the wait: the streams land one by one.
  Future<T?> settled<T>(T? Function() value, T expected) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (value() != expected && DateTime.now().isBefore(deadline)) {
      await pumpEventQueue();
    }
    return value();
  }

  /// The eat week's whole total, as the Week band reads it.
  Future<double?> weekKcal(double expected) async {
    final sub = container.listen(weekMacrosProvider(null), (_, _) {});
    // The recipe's own figure stands in while the variants load, so a total
    // is only read once they have.
    final own = container.listen(variantRecipeMacrosProvider, (_, _) {});
    expect(await settled(() => own.read().hasValue, true), isTrue);
    return settled(() => sub.read().total?.kcal, expected);
  }

  test('the Week counts a leftover as the week that cooked it', () async {
    final sat = await meal(_cookWeek, 5);
    await meal(_eatWeek, 3, cooking: sat);
    await cream(_cookWeek);
    expect(await weekKcal(_withCream), _withCream);
  });

  test(
    'a fresh cook beside a leftover of the same dish keeps its own',
    () async {
      final sat = await meal(_cookWeek, 5);
      await meal(_eatWeek, 1, cooking: sat);
      await meal(_eatWeek, 6);
      await cream(_cookWeek);
      expect(await weekKcal(_withCream + _plain), _withCream + _plain);
    },
  );

  test('this week’s change never reaches last week’s pot', () async {
    final sat = await meal(_cookWeek, 5);
    await meal(_eatWeek, 1, cooking: sat);
    await meal(_eatWeek, 6);
    await cream(_eatWeek);
    expect(await weekKcal(_plain + _withCream), _plain + _withCream);
  });

  test('food said by hand reads as the recipe is written', () async {
    await insertCooking(
      db,
      id: 'hand',
      recipeId: 'curry',
      made: 2,
      place: 'fridge',
      since: '2026-08-30',
    );
    await meal(_eatWeek, 1, cooking: 'hand');
    await cream(_eatWeek);
    expect(await weekKcal(_plain), _plain);
  });

  test('Health sends what was in the pot', () async {
    final sat = await meal(_cookWeek, 5);
    final thu = await meal(_eatWeek, 3, cooking: sat);
    await cream(_cookWeek);
    final entries = (await planning.watchWeek(_eatWeek).first)!.entries;
    final entry = entries.singleWhere((e) => e.id == thu);
    final sub = container.listen(healthWeekMacrosProvider(_eatKey), (_, _) {});
    expect(
      await settled(() => sub.read()?.of(entry)?.perServing?.kcal, _withCream),
      _withCream,
    );
  });

  test('Ask answers the week as the Week does', () async {
    final sat = await meal(_cookWeek, 5);
    await meal(_eatWeek, 3, cooking: sat);
    await cream(_cookWeek);
    final answer = await askNutrition(
      container,
      AskPlanFigures(weekStart: _eatWeek, forWhom: 'everyone'),
    );
    expect(answer, contains('400'));
  });

  test('the recipe page opens on the cooking’s week, and a week that only '
      'eats the dish offers no switch', () async {
    final sat = await meal(_cookWeek, 5);
    await meal(_eatWeek, 3, cooking: sat);
    final entry = (await planning.watchWeek(_eatWeek).first)!.entries.single;
    expect(
      mealTitleRoute(entry, weekKey: _eatKey),
      '/recipes/curry?week=2026-08-24',
    );
    expect(variantDaysOf([entry], 'curry'), isEmpty);

    final plan = container.listen(weekPlanForProvider(_eatKey), (_, _) {});
    await settled(() => plan.read().hasValue, true);
    expect(
      container.read(weekRecipePlacementProvider('curry', _eatKey)).days,
      isEmpty,
    );
  });
}
