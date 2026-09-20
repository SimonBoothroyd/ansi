/// The data layer for a recipe's own words — `3 blob` of a sauce, end to end
/// over the real PowerSync views (ADR-0018, migration 0048).
///
/// This build cannot AUTHOR a measured line: no screen on it writes one. It
/// must still read every one it meets, because the seam ships a release ahead
/// of the authoring UI — a device that cannot read a measured line throws on it
/// or drops it in silence, and the shape of that silence is what these tests
/// exist to keep out.
library;

import 'dart:async';
import 'dart:io';

import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/planning/data/week_variant_repository_impl.dart';
import 'package:ansi/features/planning/domain/week_variant_repository.dart';
import 'package:ansi/features/recipes/data/recipe_measure_repository_impl.dart';
import 'package:ansi/features/recipes/data/recipe_repository_impl.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_cost.dart';
import 'package:ansi/features/recipes/domain/recipe_measure_repository.dart';
import 'package:ansi/features/recipes/domain/recipe_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

/// What the aioli says a batch makes. Every word below is an amount in this
/// family, because that is the gate: a word is only sayable against a `makes`
/// it can be held to (ADR-0018 rule 2).
const _yield = (qty: 300.0, unit: g);

/// Every measure this file uses is built here, so re-stating what a measure IS
/// (the denomination it carries) is one edit rather than forty. `blob()` is *a
/// blob is 15 g*, which against `makes 300 g` is a twentieth of a batch.
RecipeMeasure word(
  String label, {
  double amount = 15,
  Unit unit = g,
  String? id,
  int sortOrder = 0,
}) => RecipeMeasure(
  id: id ?? 'm-$label',
  recipeId: 'aioli',
  label: label,
  amount: amount,
  unit: unit,
  sortOrder: sortOrder,
);

RecipeMeasure blob({double amount = 15, Unit unit = g}) =>
    word('blob', amount: amount, unit: unit);

