import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/scaling.dart';
import 'package:flutter_test/flutter_test.dart';

LineItem _line(String name, double? qty, Unit unit) => LineItem(
  id: name,
  ingredientId: name,
  ingredientName: name,
  unit: unit,
  quantity: qty,
);

void main() {
  group('scaleFactorFor', () {
    test('is target / base', () {
      const r = Recipe(id: 'r', title: 'x', servingsBase: 4);
      expect(scaleFactorFor(r, 6), closeTo(1.5, 1e-9));
    });
  });

  group('scaleLineItem', () {
    test('multiplies a precise quantity', () {
      final scaled = scaleLineItem(_line('flour', 200, g), 1.5);
      expect(scaled.quantity, closeTo(300, 1e-9));
      expect(scaled.unit, g);
    });

    test('leaves imprecise units unchanged (never invent a number)', () {
      final scaled = scaleLineItem(_line('salt', null, toTaste), 3);
      expect(scaled.quantity, isNull);
      expect(scaled.unit, toTaste);
    });

    test('leaves a numberless precise line untouched', () {
      // e.g. "1 piece" scales fine, but a null quantity has nothing to scale.
      final scaled = scaleLineItem(_line('egg', null, pieces), 2);
      expect(scaled.quantity, isNull);
    });

    test('scales count units linearly', () {
      final scaled = scaleLineItem(_line('egg', 2, pieces), 2);
      expect(scaled.quantity, closeTo(4, 1e-9));
    });

    test("scales a component line said in its target's own word", () {
      // `2 blob` has no catalog unit, so no Quantity; a blob is a fixed
      // amount, so doubling the recipe doubles the blobs.
      const line = LineItem(
        id: 'butter',
        subRecipeId: 'mb',
        subRecipe: SubRecipeTarget(
          id: 'mb',
          title: 'Miso butter',
          yieldQty: 150,
          yieldUnit: g,
          measures: [
            RecipeMeasure(
              id: 'm-blob',
              recipeId: 'mb',
              label: 'blob',
              amount: 15,
              unit: g,
            ),
          ],
        ),
        ingredientName: 'Miso butter',
        quantity: 2,
        recipeMeasureId: 'm-blob',
      );
      final scaled = scaleLineItem(line, 2);
      expect(scaled.quantity, closeTo(4, 1e-9));
      expect(scaled.unit, isNull);
      expect(scaled.recipeMeasureId, 'm-blob');
    });

    test('scales a word line whose word has gone, keeping no unit', () {
      // The target no longer has `m-blob`: the number still reads (see
      // `amountOfLine`), so it still scales; nothing is re-read as a count.
      const line = LineItem(
        id: 'butter',
        subRecipeId: 'mb',
        ingredientName: 'Miso butter',
        quantity: 3,
        recipeMeasureId: 'm-blob',
      );
      expect(scaleLineItem(line, 1.5).quantity, closeTo(4.5, 1e-9));
    });
  });

  group('scaleGroups', () {
    final recipe = Recipe(
      id: 'r',
      title: 'Curry',
      servingsBase: 2,
      groups: [
        IngredientGroup(
          id: 'g1',
          name: 'For the sauce',
          items: [_line('onion', 1, pieces), _line('cumin', 1, tsp)],
        ),
        IngredientGroup(id: 'g2', items: [_line('salt', null, toTaste)]),
      ],
    );

    test('scales every item and preserves group + item order', () {
      final groups = scaleGroups(recipe, 4); // ×2

      expect(groups.map((g) => g.id), ['g1', 'g2']);
      expect(groups[0].name, 'For the sauce');
      expect(groups[0].items.map((i) => i.ingredientName), ['onion', 'cumin']);
      expect(groups[0].items[0].quantity, closeTo(2, 1e-9));
      expect(groups[0].items[1].quantity, closeTo(2, 1e-9));
      expect(groups[1].items[0].quantity, isNull); // imprecise untouched
    });

    test('does not mutate the source recipe', () {
      scaleGroups(recipe, 10);
      expect(recipe.groups[0].items[0].quantity, 1);
    });
  });
}
