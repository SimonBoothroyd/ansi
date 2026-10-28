import 'dart:io';

import 'package:ansi/core/sync/dropped_write.dart';
import 'package:ansi/shared/dropped_write_subject.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../helpers/test_db.dart';

DroppedWrite _drop(String table, String rowId, {String op = 'PATCH'}) =>
    DroppedWrite(
      table: table,
      op: op,
      rowId: rowId,
      code: '42501',
      message: 'permission denied',
      at: DateTime(2026, 10, 28, 14, 2),
    );

void main() {
  late PowerSyncDatabase db;
  late Directory dir;

  setUp(() async {
    (db, dir) = await openTestDb();
  });

  tearDown(() => closeTestDb(db, dir));

  Future<DroppedWriteSubject> describe(String table, String id) =>
      describeDroppedWrite(db, _drop(table, id));

  Future<void> insert(String table, Map<String, Object?> row) => db.execute(
    'INSERT INTO $table (${row.keys.join(', ')}) '
    'VALUES (${List.filled(row.length, '?').join(', ')})',
    row.values.toList(),
  );

  group('a recipe', () {
    setUp(() async {
      await insert('recipe', {'id': 'r1', 'title': 'Weeknight Chicken Curry'});
      await insert('ingredient_group', {'id': 'g1', 'recipe_id': 'r1'});
      await insert('recipe_line_item', {'id': 'l1', 'group_id': 'g1'});
      await insert('recipe_measure', {'id': 'm1', 'recipe_id': 'r1'});
    });

    test('is named by its title and opens its page', () async {
      expect(
        await describe('recipe', 'r1'),
        const DroppedWriteSubject(
          name: 'Weeknight Chicken Curry',
          kind: 'recipe edit',
          route: '/recipes/r1',
        ),
      );
    });

    test('a line, a group or a measure is its recipe', () async {
      for (final (table, id) in [
        ('recipe_line_item', 'l1'),
        ('ingredient_group', 'g1'),
        ('recipe_measure', 'm1'),
      ]) {
        final subject = await describe(table, id);
        expect(subject.name, 'Weeknight Chicken Curry', reason: table);
        expect(subject.route, '/recipes/r1', reason: table);
        expect(subject.kind, 'recipe edit', reason: table);
      }
    });

    test('once deleted keeps its name and opens nothing', () async {
      await db.execute('UPDATE recipe SET deleted_at = ? WHERE id = ?', [
        '2026-10-28T14:02:00Z',
        'r1',
      ]);
      final subject = await describe('recipe', 'r1');
      expect(subject.name, 'Weeknight Chicken Curry');
      expect(subject.route, isNull);
    });

    test('a this-week edit opens the recipe in its week', () async {
      await insert('week_plan', {'id': 'w1', 'week_start_date': '2026-11-02'});
      await insert('week_recipe_line_override', {
        'id': 'o1',
        'week_plan_id': 'w1',
        'recipe_id': 'r1',
      });
      expect(
        await describe('week_recipe_line_override', 'o1'),
        const DroppedWriteSubject(
          name: 'Weeknight Chicken Curry',
          kind: 'this-week edit',
          route: '/recipes/r1?week=2026-11-02',
        ),
      );
    });
  });

  group('a meal', () {
    setUp(() async {
      await insert('recipe', {'id': 'r1', 'title': 'Weeknight Chicken Curry'});
      // A Sunday-first week: offset 2 is the Tuesday.
      await insert('week_plan', {'id': 'w1', 'week_start_date': '2026-11-01'});
      await insert('plan_entry', {
        'id': 'p1',
        'week_plan_id': 'w1',
        'day_of_week': 2,
        'meal_slot': 'Dinner',
        'recipe_id': 'r1',
      });
      await insert('plan_entry', {
        'id': 'p2',
        'week_plan_id': 'w1',
        'day_of_week': 0,
        'meal_slot': '',
        'label': 'Pizza out',
      });
    });

    test('is named by its day, counted from its own week, and slot', () async {
      expect(
        await describe('plan_entry', 'p1'),
        const DroppedWriteSubject(
          name: 'Tuesday dinner',
          kind: 'meal change',
          route: '/week?week=2026-11-01&day=2026-11-03',
        ),
      );
    });

    test('with no slot is named by its day and what it is', () async {
      final subject = await describe('plan_entry', 'p2');
      expect(subject.name, 'Sunday · Pizza out');
      expect(subject.route, '/week?week=2026-11-01&day=2026-11-01');
    });

    test('an eaten mark or a leftovers answer is its meal', () async {
      await insert('meal_eaten', {'id': 'e1', 'plan_entry_id': 'p1'});
      await insert('batch_leftover', {'id': 'b1', 'plan_entry_id': 'p1'});
      final eaten = await describe('meal_eaten', 'e1');
      expect(eaten.name, 'Tuesday dinner');
      expect(eaten.kind, 'meal eaten');
      final leftover = await describe('batch_leftover', 'b1');
      expect(leftover.name, 'Tuesday dinner');
      expect(leftover.kind, 'leftovers');
    });

    test('a week is named by its first day', () async {
      expect(
        await describe('week_plan', 'w1'),
        const DroppedWriteSubject(
          name: 'Week of 1 Nov',
          kind: 'week change',
          route: '/week?week=2026-11-01',
        ),
      );
    });
  });

  test('a shopping item opens its week’s list', () async {
    await insert('ingredient', {'id': 'i1', 'canonical_name': 'Onion'});
    await insert('shopping_list_entry', {
      'id': 's1',
      'ingredient_id': 'i1',
      'week_start_date': '2026-11-02',
    });
    await insert('shopping_list_entry', {'id': 's2', 'free_text': 'Foil'});
    await insert('shopping_list_contribution', {'id': 'c1', 'entry_id': 's1'});

    expect(
      await describe('shopping_list_contribution', 'c1'),
      const DroppedWriteSubject(
        name: 'Onion',
        kind: 'shopping list change',
        route: '/shop?week=2026-11-02',
      ),
    );
    final foil = await describe('shopping_list_entry', 's2');
    expect(foil.name, 'Foil');
    expect(foil.route, '/shop');
  });

  test(
    'an ingredient, its alias and its measure open the ingredient',
    () async {
      await insert('ingredient', {'id': 'i1', 'canonical_name': 'Onion'});
      await insert('ingredient_alias', {'id': 'a1', 'ingredient_id': 'i1'});
      await insert('ingredient_measure', {'id': 'm1', 'ingredient_id': 'i1'});
      for (final (table, id) in [
        ('ingredient', 'i1'),
        ('ingredient_alias', 'a1'),
        ('ingredient_measure', 'm1'),
      ]) {
        expect(
          await describe(table, id),
          const DroppedWriteSubject(
            name: 'Onion',
            kind: 'ingredient edit',
            route: '/ingredients/i1',
          ),
          reason: table,
        );
      }
    },
  );

  test('a book section opens its book; a receipt line its receipt', () async {
    await insert('book', {'id': 'b1', 'name': 'Our Cookbook'});
    await insert('book_section', {'id': 'bs1', 'book_id': 'b1'});
    await insert('receipt', {'id': 'rc1', 'store': 'Trader Joe’s'});
    await insert('receipt_line', {'id': 'rl1', 'receipt_id': 'rc1'});

    expect(
      await describe('book_section', 'bs1'),
      const DroppedWriteSubject(
        name: 'Our Cookbook',
        kind: 'book change',
        route: '/books/b1',
      ),
    );
    expect(
      await describe('receipt_line', 'rl1'),
      const DroppedWriteSubject(
        name: 'Trader Joe’s',
        kind: 'receipt edit',
        route: '/receipts/rc1',
      ),
    );
  });

  test('a household member opens the account page', () async {
    await insert('household_member', {'id': 'hm1', 'display_name': 'Sam'});
    expect(
      await describe('household_member', 'hm1'),
      const DroppedWriteSubject(
        name: 'Sam',
        kind: 'portion change',
        route: '/account',
      ),
    );
  });

  group('a row that cannot be found', () {
    test('falls back to its kind’s plain noun, opening nothing', () async {
      expect(
        await describe('recipe', 'gone'),
        const DroppedWriteSubject(name: 'A recipe', kind: 'recipe edit'),
      );
      expect(
        await describe('plan_entry', 'gone'),
        const DroppedWriteSubject(name: 'A meal', kind: 'meal change'),
      );
      expect(
        await describe('recipe_line_item', 'gone'),
        const DroppedWriteSubject(name: 'A recipe', kind: 'recipe edit'),
      );
    });

    test('in a table the lookup does not know is "A change"', () async {
      expect(
        await describe('cook_session', 'x'),
        const DroppedWriteSubject(name: 'A change', kind: 'change'),
      );
    });

    test('a read that throws is a row that cannot be found', () async {
      await db.close();
      expect(
        await describe('recipe', 'r1'),
        const DroppedWriteSubject(name: 'A recipe', kind: 'recipe edit'),
      );
      // Reopened so the tear-down's close has something to close.
      dir.deleteSync(recursive: true);
      (db, dir) = await openTestDb();
    });
  });
}
