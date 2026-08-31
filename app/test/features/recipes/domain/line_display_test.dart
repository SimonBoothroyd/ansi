import 'package:flutter_test/flutter_test.dart';
import 'package:mise/core/units/units.dart';
import 'package:mise/features/recipes/domain/line_display.dart';
import 'package:mise/features/recipes/domain/recipe.dart';

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
}
