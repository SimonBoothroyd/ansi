import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/effective_lines.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

LineItem _line(String id, {bool optional = false, SubRecipeTarget? sub}) =>
    LineItem(
      id: id,
      ingredientId: sub == null ? 'ing-$id' : null,
      subRecipeId: sub?.id,
      subRecipe: sub,
      ingredientName: id,
      unit: sub == null ? g : batches,
      quantity: 1,
      optional: optional,
    );

void main() {
  group('effectiveLines — the one seam every derivation runs over', () {
    test(
      'nothing optional: every line kept, in stored order, nothing dropped',
      () {
        final lines = [_line('a'), _line('b'), _line('c')];
        final result = effectiveLines(lines);
        expect(result.kept, lines);
        expect(result.dropped, isEmpty);
      },
    );

    test('optional lines are dropped WITH a reason; both sides keep order', () {
      final lime = _line('lime', optional: true);
      final coriander = _line('coriander', optional: true);
      final result = effectiveLines([
        _line('rice'),
        lime,
        _line('onion'),
        coriander,
      ]);
      expect(result.kept.map((l) => l.id), ['rice', 'onion']);
      expect(result.dropped, [
        (line: lime, reason: LineDropReason.optional),
        (line: coriander, reason: LineDropReason.optional),
      ]);
    });

    test('no overrides: the recipe as it stands', () {
      final lines = [_line('rice'), _line('lime', optional: true)];
      expect(effectiveLines(lines).kept.map((l) => l.id), ['rice']);
    });

    test(
      "droppedNames prints the ingredient name — or a component's title",
      () {
        const aioli = SubRecipeTarget(id: 'r-aioli', title: 'Romesco Aioli');
        final result = effectiveLines([
          _line('lime', optional: true),
          _line('c', optional: true, sub: aioli),
          _line('rice'),
        ]);
        expect(droppedNames(result, LineDropReason.optional), [
          'lime',
          'Romesco Aioli',
        ]);
      },
    );
  });

  group("effectiveLines — this week's variant, applied", () {
    test("exclude drops the line with the week's own reason", () {
      final wine = _line('wine');
      final result = effectiveLines(
        [_line('rice'), wine],
        overrides: const [
          LineOverride(
            action: LineOverrideAction.exclude,
            recipeLineItemId: 'wine',
          ),
        ],
      );
      expect(result.kept.map((l) => l.id), ['rice']);
      expect(result.dropped, [(line: wine, reason: LineDropReason.thisWeek)]);
      expect(droppedNames(result, LineDropReason.thisWeek), ['wine']);
    });

    test("replace carries absolute values, and keeps the line's id", () {
      final result = effectiveLines(
        [_line('sausage')],
        overrides: const [
          LineOverride(
            action: LineOverrideAction.replace,
            recipeLineItemId: 'sausage',
            ingredientId: 'ing-mince',
            ingredientName: 'Beef mince',
            quantity: 400,
            unit: g,
            note: 'browned',
          ),
        ],
      );
      final line = result.kept.single;
      expect(line.id, 'sausage');
      expect(line.ingredientId, 'ing-mince');
      expect(line.ingredientName, 'Beef mince');
      expect(line.quantity, 400);
      expect(line.note, 'browned');
    });

    test('a swap off a RETIRED ingredient clears the broken-link flag — the '
        'week re-pointed the line, which is the repair', () {
      final broken = _line('kraut').copyWith(ingredientDeleted: true);
      final result = effectiveLines(
        [broken],
        overrides: const [
          LineOverride(
            action: LineOverrideAction.replace,
            recipeLineItemId: 'kraut',
            ingredientId: 'ing-cabbage',
            ingredientName: 'Red cabbage',
            quantity: 200,
            unit: g,
          ),
        ],
      );
      expect(result.kept.single.ingredientDeleted, isFalse);
    });

    test('an amount changed for the week does not un-break the line — the row '
        'it names is still gone', () {
      final broken = _line('kraut').copyWith(ingredientDeleted: true);
      final result = effectiveLines(
        [broken],
        overrides: const [
          LineOverride(
            action: LineOverrideAction.replace,
            recipeLineItemId: 'kraut',
            ingredientId: 'ing-kraut',
            quantity: 300,
            unit: g,
          ),
        ],
      );
      expect(result.kept.single.ingredientDeleted, isTrue);
    });

    test('include keeps an optional line, and clears the flag so a second '
        'pass is a no-op', () {
      final result = effectiveLines(
        [_line('parmesan', optional: true)],
        overrides: const [
          LineOverride(
            action: LineOverrideAction.include,
            recipeLineItemId: 'parmesan',
          ),
        ],
      );
      expect(result.kept.single.optional, isFalse);
      expect(result.dropped, isEmpty);
      expect(effectiveLines(result.kept).kept, result.kept);
    });

    test('a replaced optional line counts too', () {
      final result = effectiveLines(
        [_line('parmesan', optional: true)],
        overrides: const [
          LineOverride(
            action: LineOverrideAction.replace,
            recipeLineItemId: 'parmesan',
            ingredientId: 'ing-parmesan',
            ingredientName: 'Parmesan, grated',
            quantity: 60,
            unit: g,
          ),
        ],
      );
      expect(result.kept.single.quantity, 60);
      expect(result.kept.single.optional, isFalse);
    });

    test("add lands at the end, carrying the override row's id", () {
      final result = effectiveLines(
        [_line('rice')],
        overrides: const [
          LineOverride(
            id: 'ov-basil',
            action: LineOverrideAction.add,
            ingredientId: 'ing-basil',
            ingredientName: 'Basil',
            quantity: 1,
            unit: pieces,
            note: 'torn',
          ),
        ],
      );
      expect(result.kept.map((l) => l.id), ['rice', 'ov-basil']);
      expect(result.kept.last.ingredientName, 'Basil');
      expect(result.kept.last.note, 'torn');
    });

    test("an override for another recipe's line is simply not found", () {
      // The guard behind "a variant never leaks into another week": the seam
      // only ever applies an override whose line is in front of it, so a set
      // read for the wrong week changes nothing rather than half-applying.
      final lines = [_line('rice'), _line('lime', optional: true)];
      final result = effectiveLines(
        lines,
        overrides: const [
          LineOverride(
            action: LineOverrideAction.exclude,
            recipeLineItemId: 'some-other-recipes-line',
          ),
          LineOverride(
            action: LineOverrideAction.include,
            recipeLineItemId: 'also-not-here',
          ),
        ],
      );
      expect(result.kept, effectiveLines(lines).kept);
      expect(result.dropped, effectiveLines(lines).dropped);
    });
  });
}
