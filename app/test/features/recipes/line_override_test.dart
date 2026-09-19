import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

LineItem _line(
  String id, {
  String? ingredientId,
  String name = 'Onion',
  double? quantity = 2,
  Unit? unit = g,
  bool optional = false,
  String? note,
  String? measureId,
  Measure? measure,
  String? recipeMeasureId,
}) => LineItem(
  id: id,
  ingredientId: ingredientId ?? 'ing-$id',
  ingredientName: name,
  unit: recipeMeasureId == null ? unit : null,
  quantity: quantity,
  optional: optional,
  note: note,
  measureId: measureId,
  measure: measure,
  recipeMeasureId: recipeMeasureId,
);

/// A component line said in the target's own word — no catalog unit at all.
LineItem _measured(String id, {double? quantity = 3, String word = 'blob'}) =>
    LineItem(
      id: id,
      subRecipeId: 'aioli',
      ingredientName: 'Romesco Aioli',
      quantity: quantity,
      recipeMeasureId: word,
    );

WeekDraftLine _kept(LineItem line) =>
    (line: line, excluded: false, added: false);

void main() {
  group('diffLineOverrides — recomputed whole, never accumulated', () {
    test('an untouched list produces no rows at all', () {
      final base = [_line('a'), _line('b'), _line('c', optional: true)];
      expect(diffLineOverrides(base: base, draft: base.map(_kept)), isEmpty);
    });

    test('a changed amount is one replace carrying every value', () {
      final base = [_line('onion', unit: pieces)];
      final overrides = diffLineOverrides(
        base: base,
        draft: [_kept(base.single.copyWith(quantity: 3))],
      );
      final row = overrides.single;
      expect(row.action, LineOverrideAction.replace);
      expect(row.recipeLineItemId, 'onion');
      expect(row.quantity, 3);
      expect(row.unit, pieces);
      expect(row.ingredientId, 'ing-onion');
      expect(row.ingredientName, 'Onion');
    });

    test('edited back to the recipe leaves nothing behind', () {
      final base = [_line('onion')];
      final wandered = base.single.copyWith(quantity: 3);
      expect(
        diffLineOverrides(
          base: base,
          draft: [_kept(wandered.copyWith(quantity: 2))],
        ),
        isEmpty,
      );
    });

    test('a swap names the new target, absolutely', () {
      final base = [_line('sausage', name: 'Pork sausage', quantity: 400)];
      final row = diffLineOverrides(
        base: base,
        draft: [
          _kept(
            base.single.copyWith(
              ingredientId: 'ing-mince',
              ingredientName: 'Beef mince, 5%',
            ),
          ),
        ],
      ).single;
      expect(row.action, LineOverrideAction.replace);
      expect(row.ingredientId, 'ing-mince');
      expect(row.ingredientName, 'Beef mince, 5%');
      expect(row.quantity, 400);
      expect(weekChangeOf(row, base.single), WeekChange.swapped);
    });

    test('a note is compared trimmed, and stored trimmed', () {
      final base = [_line('onion', note: 'finely chopped')];
      expect(
        diffLineOverrides(
          base: base,
          draft: [_kept(base.single.copyWith(note: '  finely chopped  '))],
        ),
        isEmpty,
      );
      final row = diffLineOverrides(
        base: base,
        draft: [_kept(base.single.copyWith(note: '  sliced '))],
      ).single;
      expect(row.note, 'sliced');
    });

    test('the bin on a recipe line excludes it', () {
      final base = [_line('wine')];
      final row = diffLineOverrides(
        base: base,
        draft: [(line: base.single, excluded: true, added: false)],
      ).single;
      expect(row.action, LineOverrideAction.exclude);
      expect(row.recipeLineItemId, 'wine');
      expect(row.quantity, isNull);
      expect(row.ingredientId, isNull);
      expect(weekChangeOf(row, base.single), WeekChange.leftOut);
    });

    test('marking a counted line optional is the same exclusion', () {
      // The amount sheet's switch and the bin are one control from two sides:
      // the seam drops the line either way, so one action stores both.
      final base = [_line('wine')];
      final row = diffLineOverrides(
        base: base,
        draft: [_kept(base.single.copyWith(optional: true))],
      ).single;
      expect(row.action, LineOverrideAction.exclude);
    });

    test('an optional line kept is an include, and carries nothing', () {
      final base = [_line('parmesan', optional: true)];
      final row = diffLineOverrides(
        base: base,
        draft: [_kept(base.single.copyWith(optional: false))],
      ).single;
      expect(row.action, LineOverrideAction.include);
      expect(row.recipeLineItemId, 'parmesan');
      expect(row.quantity, isNull);
      expect(weekChangeOf(row, base.single), WeekChange.included);
    });

    test("an optional line left alone stays the recipe's business", () {
      final base = [_line('parmesan', optional: true)];
      expect(
        diffLineOverrides(base: base, draft: [_kept(base.single)]),
        isEmpty,
      );
    });

    test('an optional line ticked in AND changed is one replace', () {
      final base = [_line('parmesan', optional: true, quantity: 30)];
      final rows = diffLineOverrides(
        base: base,
        draft: [_kept(base.single.copyWith(optional: false, quantity: 60))],
      );
      expect(rows, hasLength(1));
      expect(rows.single.action, LineOverrideAction.replace);
      expect(rows.single.quantity, 60);
    });

    test('an added line keeps its own id and takes the foot of the list', () {
      final base = [_line('rice')];
      final basil = _line('draft-basil', name: 'Basil', quantity: 1);
      final rows = diffLineOverrides(
        base: base,
        draft: [
          _kept(base.single),
          (line: basil, excluded: false, added: true),
        ],
      );
      final row = rows.single;
      expect(row.action, LineOverrideAction.add);
      expect(row.id, 'draft-basil');
      expect(row.recipeLineItemId, isNull);
      expect(row.ingredientName, 'Basil');
      expect(row.sortOrder, 0);
      expect(weekChangeOf(row, null), WeekChange.added);
    });

    test('a base line the draft never saw is excluded, not forgotten', () {
      final base = [_line('rice'), _line('wine')];
      final rows = diffLineOverrides(base: base, draft: [_kept(base.first)]);
      expect(rows.single.action, LineOverrideAction.exclude);
      expect(rows.single.recipeLineItemId, 'wine');
    });

    test('a draft line whose recipe line is gone produces nothing', () {
      final ghost = _line('deleted-line');
      expect(diffLineOverrides(base: const [], draft: [_kept(ghost)]), isEmpty);
    });

    test('every action at once, in draft order', () {
      final base = [
        _line('sausage', name: 'Pork sausage', quantity: 400),
        _line('onion'),
        _line('wine'),
        _line('parmesan', optional: true),
        _line('chuck'),
      ];
      final rows = diffLineOverrides(
        base: base,
        draft: [
          _kept(base[0].copyWith(ingredientId: 'ing-mince')),
          _kept(base[1].copyWith(quantity: 3)),
          (line: base[2], excluded: true, added: false),
          _kept(base[3].copyWith(optional: false)),
          _kept(base[4]),
          (
            line: _line('draft-basil', name: 'Basil'),
            excluded: false,
            added: true,
          ),
        ],
      );
      expect(rows.map((r) => r.action), [
        LineOverrideAction.replace,
        LineOverrideAction.replace,
        LineOverrideAction.exclude,
        LineOverrideAction.include,
        LineOverrideAction.add,
      ]);
    });
  });

  group("the week carries a component's own word too", () {
    test('a replace stores the word and no unit beside it', () {
      final base = _measured('a');
      final edited = _measured('a', quantity: 6);
      final overrides = diffLineOverrides(base: [base], draft: [_kept(edited)]);
      final row = overrides.single;
      expect(row.action, LineOverrideAction.replace);
      expect(row.recipeMeasureId, 'blob');
      expect(row.unit, isNull);
      expect(row.quantity, 6);
    });

    test('changing only the WORD is a change like any other', () {
      final overrides = diffLineOverrides(
        base: [_measured('a')],
        draft: [_kept(_measured('a', word: 'ladle'))],
      );
      expect(overrides.single.recipeMeasureId, 'ladle');
    });

    test('an unchanged measured line produces no row at all', () {
      expect(
        diffLineOverrides(
          base: [_measured('a')],
          draft: [_kept(_measured('a'))],
        ),
        isEmpty,
      );
    });

    test('applying it gives the line back, word and all', () {
      final line = applyOverride(
        _measured('a'),
        const LineOverride(
          action: LineOverrideAction.replace,
          recipeLineItemId: 'a',
          recipeMeasureId: 'blob',
          quantity: 6,
        ),
      );
      expect(line.recipeMeasureId, 'blob');
      expect(line.unit, isNull);
      expect(line.quantity, 6);
    });

    test('an added line can be one, and reads back as one', () {
      final added = addedLine(
        const LineOverride(
          id: 'ov',
          action: LineOverrideAction.add,
          subRecipeId: 'aioli',
          ingredientName: 'Romesco Aioli',
          recipeMeasureId: 'blob',
          quantity: 3,
        ),
      );
      expect(added.recipeMeasureId, 'blob');
      expect(added.unit, isNull);
    });

    test('an added line with neither word nor unit still says something', () {
      // Totality: the row is malformed, and a line the model cannot build is
      // worse than one that falls back to a bare count.
      final added = addedLine(
        const LineOverride(
          id: 'ov',
          action: LineOverrideAction.add,
          ingredientName: 'Onion',
          quantity: 1,
        ),
      );
      expect(added.unit, pieces);
      expect(added.recipeMeasureId, isNull);
    });

    test('the draft round-trips: diff, draft, diff again — same rows', () {
      final base = [_measured('a'), _line('b')];
      final overrides = diffLineOverrides(
        base: base,
        draft: [_kept(_measured('a', quantity: 6)), _kept(_line('b'))],
      );
      final again = diffLineOverrides(
        base: base,
        draft: draftLines(base, overrides),
      );
      expect(
        again.map((o) => o.recipeMeasureId),
        overrides.map((o) => o.recipeMeasureId),
      );
      expect(again.map((o) => o.quantity), overrides.map((o) => o.quantity));
    });
  });
}
