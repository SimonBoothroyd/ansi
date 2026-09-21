/// The world the recipe-measure tests share: an aioli that makes 300 g, its
/// word "a blob is 15 g" (a twentieth of a batch), and the sliders that say it.
library;

import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:powersync/powersync.dart';

const aioliYield = (qty: 300.0, unit: g);

/// The blob for a const context; [blob] re-states it.
const blobWord = RecipeMeasure(
  id: 'm-blob',
  recipeId: 'aioli',
  label: 'blob',
  amount: 15,
  unit: g,
);

RecipeMeasure blob({String id = 'm-blob', double amount = 15, Unit unit = g}) =>
    RecipeMeasure(
      id: id,
      recipeId: 'aioli',
      label: 'blob',
      amount: amount,
      unit: unit,
    );

/// The aioli as a component line sees it, before any word is attached.
const aioliTarget = SubRecipeTarget(
  id: 'aioli',
  title: 'Romesco Aioli',
  yieldQty: 300,
  yieldUnit: g,
);

/// What [count] of [word] comes to in batches, through the app's own
/// resolution, so an expectation follows the word when it is re-stated.
double batchesOf(double count, [RecipeMeasure word = blobWord]) =>
    (resolveComponentAmount(
              quantity: count,
              unit: null,
              yields: const [aioliYield],
              recipeMeasureId: word.id,
              measures: [word],
            )
            as ResolvedComponentAmount)
        .batches;

/// The aioli itself: one 240 g line of rice and the household's [words].
Recipe aioliRecipe({List<RecipeMeasure> words = const [blobWord]}) => Recipe(
  id: 'aioli',
  title: 'Romesco Aioli',
  servingsBase: 4,
  keepsForDays: 5,
  yieldQty: aioliYield.qty,
  yieldUnit: aioliYield.unit,
  measures: words,
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
);

/// A parent whose only line asks for the aioli: [quantity] of the word
/// [measureId] by default, or of [unit] when the word is null.
Recipe sliders({
  double? quantity = 3,
  String? measureId = 'm-blob',
  Unit? unit,
  SubRecipeTarget? target,
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
          subRecipe: target,
          ingredientName: 'Romesco Aioli',
          quantity: quantity,
          unit: unit,
          recipeMeasureId: measureId,
        ),
      ],
    ),
  ],
);

/// Rice with per-gram macros and one receipt price, so the aioli has figures
/// for a parent to take a share of.
Future<void> seedPricedRice(PowerSyncDatabase db) async {
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
}
