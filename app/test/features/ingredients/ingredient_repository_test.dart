import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mise/features/ingredients/data/ingredient_repository_impl.dart';
import 'package:mise/features/ingredients/domain/ingredient.dart';
import 'package:mise/features/ingredients/domain/search_query.dart';
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
  String? deletedAt,
}) async {
  // match_text mirrors the server normalizer's character rules — the same
  // helper the repository normalizes queries with, so seed and query agree.
  await db.execute(
    'INSERT INTO ingredient (id, household_id, canonical_name, category, '
    'default_unit, status, source, match_text, deleted_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      id,
      'h',
      name,
      category,
      unit,
      status,
      'seed',
      normalizeSearchQuery(name),
      deletedAt,
    ],
  );
  for (final a in aliases) {
    await db.execute(
      'INSERT INTO ingredient_alias '
      '(id, ingredient_id, alias_text, match_text) '
      'VALUES (?, ?, ?, ?)',
      ['$id-${a.hashCode}', id, a, normalizeSearchQuery(a)],
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
    await _seed(db, id: '4', name: 'Extra Firm Tofu');
    await _seed(db, id: '5', name: 'All-Purpose Flour');
  });

  tearDown(() => closeTestDb(db, dir));

  test('empty query returns the head, alphabetical', () async {
    final all = await repo.search('');
    expect(all.map((i) => i.canonicalName), [
      'All-Purpose Flour',
      'Extra Firm Tofu',
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

  test('matches on any word boundary, not just the leading word', () async {
    // "tofu" must find "Extra Firm Tofu" — a strict prefix never could.
    final r = await repo.search('tofu');
    expect(r.map((i) => i.canonicalName), contains('Extra Firm Tofu'));
    // Word-boundary only: "nion" is not a word start of "Onion".
    expect(await repo.search('nion'), isEmpty);
  });

  test('normalizes the query like match_text ("all-purpose" hits)', () async {
    final r = await repo.search('all-purpose');
    expect(r.map((i) => i.canonicalName), contains('All-Purpose Flour'));
    // And the un-hyphenated spelling hits the same row.
    final r2 = await repo.search('all purpose');
    expect(r2.map((i) => i.canonicalName), contains('All-Purpose Flour'));
  });

  test('a LIKE wildcard in the query is stripped, not a pattern', () async {
    // If '_' leaked through as a single-char wildcard, 'on_on' would match
    // "onion"; normalization strips it to 'onon' → no hits. (A bare '%'
    // normalizes to the empty query and just browses the head.)
    expect(await repo.search('on_on'), isEmpty);
  });

  test('tombstoned vocab is not searchable or listable', () async {
    await _seed(
      db,
      id: '9',
      name: 'Onion Powder',
      deletedAt: '2026-01-01T00:00:00Z',
    );
    final hits = await repo.search('onion');
    expect(hits.map((i) => i.canonicalName), isNot(contains('Onion Powder')));
    final all = await repo.search('');
    expect(all.map((i) => i.canonicalName), isNot(contains('Onion Powder')));
  });

  test('maps status and category', () async {
    final oil = (await repo.search('olive')).single;
    expect(oil.status, IngredientStatus.stub);
    final onion = (await repo.search('onion')).first;
    expect(onion.category, 'vegetables');
  });
}
