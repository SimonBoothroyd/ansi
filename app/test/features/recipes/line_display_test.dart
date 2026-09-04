import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/line_display.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

LineItem _item(
  String id,
  String ingredientId,
  String name, {
  double? quantity,
  Unit unit = g,
  String? note,
}) => LineItem(
  id: id,
  ingredientId: ingredientId,
  ingredientName: name,
  unit: unit,
  quantity: quantity,
  note: note,
);

void main() {
  group('joinSourceLine (the import review\'s "from source" reference)', () {
    test('elides the measure word both halves print', () {
      // The reported stutter: "2–3 cloves garlic cloves, sliced".
      expect(
        joinSourceLine('2–3 cloves', 'garlic cloves, sliced'),
        '2–3 garlic cloves, sliced',
      );
    });

    test('is case- and plural-insensitive', () {
      expect(
        joinSourceLine('2 Cloves', 'clove of garlic'),
        '2 clove of garlic',
      );
      expect(joinSourceLine('1 tin', 'Tins of tomatoes'), '1 Tins of tomatoes');
    });

    test('elides a multi-word overlap, once', () {
      expect(
        joinSourceLine('2 spring onions', 'spring onions, trimmed'),
        '2 spring onions, trimmed',
      );
    });

    test('leaves a line whose halves share nothing', () {
      expect(joinSourceLine('200g', 'spaghetti'), '200g spaghetti');
      // "tin" is not "tinned" — a near miss is left alone rather than stemmed
      // into a match that would drop a word the source printed.
      expect(
        joinSourceLine('1 x 400g tin', 'tinned chopped tomatoes'),
        '1 x 400g tin tinned chopped tomatoes',
      );
    });

    test('only the LEADING phrase counts — a prep note is a second fact', () {
      expect(
        joinSourceLine('2 cloves', 'garlic, cloves separated'),
        '2 cloves garlic, cloves separated',
      );
    });

    test('an all-overlap amount leaves the ingredient text standing', () {
      expect(joinSourceLine('cloves', 'cloves of garlic'), 'cloves of garlic');
    });

    test('a missing half is not padded', () {
      expect(joinSourceLine('', 'basil leaves'), 'basil leaves');
      expect(joinSourceLine('  ', ''), '');
    });
  });

  test('single-use items each become their own row, in order', () {
    final rows = groupLineUses([
      _item('a', 'chicken', 'Chicken thigh', quantity: 6, unit: pieces),
      _item('b', 'tomato', 'Chopped tomatoes', quantity: 400),
    ]);

    expect(rows, hasLength(2));
    expect(rows[0].ingredientId, 'chicken');
    expect(rows[0].isMultiUse, isFalse);
    expect(rows[1].ingredientName, 'Chopped tomatoes');
  });

  test('same ingredientId folds into one multi-use row at first position', () {
    final rows = groupLineUses([
      _item(
        'a',
        'garlic',
        'Garlic',
        quantity: 2,
        unit: pieces,
        note: 'finely chopped',
      ),
      _item('b', 'tomato', 'Chopped tomatoes', quantity: 400),
      _item(
        'c',
        'garlic',
        'Garlic',
        quantity: 1,
        unit: pieces,
        note: 'sliced, for garnish',
      ),
    ]);

    // Garlic folds (first-occurrence position 0); tomatoes stays its own row.
    expect(rows, hasLength(2));
    expect(rows[0].ingredientId, 'garlic');
    expect(rows[0].isMultiUse, isTrue);
    expect(rows[0].uses, hasLength(2));
    // Notes stay parallel + in order, never merged.
    expect(rows[0].notes, ['finely chopped', 'sliced, for garnish']);
    expect(rows[1].ingredientId, 'tomato');
  });

  test('a use with no note drops its slot rather than dangling', () {
    final rows = groupLineUses([
      _item('a', 'chilli', 'Chilli flakes', note: 'toasted', unit: toTaste),
      _item('b', 'chilli', 'Chilli flakes', unit: toTaste),
    ]);

    expect(rows, hasLength(1));
    expect(rows[0].isMultiUse, isTrue);
    // Only the present note survives — no empty second slot.
    expect(rows[0].notes, ['toasted']);
  });

  test('a component line is its own row, keyed by its target (step 8.6)', () {
    final rows = groupLineUses([
      _item('a', 'garlic', 'Garlic', quantity: 2, unit: pieces),
      const LineItem(
        id: 'b',
        subRecipeId: 'aioli',
        ingredientName: 'Romesco Aioli',
        unit: cup,
        quantity: 0.25,
      ),
    ]);

    expect(rows, hasLength(2));
    expect(rows[1].isComponent, isTrue);
    expect(rows[1].subRecipeId, 'aioli');
    expect(rows[1].ingredientId, isNull);
    expect(rows[1].ingredientName, 'Romesco Aioli');
  });

  test(
    'two references to the same sub-recipe fold like one ingredient does',
    () {
      LineItem component(String id, double qty, String? note) => LineItem(
        id: id,
        subRecipeId: 'aioli',
        ingredientName: 'Romesco Aioli',
        unit: cup,
        quantity: qty,
        note: note,
      );
      final rows = groupLineUses([
        component('a', 0.25, 'in the mix'),
        _item('b', 'tomato', 'Chopped tomatoes', quantity: 400),
        component('c', 0.5, 'to serve'),
      ]);

      expect(rows, hasLength(2));
      expect(rows[0].isMultiUse, isTrue);
      expect(rows[0].subRecipeId, 'aioli');
      expect(rows[0].notes, ['in the mix', 'to serve']);
    },
  );

  test('an ingredient row keeps a null subRecipeId — the XOR, mirrored', () {
    final rows = groupLineUses([
      _item('a', 'garlic', 'Garlic', quantity: 2, unit: pieces),
    ]);
    expect(rows.single.subRecipeId, isNull);
    expect(rows.single.isComponent, isFalse);
    expect(rows.single.ingredientId, 'garlic');
  });
}
