import 'dart:convert';
import 'dart:io';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/ingredient_repository_impl.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/ingredients/domain/normalize.dart';
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
  // match_text is written with the SERVER's phrase rules, exactly as every
  // real row's is (`normalizeMatchText` — the plan-0020 D6 port). It is NOT
  // the query normalizer: the two differ ("Almonds" is `almond` to the server,
  // `almonds` to a search query), and seeding the query's own spelling would
  // hide precisely the mismatch the search has to bridge.
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
      normalizeMatchText(name),
      deletedAt,
    ],
  );
  for (final a in aliases) {
    await db.execute(
      'INSERT INTO ingredient_alias '
      '(id, ingredient_id, alias_text, match_text) '
      'VALUES (?, ?, ?, ?)',
      ['$id-${a.hashCode}', id, a, normalizeMatchText(a)],
    );
  }
}

/// The rows a search returned. The `guessed` flag it also carries is the
/// subject of its own group below, not of every ordering assertion.
Future<List<Ingredient>> _search(
  IngredientRepository repo,
  String query, {
  int limit = 30,
}) async => (await repo.search(query, limit: limit)).rows;

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
    // Plural names, whose match_text the normalizer singularizes: 'almond',
    // 'black bean', 'beansprout'.
    // (Ids outside the numeric run — later tests seed '9'…'13' themselves.)
    await _seed(db, id: 'p1', name: 'Almonds');
    await _seed(db, id: 'p2', name: 'Black Beans');
    await _seed(db, id: 'p3', name: 'Beansprouts');
  });

  tearDown(() => closeTestDb(db, dir));

  test('empty query returns the head, alphabetical', () async {
    final all = await _search(repo, '');
    expect(all.map((i) => i.canonicalName), [
      'All-Purpose Flour',
      'Almonds',
      'Beansprouts',
      'Black Beans',
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
    final r = await _search(repo, 'oni');
    expect(r.map((i) => i.canonicalName), contains('Onion'));
    expect(r.map((i) => i.canonicalName), isNot(contains('Olive Oil')));
  });

  test('matches an alias (scallion → Spring Onion)', () async {
    final r = await _search(repo, 'scall');
    expect(r.single.canonicalName, 'Spring Onion');
  });

  test('exact name is ranked first', () async {
    final r = await _search(repo, 'onion');
    expect(r.first.canonicalName, 'Onion'); // exact beats "Spring Onion"
  });

  test('matches on any word boundary, not just the leading word', () async {
    // "tofu" must find "Extra Firm Tofu" — a strict prefix never could.
    final r = await _search(repo, 'tofu');
    expect(r.map((i) => i.canonicalName), contains('Extra Firm Tofu'));
    // "nion" is not a word start of "Onion", so tiers 0 and 1 refuse it —
    // which is exactly when the typo tier gets to answer. It offers Onion as
    // a GUESS (owner ruling, 2026-09-02), never as a spelled hit.
    final guess = await repo.search('nion');
    expect(guess.rows.first.canonicalName, 'Onion');
    expect(guess.guessed, isTrue);
  });

  test('normalizes the query like match_text ("all-purpose" hits)', () async {
    final r = await _search(repo, 'all-purpose');
    expect(r.map((i) => i.canonicalName), contains('All-Purpose Flour'));
    // And the un-hyphenated spelling hits the same row.
    final r2 = await _search(repo, 'all purpose');
    expect(r2.map((i) => i.canonicalName), contains('All-Purpose Flour'));
  });

  group('token-subset search (order-independent, extra words fine)', () {
    test('"canned tomatoes" finds "Canned Whole Tomatoes"', () async {
      final r = await _search(repo, 'canned tomatoes');
      expect(r.map((i) => i.canonicalName), contains('Canned Whole Tomatoes'));
    });

    test('"coconut milk" finds "Coconut milk, canned"', () async {
      final r = await _search(repo, 'coconut milk');
      expect(r.map((i) => i.canonicalName), contains('Coconut milk, canned'));
    });

    test('word order does not matter', () async {
      final r = await _search(repo, 'tomatoes canned');
      expect(r.map((i) => i.canonicalName), contains('Canned Whole Tomatoes'));
    });

    test(
      'every token must be present — a missing token excludes the row',
      () async {
        // "canned" alone hits both canned rows; adding "beans" (present in
        // neither) must drop them.
        expect(await _search(repo, 'canned beans'), isEmpty);
      },
    );

    test('a mistyped token in a multi-word query still finds it', () async {
      // "chiken" is one edit from "chicken", and a six-character token is
      // allowed one. The correctly spelled "thigh" beside it is what a
      // three-character token would need; this one stands on its own.
      final r = await repo.search('chiken thigh');
      expect(r.rows.map((i) => i.canonicalName), contains('Chicken thigh'));
      expect(r.guessed, isTrue);
    });

    test('a single mistyped word IS guessed at, above the floor', () async {
      // Four characters is where the phone starts guessing (owner ruling,
      // 2026-09-02) — the corroboration of a second token is no longer the
      // price of admission.
      final r = await repo.search('chiken');
      expect(r.rows.first.canonicalName, 'Chicken thigh');
      expect(r.guessed, isTrue);
    });

    test('a typo beyond the edit budget stays silent, however many tokens '
        'stand beside it', () async {
      // "chikn" is TWO edits from "chicken" (an insertion for the 'c' and one
      // for the 'e'), and a five-character token is allowed one. The
      // corroborating "thigh" buys no extra budget: the guard is per TOKEN.
      expect((await repo.search('chikn thigh')).rows, isEmpty);
      expect((await repo.search('chikn')).rows, isEmpty);
      // And three characters is where guessing stops altogether.
      expect((await repo.search('tfu')).rows, isEmpty);
    });
  });

  group('a plural query hits its singularized match_text', () {
    test('"almonds" finds Almonds, ranked first', () async {
      // The bug: match_text is 'almond' (the phrase normalizer singularizes)
      // while the query stays 'almonds', so `'almond' LIKE 'almonds%'` was
      // false and the row was unreachable. It is a SPELLING, not a guess —
      // the singular form is what the exact tier compares, so the result is
      // never flagged as one.
      final r = await repo.search('almonds');
      expect(r.rows.first.canonicalName, 'Almonds');
      expect(r.guessed, isFalse);
    });

    test('the singular spelling is unchanged', () async {
      expect((await _search(repo, 'almond')).first.canonicalName, 'Almonds');
    });

    test('a mid-typing prefix is unchanged', () async {
      final r = await _search(repo, 'almo');
      expect(r.map((i) => i.canonicalName), contains('Almonds'));
    });

    test('the raw form still matches what only IT prefixes', () async {
      // 'beans' → singular 'bean' reaches 'black bean'; the raw form is what
      // reaches 'beansprout'. Dropping either branch loses a row.
      final r = await _search(repo, 'beans');
      expect(
        r.map((i) => i.canonicalName),
        containsAll(<String>['Black Beans', 'Beansprouts']),
      );
    });

    test('a plural in a multi-word query hits too', () async {
      final r = await _search(repo, 'black beans');
      expect(r.single.canonicalName, 'Black Beans');
    });
  });

  test('a LIKE wildcard in the query is stripped, not a pattern', () async {
    // If '_' leaked through as a single-char wildcard, 'on_on' would match
    // "onion" as a SPELLING. It does not: the character is stripped, so the
    // query behaves exactly like the wildcard-free text it normalizes to, and
    // tiers 0 and 1 find nothing at all. (A bare '%' normalizes to the empty
    // query and just browses the head.)
    final stripped = await repo.search('on_on');
    expect(stripped.guessed, isTrue);
    expect(
      stripped.rows.map((i) => i.canonicalName),
      (await _search(repo, 'onon')).map((i) => i.canonicalName),
    );
    // The singular of a stripped token is still stripped — singularization
    // only ever trims the tail, so it cannot resurrect a wildcard: 'on_ons'
    // normalizes to 'onons', whose singular 'onon' is still not a pattern.
    expect(
      (await _search(repo, 'on_ons')).map((i) => i.canonicalName),
      (await _search(repo, 'onons')).map((i) => i.canonicalName),
    );
  });

  group('the "did you mean" band', () {
    test('a spelling is never flagged as a guess', () async {
      expect((await repo.search('onion')).guessed, isFalse);
      expect((await repo.search('tofu')).guessed, isFalse);
      expect((await repo.search('')).guessed, isFalse);
    });

    test('a guess is flagged, and it is the WHOLE list', () async {
      // Tier 2 runs only when tiers 0 and 1 are empty, so a band is never a
      // tail of weak rows under strong ones.
      final guess = await repo.search('almnd');
      expect(guess.rows.first.canonicalName, 'Almonds');
      expect(guess.guessed, isTrue);
    });

    test('an empty answer is an ANSWER — nothing is invented', () async {
      final none = await repo.search('xylophone');
      expect(none.rows, isEmpty);
      expect(none.guessed, isFalse);
    });

    test(
      'a name word the phrase normalizer eats is still a spelling',
      () async {
        // "Jars" is in the measure strip set, so match_text loses it and the
        // SQL pass cannot find it. searchRank also sees the raw name, so the
        // row comes back through the fallback — as a PREFIX hit, not a guess.
        await _seed(db, id: 'j1', name: 'Chickpea Jars');
        final r = await repo.search('jars');
        expect(r.rows.single.canonicalName, 'Chickpea Jars');
        expect(r.guessed, isFalse);
      },
    );
  });

  test('tombstoned vocab is not searchable or listable', () async {
    await _seed(
      db,
      id: '9',
      name: 'Onion Powder',
      deletedAt: '2026-01-01T00:00:00Z',
    );
    final hits = await _search(repo, 'onion');
    expect(hits.map((i) => i.canonicalName), isNot(contains('Onion Powder')));
    final all = await _search(repo, '');
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
    final oil = (await _search(repo, 'olive')).single;
    expect(oil.status, IngredientStatus.stub);
    final onion = (await _search(repo, 'onion')).first;
    expect(onion.category, 'vegetables');
  });

  test('maps macros with their stored basis (0011)', () async {
    await db.execute(
      "UPDATE ingredient SET macros = ?, macros_basis = 'ml' WHERE id = '1'",
      ['{"kcal":40,"protein":1,"carb":9,"fat":0}'],
    );
    final onion = (await _search(repo, 'onion')).first;
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
    final onion = (await _search(repo, 'onion')).first;
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
    final onion = (await _search(repo, 'onion')).first;
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

    final found = (await _search(repo, 'curry')).single;
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
      // `pt` rides with `cup` on the cross leg (plan 0025 D2b); `qt` does
      // not, because `l` never did.
      expect(updated!.allowedUnits!.map((u) => u.id).toSet(), {
        'g',
        'kg',
        'tsp',
        'tbsp',
        'cup',
        'pt',
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
        'pt',
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

  group('stopOfferingPiece (plan 0022 / ADR-0010: `piece` is an admission)', () {
    setUp(() async {
      // The garlic shape: a count row whose measure (a clove) names the thing.
      await db.execute(
        "UPDATE ingredient SET default_unit = 'piece' WHERE id = '1'",
      );
    });

    test('`piece` comes out of a row still on the derived fallback — the '
        'list is materialized first, so there is something to remove '
        'from', () async {
      final row = await db.get(
        "SELECT allowed_units FROM ingredient WHERE id = '1'",
      );
      expect(row['allowed_units'], isNull, reason: 'derived fallback');

      final updated = await repo.stopOfferingPiece('1');
      expect(updated!.allowedUnits!.map((u) => u.id), isNot(contains('piece')));
      // The basis family is untouched: it never needed `piece` to be sayable.
      expect(updated.allowedUnits!.map((u) => u.id), contains('g'));

      final after = await db.get(
        "SELECT allowed_units FROM ingredient WHERE id = '1'",
      );
      expect(
        jsonDecode(after['allowed_units'] as String) as List,
        isNot(contains('piece')),
      );
    });

    test('every other admission the row carries survives — this takes one '
        'word away, not the curation around it', () async {
      await db.execute('UPDATE ingredient SET allowed_units = ? WHERE id = ?', [
        jsonEncode(['piece', 'g', 'cup', 'to_taste']),
        '1',
      ]);
      final updated = await repo.stopOfferingPiece('1');
      // Exactly one word out of the stored list. `cup` stays stored even
      // though this row has no density to make it sayable — the strip that
      // hides it is `allowedUnitsFor`'s to do at read time, and this write
      // has no business quietly re-curating a list the household owns.
      expect(updated!.allowedUnits!.map((u) => u.id).toSet(), {
        'g',
        'cup',
        'to_taste',
      });
    });

    test('idempotent, and null for an unknown id', () async {
      await repo.stopOfferingPiece('1');
      final again = await repo.stopOfferingPiece('1');
      expect(again!.allowedUnits!.map((u) => u.id), isNot(contains('piece')));
      expect(await repo.stopOfferingPiece('nope'), isNull);
    });

    test('a row that never admitted `piece` is left exactly as it was — no '
        'materialization, no write', () async {
      final before = await db.get(
        "SELECT allowed_units, updated_at FROM ingredient WHERE id = '5'",
      );
      final same = await repo.stopOfferingPiece('5');
      expect(same, isNotNull);
      final after = await db.get(
        "SELECT allowed_units, updated_at FROM ingredient WHERE id = '5'",
      );
      expect(after['allowed_units'], before['allowed_units']);
      expect(after['updated_at'], before['updated_at']);
    });
  });

  group('setDefaultMeasure (0023 / seam D1: what "2 onions" means)', () {
    setUp(() async {
      await db.execute(
        'INSERT INTO ingredient_measure '
        '(id, household_id, ingredient_id, label, basis_amount, sort_order) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['m1', 'h', '1', 'onion, medium', 110, 0],
      );
      await db.execute(
        'INSERT INTO ingredient_measure '
        '(id, household_id, ingredient_id, label, basis_amount, sort_order) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['m2', 'h', '1', 'onion, large', 150, 1],
      );
      await db.execute(
        'INSERT INTO ingredient_measure '
        '(id, household_id, ingredient_id, label, basis_amount, sort_order) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['m9', 'h', '2', 'spear', 31, 0],
      );
    });

    test('a row starts with no default, and the pick reads back', () async {
      expect((await repo.byId('1'))!.defaultMeasureId, isNull);
      final updated = await repo.setDefaultMeasure('1', 'm1');
      expect(updated!.defaultMeasureId, 'm1');
      expect((await repo.byId('1'))!.defaultMeasureId, 'm1');
      // …and through the batched read the import review uses.
      expect((await repo.byIds({'1'}))['1']!.defaultMeasureId, 'm1');
    });

    test('clearing it back to "ask me each time" sticks — a null is a real '
        'answer, not "unchanged"', () async {
      await repo.setDefaultMeasure('1', 'm2');
      final cleared = await repo.setDefaultMeasure('1', null);
      expect(cleared!.defaultMeasureId, isNull);
      expect((await repo.byId('1'))!.defaultMeasureId, isNull);
    });

    test('clearing never deletes the measure — the row keeps every label it '
        'had, and only stops having a preferred one', () async {
      await repo.setDefaultMeasure('1', 'm1');
      await repo.setDefaultMeasure('1', null);
      final live = await db.getAll(
        "SELECT label FROM ingredient_measure WHERE ingredient_id = '1' "
        'AND deleted_at IS NULL ORDER BY sort_order',
      );
      expect(live.map((r) => r['label']), ['onion, medium', 'onion, large']);
    });

    test("a measure of ANOTHER row is refused — a '1 onion' silently counted "
        'as a spear is the one lie this column could tell', () async {
      await expectLater(
        repo.setDefaultMeasure('1', 'm9'),
        throwsA(isA<ArgumentError>()),
      );
      expect((await repo.byId('1'))!.defaultMeasureId, isNull);
    });

    test('a tombstoned measure is refused too', () async {
      await db.execute(
        "UPDATE ingredient_measure SET deleted_at = '2026-09-03T00:00:00Z' "
        "WHERE id = 'm1'",
      );
      await expectLater(
        repo.setDefaultMeasure('1', 'm1'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('null for an unknown id', () async {
      expect(await repo.setDefaultMeasure('nope', null), isNull);
    });
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
        'pt',
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
        expect(rows.length, 11);
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
        expect((await repo.watchVocabulary().first).length, 11);
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
      expect((await _search(repo, 'curry')).single.id, '1');
      expect(await _search(repo, 'onion'), isNot(contains('1')));
    });

    test(
      'provenance is patch-shaped: null keeps the stored stamp, a value '
      'writes it in the same statement as the macros (plan 0025 #8)',
      () async {
        final before = (await db.get(
          "SELECT source FROM ingredient WHERE id = '1'",
        ))['source'];
        await repo.saveEdit('1', _edit(name: 'Onion'));
        expect(
          (await db.get(
            "SELECT source FROM ingredient WHERE id = '1'",
          ))['source'],
          before,
          reason: 'an ordinary save must not touch provenance',
        );

        const panel = Macros(kcal: 539, protein: 6.3, carb: 57.5, fat: 30.9);
        final stamped = await repo.saveEdit(
          '1',
          _edit(name: 'Onion', macros: panel, source: 'off:3017620422003'),
        );
        expect(stamped!.source, 'off:3017620422003');
        expect(stamped.macros, panel);

        // …and the next plain save leaves the stamp where it is.
        final again = await repo.saveEdit(
          '1',
          _edit(name: 'Onion', macros: panel),
        );
        expect(again!.source, 'off:3017620422003');
      },
    );

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
        expect((await _search(repo, 'yellow')).single.id, '1');
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
      expect(await _search(repo, 'yellow'), isEmpty);
    });
  });

  // The shared vectors, through REAL SQLite. `search_rank_test.dart` runs the
  // same file against `searchRank` alone; this proves the SQL tier-0/1 pass
  // and the Dart tier-2 pass land on the same answers, which is the thing that
  // would otherwise drift.
  group('shared vectors, over the real database', () {
    late PowerSyncDatabase vdb;
    late Directory vdir;
    late SqliteIngredientRepository vrepo;
    final vectors =
        jsonDecode(
              File(
                'test/features/ingredients/search_vectors.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    setUp(() async {
      (vdb, vdir) = await openTestDb();
      vrepo = SqliteIngredientRepository(vdb, householdId: 'h');
      var n = 0;
      for (final row
          in (vectors['vocab'] as List).cast<Map<String, dynamic>>()) {
        await _seed(
          vdb,
          id: 'v${n++}',
          name: row['name'] as String,
          aliases: ((row['aliases'] as List<dynamic>?) ?? const [])
              .cast<String>(),
        );
      }
    });

    tearDown(() => closeTestDb(vdb, vdir));

    for (final v in (vectors['tiers'] as List).cast<Map<String, dynamic>>()) {
      final query = v['q'] as String;
      test('"$query" finds ${v['want']}', () async {
        final got = await vrepo.search(query);
        expect(got.rows.first.canonicalName, v['want']);
        expect(got.guessed, v['tier'] == 'typo');
      });
    }

    for (final query in (vectors['refusals'] as List).cast<String>()) {
      test('"$query" returns nothing', () async {
        expect((await vrepo.search(query)).rows, isEmpty);
      });
    }

    for (final query in (vectors['tier1_answers'] as List).cast<String>()) {
      test('"$query" is answered by a spelling, never a guess', () async {
        final got = await vrepo.search(query);
        expect(got.rows, isNotEmpty);
        expect(got.guessed, isFalse);
      });
    }
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
  String? source,
}) => IngredientEdit(
  canonicalName: name,
  defaultUnit: unit,
  macrosBasis: basis,
  allowedUnits: allowed,
  category: category,
  macros: macros,
  source: source,
);
