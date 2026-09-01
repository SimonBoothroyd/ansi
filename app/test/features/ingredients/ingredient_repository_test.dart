import 'dart:convert';
import 'dart:io';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/ingredient_repository_impl.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/ingredients/domain/search_query.dart';
import 'package:flutter_test/flutter_test.dart';
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
      expect(r.map((i) => i.canonicalName), contains('Canned Whole Tomatoes'));
    });

    test('"coconut milk" finds "Coconut milk, canned"', () async {
      final r = await repo.search('coconut milk');
      expect(r.map((i) => i.canonicalName), contains('Coconut milk, canned'));
    });

    test('word order does not matter', () async {
      final r = await repo.search('tomatoes canned');
      expect(r.map((i) => i.canonicalName), contains('Canned Whole Tomatoes'));
    });

    test(
      'every token must be present — a missing token excludes the row',
      () async {
        // "canned" alone hits both canned rows; adding "beans" (present in
        // neither) must drop them.
        expect(await repo.search('canned beans'), isEmpty);
      },
    );

    test('a mistyped token in a multi-word query still finds it (fuzzy '
        'fallback)', () async {
      final r = await repo.search('chikn thigh');
      expect(r.map((i) => i.canonicalName), contains('Chicken thigh'));
    });

    test(
      'a single mistyped word does NOT fuzzy-hit (strict word boundary)',
      () async {
        // The fuzzy fallback needs the corroboration of a second token.
        expect(await repo.search('chikn'), isEmpty);
      },
    );
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

  test('byIds loads a whole set in one query, skipping the dead', () async {
    // The import review validates every line's unit against its ingredient;
    // doing that one `byId` at a time was a DB round-trip per line per edit.
    await _seed(
      db,
      id: '9',
      name: 'Onion Powder',
      deletedAt: '2026-01-01T00:00:00Z',
    );
    final byIds = await repo.byIds({'1', '2', '9', 'nope'});
    expect(byIds.keys, containsAll(<String>['1', '2']));
    expect(byIds['1']!.canonicalName, 'Onion');
    expect(byIds.containsKey('9'), isFalse); // tombstoned
    expect(byIds.containsKey('nope'), isFalse);
    expect(await repo.byIds(const {}), isEmpty);
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
    // The SERVER's phrase rules, not just the character ones (plan 0020 D6):
    // singularized, so this is byte-identical to the `match_text` an import
    // would have written for the same phrase — which is the whole point.
    expect(row['match_text'], 'curry leaf');
    expect(row['status'], 'stub');
    // A bare create carries no panel — a NULL column, not four zeros.
    expect(row['macros'], isNull);
  });

  test(
    "createStub carries a barcode draft's provenance and panel (D1)",
    () async {
      final created = await repo.createStub(
        'Coconut milk, canned',
        source: 'off:5000159407236',
        macros: const Macros(kcal: 197, protein: 2, carb: 3, fat: 20),
        macrosBasis: MacrosBasis.perMl,
      );
      final row = await db.get(
        'SELECT source, macros, macros_basis, status, density_g_per_ml '
        'FROM ingredient WHERE id = ?',
        [created.id],
      );
      // The `source` column gets the draft's own `off:<barcode>` value…
      expect(row['source'], 'off:5000159407236');
      // …the panel is stored in the basis the label read it in (7.7)…
      expect(Macros.tryParse(row['macros'] as String?)?.kcal, 197);
      expect(row['macros_basis'], 'ml');
      // …and none of it completes the row, or invents a density OFF never had.
      expect(row['status'], 'stub');
      expect(row['density_g_per_ml'], isNull);
    },
  );

  test('createStub with no panel writes no macros at all', () async {
    final created = await repo.createStub(
      'NESQUIK Cacao',
      source: 'off:3033710065967',
    );
    final row = await db.get(
      'SELECT source, macros FROM ingredient WHERE id = ?',
      [created.id],
    );
    expect(row['source'], 'off:3033710065967');
    expect(row['macros'], isNull);
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

  group('clearDensity (D4b: the one leg where the admission list shrinks)', () {
    test('the density goes and the cross-family units go with it, in one '
        'write — the basis family stays', () async {
      // A piece-default per-g row: the mango shape, where the volume chips
      // exist only because of the number being deleted.
      await db.execute(
        "UPDATE ingredient SET default_unit = 'piece' WHERE id = '1'",
      );
      await repo.setDensity('1', 0.66);

      final cleared = await repo.clearDensity('1');
      expect(cleared, isNotNull);
      expect(cleared!.densityGPerMl, isNull);
      expect(cleared.allowedUnits!.map((u) => u.id).toSet(), {'piece', 'g'});

      // One write, not a read-then-patch: the row on disk agrees.
      final row = await db.get(
        "SELECT density_g_per_ml, allowed_units FROM ingredient WHERE id = '1'",
      );
      expect(row['density_g_per_ml'], isNull);
      expect((jsonDecode(row['allowed_units'] as String) as List).toSet(), {
        'piece',
        'g',
      });
    });

    test(
      'a curated unit the density never unlocked survives the strip',
      () async {
        await db.execute(
          "UPDATE ingredient SET default_unit = 'piece' WHERE id = '1'",
        );
        await repo.setDensity('1', 0.66);
        await db.execute(
          'UPDATE ingredient SET allowed_units = ? WHERE id = ?',
          [
            jsonEncode(['piece', 'g', 'cup', 'ml', 'to_taste']),
            '1',
          ],
        );
        final cleared = await repo.clearDensity('1');
        expect(cleared!.allowedUnits!.map((u) => u.id).toSet(), {
          'piece',
          'g',
          'to_taste',
        });
      },
    );

    test('THE FLOUR SHAPE under D4c: the density gives the volume family and '
        'takes it back — the row’s own default unit included', () async {
      await db.execute(
        "UPDATE ingredient SET default_unit = 'cup' WHERE id = '5'",
      );
      final withDensity = await repo.setDensity('5', 0.59);
      // Before D4c the union added `g` (already admitted) and left `cup` —
      // the row's OWN default — unadmitted. It now lands the whole family.
      expect(
        withDensity!.allowedUnits!.map((u) => u.id).toSet(),
        containsAll(<String>['cup', 'tbsp', 'ml', 'l']),
      );
      final cleared = await repo.clearDensity('5');
      expect(cleared!.densityGPerMl, isNull);
      // Mass is its basis family and survives. The volume side goes, default
      // unit and all — which is the state the form flags with a one-tap fix
      // rather than rewriting the default behind the user's back.
      expect(cleared.allowedUnits!.map((u) => u.id).toSet(), {'g', 'kg'});
    });

    test(
      'a no-op on a row that never had one, null for an unknown id',
      () async {
        final same = await repo.clearDensity('1');
        expect(same!.densityGPerMl, isNull);
        expect(await repo.clearDensity('nope'), isNull);
      },
    );
  });

  group('applyUsdaProbe (D7b: the local half of the enrichment)', () {
    test('fills a bare stub and extends allowed_units with what the density '
        'unlocks — the same event, the same rule as setDensity', () async {
      // id '3' is the seeded stub, default_unit 'g'.
      final applied = await repo.applyUsdaProbe(
        '3',
        source: 'usda_fdc:11216',
        densityGPerMl: 0.35,
        macros: const Macros(kcal: 108, protein: 6, carb: 19, fat: 1),
      );
      expect(applied, isNotNull);
      expect(applied!.densityGPerMl, 0.35);
      expect(applied.macros!.kcal, 108);
      expect(applied.source, 'usda_fdc:11216');
      // Still a stub: confirming is a human act (D5).
      expect(applied.status, IngredientStatus.stub);
      expect(applied.allowedUnits!.map((u) => u.id).toSet(), {
        'g',
        'kg',
        'tsp',
        'tbsp',
        'cup',
        'ml',
      });
    });

    test('REFUSES a row that already has numbers — the guard is re-checked '
        'here, not just by the caller', () async {
      await repo.setDensity('3', 0.9);
      expect(
        await repo.applyUsdaProbe('3', source: 'usda_fdc:1', densityGPerMl: 2),
        isNull,
      );
      expect((await repo.byId('3'))!.densityGPerMl, 0.9);
      expect((await repo.byId('3'))!.source, 'seed');
    });

    test('refuses a complete row, and an unknown id', () async {
      // id '1' (Onion) is complete.
      expect(
        await repo.applyUsdaProbe('1', source: 'usda_fdc:1', densityGPerMl: 1),
        isNull,
      );
      expect(
        await repo.applyUsdaProbe(
          'nope',
          source: 'usda_fdc:1',
          densityGPerMl: 1,
        ),
        isNull,
      );
    });

    test('a candidate with nothing to copy writes nothing — the source is '
        'not churned for a name match', () async {
      expect(await repo.applyUsdaProbe('3', source: 'usda_fdc:1'), isNull);
      expect((await repo.byId('3'))!.source, 'seed');
    });

    test('macros without a density leave the allowed list alone', () async {
      final applied = await repo.applyUsdaProbe(
        '3',
        source: 'usda_fdc:2',
        macros: const Macros(kcal: 1, protein: 2, carb: 3, fat: 4),
      );
      expect(applied!.macros!.kcal, 1);
      expect(applied.densityGPerMl, isNull);
      // Nothing unlocked, because nothing bridged: the row had no explicit
      // list and still has none.
      expect(applied.allowedUnits, isNull);
    });
  });

  // --- The manager's write half (step 8.5, plan 0020) ------------------------

  group('watchVocabulary / watchStubCount', () {
    test(
      'the whole live vocabulary, name-ordered, with measure counts',
      () async {
        final rows = await repo.watchVocabulary().first;
        expect(rows.length, 8);
        expect(rows.first.canonicalName, 'All-Purpose Flour');
        expect(rows.map((r) => r.canonicalName), isNot(contains('Ghost')));
      },
    );

    test(
      'a tombstoned row is out of both the list and the stub count',
      () async {
        await _seed(
          db,
          id: '99',
          name: 'Ghost',
          status: 'stub',
          deletedAt: '2026-01-01',
        );
        expect((await repo.watchVocabulary().first).length, 8);
        expect(await repo.watchStubCount().first, 1); // only Olive Oil
      },
    );
  });

  group('watchCategories (F3: the vocabulary IS the category list)', () {
    test(
      'distinct, trimmed, alphabetical — blanks are not a category',
      () async {
        await _seed(db, id: '10', name: 'Leek', category: 'vegetables');
        await _seed(db, id: '11', name: 'Basil', category: ' herbs ');
        await _seed(db, id: '12', name: 'Salt', category: '');
        await _seed(db, id: '13', name: 'Sugar');

        expect(await repo.watchCategories().first, ['herbs', 'vegetables']);
      },
    );

    test('a tombstoned row stops contributing its category', () async {
      await _seed(
        db,
        id: '10',
        name: 'Ghost pepper',
        category: 'chillies',
        deletedAt: '2026-01-01',
      );
      expect(await repo.watchCategories().first, ['vegetables']);
    });
  });

  group('saveEdit', () {
    test('a RENAME rewrites match_text with the server phrase rules — the '
        'hazard plan 0020 D6 names', () async {
      final saved = await repo.saveEdit('1', _edit(name: 'Curry leaves'));
      expect(saved!.canonicalName, 'Curry leaves');
      final row = await db.get(
        "SELECT canonical_name, match_text FROM ingredient WHERE id = '1'",
      );
      expect(row['canonical_name'], 'Curry leaves');
      // Singularized, exactly as an import's own write would have been —
      // leaving 'onion' behind would be a silent matching regression.
      expect(row['match_text'], 'curry leaf');
      // …and the row is findable by the new name, not the old one.
      expect((await repo.search('curry')).single.id, '1');
      expect(await repo.search('onion'), isNot(contains('1')));
    });

    test('writes the explicit allowed_units list verbatim — an editor that '
        'recomputed it would silently discard a curated set', () async {
      final saved = await repo.saveEdit(
        '1',
        _edit(name: 'Onion', allowed: {pieces, g, toTaste}),
      );
      expect(saved!.allowedUnits!.map((u) => u.id).toSet(), {
        'piece',
        'g',
        'to_taste',
      });
      final row = await db.get(
        "SELECT allowed_units FROM ingredient WHERE id = '1'",
      );
      expect((jsonDecode(row['allowed_units'] as String) as List).toSet(), {
        'piece',
        'g',
        'to_taste',
      });
    });

    test(
      'macros round-trip with their basis, unconverted (7.7/0011)',
      () async {
        final saved = await repo.saveEdit(
          '1',
          _edit(
            name: 'Coconut milk',
            macros: const Macros(kcal: 197, protein: 2, carb: 3, fat: 20),
            basis: MacrosBasis.perMl,
          ),
        );
        expect(
          saved!.macros,
          const Macros(kcal: 197, protein: 2, carb: 3, fat: 20),
        );
        expect(saved.macrosBasis, MacrosBasis.perMl);
      },
    );

    test('clearing the macros of a COMPLETE row returns it to stub — a row is '
        'never left asserting a number it no longer has (D5)', () async {
      await db.execute(
        "UPDATE ingredient SET status = 'complete', "
        'macros = \'{"kcal":1,"protein":1,"carb":1,"fat":1}\' '
        "WHERE id = '1'",
      );
      final saved = await repo.saveEdit('1', _edit(name: 'Onion'));
      expect(saved!.status, IngredientStatus.stub);
      expect(saved.macros, isNull);
    });

    test(
      'filling the macros in does NOT promote — confirming is a human act',
      () async {
        final saved = await repo.saveEdit(
          '1',
          _edit(
            name: 'Onion',
            macros: const Macros(kcal: 40, protein: 1, carb: 9, fat: 0),
          ),
        );
        expect(saved!.status, IngredientStatus.complete); // it started complete
        final stub = await repo.saveEdit(
          '3', // Olive Oil, seeded as a stub
          _edit(
            name: 'Olive Oil',
            macros: const Macros(kcal: 884, protein: 0, carb: 0, fat: 100),
          ),
        );
        expect(stub!.status, IngredientStatus.stub);
      },
    );

    test('refuses a blank name and null for an unknown id', () async {
      await expectLater(
        repo.saveEdit('1', _edit(name: '   ')),
        throwsArgumentError,
      );
      expect(await repo.saveEdit('nope', _edit(name: 'x')), isNull);
    });
  });

  group('confirm / unconfirm (D5: macros gate, density does not)', () {
    test('a stub with macros but NO density confirms', () async {
      await repo.saveEdit(
        '3',
        _edit(
          name: 'Olive Oil',
          macros: const Macros(kcal: 884, protein: 0, carb: 0, fat: 100),
        ),
      );
      final confirmed = await repo.confirmStub('3');
      expect(confirmed!.status, IngredientStatus.complete);
      expect(confirmed.densityGPerMl, isNull);
      expect(await repo.watchStubCount().first, 0);
    });

    test(
      'a stub with a density but no macros is REFUSED — the gate is macros',
      () async {
        await repo.setDensity('3', 0.91);
        await expectLater(repo.confirmStub('3'), throwsStateError);
        expect((await repo.byId('3'))!.status, IngredientStatus.stub);
      },
    );

    test('confirm is reversible', () async {
      await repo.saveEdit(
        '3',
        _edit(
          name: 'Olive Oil',
          macros: const Macros(kcal: 884, protein: 0, carb: 0, fat: 100),
        ),
      );
      await repo.confirmStub('3');
      final back = await repo.unconfirm('3');
      expect(back!.status, IngredientStatus.stub);
      // The macros stay — unconfirming stops it counting, it doesn't erase
      // what someone typed.
      expect(back.macros, isNotNull);
      expect(await repo.confirmStub('3'), isNotNull);
    });

    test('null for an unknown id', () async {
      expect(await repo.confirmStub('nope'), isNull);
      expect(await repo.unconfirm('nope'), isNull);
    });
  });

  group(
    'softDelete (the signed rule: refuse while a live line points here)',
    () {
      Future<void> line(String recipe, String group, String ingredient) async {
        await db.execute(
          'INSERT INTO recipe (id, household_id, title) VALUES (?, ?, ?)',
          [recipe, 'h', 'A recipe'],
        );
        await db.execute(
          'INSERT INTO ingredient_group (id, household_id, recipe_id) '
          'VALUES (?, ?, ?)',
          [group, 'h', recipe],
        );
        await db.execute(
          'INSERT INTO recipe_line_item (id, household_id, group_id, '
          'ingredient_id, quantity, unit) VALUES (?, ?, ?, ?, 1, ?)',
          ['line-$group', 'h', group, ingredient, 'g'],
        );
      }

      test(
        'an unreferenced row tombstones, and takes its aliases with it',
        () async {
          await repo.addAlias('1', 'yellow onion');
          expect(await repo.softDelete('1'), isA<Deleted>());
          expect(await repo.byId('1'), isNull);
          expect(await repo.aliases('1'), isEmpty);
          final row = await db.get(
            "SELECT deleted_at FROM ingredient WHERE id = '1'",
          );
          expect(
            row['deleted_at'],
            isNotNull,
          ); // a tombstone, not a hard delete
        },
      );

      test(
        'a referenced row is refused, with the counts the screen shows',
        () async {
          await line('r1', 'g1', '1');
          await line('r2', 'g2', '1');
          final outcome = await repo.softDelete('1');
          expect(outcome, isA<DeleteRefused>());
          expect((outcome as DeleteRefused).recipeCount, 2);
          expect(outcome.lineCount, 2);
          expect(await repo.byId('1'), isNotNull); // still there, untouched
        },
      );

      test(
        'a line in a tombstoned recipe does not hold the ingredient hostage',
        () async {
          await line('r1', 'g1', '1');
          await db.execute(
            "UPDATE recipe SET deleted_at = '2026-01-01' WHERE id = 'r1'",
          );
          expect(await repo.recipeReferences('1'), (
            recipeCount: 0,
            lineCount: 0,
          ));
          expect(await repo.softDelete('1'), isA<Deleted>());
        },
      );

      test(
        'deleting what is already gone says so rather than pretending',
        () async {
          expect(await repo.softDelete('nope'), isA<DeleteMissing>());
        },
      );
    },
  );

  group('aliases', () {
    test(
      'an alias is stored with the server-rule match_text and is findable',
      () async {
        final alias = await repo.addAlias('1', 'Yellow Onions');
        expect(alias.text, 'Yellow Onions');
        expect(alias.source, 'manual');
        final row = await db.get(
          'SELECT match_text, household_id FROM ingredient_alias WHERE id = ?',
          [alias.id],
        );
        expect(
          row['match_text'],
          'yellow onion',
        ); // singularized, as the server
        expect(row['household_id'], 'h');
        expect((await repo.search('yellow')).single.id, '1');
      },
    );

    test(
      'adding the same alias twice is a no-op, not a duplicate row',
      () async {
        final first = await repo.addAlias('1', 'Yellow Onions');
        final second = await repo.addAlias('1', 'yellow onion');
        expect(second.id, first.id);
        expect(await repo.aliases('1'), hasLength(1));
      },
    );

    test(
      'refuses an alias with no identity word — it would match everything',
      () async {
        await expectLater(
          repo.addAlias('1', 'a handful of'),
          throwsArgumentError,
        );
      },
    );

    test('removing an alias tombstones it and it stops matching', () async {
      final alias = await repo.addAlias('1', 'Yellow Onions');
      await repo.removeAlias(alias.id);
      expect(await repo.aliases('1'), isEmpty);
      expect(await repo.search('yellow'), isEmpty);
    });
  });
}

/// A whole-row edit, defaulted to the seed's shape so each test states only
/// the field it is about. [IngredientEdit] is a replacement, not a patch —
/// the form always holds the whole row.
IngredientEdit _edit({
  required String name,
  String? category,
  Unit unit = g,
  Macros? macros,
  MacrosBasis basis = MacrosBasis.perG,
  Set<Unit> allowed = const {g},
}) => IngredientEdit(
  canonicalName: name,
  defaultUnit: unit,
  macrosBasis: basis,
  allowedUnits: allowed,
  category: category,
  macros: macros,
);
