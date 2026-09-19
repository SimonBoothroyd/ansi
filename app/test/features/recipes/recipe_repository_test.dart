import 'dart:async';
import 'dart:io';

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/data/recipe_repository_impl.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:ansi/features/recipes/domain/effective_lines.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

Recipe _sampleRecipe() => const Recipe(
  id: 'r1',
  title: 'Weeknight Curry',
  servingsBase: 2,
  steps: ['Fry the onion', 'Add spices'],
  keepsForDays: 4,
  groups: [
    IngredientGroup(
      id: 'g1',
      name: 'For the sauce',
      items: [
        LineItem(
          id: 'i1',
          ingredientId: 'ing-onion',
          ingredientName: 'Onion',
          unit: pieces,
          quantity: 1,
        ),
        LineItem(
          id: 'i2',
          ingredientId: 'ing-salt',
          ingredientName: 'Salt',
          unit: toTaste,
        ),
      ],
    ),
    IngredientGroup(
      id: 'g2',
      items: [
        LineItem(
          id: 'i3',
          ingredientId: 'ing-rice',
          ingredientName: 'Rice',
          unit: g,
          quantity: 150,
          note: 'rinsed',
        ),
      ],
    ),
  ],
);

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteRecipeRepository repo;

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqliteRecipeRepository(db, householdId: 'h');
    // Line-item names resolve via a join to `ingredient`, so the referenced
    // vocab rows must exist (they always do in the app — the picker only picks
    // existing ingredients).
    for (final (id, name) in const [
      ('ing-onion', 'Onion'),
      ('ing-salt', 'Salt'),
      ('ing-rice', 'Rice'),
    ]) {
      await db.execute(
        'INSERT INTO ingredient (id, household_id, canonical_name, '
        'default_unit, status, source, match_text) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [id, 'h', name, 'g', 'complete', 'seed', name.toLowerCase()],
      );
    }
  });

  tearDown(() => closeTestDb(db, dir));

  test('saveRecipe round-trips the full aggregate', () async {
    await repo.saveRecipe(_sampleRecipe());

    final loaded = await repo.watchRecipe('r1').first;
    expect(loaded, isNotNull);
    expect(loaded!.title, 'Weeknight Curry');
    expect(loaded.servingsBase, 2);
    expect(loaded.steps, ['Fry the onion', 'Add spices']);
    expect(loaded.keepsForDays, 4);

    expect(loaded.groups.map((g) => g.name), ['For the sauce', null]);
    expect(loaded.groups[0].items.map((i) => i.ingredientName), [
      'Onion',
      'Salt',
    ]);
    final salt = loaded.groups[0].items[1];
    expect(salt.quantity, isNull);
    expect(salt.unit, toTaste);
    final rice = loaded.groups[1].items.single;
    expect(rice.quantity, 150);
    expect(rice.unit, g);
    expect(rice.note, 'rinsed');
  });

  test('a note edited on an existing line round-trips, and blank clears it '
      'rather than leaving the old words', () async {
    await repo.saveRecipe(_sampleRecipe());
    final before = await repo.watchRecipe('r1').first;

    // What the editor's card writes: the same line, a different note — and on
    // a line that had none, so the UPDATE path carries both directions.
    final noted = before!.copyWith(
      groups: [
        before.groups[0].copyWith(
          items: [
            before.groups[0].items[0].copyWith(note: 'finely chopped'),
            before.groups[0].items[1],
          ],
        ),
        before.groups[1].copyWith(
          items: [before.groups[1].items.single.copyWith(note: null)],
        ),
      ],
    );
    await repo.saveRecipe(noted);

    final after = await repo.watchRecipe('r1').first;
    expect(after!.groups[0].items[0].note, 'finely chopped');
    expect(after.groups[1].items.single.note, isNull);
    // The line is the same line — the id is what keeps its method chips.
    expect(after.groups[0].items[0].id, 'i1');
  });

  test('a moved line round-trips: the order is what was left, the ids are the '
      'ones that were there, and the emptied group is still a group', () async {
    await repo.saveRecipe(_sampleRecipe());
    final before = await repo.watchRecipe('r1').first;

    // What the drag produces: Rice leaves the second group for the top of the
    // first, and the group it left stays.
    final rice = before!.groups[1].items.single;
    await repo.saveRecipe(
      before.copyWith(
        groups: [
          before.groups[0].copyWith(items: [rice, ...before.groups[0].items]),
          before.groups[1].copyWith(items: const []),
        ],
      ),
    );

    // Reopened from the database, which reads `ORDER BY sort_order` — so this
    // is `sort_order`, written from list position and read back.
    final loaded = await repo.watchRecipe('r1').first;
    expect(loaded!.groups[0].items.map((i) => i.id), ['i3', 'i1', 'i2']);
    expect(loaded.groups[1].items, isEmpty);
    expect(loaded.groups.map((g) => g.id), [
      'g1',
      'g2',
    ], reason: 'a group emptied by a move is not swept');
    // A move is an UPDATE on the same row: nothing was deleted and re-made,
    // which is what keeps every method chip pointing where it did.
    final tombstones = await db.getAll(
      'SELECT id FROM ps_data__recipe_line_item',
    );
    expect(tombstones, hasLength(3));
  });

  test('optional survives save → load, and a flipped flag is a child-diff '
      'UPDATE on the same row', () async {
    final recipe = _sampleRecipe();
    final sauce = recipe.groups[0];
    await repo.saveRecipe(
      recipe.copyWith(
        groups: [
          sauce.copyWith(
            items: [sauce.items[0], sauce.items[1].copyWith(optional: true)],
          ),
          recipe.groups[1],
        ],
      ),
    );

    var loaded = (await repo.watchRecipe('r1').first)!;
    expect(loaded.groups[0].items.map((i) => i.optional), [false, true]);
    expect(loaded.groups[1].items.single.optional, isFalse);
    // The computed summary already reads the flag: the salt line is named
    // as optional, not as the imprecise line it would otherwise be.
    expect(loaded.macros!.optionalLines, 1);
    expect(loaded.macros!.impreciseLines, 0);
    expect(
      loaded.macros!.notes
          .where((n) => n.reason == MacroLineReason.optional)
          .single
          .name,
      'Salt',
    );
    // …and the list row's own loader agrees.
    final row = (await repo.watchRecipes().first).single;
    expect(row.macros!.optionalLines, 1);

    // Flip both lines and re-save: kept ids, so the diff must UPDATE them —
    // a flag is a change like any other field.
    final g = loaded.groups[0];
    await repo.saveRecipe(
      loaded.copyWith(
        groups: [
          g.copyWith(
            items: [
              g.items[0].copyWith(optional: true),
              g.items[1].copyWith(optional: false),
            ],
          ),
          loaded.groups[1],
        ],
      ),
    );
    loaded = (await repo.watchRecipe('r1').first)!;
    expect(loaded.groups[0].items.map((i) => i.id), ['i1', 'i2']);
    expect(loaded.groups[0].items.map((i) => i.optional), [true, false]);
    final stored = await db.getAll(
      'SELECT id, optional FROM recipe_line_item WHERE id IN (?, ?) '
      'ORDER BY id',
      ['i1', 'i2'],
    );
    expect(stored.map((r) => r['optional']), [1, 0]);
  });

  test('an imported recipe keeps its tokenized method across a save', () async {
    // An import-shaped recipe: the method lives in `methodSteps` (token stream)
    // and the plain `steps` list is empty. Editing anything else and saving
    // must not erase it — serializing the empty plain list would.
    final imported = _sampleRecipe().copyWith(
      steps: const [],
      methodSteps: const [
        MethodStep(
          tokens: [
            MethodToken.text(s: 'Fry the '),
            MethodToken.ref(refs: ['i1'], label: 'onion'),
            MethodToken.text(s: ' for '),
            MethodToken.timer(lowSeconds: 300, highSeconds: 480),
          ],
        ),
      ],
    );
    await repo.saveRecipe(imported);

    var loaded = await repo.watchRecipe('r1').first;
    expect(loaded!.steps, isEmpty);
    expect(loaded.methodSteps, hasLength(1));

    // The round-trip survives a second save of what was loaded — the editor's
    // save path (title edit, method untouched).
    await repo.saveRecipe(loaded.copyWith(title: 'Renamed'));
    loaded = await repo.watchRecipe('r1').first;
    expect(loaded!.title, 'Renamed');
    expect(loaded.methodSteps, hasLength(1));
    final tokens = loaded.methodSteps!.single.tokens;
    expect(tokens, hasLength(4));
    final refToken = tokens.whereType<MethodRef>().single;
    expect(refToken.refs, ['i1']);
    expect(refToken.label, 'onion');
    expect(refToken.amountRule, ChipAmountRule.showAmount);
    final timer = tokens.whereType<MethodTimer>().single;
    expect(timer.lowSeconds, 300);
    expect(timer.highSeconds, 480);
  });

  test('a measure line round-trips: id persisted, measure resolved', () async {
    await db.execute(
      'INSERT INTO ingredient_measure '
      '(id, household_id, ingredient_id, label, basis_amount, sort_order) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      ['m-onion', 'h', 'ing-onion', 'onion, medium', 110, 0],
    );
    final recipe = _sampleRecipe();
    final withMeasure = recipe.copyWith(
      groups: [
        recipe.groups.first.copyWith(
          items: [
            recipe.groups.first.items.first.copyWith(
              quantity: 2,
              measureId: 'm-onion',
            ),
            ...recipe.groups.first.items.skip(1),
          ],
        ),
        ...recipe.groups.skip(1),
      ],
    );
    await repo.saveRecipe(withMeasure);

    final loaded = await repo.watchRecipe('r1').first;
    final onion = loaded!.groups.first.items.first;
    expect(onion.measureId, 'm-onion');
    expect(onion.measure, isNotNull);
    expect(onion.measure!.label, 'onion, medium');
    expect(onion.measure!.amount, 110);
    expect(onion.unit, pieces); // the honest count fallback stays stored
  });

  test('an unresolved measure_id survives a re-save (never '
      'stripped)', () async {
    // The measure row hasn't synced (or was deleted): the line loads with
    // measure null but keeps its id, and an unrelated edit re-saves it.
    final recipe = _sampleRecipe();
    final withMeasure = recipe.copyWith(
      groups: [
        recipe.groups.first.copyWith(
          items: [
            recipe.groups.first.items.first.copyWith(measureId: 'm-ghost'),
            ...recipe.groups.first.items.skip(1),
          ],
        ),
        ...recipe.groups.skip(1),
      ],
    );
    await repo.saveRecipe(withMeasure);

    final loaded = await repo.watchRecipe('r1').first;
    final onion = loaded!.groups.first.items.first;
    expect(onion.measure, isNull);
    expect(onion.measureId, 'm-ghost');

    await repo.saveRecipe(loaded.copyWith(title: 'Renamed'));
    final reloaded = await repo.watchRecipe('r1').first;
    expect(reloaded!.groups.first.items.first.measureId, 'm-ghost');
  });

  test('a DELETED measure is told apart from one that has not '
      'synced', () async {
    await db.execute(
      'INSERT INTO ingredient_measure '
      '(id, household_id, ingredient_id, label, basis_amount, sort_order, '
      'deleted_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      ['m-gone', 'h', 'ing-onion', 'onion, medium', 110, 0, '2026-01-01'],
    );
    final recipe = _sampleRecipe();
    await repo.saveRecipe(
      recipe.copyWith(
        groups: [
          recipe.groups.first.copyWith(
            items: [
              recipe.groups.first.items.first.copyWith(measureId: 'm-gone'),
              recipe.groups.first.items.last.copyWith(measureId: 'm-ghost'),
            ],
          ),
          ...recipe.groups.skip(1),
        ],
      ),
    );

    final items = (await repo.watchRecipe('r1').first)!.groups.first.items;
    // Both read as their stored count; only one of them is ever coming back.
    expect(items.first.measure, isNull);
    expect(items.first.measureDeleted, isTrue);
    expect(items.last.measure, isNull);
    expect(items.last.measureDeleted, isFalse, reason: 'no row at all yet');
  });

  test('watchRecipe re-fires when a measure is renamed', () async {
    await db.execute(
      'INSERT INTO ingredient_measure '
      '(id, household_id, ingredient_id, label, basis_amount, sort_order) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      ['m-onion', 'h', 'ing-onion', 'onion, medium', 110, 0],
    );
    final recipe = _sampleRecipe();
    await repo.saveRecipe(
      recipe.copyWith(
        groups: [
          recipe.groups.first.copyWith(
            items: [
              recipe.groups.first.items.first.copyWith(
                quantity: 2,
                measureId: 'm-onion',
              ),
              ...recipe.groups.first.items.skip(1),
            ],
          ),
          ...recipe.groups.skip(1),
        ],
      ),
    );

    // The UPDATE must land AFTER the watch has read the table once, or the
    // rename is already there when the stream opens, `distinct` sees one
    // label and the test waits out its own timeout. Waiting on the first
    // emission says that; a fixed delay only guesses at how long a loaded
    // machine takes to get there.
    final labels = <String?>[];
    final first = Completer<void>();
    final both = Completer<void>();
    final sub = repo
        .watchRecipe('r1')
        .map((r) => r?.groups.first.items.first.measure?.label)
        .distinct()
        .listen((label) {
          labels.add(label);
          if (labels.length == 1) first.complete();
          if (labels.length == 2 && !both.isCompleted) both.complete();
        });
    addTearDown(sub.cancel);

    await first.future;
    await db.execute('UPDATE ingredient_measure SET label = ? WHERE id = ?', [
      'onion, large',
      'm-onion',
    ]);
    await both.future;
    expect(labels, ['onion, medium', 'onion, large']);
  });

  test('watchRecipes lists saved recipes (summaries)', () async {
    await repo.saveRecipe(_sampleRecipe());
    await repo.saveRecipe(
      const Recipe(
        id: 'r2',
        title: 'Salad',
        servingsBase: 4,
        groups: [IngredientGroup(id: 'r2-g1')],
      ),
    );

    final list = await repo.watchRecipes().first;
    expect(list.map((r) => r.title), containsAll(['Weeknight Curry', 'Salad']));
    expect(list.firstWhere((r) => r.id == 'r2').servingsBase, 4);
  });

  test('summaries carry a computed per-serving macro summary', () async {
    // Rice and Onion carry per-100 g macros, but the sample's Onion line is
    // a bare count (unbridgeable without a measure) — so the summary must be
    // honestly incomplete, never a partial total. Its Salt line says "to
    // taste", which seam D6 excludes BY RULE: it is not a stub line, not a
    // failed conversion, and not a reason the summary refuses.
    for (final id in ['ing-rice', 'ing-onion']) {
      await db.execute('UPDATE ingredient SET macros = ? WHERE id = ?', [
        '{"kcal":130,"protein":2.7,"carb":28,"fat":0.3}',
        id,
      ]);
    }
    await repo.saveRecipe(_sampleRecipe());

    var summary = (await repo.watchRecipes().first).single.macros!;
    expect(summary.incomplete, isTrue);
    expect(summary.stubLines, 0);
    expect(summary.impreciseLines, 1); // Salt, to taste
    // Onion: a bare count with no measure — its own D6 reason, not a
    // failed conversion.
    expect(summary.countLinesWithoutMeasure, 1);
    expect(summary.unconvertibleLines, 0);
    // …and the refusal NAMES the line it is waiting on (seam D5), by the
    // display name the page uses.
    expect(summary.notes.map((n) => n.name), ['Onion', 'Salt']);
    expect(summary.notes.first.reason, MacroLineReason.needsWeight);
    expect(summary.notes.first.lineId, 'i1');

    // A recipe whose every line joins computes per-serving numbers: 150 g of
    // rice across 2 servings.
    await repo.saveRecipe(
      const Recipe(
        id: 'r-rice',
        title: 'Plain rice',
        servingsBase: 2,
        groups: [
          IngredientGroup(
            id: 'gr1',
            items: [
              LineItem(
                id: 'ri1',
                ingredientId: 'ing-rice',
                ingredientName: 'Rice',
                unit: g,
                quantity: 150,
              ),
            ],
          ),
        ],
      ),
    );
    final list = await repo.watchRecipes().first;
    summary = list.firstWhere((r) => r.id == 'r-rice').macros!;
    expect(summary.incomplete, isFalse);
    expect(summary.perServing!.kcal, closeTo(97.5, 1e-9)); // 130 × 1.5 / 2
    expect(summary.perServing!.protein, closeTo(2.025, 1e-9));
  });

  test('the nutrition read carries the row PIECE WEIGHT, so a bare count '
      'joins the total (ADR-0015)', () async {
    // Same sample, same bare "1 Onion" line as above — the only difference is
    // one number on the vocab row, which is the whole claim of ADR-0015.
    for (final id in ['ing-rice', 'ing-onion']) {
      await db.execute('UPDATE ingredient SET macros = ? WHERE id = ?', [
        '{"kcal":130,"protein":2.7,"carb":28,"fat":0.3}',
        id,
      ]);
    }
    await db.execute(
      'UPDATE ingredient SET piece_basis_amount = ? WHERE id = ?',
      [110, 'ing-onion'],
    );
    await repo.saveRecipe(_sampleRecipe());

    // 1 onion × 110 g + 150 g rice = 260 g × 1.3 kcal/g = 338 kcal, over two
    // servings. The Salt line is still excluded BY RULE and still does not
    // make the summary refuse.
    final summary = (await repo.watchRecipes().first).single.macros!;
    expect(summary.countLinesWithoutMeasure, 0);
    expect(summary.incomplete, isFalse);
    expect(summary.perServing!.kcal, closeTo(169, 1e-9));
    expect(summary.impreciseLines, 1);

    // The aggregate reads the column through its own query, so it is asserted
    // through its own read rather than assumed from the list row's.
    final aggregate = (await repo.watchRecipe('r1').first)!.macros!;
    expect(aggregate, summary);
  });

  test('a recipe saved with no lines can never render ~0 kcal', () async {
    // The picker-row bug this pins: an EMPTY line set once summed to a
    // "complete" zero total, so a just-created recipe fabricated
    // "~0 kcal · 0P /serving" end-to-end. Empty means incomplete (noLines).
    await repo.saveRecipe(
      const Recipe(id: 'r-bare', title: 'Bare', servingsBase: 4),
    );
    await repo.saveRecipe(
      const Recipe(
        id: 'r-empty-group',
        title: 'Empty group',
        servingsBase: 4,
        groups: [IngredientGroup(id: 'ge1')],
      ),
    );

    final list = await repo.watchRecipes().first;
    for (final id in ['r-bare', 'r-empty-group']) {
      final summary = list.firstWhere((r) => r.id == id).macros!;
      expect(summary.incomplete, isTrue, reason: id);
      expect(summary.perServing, isNull, reason: id);
      expect(summary.noLines, isTrue, reason: id);
    }
  });

  test('the list re-fires when vocab macros change under it', () async {
    await repo.saveRecipe(_sampleRecipe());
    // Same rule as the rename above: edit only once the watch has fired once,
    // so the second fire is the thing being tested rather than a race with
    // the first.
    var emissions = 0;
    final first = Completer<void>();
    final both = Completer<void>();
    final sub = repo.watchRecipes().listen((_) {
      emissions++;
      if (emissions == 1) first.complete();
      if (emissions == 2 && !both.isCompleted) both.complete();
    });
    addTearDown(sub.cancel);

    await first.future;
    await db.execute('UPDATE ingredient SET macros = ? WHERE id = ?', [
      '{"kcal":130,"protein":2.7,"carb":28,"fat":0.3}',
      'ing-rice',
    ]);
    await both.future;
    expect(emissions, 2); // the vocab edit re-fired the summaries
  });

  test(
    'the recipe aggregate carries the same macro summary as its list row',
    () async {
      for (final id in ['ing-rice', 'ing-onion']) {
        await db.execute('UPDATE ingredient SET macros = ? WHERE id = ?', [
          '{"kcal":130,"protein":2.7,"carb":28,"fat":0.3}',
          id,
        ]);
      }
      await repo.saveRecipe(_sampleRecipe());
      await repo.saveRecipe(
        const Recipe(
          id: 'r-rice',
          title: 'Plain rice',
          servingsBase: 2,
          groups: [
            IngredientGroup(
              id: 'gr1',
              items: [
                LineItem(
                  id: 'ri1',
                  ingredientId: 'ing-rice',
                  ingredientName: 'Rice',
                  unit: g,
                  quantity: 150,
                ),
              ],
            ),
          ],
        ),
      );

      // The panel and the picker row must never disagree about the same
      // recipe: both read the one summation over the same rows.
      final rows = {
        for (final r in await repo.watchRecipes().first) r.id: r.macros,
      };
      for (final id in ['r1', 'r-rice']) {
        final page = (await repo.watchRecipe(id).first)!.macros;
        expect(page, rows[id], reason: id);
      }

      final complete = (await repo.watchRecipe('r-rice').first)!.macros!;
      expect(complete.incomplete, isFalse);
      expect(complete.perServing!.kcal, closeTo(97.5, 1e-9)); // 130 × 1.5 / 2
      final incomplete = (await repo.watchRecipe('r1').first)!.macros!;
      expect(incomplete.incomplete, isTrue);
      expect(incomplete.impreciseLines, 1); // Salt, to taste — excluded by rule
      expect(incomplete.stubLines, 0);
      expect(
        incomplete.countLinesWithoutMeasure,
        1,
      ); // Onion: count, no measure
      expect(incomplete.unconvertibleLines, 0);
      // The two surfaces agreeing INCLUDES the names now (seam D5): a picker
      // row and the page must call the same line the same thing.
      expect(incomplete.notes.map((n) => n.name), ['Onion', 'Salt']);
    },
  );

  test('a recipe page with no lines is incomplete, never ~0 kcal', () async {
    await repo.saveRecipe(
      const Recipe(id: 'r-bare', title: 'Bare', servingsBase: 4),
    );
    final macros = (await repo.watchRecipe('r-bare').first)!.macros!;
    expect(macros.noLines, isTrue);
    expect(macros.perServing, isNull);
  });

  test('the recipe page re-fires when vocab macros change under it', () async {
    await repo.saveRecipe(
      const Recipe(
        id: 'r-rice',
        title: 'Plain rice',
        servingsBase: 2,
        groups: [
          IngredientGroup(
            id: 'gr1',
            items: [
              LineItem(
                id: 'ri1',
                ingredientId: 'ing-rice',
                ingredientName: 'Rice',
                unit: g,
                quantity: 150,
              ),
            ],
          ),
        ],
      ),
    );
    final recipes = StreamIterator(repo.watchRecipe('r-rice'));
    expect(await recipes.moveNext(), isTrue);
    expect(recipes.current!.macros!.incomplete, isTrue); // no macros yet

    await db.execute('UPDATE ingredient SET macros = ? WHERE id = ?', [
      '{"kcal":130,"protein":2.7,"carb":28,"fat":0.3}',
      'ing-rice',
    ]);
    // The panel is derived from the watched aggregate, so a vocab row
    // gaining macros turns the badge into numbers without a page reload.
    expect(await recipes.moveNext(), isTrue);
    expect(recipes.current!.macros!.perServing!.kcal, closeTo(97.5, 1e-9));
    await recipes.cancel();
  });

  test('a tombstoned ingredient reads as a stub line on the page', () async {
    await db.execute('UPDATE ingredient SET macros = ? WHERE id = ?', [
      '{"kcal":130,"protein":2.7,"carb":28,"fat":0.3}',
      'ing-rice',
    ]);
    await repo.saveRecipe(
      const Recipe(
        id: 'r-rice',
        title: 'Plain rice',
        servingsBase: 2,
        groups: [
          IngredientGroup(
            id: 'gr1',
            items: [
              LineItem(
                id: 'ri1',
                ingredientId: 'ing-rice',
                ingredientName: 'Rice',
                unit: g,
                quantity: 150,
              ),
            ],
          ),
        ],
      ),
    );
    expect(
      (await repo.watchRecipe('r-rice').first)!.macros!.incomplete,
      isFalse,
    );

    await db.execute('UPDATE ingredient SET deleted_at = ? WHERE id = ?', [
      DateTime.now().toUtc().toIso8601String(),
      'ing-rice',
    ]);
    // A tombstoned vocab row must not keep feeding a total the picker rows
    // already refuse to compute (their join drops it).
    final macros = (await repo.watchRecipe('r-rice').first)!.macros!;
    expect(macros.incomplete, isTrue);
    expect(macros.stubLines, 1);
  });

  test('a line whose ingredient was RETIRED is still returned, named, and '
      'flagged — never dropped and never blank', () async {
    await repo.saveRecipe(_sampleRecipe());
    await db.execute('UPDATE ingredient SET deleted_at = ? WHERE id = ?', [
      DateTime.now().toUtc().toIso8601String(),
      'ing-onion',
    ]);

    final loaded = await repo.watchRecipe('r1').first;
    final items = loaded!.groups.first.items;
    // The line is where it was. A reader who cannot see it cannot fix it,
    // and a recipe silently one line short is the incident this guards.
    expect(items.map((i) => i.id), ['i1', 'i2']);
    final onion = items.first;
    expect(onion.ingredientId, 'ing-onion', reason: 'the id is kept verbatim');
    expect(onion.ingredientName, 'Onion', reason: 'the last known name');
    expect(onion.ingredientDeleted, isTrue);
    expect(
      items.last.ingredientDeleted,
      isFalse,
      reason: 'a live row is not tarred by its neighbour',
    );

    // Nothing is derived from the retired row, and the total says which line
    // it is waiting on — in the words that name the fix.
    final notes = loaded.macros!.notes;
    expect(
      notes
          .where((n) => n.reason == MacroLineReason.removedIngredient)
          .map((n) => n.name),
      ['Onion'],
    );
  });

  test('re-pointing the line at a live row clears the flag', () async {
    await repo.saveRecipe(_sampleRecipe());
    await db.execute('UPDATE ingredient SET deleted_at = ? WHERE id = ?', [
      DateTime.now().toUtc().toIso8601String(),
      'ing-onion',
    ]);
    final broken = await repo.watchRecipe('r1').first;
    final line = broken!.groups.first.items.first;

    // What the editor's picker does: same line id, a live ingredient.
    await repo.saveRecipe(
      broken.copyWith(
        groups: [
          broken.groups.first.copyWith(
            items: [
              line.copyWith(
                ingredientId: 'ing-rice',
                ingredientName: 'Rice',
                ingredientDeleted: false,
              ),
              ...broken.groups.first.items.skip(1),
            ],
          ),
          ...broken.groups.skip(1),
        ],
      ),
    );

    final repaired = (await repo.watchRecipe('r1').first)!.groups.first.items;
    expect(repaired.first.id, 'i1', reason: 'a re-point keeps the line id');
    expect(repaired.first.ingredientDeleted, isFalse);
    expect(repaired.first.ingredientName, 'Rice');
  });

  test('setFavorite round-trips through the summary row', () async {
    await repo.saveRecipe(_sampleRecipe());
    expect((await repo.watchRecipes().first).single.favorite, isFalse);

    await repo.setFavorite('r1', true);
    expect((await repo.watchRecipes().first).single.favorite, isTrue);

    await repo.setFavorite('r1', false);
    expect((await repo.watchRecipes().first).single.favorite, isFalse);
  });

  test('setFiling re-shelves without touching anything else', () async {
    await repo.saveRecipe(_sampleRecipe());
    final before = (await repo.watchRecipe('r1').first)!;

    await repo.setFiling('r1', 'b9', 's9');
    final moved = (await repo.watchRecipe('r1').first)!;
    expect(moved.bookId, 'b9');
    expect(moved.sectionId, 's9');

    // A narrow write, not a save: re-shelving a recipe must not become an
    // edit of every field it holds — including ones the mover never loaded.
    expect(moved.title, before.title);
    expect(moved.servingsBase, before.servingsBase);
    expect(moved.groups.length, before.groups.length);
    expect(moved.groups.first.items.length, before.groups.first.items.length);

    // Null files it unsectioned, which is what crossing a book always means.
    await repo.setFiling('r1', 'b9', null);
    expect((await repo.watchRecipe('r1').first)!.sectionId, isNull);
  });

  test('saveRecipe replaces children rather than duplicating them', () async {
    await repo.saveRecipe(_sampleRecipe());

    // Re-save with a single group holding one item.
    await repo.saveRecipe(
      _sampleRecipe().copyWith(
        groups: [
          const IngredientGroup(
            id: 'g1',
            name: 'Simplified',
            items: [
              LineItem(
                id: 'i9',
                ingredientId: 'ing-onion',
                ingredientName: 'Onion',
                unit: pieces,
                quantity: 3,
              ),
            ],
          ),
        ],
      ),
    );

    final loaded = await repo.watchRecipe('r1').first;
    expect(loaded!.groups.length, 1);
    expect(loaded.groups.single.name, 'Simplified');
    expect(loaded.groups.single.items.single.quantity, 3);

    // No stale *live* rows left behind — dropped children are tombstoned
    // (deleted_at set), never hard-deleted, so the delete syncs upstream.
    final itemCount = await db.get(
      'SELECT count(*) AS c FROM recipe_line_item WHERE deleted_at IS NULL',
    );
    expect(itemCount['c'], 1);
    final groupCount = await db.get(
      'SELECT count(*) AS c FROM ingredient_group WHERE deleted_at IS NULL',
    );
    expect(groupCount['c'], 1);
    final tombstones = await db.get(
      'SELECT count(*) AS c FROM recipe_line_item WHERE deleted_at IS NOT NULL',
    );
    expect(tombstones['c'], 3, reason: 'i1, i2 and i3 were all dropped');
  });

  test('an edited re-save queues no DELETE for kept children', () async {
    await repo.saveRecipe(_sampleRecipe());
    await drainCrudQueue(db);

    // A title-only edit keeps every child id. The old delete + re-insert
    // implementation queued DELETE-then-PUT per child; the connector maps
    // DELETE to a server tombstone the later PUT never cleared, so every
    // ingredient vanished on other devices after any edit.
    await repo.saveRecipe(_sampleRecipe().copyWith(title: 'Renamed'));

    final ops = await queuedCrudOps(db);
    expect(
      ops.where((o) => o['op'] == 'DELETE'),
      isEmpty,
      reason: 'kept child ids must never round-trip through DELETE',
    );

    // The children still exist, live, exactly once.
    final itemCount = await db.get(
      'SELECT count(*) AS c FROM recipe_line_item WHERE deleted_at IS NULL',
    );
    expect(itemCount['c'], 3);
  });

  test(
    'dropping a child on re-save queues a tombstone PATCH, not a DELETE',
    () async {
      await repo.saveRecipe(_sampleRecipe());
      await drainCrudQueue(db);

      final edited = _sampleRecipe();
      await repo.saveRecipe(
        edited.copyWith(
          groups: [
            edited.groups.first, // keep g1 (i1, i2); drop g2 (i3)
          ],
        ),
      );

      final ops = await queuedCrudOps(db);
      expect(ops.where((o) => o['op'] == 'DELETE'), isEmpty);

      final itemTombstone = ops.singleWhere(
        (o) =>
            o['type'] == 'recipe_line_item' &&
            o['id'] == 'i3' &&
            o['op'] == 'PATCH',
      );
      expect((itemTombstone['data'] as Map)['deleted_at'], isNotNull);
      final groupTombstone = ops.singleWhere(
        (o) =>
            o['type'] == 'ingredient_group' &&
            o['id'] == 'g2' &&
            o['op'] == 'PATCH',
      );
      expect((groupTombstone['data'] as Map)['deleted_at'], isNotNull);
    },
  );

  test('watchRecipe re-fires when an ingredient is renamed', () async {
    await repo.saveRecipe(_sampleRecipe());

    final recipes = StreamIterator(repo.watchRecipe('r1'));
    addTearDown(recipes.cancel);

    expect(await recipes.moveNext(), isTrue);
    expect(recipes.current?.groups.first.items.first.ingredientName, 'Onion');

    // A server-side vocab rename arrives as a plain UPDATE on `ingredient`;
    // the open recipe page must re-assemble (the watch has to name the
    // ingredient table with a selected column, or SQLite drops the join).
    await db.execute('UPDATE ingredient SET canonical_name = ? WHERE id = ?', [
      'Brown Onion',
      'ing-onion',
    ]);
    expect(await recipes.moveNext(), isTrue);
    expect(
      recipes.current?.groups.first.items.first.ingredientName,
      'Brown Onion',
    );
  });

  test('watchRecipe re-fires when its section is renamed', () async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.execute(
      'INSERT INTO book (id, household_id, name, sort_order, created_at, '
      'updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      ['b1', 'h', 'Our Cookbook', 0, now, now],
    );
    await db.execute(
      'INSERT INTO book_section (id, household_id, book_id, name, sort_order, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      ['s1', 'h', 'b1', 'Weeknight', 0, now, now],
    );
    await repo.saveRecipe(
      _sampleRecipe().copyWith(bookId: 'b1', sectionId: 's1'),
    );

    // The breadcrumb is a join, so the watched query has to name the filing
    // tables too — otherwise a rename leaves the recipe page stale.
    final recipes = StreamIterator(repo.watchRecipe('r1'));
    addTearDown(recipes.cancel);

    expect(await recipes.moveNext(), isTrue);
    expect(recipes.current?.sectionName, 'Weeknight');

    await db.execute('UPDATE book_section SET name = ? WHERE id = ?', [
      'Sunday Batch',
      's1',
    ]);
    expect(await recipes.moveNext(), isTrue);
    expect(recipes.current?.sectionName, 'Sunday Batch');

    await db.execute('UPDATE book SET name = ? WHERE id = ?', [
      'The Big Book',
      'b1',
    ]);
    expect(await recipes.moveNext(), isTrue);
    expect(recipes.current?.bookName, 'The Big Book');
  });

  test('deleteRecipe soft-deletes: gone from list and lookup', () async {
    await repo.saveRecipe(_sampleRecipe());
    await repo.deleteRecipe('r1');

    expect(await repo.watchRecipe('r1').first, isNull);
    expect(await repo.watchRecipes().first, isEmpty);

    // Row remains as a tombstone.
    final row = await db.get('SELECT deleted_at FROM recipe WHERE id = ?', [
      'r1',
    ]);
    expect(row['deleted_at'], isNotNull);
  });

  group('nested recipes', () {
    /// The Romesco Aioli: serves 4, makes 1 cup, keeps 5 days, one line.
    Future<void> seedAioli({
      double? yieldQty = 1,
      Unit? yieldUnit = cup,
      double? yieldQty2,
      Unit? yieldUnit2,
    }) => repo.saveRecipe(
      Recipe(
        id: 'aioli',
        title: 'Romesco Aioli',
        servingsBase: 4,
        keepsForDays: 5,
        yieldQty: yieldQty,
        yieldUnit: yieldUnit,
        yieldQty2: yieldQty2,
        yieldUnit2: yieldUnit2,
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

    /// A parent whose second line is a component of the aioli.
    Recipe parent({double? quantity = 0.25, Unit unit = cup}) => Recipe(
      id: 'sliders',
      title: 'Sausage Sliders',
      servingsBase: 8,
      groups: [
        IngredientGroup(
          id: 'sg',
          items: [
            const LineItem(
              id: 'si1',
              ingredientId: 'ing-onion',
              ingredientName: 'Onion',
              unit: pieces,
              quantity: 2,
            ),
            LineItem(
              id: 'si2',
              subRecipeId: 'aioli',
              ingredientName: 'Romesco Aioli',
              unit: unit,
              quantity: quantity,
            ),
          ],
        ),
      ],
    );

    test(
      'saveRecipe persists the XOR: sub_recipe_id set, ingredient_id null',
      () async {
        await seedAioli();
        await repo.saveRecipe(parent());

        final row = await db.get(
          'SELECT ingredient_id, sub_recipe_id, measure_id, unit, quantity '
          'FROM recipe_line_item WHERE id = ?',
          ['si2'],
        );
        expect(row['ingredient_id'], isNull);
        expect(row['sub_recipe_id'], 'aioli');
        expect(row['measure_id'], isNull);
        expect(row['unit'], 'cup');
        expect(row['quantity'], 0.25);

        // The sibling ingredient line keeps the other half of the XOR.
        final sibling = await db.get(
          'SELECT ingredient_id, sub_recipe_id FROM recipe_line_item '
          'WHERE id = ?',
          ['si1'],
        );
        expect(sibling['ingredient_id'], 'ing-onion');
        expect(sibling['sub_recipe_id'], isNull);
      },
    );

    test(
      'a component line never carries a measure, even if one is passed',
      () async {
        await seedAioli();
        await repo.saveRecipe(
          parent().copyWith(
            groups: [
              const IngredientGroup(
                id: 'sg',
                items: [
                  LineItem(
                    id: 'si2',
                    subRecipeId: 'aioli',
                    measureId: 'm-stray',
                    ingredientName: 'Romesco Aioli',
                    unit: cup,
                    quantity: 0.25,
                  ),
                ],
              ),
            ],
          ),
        );
        final row = await db.get(
          'SELECT measure_id FROM recipe_line_item WHERE id = ?',
          ['si2'],
        );
        expect(row['measure_id'], isNull);
      },
    );

    test(
      'a component line can be optional, and the seam names its title',
      () async {
        await seedAioli();
        await repo.saveRecipe(
          parent().copyWith(
            groups: [
              IngredientGroup(
                id: 'sg',
                items: [
                  parent().groups[0].items[0],
                  parent().groups[0].items[1].copyWith(optional: true),
                ],
              ),
            ],
          ),
        );

        final row = await db.get(
          'SELECT optional, sub_recipe_id FROM recipe_line_item WHERE id = ?',
          ['si2'],
        );
        expect(row['optional'], 1);
        expect(row['sub_recipe_id'], 'aioli');

        final loaded = (await repo.watchRecipe('sliders').first)!;
        final component = loaded.groups[0].items[1];
        expect(component.optional, isTrue);
        expect(component.isComponent, isTrue);

        // The one seam every derivation shares drops it, and names the recipe
        // it points at rather than the text the line stored.
        final effective = effectiveLines(loaded.groups[0].items);
        expect(effective.kept.map((l) => l.id), ['si1']);
        expect(droppedNames(effective, LineDropReason.optional), [
          'Romesco Aioli',
        ]);
      },
    );

    test(
      'an UPDATE converts an ingredient line into a component and back',
      () async {
        await seedAioli();
        // First saved as an ingredient line…
        await repo.saveRecipe(
          const Recipe(
            id: 'sliders',
            title: 'Sausage Sliders',
            servingsBase: 8,
            groups: [
              IngredientGroup(
                id: 'sg',
                items: [
                  LineItem(
                    id: 'si2',
                    ingredientId: 'ing-onion',
                    ingredientName: 'Onion',
                    unit: pieces,
                    quantity: 1,
                  ),
                ],
              ),
            ],
          ),
        );
        // …then re-picked as a component (D7: re-picking IS the conversion).
        await repo.saveRecipe(
          parent().copyWith(
            groups: [
              const IngredientGroup(
                id: 'sg',
                items: [
                  LineItem(
                    id: 'si2',
                    subRecipeId: 'aioli',
                    ingredientName: 'Romesco Aioli',
                    unit: cup,
                    quantity: 0.25,
                  ),
                ],
              ),
            ],
          ),
        );
        var row = await db.get(
          'SELECT ingredient_id, sub_recipe_id FROM recipe_line_item '
          'WHERE id = ?',
          ['si2'],
        );
        expect(row['ingredient_id'], isNull);
        expect(row['sub_recipe_id'], 'aioli');

        // …and back again — neither id is ever left set alongside the other.
        await repo.saveRecipe(
          const Recipe(
            id: 'sliders',
            title: 'Sausage Sliders',
            servingsBase: 8,
            groups: [
              IngredientGroup(
                id: 'sg',
                items: [
                  LineItem(
                    id: 'si2',
                    ingredientId: 'ing-onion',
                    ingredientName: 'Onion',
                    unit: pieces,
                    quantity: 1,
                  ),
                ],
              ),
            ],
          ),
        );
        row = await db.get(
          'SELECT ingredient_id, sub_recipe_id FROM recipe_line_item '
          'WHERE id = ?',
          ['si2'],
        );
        expect(row['ingredient_id'], 'ing-onion');
        expect(row['sub_recipe_id'], isNull);
      },
    );

    test('saveRecipe round-trips both yield denominations', () async {
      await seedAioli(
        yieldQty: 250,
        yieldUnit: g,
        yieldQty2: 16,
        yieldUnit2: tbsp,
      );
      final loaded = (await repo.watchRecipe('aioli').first)!;
      expect(loaded.yieldQty, 250);
      expect(loaded.yieldUnit, g);
      expect(loaded.yieldQty2, 16);
      expect(loaded.yieldUnit2, tbsp);
      expect(loaded.yields, [(qty: 250.0, unit: g), (qty: 16.0, unit: tbsp)]);
    });

    test('a yield-less recipe still saves and loads', () async {
      await seedAioli(yieldQty: null, yieldUnit: null);
      final loaded = (await repo.watchRecipe('aioli').first)!;
      expect(loaded.yieldQty, isNull);
      expect(loaded.yields, isEmpty);
    });

    test('watchRecipe joins the target title AND its yields, so the batch math '
        'resolves on the loaded line', () async {
      await seedAioli();
      await repo.saveRecipe(parent());

      final loaded = (await repo.watchRecipe('sliders').first)!;
      final line = loaded.groups.single.items[1];
      expect(line.isComponent, isTrue);
      expect(line.subRecipeId, 'aioli');
      expect(line.ingredientName, 'Romesco Aioli');
      expect(line.subRecipe!.title, 'Romesco Aioli');
      expect(line.subRecipe!.yields, [(qty: 1.0, unit: cup)]);
      expect(
        (line.componentAmount! as ResolvedComponentAmount).batches,
        closeTo(0.25, 1e-12),
      );
    });

    test(
      'renaming the target re-fires the parent’s watch with the new title',
      () async {
        await seedAioli();
        await repo.saveRecipe(parent());

        // The target's title and yields arrive through a join, so the watched
        // query has to name — and SELECT a column from — the `recipe sub`
        // alias, or a rename leaves the parent's page stale.
        final recipes = StreamIterator(repo.watchRecipe('sliders'));
        addTearDown(recipes.cancel);

        expect(await recipes.moveNext(), isTrue);
        expect(
          recipes.current?.groups.single.items[1].subRecipe?.title,
          'Romesco Aioli',
        );

        await db.execute('UPDATE recipe SET title = ? WHERE id = ?', [
          'Romesco Aioli (new)',
          'aioli',
        ]);
        expect(await recipes.moveNext(), isTrue);
        expect(
          recipes.current?.groups.single.items[1].subRecipe?.title,
          'Romesco Aioli (new)',
        );

        // A yield edit on the TARGET moves the parent's batch math too.
        await db.execute('UPDATE recipe SET yield_qty = ? WHERE id = ?', [
          2,
          'aioli',
        ]);
        expect(await recipes.moveNext(), isTrue);
        final line = recipes.current!.groups.single.items[1];
        expect(
          (line.componentAmount! as ResolvedComponentAmount).batches,
          closeTo(0.125, 1e-12),
        );
      },
    );

    test(
      'a dangling link degrades to plain text and derives nothing',
      () async {
        await seedAioli();
        await repo.saveRecipe(parent());
        await repo.deleteRecipe('aioli');

        final loaded = (await repo.watchRecipe('sliders').first)!;
        final line = loaded.groups.single.items[1];
        expect(line.subRecipeId, 'aioli'); // the stored id is kept verbatim
        expect(line.subRecipe, isNull);
        expect(
          line.componentAmount,
          isNull,
        ); // nothing derived, nothing invented
      },
    );

    test(
      'the macro panel folds a resolvable component across recipes',
      () async {
        // Rice: 100 kcal/100 g. The aioli is 240 g of it (240 kcal over 4
        // servings); ¼ batch is 60 kcal, plus 2 onions the parent also has.
        await db.execute(
          'UPDATE ingredient SET macros = ?, macros_basis = ? WHERE id = ?',
          ['{"kcal":100,"protein":0,"carb":0,"fat":0}', 'per_100g', 'ing-rice'],
        );
        await db.execute(
          'UPDATE ingredient SET macros = ?, macros_basis = ?, '
          'default_unit = ? WHERE id = ?',
          [
            '{"kcal":40,"protein":0,"carb":0,"fat":0}',
            'per_100g',
            'g',
            'ing-onion',
          ],
        );
        await seedAioli();
        // The parent's onion line in grams, so it bridges honestly.
        await repo.saveRecipe(
          parent().copyWith(
            groups: [
              const IngredientGroup(
                id: 'sg',
                items: [
                  LineItem(
                    id: 'si1',
                    ingredientId: 'ing-onion',
                    ingredientName: 'Onion',
                    unit: g,
                    quantity: 100,
                  ),
                  LineItem(
                    id: 'si2',
                    subRecipeId: 'aioli',
                    ingredientName: 'Romesco Aioli',
                    unit: cup,
                    quantity: 0.25,
                  ),
                ],
              ),
            ],
          ),
        );

        final loaded = (await repo.watchRecipe('sliders').first)!;
        expect(loaded.macros!.incomplete, isFalse);
        // (40 kcal onion + 60 kcal aioli share) / 8 servings.
        expect(loaded.macros!.perServing!.kcal, closeTo(12.5, 1e-9));
      },
    );

    test('a component of a yield-less recipe makes the parent incomplete with '
        'the sub-recipe reason, never a 1× total', () async {
      await db.execute(
        'UPDATE ingredient SET macros = ?, macros_basis = ? WHERE id = ?',
        ['{"kcal":100,"protein":0,"carb":0,"fat":0}', 'per_100g', 'ing-rice'],
      );
      await seedAioli(yieldQty: null, yieldUnit: null);
      await repo.saveRecipe(
        parent().copyWith(
          groups: [
            const IngredientGroup(
              id: 'sg',
              items: [
                LineItem(
                  id: 'si2',
                  subRecipeId: 'aioli',
                  ingredientName: 'Romesco Aioli',
                  unit: cup,
                  quantity: 0.25,
                ),
              ],
            ),
          ],
        ),
      );
      final loaded = (await repo.watchRecipe('sliders').first)!;
      expect(loaded.macros!.incomplete, isTrue);
      expect(loaded.macros!.subRecipesUnresolved, 1);
      expect(loaded.macros!.perServing, isNull);
    });

    test('watchRecipes carries the yields onto the summary row', () async {
      await seedAioli();
      final summaries = await repo.watchRecipes().first;
      final aioli = summaries.firstWhere((s) => s.id == 'aioli');
      expect(aioli.yieldQty, 1);
      expect(aioli.yieldUnit, cup);
      expect(aioli.yields, [(qty: 1.0, unit: cup)]);
    });

    group('usedIn (the tab rows and the delete refusal, one query)', () {
      test('is empty for a recipe nothing points at', () async {
        await seedAioli();
        expect(await repo.usedIn('aioli'), isEmpty);
      });

      test(
        'names each referencing recipe with its amount and batch share',
        () async {
          await seedAioli();
          await repo.saveRecipe(parent());
          await repo.saveRecipe(
            const Recipe(
              id: 'toasts',
              title: 'Romesco Toasts',
              servingsBase: 2,
              groups: [
                IngredientGroup(
                  id: 'tg',
                  items: [
                    LineItem(
                      id: 'ti1',
                      subRecipeId: 'aioli',
                      ingredientName: 'Romesco Aioli',
                      unit: batches,
                      quantity: 1,
                    ),
                  ],
                ),
              ],
            ),
          );

          final uses = await repo.usedIn('aioli');
          expect(
            uses,
            hasLength(2),
          ); // the delete refusal's "used in 2 recipes"
          // Ordered by parent title.
          expect(uses.map((u) => u.title), [
            'Romesco Toasts',
            'Sausage Sliders',
          ]);
          final sliders = uses.firstWhere((u) => u.recipeId == 'sliders');
          expect(sliders.quantity, 0.25);
          expect(sliders.unit, cup);
          expect(
            (sliders.amount as ResolvedComponentAmount).batches,
            closeTo(0.25, 1e-12),
          );
          expect(sliders.lineId, 'si2');
          final toasts = uses.firstWhere((u) => u.recipeId == 'toasts');
          expect((toasts.amount as ResolvedComponentAmount).batches, 1);
        },
      );

      test(
        'a yield-less target still lists its uses, honestly unresolved',
        () async {
          await seedAioli(yieldQty: null, yieldUnit: null);
          await repo.saveRecipe(parent());
          final use = (await repo.usedIn('aioli')).single;
          expect(use.amount, const ComponentYieldMissing());
        },
      );

      test('a deleted parent drops off the count', () async {
        await seedAioli();
        await repo.saveRecipe(parent());
        expect(await repo.usedIn('aioli'), hasLength(1));
        await repo.deleteRecipe('sliders');
        expect(await repo.usedIn('aioli'), isEmpty);
      });

      test('a removed component line drops off the count', () async {
        await seedAioli();
        await repo.saveRecipe(parent());
        await repo.saveRecipe(
          parent().copyWith(groups: const [IngredientGroup(id: 'sg')]),
        );
        expect(await repo.usedIn('aioli'), isEmpty);
      });
    });

    group('componentLinkWouldCycle (the client half)', () {
      test('a fresh link is allowed', () async {
        await seedAioli();
        await repo.saveRecipe(parent());
        expect(
          await repo.componentLinkWouldCycle(
            recipeId: 'aioli',
            subRecipeId: 'unrelated',
          ),
          isFalse,
        );
      });

      test('a self-link is refused', () async {
        await seedAioli();
        expect(
          await repo.componentLinkWouldCycle(
            recipeId: 'aioli',
            subRecipeId: 'aioli',
          ),
          isTrue,
        );
      });

      test(
        'a link the target already reaches back through is refused',
        () async {
          await seedAioli();
          await repo.saveRecipe(parent()); // sliders → aioli
          // Linking the aioli to the sliders would close the loop.
          expect(
            await repo.componentLinkWouldCycle(
              recipeId: 'aioli',
              subRecipeId: 'sliders',
            ),
            isTrue,
          );
        },
      );

      test('a soft-deleted link is not an edge', () async {
        await seedAioli();
        await repo.saveRecipe(parent());
        await repo.saveRecipe(
          parent().copyWith(groups: const [IngredientGroup(id: 'sg')]),
        );
        expect(
          await repo.componentLinkWouldCycle(
            recipeId: 'aioli',
            subRecipeId: 'sliders',
          ),
          isFalse,
        );
      });
    });
  });

  group('cook and total times', () {
    test('round-trip through saveRecipe, on insert and on update', () async {
      await repo.saveRecipe(
        _sampleRecipe().copyWith(cookTimeSeconds: 2100, totalTimeSeconds: 4200),
      );
      final loaded = (await repo.watchRecipe('r1').first)!;
      expect((loaded.cookTimeSeconds, loaded.totalTimeSeconds), (2100, 4200));

      // The editor's path: open, change something else, save the aggregate.
      await repo.saveRecipe(
        loaded.copyWith(title: 'Renamed', totalTimeSeconds: 4500),
      );
      final again = (await repo.watchRecipe('r1').first)!;
      expect((again.cookTimeSeconds, again.totalTimeSeconds), (2100, 4500));
      // …and clearing one writes a null, never a stale number.
      await repo.saveRecipe(again.copyWith(cookTimeSeconds: null));
      expect((await repo.watchRecipe('r1').first)!.cookTimeSeconds, isNull);
    });

    test('the times an import wrote survive an editor re-save', () async {
      // What the import commit writes and the editor used to be blind to:
      // before the entity carried these, an editor save left the columns
      // alone by luck of the UPDATE list rather than by reading them.
      await db.execute(
        'INSERT INTO recipe (id, household_id, title, servings_base, steps, '
        'cook_time_seconds, total_time_seconds) '
        "VALUES ('imp', 'h', 'Imported', 2, '[]', 1500, 2400)",
      );
      final loaded = (await repo.watchRecipe('imp').first)!;
      expect((loaded.cookTimeSeconds, loaded.totalTimeSeconds), (1500, 2400));

      await repo.saveRecipe(loaded.copyWith(title: 'Imported, edited'));
      final row = await db.get(
        'SELECT cook_time_seconds, total_time_seconds FROM recipe WHERE id = ?',
        ['imp'],
      );
      expect(row['cook_time_seconds'], 1500);
      expect(row['total_time_seconds'], 2400);
    });
  });
}
