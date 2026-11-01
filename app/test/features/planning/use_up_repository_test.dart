import 'dart:io';

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/planning/data/planning_repository_impl.dart';
import 'package:ansi/features/planning/data/use_up_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

/// Last week (Monday 24 August) and the week being planned after it.
final _last = DateTime.utc(2026, 8, 24);
final _next = DateTime.utc(2026, 8, 31);

/// The Sunday the household plans on: every day of last week is behind it.
final _sunday = DateTime(2026, 8, 30);

const _stamp = '2026-08-20T10:00:00Z';

Future<void> _ingredient(
  PowerSyncDatabase db,
  String id,
  String category, {
  String unit = 'g',
  double? pieceWeight,
}) => db.execute(
  'INSERT INTO ingredient (id, household_id, canonical_name, category, '
  'default_unit, piece_basis_amount, status, source, match_text, macros_basis, '
  'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
  [
    id,
    'h',
    id,
    category,
    unit,
    pieceWeight,
    'complete',
    'seed',
    id,
    'g',
    _stamp,
    _stamp,
  ],
);

Future<void> _recipe(
  PowerSyncDatabase db,
  String id, {
  required List<(String, double, Unit)> lines,
}) async {
  await db.execute(
    'INSERT INTO recipe (id, household_id, title, servings_base, '
    'keeps_for_days, freezable, created_at, updated_at) '
    'VALUES (?, ?, ?, 2, 4, 0, ?, ?)',
    [id, 'h', id, _stamp, _stamp],
  );
  await db.execute(
    'INSERT INTO ingredient_group (id, household_id, recipe_id, sort_order, '
    'created_at, updated_at) VALUES (?, ?, ?, 0, ?, ?)',
    ['$id-g', 'h', id, _stamp, _stamp],
  );
  for (final (i, (ingredient, qty, unit)) in lines.indexed) {
    await db.execute(
      'INSERT INTO recipe_line_item (id, household_id, group_id, '
      'ingredient_id, quantity, unit, sort_order, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      ['$id-$i', 'h', '$id-g', ingredient, qty, unit.id, i, _stamp, _stamp],
    );
  }
}

/// A receipt on [day] for [grams] of [ingredient] in one pack, at [cents].
Future<void> _receipt(
  PowerSyncDatabase db,
  String ingredient, {
  required DateTime day,
  required double grams,
  required int cents,
}) async {
  final stamp = DateTime.utc(
    day.year,
    day.month,
    day.day,
    10,
  ).toIso8601String();
  await db.execute(
    'INSERT INTO receipt (id, household_id, store, purchased_at, source, '
    'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
    ['rc-$ingredient', 'h', 'Aldi', stamp, 'photo', stamp, stamp],
  );
  await db.execute(
    'INSERT INTO receipt_line (id, household_id, receipt_id, ingredient_id, '
    'cents, discount_cents, kind, pack_basis_amount, count, sort_order, '
    'created_at, updated_at) VALUES (?, ?, ?, ?, ?, 0, ?, ?, 1, 0, ?, ?)',
    [
      'rl-$ingredient',
      'h',
      'rc-$ingredient',
      ingredient,
      cents,
      'item',
      grams,
      stamp,
      stamp,
    ],
  );
}

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqlitePlanningRepository planning;
  late SqliteUseUpRepository repo;

  setUp(() async {
    (db, dir) = await openTestDb();
    planning = SqlitePlanningRepository(db, householdId: 'h');
    repo = SqliteUseUpRepository(db, householdId: 'h');
    await db.execute(
      'INSERT INTO household_member (id, household_id, display_name, '
      'sort_order, portion_factor, created_at, updated_at) VALUES '
      "('a', 'h', 'Ada', 0, 1, '$_stamp', '$_stamp'), "
      "('b', 'h', 'Jun', 1, 1, '$_stamp', '$_stamp')",
    );
    await _ingredient(db, 'spinach', 'produce');
    await _ingredient(db, 'onion', 'produce', unit: 'piece', pieceWeight: 150);
    await _ingredient(db, 'tofu', 'proteins');
    await _ingredient(db, 'rice', 'grains');
    // The pie was cooked on Monday; the ragù, planned for Friday, never was.
    await _recipe(
      db,
      'pie',
      lines: [('spinach', 200, g), ('onion', 0.5, pieces), ('rice', 100, g)],
    );
    await _recipe(db, 'ragu', lines: [('tofu', 300, g)]);
    final pie = await planning.addEntry(
      weekStart: _last,
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'pie',
      eaterIds: const ['a', 'b'],
    );
    await planning.setMealEaten(
      pie,
      memberId: 'a',
      eatenAt: DateTime.utc(2026, 8, 24, 19),
    );
    await planning.addEntry(
      weekStart: _last,
      dayOfWeek: 4,
      mealSlot: 'Dinner',
      recipeId: 'ragu',
      eaterIds: const ['a', 'b'],
    );
    // Spinach came in a 500 g bag.
    await _receipt(
      db,
      'spinach',
      day: DateTime(2026, 8, 24),
      grams: 500,
      cents: 350,
    );
  });

  tearDown(() => closeTestDb(db, dir));

  test('last week leaves its pack surplus, its rounding and its uncooked '
      'batch, fresh food only', () async {
    final facts = await repo.lastWeekFor(_next, today: _sunday);
    final spare = {for (final s in facts.spare) s.ingredientId: s};
    expect(spare.keys.toSet(), {'spinach', 'onion', 'tofu'});
    // A 500 g bag for 200 g, priced off the receipt at 0.7c a gram.
    expect(spare['spinach']!.amount, closeTo(300, 1e-9));
    expect(spare['spinach']!.bought, closeTo(500, 1e-9));
    expect(spare['spinach']!.centsPerUnit, closeTo(0.7, 1e-9));
    // Half an onion needed, a whole one bought.
    expect(spare['onion']!.amount, closeTo(75, 1e-9));
    // The ragù was never cooked: all its tofu is spare.
    expect(spare['tofu']!.amount, closeTo(300, 1e-9));
  });

  test('a batch with days still to come is not spare yet', () async {
    // On Thursday the ragù is still to be cooked.
    final facts = await repo.lastWeekFor(
      _last.add(const Duration(days: 7)),
      today: DateTime(2026, 8, 27),
    );
    expect(facts.spare.map((s) => s.ingredientId), isNot(contains('tofu')));
  });

  test('every recipe says what one batch uses, in grams', () async {
    final facts = await repo.lastWeekFor(_next, today: _sunday);
    final pie = facts.recipes.singleWhere((r) => r.recipeId == 'pie');
    expect(pie.servingsBase, 2);
    expect(pie.perBatch, {'spinach': 200, 'onion': 75, 'rice': 100});
  });
}
