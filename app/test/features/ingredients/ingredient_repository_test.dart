import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mise/features/ingredients/data/ingredient_repository_impl.dart';
import 'package:mise/features/ingredients/domain/ingredient.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

Future<void> _seed(
  PowerSyncDatabase db, {
  required String id,
  required String name,
  String? category,
  String unit = 'g',
  String status = 'complete',
  List<String> aliases = const [],
}) async {
  await db.execute(
    'INSERT INTO ingredient (id, household_id, canonical_name, category, '
    'default_unit, status, source, match_text) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [id, 'h', name, category, unit, status, 'seed', name.toLowerCase()],
  );
  for (final a in aliases) {
    await db.execute(
      'INSERT INTO ingredient_alias '
      '(id, ingredient_id, alias_text, match_text) '
      'VALUES (?, ?, ?, ?)',
      ['$id-${a.hashCode}', id, a, a.toLowerCase()],
    );
  }
}

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteIngredientRepository repo;

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqliteIngredientRepository(db);
    await _seed(db, id: '1', name: 'Onion', category: 'vegetables');
    await _seed(
      db,
      id: '2',
      name: 'Spring Onion',
      aliases: ['scallion', 'green onion'],
    );
    await _seed(db, id: '3', name: 'Olive Oil', status: 'stub');
  });

  tearDown(() => closeTestDb(db, dir));

  test('empty query returns the head, alphabetical', () async {
    final all = await repo.search('');
    expect(all.map((i) => i.canonicalName), [
      'Olive Oil',
      'Onion',
      'Spring Onion',
    ]);
  });

  test('prefix matches the ingredient name', () async {
    final r = await repo.search('oni');
    expect(r.map((i) => i.canonicalName), contains('Onion'));
    expect(r.map((i) => i.canonicalName), isNot(contains('Olive Oil')));
  });

  test('matches an alias (scallion → Spring Onion)', () async {
    final r = await repo.search('scall');
    expect(r.single.canonicalName, 'Spring Onion');
  });

  test('exact name is ranked first', () async {
    final r = await repo.search('onion');
    expect(r.first.canonicalName, 'Onion'); // exact beats "Spring Onion"
  });

  test('maps status and category', () async {
    final oil = (await repo.search('olive')).single;
    expect(oil.status, IngredientStatus.stub);
    final onion = (await repo.search('onion')).first;
    expect(onion.category, 'vegetables');
  });
}
