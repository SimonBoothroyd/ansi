import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:ansi/features/recipes/domain/optional_choices.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rice = LineItem(
    id: 'rice',
    ingredientName: 'Rice',
    quantity: 100,
    unit: g,
  );
  const lime = LineItem(
    id: 'lime',
    ingredientName: 'Lime',
    quantity: 2,
    unit: pieces,
    optional: true,
  );

  test('only the optional lines are asked, out until the week says', () {
    final choice = optionalChoices([rice, lime], const []).single;
    expect(choice.uses.uses.single.id, 'lime');
    expect(choice.included, isFalse);
    expect(choice.lineIds, ['lime']);
  });

  test('an include is in, and an exclusion is out', () {
    for (final (action, included) in [
      (LineOverrideAction.include, true),
      (LineOverrideAction.exclude, false),
    ]) {
      final choice = optionalChoices(
        [lime],
        [LineOverride(action: action, recipeLineItemId: 'lime')],
      ).single;
      expect(choice.included, included, reason: action.name);
    }
  });

  test('a stated amount is in, at that amount', () {
    final choice = optionalChoices(
      [lime],
      const [
        LineOverride(
          action: LineOverrideAction.replace,
          recipeLineItemId: 'lime',
          quantity: 3,
          unit: pieces,
        ),
      ],
    ).single;
    expect(choice.included, isTrue);
    expect(choice.lineIds, isEmpty, reason: 'changed in the editor');
    expect(choice.uses.uses.single.quantity, 3);
  });

  test('two optional lines of one food are one choice, in when both are', () {
    LineItem use(String id) => LineItem(
      id: id,
      ingredientId: 'i-lime',
      ingredientName: 'Lime',
      quantity: 1,
      unit: pieces,
      optional: true,
    );
    const first = LineOverride(
      action: LineOverrideAction.include,
      recipeLineItemId: 'a',
    );
    final half = optionalChoices([use('a'), use('b')], const [first]).single;
    expect(half.lineIds, ['a', 'b']);
    expect(half.included, isFalse);

    final both = optionalChoices(
      [use('a'), use('b')],
      const [
        first,
        LineOverride(action: LineOverrideAction.include, recipeLineItemId: 'b'),
      ],
    ).single;
    expect(both.included, isTrue);
  });
}
