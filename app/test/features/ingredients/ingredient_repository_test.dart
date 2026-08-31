import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mise/core/units/macros.dart';
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
    repo = SqliteIngredientRepository(db, householdId: 'h');
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
    await _seed(db, id: '6', name: 'Canned Whole Tomatoes');
    await _seed(db, id: '7', name: 'Chicken thigh');
    await _seed(db, id: '8', name: 'Coconut milk, canned');
  });

  tearDown(() => closeTestDb(db, dir));

  test('empty query returns the head, alphabetical', () async {
    final all = await repo.search('');
    expect(all.map((i) => i.canonicalName), [
      'All-Purpose Flour',
      'Canned Whole Tomatoes',
      'Chicken thigh',
      'Coconut milk, canned',
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

  group('token-subset search (order-independent, extra words fine)', () {
    test('"canned tomatoes" finds "Canned Whole Tomatoes"', () async {
      final r = await repo.search('canned tomatoes');
      expect(
        r.map((i) => i.canonicalName),
        contains('Canned Whole Tomatoes'),
      );
    });

    test('"coconut milk" finds "Coconut milk, canned"', () async {
      final r = await repo.search('coconut milk');
      expect(r.map((i) => i.canonicalName), contains('Coconut milk, canned'));
    });

    test('word order does not matter', () async {
      final r = await repo.search('tomatoes canned');
      expect(
        r.map((i) => i.canonicalName),
        contains('Canned Whole Tomatoes'),
      );
    });

    test('every token must be present — a missing token excludes the row',
        () async {
      // "canned" alone hits both canned rows; adding "beans" (present in
      // neither) must drop them.
      expect(await repo.search('canned beans'), isEmpty);
    });

    test('a mistyped token in a multi-word query still finds it (fuzzy '
        'fallback)', () async {
      final r = await repo.search('chikn thigh');
      expect(r.map((i) => i.canonicalName), contains('Chicken thigh'));
    });

    test('a single mistyped word does NOT fuzzy-hit (strict word boundary)',
        () async {
      // The fuzzy fallback needs the corroboration of a second token.
      expect(await repo.search('chikn'), isEmpty);
    });
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

  test('byId resolves a live row and refuses a tombstoned one', () async {
    final onion = await repo.byId('1');
    expect(onion?.canonicalName, 'Onion');
    expect(await repo.byId('nope'), isNull);

    await _seed(
      db,
      id: '9',
      name: 'Onion Powder',
      deletedAt: '2026-01-01T00:00:00Z',
    );
    expect(await repo.byId('9'), isNull);
  });

  test('maps status and category', () async {
    final oil = (await repo.search('olive')).single;
    expect(oil.status, IngredientStatus.stub);
    final onion = (await repo.search('onion')).first;
    expect(onion.category, 'vegetables');
  });

  test('maps macros with their stored basis (0011)', () async {
    await db.execute(
      "UPDATE ingredient SET macros = ?, macros_basis = 'ml' WHERE id = '1'",
      ['{"kcal":40,"protein":1,"carb":9,"fat":0}'],
    );
    final onion = (await repo.search('onion')).first;
    expect(onion.macros, isNotNull);
    expect(onion.macros!.kcal, 40);
    expect(onion.macrosBasis, MacrosBasis.perMl);
  });

  test('counts distinct live measure labels for the row hint (7.7)', () async {
    for (final (mid, label, deleted) in [
      ('m1', 'onion, medium', null),
      ('m2', 'onion, large', null),
      ('m3', 'onion, medium', null), // offline dupe — merges to one chip
      ('m4', 'retired', '2026-01-02'),
    ]) {
      await db.execute(
        'INSERT INTO ingredient_measure '
        '(id, household_id, ingredient_id, label, basis_amount, deleted_at) '
        'VALUES (?, ?, ?, ?, 100, ?)',
        [mid, 'h', '1', label, deleted],
      );
    }
    final onion = (await repo.search('onion')).first;
    expect(onion.measureCount, 2);
  });

  test('the measure-count hint excludes volume-named labels', () async {
    // The chip row refuses labels that merely name a volume unit (density
    // owns volume conversion), so the "N measures" hint must not count what
    // the picker will never offer — plural/case disguises included.
    for (final (mid, label) in [
      ('m1', 'onion, medium'),
      ('m2', 'cup'),
      ('m3', ' Cups '),
      ('m4', 'tbsp'),
    ]) {
      await db.execute(
        'INSERT INTO ingredient_measure '
        '(id, household_id, ingredient_id, label, basis_amount) '
        'VALUES (?, ?, ?, ?, 100)',
        [mid, 'h', '1', label],
      );
    }
    final onion = (await repo.search('onion')).first;
    expect(onion.measureCount, 1);
  });

  test('recentlyUsed surfaces line-item and top-up ingredients, newest '
      'first', () async {
    // Onion used in a recipe line (older), Tofu topped up manually (newer).
    await db.execute(
      'INSERT INTO recipe_line_item (id, household_id, group_id, '
      "ingredient_id, unit, created_at) VALUES ('li1', 'h', 'g1', '1', 'g', "
      "'2026-01-01')",
    );
    await db.execute(
      'INSERT INTO shopping_list_entry (id, household_id, ingredient_id) '
      "VALUES ('e1', 'h', '2')",
    );
    await db.execute(
      'INSERT INTO shopping_list_contribution (id, household_id, entry_id, '
      "source_type, quantity, unit, created_at) VALUES ('c1', 'h', 'e1', "
      "'manual', 1, 'g', '2026-01-02')",
    );

    final recent = await repo.recentlyUsed();
    expect(recent.map((i) => i.id).toList(), ['2', '1']);
  });

  test('recentlyUsed is empty when nothing was ever used', () async {
    expect(await repo.recentlyUsed(), isEmpty);
  });

  test('recentlyUsed ignores tombstoned shopping entries', () async {
    // The contribution is live but its ENTRY was soft-deleted (e.g. a
    // cleared item): the reference must not keep the ingredient recent.
    await db.execute(
      'INSERT INTO shopping_list_entry (id, household_id, ingredient_id, '
      "deleted_at) VALUES ('e-dead', 'h', '2', '2026-01-03')",
    );
    await db.execute(
      'INSERT INTO shopping_list_contribution (id, household_id, entry_id, '
      "source_type, quantity, unit, created_at) VALUES ('c1', 'h', 'e-dead', "
      "'manual', 1, 'g', '2026-01-02')",
    );

    expect(await repo.recentlyUsed(), isEmpty);
  });

  test('createStub writes a findable manual stub (7.7 add-new)', () async {
    final created = await repo.createStub('  Curry Leaves ');
    expect(created.canonicalName, 'Curry Leaves');
    expect(created.status, IngredientStatus.stub);

    final found = (await repo.search('curry')).single;
    expect(found.id, created.id);
    expect(found.status, IngredientStatus.stub);
    final row = await db.get(
      'SELECT household_id, source, match_text, status FROM ingredient '
      'WHERE id = ?',
      [created.id],
    );
    expect(row['household_id'], 'h');
    expect(row['source'], 'manual');
    expect(row['match_text'], 'curry leaves');
    expect(row['status'], 'stub');
  });

  group('setDensity (ADR-0008: the single volume⇄mass fact)', () {
    test(
      'writes the density and extends allowed_units in the same write',
      () async {
        // A tsp-default per-g row on the derived fallback (no explicit list):
        // the write materializes the defaults AND appends the density leg.
        await db.execute(
          "UPDATE ingredient SET default_unit = 'tsp' WHERE id = '1'",
        );
        final updated = await repo.setDensity('1', 0.7);
        expect(updated, isNotNull);
        expect(updated!.densityGPerMl, 0.7);
        expect(updated.allowedUnits, isNotNull);
        // The yeast shape (tsp/tbsp/g) plus nothing else — the ml the density
        // could unlock for a MASS-default row doesn't apply to a volume
        // default beyond g (already the basis base).
        expect(updated.allowedUnits!.map((u) => u.id).toSet(), {
          'tsp',
          'tbsp',
          'g',
        });

        final row = await db.get(
          'SELECT density_g_per_ml, allowed_units FROM ingredient '
          "WHERE id = '1'",
        );
        expect((row['density_g_per_ml'] as num).toDouble(), 0.7);
        expect(row['allowed_units'], isNotNull);
      },
    );

    test('a mass-default row gains the kitchen volume workhorses', () async {
      final updated = await repo.setDensity('1', 0.7); // default_unit 'g'
      expect(updated!.allowedUnits!.map((u) => u.id).toSet(), {
        'g',
        'kg',
        'tsp',
        'tbsp',
        'cup',
        'ml',
      });
    });

    test('an existing explicit list is extended, never replaced', () async {
      await db.execute(
        "UPDATE ingredient SET allowed_units = '[\"g\", \"to_taste\"]' "
        "WHERE id = '1'",
      );
      final updated = await repo.setDensity('1', 1.1);
      // The user's curated entries survive; only the unlock is unioned in.
      expect(updated!.allowedUnits!.map((u) => u.id).toSet(), {
        'g',
        'to_taste',
        'tsp',
        'tbsp',
        'cup',
        'ml',
      });
    });

    test('refuses a dishonest density', () async {
      for (final bad in [0.0, -1.0, double.nan]) {
        await expectLater(
          repo.setDensity('1', bad),
          throwsArgumentError,
          reason: '$bad',
        );
      }
    });

    test('null for an unknown id', () async {
      expect(await repo.setDensity('nope', 1), isNull);
    });
  });
}