/// What a count of the word comes to in batches — read through the one
/// resolution every reader uses rather than written as a literal, so an
/// expectation says "a share of the target's batch" instead of a number that
/// would quietly stop being the right one if the denomination were re-stated.
double batchesOf(double count, [RecipeMeasure? measure]) {
  final m = measure ?? blob();
  return (resolveComponentAmount(
            quantity: count,
            unit: null,
            yields: const [_yield],
            recipeMeasureId: m.id,
            measures: [m],
          )
          as ResolvedComponentAmount)
      .batches;
}

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteRecipeRepository repo;
  late SqliteRecipeMeasureRepository measures;
  late SqliteWeekVariantRepository week;

  /// The Romesco Aioli: makes 300 g, one 240 g line of rice, and the
  /// household's word for a ladleful of it.
  Future<void> seedAioli({List<RecipeMeasure>? words}) => repo.saveRecipe(
    Recipe(
      id: 'aioli',
      title: 'Romesco Aioli',
      servingsBase: 4,
      keepsForDays: 5,
      yieldQty: _yield.qty,
      yieldUnit: _yield.unit,
      measures: words ?? [blob()],
      groups: const [
        IngredientGroup(
          id: 'ag',
          items: [
            LineItem(
              id: 'ai1',
              ingredientId: 'ing-rice',
              ingredientName: 'Rice',
              unit: g,
              quantity: 240,
            ),
          ],
        ),
      ],
    ),
  );

  /// A parent whose only line asks for [quantity] of the aioli's word — the
  /// line no screen on this build can write.
  Recipe parent({
    double? quantity = 3,
    String? measureId = 'm-blob',
    double servings = 8,
  }) => Recipe(
    id: 'sliders',
    title: 'Sausage Sliders',
    servingsBase: servings,
    groups: [
      IngredientGroup(
        id: 'sg',
        items: [
          LineItem(
            id: 'si1',
            subRecipeId: 'aioli',
            ingredientName: 'Romesco Aioli',
            quantity: quantity,
            recipeMeasureId: measureId,
          ),
        ],
      ),
    ],
  );

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqliteRecipeRepository(db, householdId: 'h');
    measures = SqliteRecipeMeasureRepository(db, householdId: 'h');
    week = SqliteWeekVariantRepository(db, householdId: 'h');
    // Rice carries per-100 g macros and a price, so a parent's figures have
    // something real to be a share OF.
    await db.execute(
      'INSERT INTO ingredient (id, household_id, canonical_name, '
      'default_unit, status, source, match_text, macros, macros_basis) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'ing-rice',
        'h',
        'Rice',
        'g',
        'complete',
        'seed',
        'rice',
        '{"kcal":360,"protein":7,"carb":80,"fat":1}',
        'per_g',
      ],
    );
    await db.execute(
      'INSERT INTO receipt (id, household_id, store, purchased_at, source, '
      'created_at) VALUES (?, ?, ?, ?, ?, ?)',
      ['rc1', 'h', "TJ's", '2026-09-03', 'photo', '2026-09-03'],
    );
    await db.execute(
      'INSERT INTO receipt_line (id, household_id, receipt_id, ingredient_id, '
      'cents, discount_cents, kind, pack_basis_amount, sort_order, created_at) '
      'VALUES (?, ?, ?, ?, ?, 0, ?, ?, 0, ?)',
      ['rl1', 'h', 'rc1', 'ing-rice', 500, 'item', 1000.0, '2026-09-03'],
    );
  });

  tearDown(() => closeTestDb(db, dir));

  /// Retires the word by hand, the way the household's bin does — and the way
  /// another device's tombstone arrives.
  Future<void> retireBlob() => db.execute(
    'UPDATE recipe_measure SET deleted_at = ? WHERE id = ?',
    ['2026-09-19T00:00:00Z', 'm-blob'],
  );

  group('a measured line, saved and read back', () {
    test('the row stores the pointer and NO unit, and the line reads the '
        'word off its target', () async {
      await seedAioli();
      await repo.saveRecipe(parent());

      final row = await db.get(
        'SELECT unit, recipe_measure_id, quantity, sub_recipe_id, measure_id '
        'FROM recipe_line_item WHERE id = ?',
        ['si1'],
      );
      // The storage contract: exactly one of the two columns is set. `batch`
      // beside the word would be the right dimension with the wrong number,
      // and `piece` is the count this design refuses to degrade to.
      expect(row['unit'], isNull);
      expect(row['recipe_measure_id'], 'm-blob');
      expect(row['quantity'], 3);
      expect(row['sub_recipe_id'], 'aioli');
      expect(row['measure_id'], isNull, reason: 'an ingredient word, not this');

      final line =
          (await repo.watchRecipe('sliders').first)!.groups.single.items.single;
      expect(line.unit, isNull);
      expect(line.recipeMeasureId, 'm-blob');
      expect(line.isMeasuredComponent, isTrue);
      expect(line.subRecipe!.measures, [blob()]);
      final amount = line.componentAmount! as ResolvedComponentAmount;
      expect(amount.batches, closeTo(batchesOf(3), 1e-12));
      expect(amount.viaMeasure, blob());
      expect(
        amount.against,
        _yield,
        reason: 'one conversion path: a word reaches a batch THROUGH the yield',
      );
    });

    test('the recipe page carries the recipe’s own words', () async {
      await seedAioli(words: [blob(), word('ladle', amount: 50, sortOrder: 1)]);
      final loaded = (await repo.watchRecipe('aioli').first)!;
      expect(loaded.measures.map((m) => m.label), ['blob', 'ladle']);
      expect(loaded.asSubRecipeTarget.measures, hasLength(2));
    });

    test('the summary carries them too, so a picker row hands a TARGET over '
        'with its words', () async {
      await seedAioli();
      final summary = (await repo.watchRecipes().first).single;
      expect(summary.measures, [blob()]);
      expect(summary.asSubRecipeTarget.measures, [blob()]);
    });

    test(
      'two devices coining one word merge on read, oldest canonical',
      () async {
        await seedAioli();
        // The second `blob`, as the other phone's row arrives: legal (there is
        // no unique index, deliberately) and hidden behind the older one.
        await db.execute(
          'INSERT INTO recipe_measure (id, household_id, recipe_id, label, '
          'amount, unit, sort_order, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            'm-blob-2',
            'h',
            'aioli',
            'blob',
            12.5,
            'g',
            0,
            '2099-01-01T00:00:00Z',
            '2099-01-01T00:00:00Z',
          ],
        );

        final loaded = (await repo.watchRecipe('aioli').first)!;
        expect(loaded.measures.map((m) => m.id), ['m-blob']);
        expect(loaded.measures.single, blob());
        // The hidden row is not deleted: a line already pointing at it still
        // resolves by id, which is the whole reason the merge hides rather than
        // refuses.
        final hidden = await db.get(
          'SELECT deleted_at FROM recipe_measure WHERE id = ?',
          ['m-blob-2'],
        );
        expect(hidden['deleted_at'], isNull);
      },
    );
  });

  group('a retired word is named, never a number and never dropped', () {
    test('on the recipe page', () async {
      await seedAioli();
      await repo.saveRecipe(parent());
      await retireBlob();

      final line =
          (await repo.watchRecipe('sliders').first)!.groups.single.items.single;
      // Kept, with its number, and repairable.
      expect(line.quantity, 3);
      expect(line.recipeMeasureId, 'm-blob');
      expect(line.unit, isNull, reason: 'never re-read as a count');
      expect(line.componentAmount, const ComponentMeasureMissing('m-blob'));
    });

    test('in the macro summary', () async {
      await seedAioli();
      await repo.saveRecipe(parent());
      await retireBlob();

      final macros = (await repo.watchRecipe('sliders').first)!.macros!;
      expect(macros.incomplete, isTrue);
      expect(macros.subRecipesUnresolved, 1);
    });

    test('in the cost summary', () async {
      await seedAioli();
      await repo.saveRecipe(parent());
      await retireBlob();

      final cost = (await repo.watchRecipeCosts().first)['sliders']!;
      expect(cost.incomplete, isTrue, reason: 'never a number for a gone word');
      expect(cost.unpriced.single.reason, CostLineReason.subRecipeUnresolved);
      expect(cost.lineCosts, isEmpty);
    });

    test(
      'in the “used in” row, which prints the word while it is there',
      () async {
        await seedAioli();
        await repo.saveRecipe(parent());

        var use = (await repo.usedIn('aioli')).single;
        expect(use.measureLabel, 'blob');
        expect(use.unit, isNull);
        expect(use.quantity, 3);
        expect(
          (use.amount as ResolvedComponentAmount).batches,
          closeTo(batchesOf(3), 1e-12),
        );

        await retireBlob();
        use = (await repo.usedIn('aioli')).single;
        expect(use.measureLabel, isNull);
        expect(use.amount, const ComponentMeasureMissing('m-blob'));
        expect(use.quantity, 3, reason: 'the number is kept');
      },
    );
  });

  group('the arithmetic is a share of the target’s whole', () {
    test('3 blob is that share of the aioli’s whole macros and cost', () async {
      await seedAioli();
      await repo.saveRecipe(parent());

      final aioli = (await repo.watchRecipe('aioli').first)!;
      final sliders = (await repo.watchRecipe('sliders').first)!;
      // Per-SERVING figures, so the share is read against the aioli's whole
      // batch: 4 servings × its per-serving kcal.
      final aioliBatch = aioli.macros!.perServing!.kcal * 4;
      expect(
        sliders.macros!.perServing!.kcal * 8,
        closeTo(batchesOf(3) * aioliBatch, 1e-9),
      );

      final costs = await repo.watchRecipeCosts().first;
      expect(
        costs['sliders']!.totalCents,
        closeTo(batchesOf(3) * costs['aioli']!.totalCents!, 1),
      );
    });

    test('×2 doubles the LINE, never the word', () async {
      await seedAioli();
      await repo.saveRecipe(parent(quantity: 6));

      final line =
          (await repo.watchRecipe('sliders').first)!.groups.single.items.single;
      expect(
        (line.componentAmount! as ResolvedComponentAmount).batches,
        closeTo(batchesOf(6), 1e-12),
      );
      expect(batchesOf(6), closeTo(2 * batchesOf(3), 1e-12));
      // The measure is a property of the sub-recipe's batch and is read the
      // same at every scale — the LINE doubled, not the word.
      expect(line.subRecipe!.measures.single, blob());

      final costs = await repo.watchRecipeCosts().first;
      expect(
        costs['sliders']!.totalCents,
        closeTo(batchesOf(6) * costs['aioli']!.totalCents!, 1),
      );
    });
  });

  group('a line denominated in nothing is refused before it is written', () {
    test('saveRecipe throws and writes nothing at all', () async {
      await seedAioli();
      await drainCrudQueue(db);

      // A shape the app can really hand over: a line that WAS `3 blob` of the
      // aioli, re-pointed at an ingredient by a caller that forgot to
      // re-denominate it. [LineItem]'s own asserts pass — the word is set, so
      // the pair is not two nulls yet — and the write door is where it becomes
      // one, because a word is only sayable about a component.
      //
      // The server's `num_nonnulls(unit, recipe_measure_id) = 1` would refuse
      // the UPLOAD, and a refused upload makes the connector drop the whole
      // crud transaction with every write queued beside it. So the refusal
      // happens here, in front of a person, before anything is written.
      const bad = Recipe(
        id: 'sliders',
        title: 'Sausage Sliders',
        servingsBase: 8,
        groups: [
          IngredientGroup(
            id: 'sg',
            items: [
              LineItem(
                id: 'si1',
                ingredientId: 'ing-rice',
                ingredientName: 'Rice',
                quantity: 3,
                recipeMeasureId: 'm-blob',
              ),
            ],
          ),
        ],
      );
      await expectLater(
        repo.saveRecipe(bad),
        throwsA(
          isA<UndenominatedLineError>()
              .having((e) => e.lineId, 'lineId', 'si1')
              .having((e) => e.name, 'name', 'Rice'),
        ),
      );
      expect(await queuedCrudOps(db), isEmpty);
      expect(await repo.watchRecipe('sliders').first, isNull);
    });

    test(
      'a measured line that says no number is refused for this week too',
      () async {
        await seedAioli();
        await repo.saveRecipe(parent());
        await expectLater(
          week.saveOverrides(
            DateTime.utc(2026, 9, 21),
            'sliders',
            overrides: const [
              LineOverride(
                id: 'wro1',
                action: LineOverrideAction.replace,
                recipeLineItemId: 'si1',
                subRecipeId: 'aioli',
                recipeMeasureId: 'm-blob',
              ),
            ],
          ),
          throwsA(isA<WordlessOverrideError>()),
        );
      },
    );
  });

  group('the measure seam', () {
    test('the ＋ door writes on tap, after the existing words', () async {
      await seedAioli();
      final minted = await measures.addRecipeMeasure(
        recipeId: 'aioli',
        label: '  ladle ',
        amount: 50,
        unit: g,
      );
      // Read by the ingredient side's rule exactly: trimmed, inner whitespace
      // collapsed, case untouched.
      expect(minted.label, 'ladle');
      expect(minted.sortOrder, 1);
      expect(
        (await measures.watchRecipeMeasures('aioli').first).map((m) => m.label),
        ['blob', 'ladle'],
      );
    });

    test('the ＋ door holds the authoring rules, not just the form', () async {
      await seedAioli();
      await expectLater(
        measures.addRecipeMeasure(
          recipeId: 'aioli',
          label: 'cup',
          amount: 50,
          unit: g,
        ),
        throwsA(
          isA<RecipeMeasureRefused>().having(
            (e) => e.code,
            'code',
            'recipe_measure/unit_word',
          ),
        ),
      );
      await expectLater(
        measures.addRecipeMeasure(
          recipeId: 'aioli',
          label: 'Blob',
          amount: 50,
          unit: g,
        ),
        throwsA(
          isA<RecipeMeasureRefused>().having(
            (e) => e.code,
            'code',
            'recipe_measure/word_taken',
          ),
        ),
      );
      await expectLater(
        measures.addRecipeMeasure(
          recipeId: 'aioli',
          label: 'ladle',
          amount: 0,
          unit: g,
        ),
        throwsA(
          isA<RecipeMeasureRefused>().having(
            (e) => e.code,
            'code',
            'recipe_measure/amount',
          ),
        ),
      );
      expect(await measures.watchRecipeMeasures('aioli').first, [blob()]);
    });

    test(
      'the ＋ door reads the MAKES off the recipe row, not off the form',
      () async {
        // The gate ADR-0018 rule 2 pays for out loud, and the reason the yields
        // are not a parameter: what a batch makes is a fact about the stored
        // recipe, so a form cannot assert its way past it.
        await seedAioli();
        await repo.saveRecipe(
          (await repo.watchRecipe('aioli').first)!.copyWith(yieldQty: null),
        );
        await expectLater(
          measures.addRecipeMeasure(
            recipeId: 'aioli',
            label: 'ladle',
            amount: 50,
            unit: g,
          ),
          throwsA(
            isA<RecipeMeasureRefused>().having(
              (e) => e.code,
              'code',
              'recipe_measure/no_yield',
            ),
          ),
        );
      },
    );

    test(
      'a word the recipe’s MAKES cannot hold is refused at the door',
      () async {
        // The aioli makes 300 g and nothing else, and a recipe has no density.
        await seedAioli();
        await expectLater(
          measures.addRecipeMeasure(
            recipeId: 'aioli',
            label: 'ladle',
            amount: 180,
            unit: ml,
          ),
          throwsA(
            isA<RecipeMeasureRefused>().having(
              (e) => e.code,
              'code',
              'recipe_measure/unit_family',
            ),
          ),
        );
        expect(await measures.watchRecipeMeasures('aioli').first, [blob()]);
      },
    );

    test('re-stating keeps the id, so every line already saying the word '
        'follows the new number', () async {
      await seedAioli();
      await repo.saveRecipe(parent());

      await measures.restateRecipeMeasure(
        measureId: 'm-blob',
        label: 'blob',
        amount: 12.5,
        unit: g,
      );

      final line =
          (await repo.watchRecipe('sliders').first)!.groups.single.items.single;
      expect(line.recipeMeasureId, 'm-blob', reason: 'the row kept its id');
      expect(
        (line.componentAmount! as ResolvedComponentAmount).batches,
        closeTo(batchesOf(3, blob(amount: 12.5)), 1e-12),
      );
    });

    test('reorder re-stamps sort_order by position', () async {
      await seedAioli();
      await measures.addRecipeMeasure(
        recipeId: 'aioli',
        label: 'ladle',
        amount: 50,
        unit: g,
      );
      final ladle = (await measures.watchRecipeMeasures('aioli').first).last;
      await measures.reorderRecipeMeasures('aioli', [ladle.id, 'm-blob']);
      expect(
        (await measures.watchRecipeMeasures('aioli').first).map((m) => m.label),
        ['ladle', 'blob'],
      );
    });

    test('the delete gate counts both tables that can point at a word, and '
        'names the recipes', () async {
      await seedAioli();
      await repo.saveRecipe(parent());
      // And this week's own amount for the same line.
      await db.execute(
        'INSERT INTO week_plan (id, household_id, week_start_date, '
        'created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        ['wp', 'h', '2026-09-21', '2026-09-19', '2026-09-19'],
      );
      await db.execute(
        'INSERT INTO week_recipe_line_override (id, household_id, '
        'week_plan_id, recipe_id, action, recipe_line_item_id, sub_recipe_id, '
        'quantity, recipe_measure_id, sort_order, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'wro1',
          'h',
          'wp',
          'sliders',
          'replace',
          'si1',
          'aioli',
          5,
          'm-blob',
          0,
          '2026-09-19',
          '2026-09-19',
        ],
      );

      final usage = await measures.countLinesUsing('m-blob');
      // Counted apart: the lines have a recipe page to send somebody to and
      // the week's own amount has none, so the refusal says them separately.
      expect(usage.lines, 1);
      expect(usage.weeks, 1);
      expect(usage.recipes, [(id: 'sliders', title: 'Sausage Sliders')]);
      expect(usage.any, isTrue);
    });

    test('the bin REFUSES while a line still says the word, and the word '
        'stays live', () async {
      await seedAioli();
      await repo.saveRecipe(parent());

      await expectLater(
        measures.softDeleteRecipeMeasure('m-blob'),
        throwsA(
          isA<RecipeMeasureInUse>()
              .having((e) => e.label, 'label', 'blob')
              .having((e) => e.usage.lines, 'lines', 1)
              .having((e) => e.usage.recipes.length, 'recipes', 1),
        ),
      );
      final row = await db.get(
        'SELECT deleted_at FROM recipe_measure WHERE id = ?',
        ['m-blob'],
      );
      expect(row['deleted_at'], isNull);
    });

    test('the bin retires a word nothing says', () async {
      await seedAioli();
      await measures.softDeleteRecipeMeasure('m-blob');
      expect(await measures.watchRecipeMeasures('aioli').first, isEmpty);
      expect(await measures.countLinesUsing('m-blob'), RecipeMeasureUsage.none);
    });

    test(
      'the deferred door diffs the list, and refuses the same delete',
      () async {
        await seedAioli();
        // A word added and one re-stated through the form's Save.
        await repo.saveRecipe(
          (await repo.watchRecipe('aioli').first)!.copyWith(
            measures: [blob(amount: 12.5), word('ladle', amount: 50)],
          ),
        );
        var loaded = (await repo.watchRecipe('aioli').first)!;
        expect(loaded.measures.map((m) => m.label), ['blob', 'ladle']);
        expect(loaded.measures.first, blob(amount: 12.5));

        // A word dropped from the list is tombstoned…
        await repo.saveRecipe(
          loaded.copyWith(measures: [loaded.measures.first]),
        );
        loaded = (await repo.watchRecipe('aioli').first)!;
        expect(loaded.measures.map((m) => m.label), ['blob']);

        // …unless something still says it, and then the whole save rolls back.
        await repo.saveRecipe(parent());
        await expectLater(
          repo.saveRecipe(
            loaded.copyWith(measures: const [], title: 'Renamed Aioli'),
          ),
          throwsA(isA<RecipeMeasureInUse>()),
        );
        final after = (await repo.watchRecipe('aioli').first)!;
        expect(after.title, 'Romesco Aioli', reason: 'the save rolled back');
        expect(after.measures, hasLength(1));
      },
    );

    test('the deferred door judges a new word against the MAKES the same Save '
        'leaves behind', () async {
      // A `makes` edit and a word arriving in one Save: the yields the gate
      // reads are the ones this Save states, not the ones the recipe used to.
      await seedAioli();
      final loaded = (await repo.watchRecipe('aioli').first)!;
      await expectLater(
        repo.saveRecipe(
          loaded.copyWith(
            yieldUnit: cup,
            yieldQty: 1.25,
            measures: [...loaded.measures, word('ladle', amount: 50)],
          ),
        ),
        throwsA(
          isA<RecipeMeasureRefused>().having(
            (e) => e.code,
            'code',
            'recipe_measure/unit_family',
          ),
        ),
      );
      // …and the other way: the same word lands when the Save says a mass.
      await repo.saveRecipe(
        loaded.copyWith(
          measures: [...loaded.measures, word('ladle', amount: 50)],
        ),
      );
      expect(
        (await repo.watchRecipe('aioli').first)!.measures.map((m) => m.label),
        ['blob', 'ladle'],
      );
    });

    test('a MAKES edit that orphans a live word warns — it never refuses the '
        'Save', () async {
      // ADR-0018 rule 4, in the one place it could be broken. What a batch
      // makes is the recipe's own fact; a gate that re-authored every word on
      // every Save would trap a person in the editor instead of letting the
      // warning do its job.
      await seedAioli();
      await repo.saveRecipe(parent());
      final loaded = (await repo.watchRecipe('aioli').first)!;

      await repo.saveRecipe(loaded.copyWith(yieldUnit: cup, yieldQty: 1.25));
      final after = (await repo.watchRecipe('aioli').first)!;
      expect(after.measures, [blob()], reason: 'the word stays, untouched');
      // Its lines go honestly unresolved, which is the consequence the
      // warning names — not a refusal, and never a guessed share.
      final line =
          (await repo.watchRecipe('sliders').first)!.groups.single.items.single;
      expect(line.componentAmount, isA<ComponentFamilyMismatch>());
    });

    test('a word in a unit this build has never heard of is SKIPPED, never '
        'read as pieces', () async {
      // How a later build reaches this one: a word coined in a unit that is
      // not in this catalog, synced down anyway. The fallback the resolution
      // would otherwise take is `pieces`, which is exactly the confidently
      // wrong batch share rule 7 refuses.
      await seedAioli();
      await repo.saveRecipe(parent());
      await db.execute('UPDATE recipe_measure SET unit = ? WHERE id = ?', [
        'furlong',
        'm-blob',
      ]);

      expect((await repo.watchRecipe('aioli').first)!.measures, isEmpty);
      final line =
          (await repo.watchRecipe('sliders').first)!.groups.single.items.single;
      expect(line.quantity, 3, reason: 'the number is kept');
      expect(line.componentAmount, const ComponentMeasureMissing('m-blob'));
    });

    test('a dropped word is revived rather than duplicated when its id comes '
        'back', () async {
      await seedAioli();
      final loaded = (await repo.watchRecipe('aioli').first)!;
      await repo.saveRecipe(loaded.copyWith(measures: const []));
      await repo.saveRecipe(loaded.copyWith(measures: [blob()]));

      final rows = await db.getAll(
        'SELECT id, deleted_at FROM recipe_measure WHERE recipe_id = ?',
        ['aioli'],
      );
      expect(rows, hasLength(1));
      expect(rows.single['deleted_at'], isNull);
    });
  });

  group('nothing is local-only: every write leaves an upload op', () {
    test('the deferred door queues the measure row', () async {
      await drainCrudQueue(db);
      await seedAioli();
      final ops = await queuedCrudOps(db);
      final put = ops.singleWhere((o) => o['type'] == 'recipe_measure');
      expect(put['op'], 'PUT');
      expect(put['id'], 'm-blob');
      expect((put['data'] as Map)['recipe_id'], 'aioli');
    });

    test(
      'the ＋ door, the re-statement, the reorder and the bin all queue',
      () async {
        await seedAioli();
        await drainCrudQueue(db);

        final ladle = await measures.addRecipeMeasure(
          recipeId: 'aioli',
          label: 'ladle',
          amount: 50,
          unit: g,
        );
        await measures.restateRecipeMeasure(
          measureId: ladle.id,
          label: 'ladle',
          amount: 37.5,
          unit: g,
        );
        await measures.reorderRecipeMeasures('aioli', [ladle.id, 'm-blob']);
        await measures.softDeleteRecipeMeasure(ladle.id);

        final ops = await queuedCrudOps(db);
        expect(
          ops.where((o) => o['type'] == 'recipe_measure'),
          hasLength(greaterThanOrEqualTo(4)),
        );
        // A soft delete is a PATCH stamping the tombstone, never a DELETE: a
        // DELETE is what the connector maps to a server-side removal.
        expect(ops.where((o) => o['op'] == 'DELETE'), isEmpty);
      },
    );

    test('a measured line queues the pointer and a null unit', () async {
      await seedAioli();
      await drainCrudQueue(db);
      await repo.saveRecipe(parent());

      final ops = await queuedCrudOps(db);
      final line = ops.singleWhere(
        (o) => o['type'] == 'recipe_line_item' && o['id'] == 'si1',
      );
      final data = line['data'] as Map;
      expect(data['recipe_measure_id'], 'm-blob');
      expect(data['unit'], isNull);
    });
  });

  group('the watches re-fire when a word moves', () {
    /// Subscribes, waits for the FIRST emission, then runs [mutate] and waits
    /// for the second. Never a sleep-then-mutate: on a loaded machine the edit
    /// lands before the stream's first read and the second emission can never
    /// come.
    Future<List<T>> twoEmissions<T>(
      Stream<T> stream,
      Future<void> Function() mutate,
    ) async {
      final seen = <T>[];
      final first = Completer<void>();
      final both = Completer<void>();
      final sub = stream.listen((value) {
        seen.add(value);
        if (seen.length == 1) first.complete();
        if (seen.length == 2 && !both.isCompleted) both.complete();
      });
      addTearDown(sub.cancel);
      await first.future;
      await mutate();
      await both.future;
      return seen;
    }

    Future<void> restate() => db.execute(
      'UPDATE recipe_measure SET amount = ? WHERE id = ?',
      [12.5, 'm-blob'],
    );

    test('watchRecipe — the parent’s page re-resolves the line', () async {
      await seedAioli();
      await repo.saveRecipe(parent());
      final seen = await twoEmissions(repo.watchRecipe('sliders'), restate);
      final batches = [
        for (final r in seen)
          (r!.groups.single.items.single.componentAmount!
                  as ResolvedComponentAmount)
              .batches,
      ];
      expect(batches.first, closeTo(batchesOf(3), 1e-12));
      expect(batches.last, closeTo(batchesOf(3, blob(amount: 12.5)), 1e-12));
    });

    test('watchRecipe — the target’s own page re-lists its words', () async {
      await seedAioli();
      final seen = await twoEmissions(
        repo.watchRecipe('aioli'),
        () => measures.addRecipeMeasure(
          recipeId: 'aioli',
          label: 'ladle',
          amount: 50,
          unit: g,
        ),
      );
      expect(seen.first!.measures, hasLength(1));
      expect(seen.last!.measures, hasLength(2));
    });

    test(
      'watchRecipes — the Library’s macro summary moves with the word',
      () async {
        await seedAioli();
        await repo.saveRecipe(parent());
        final seen = await twoEmissions(repo.watchRecipes(), restate);
        double kcal(List<RecipeSummary> list) =>
            list.firstWhere((r) => r.id == 'sliders').macros!.perServing!.kcal;
        expect(kcal(seen.last), lessThan(kcal(seen.first)));
      },
    );

    test('watchRecipeCosts — the cost moves with the word', () async {
      await seedAioli();
      await repo.saveRecipe(parent());
      final seen = await twoEmissions(repo.watchRecipeCosts(), restate);
      expect(
        seen.last['sliders']!.totalCents,
        lessThan(seen.first['sliders']!.totalCents!),
      );
    });

    test('watchRecipeMeasures — the word’s own list', () async {
      await seedAioli();
      final seen = await twoEmissions(
        measures.watchRecipeMeasures('aioli'),
        restate,
      );
      expect(seen.first.single, blob());
      expect(seen.last.single, blob(amount: 12.5));
    });
  });
}
