import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/unit_choice.dart';
import 'package:ansi/core/units/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UnitOption', () {
    test('labels itself as the catalog does, and is value-equal', () {
      expect(const UnitOption(cup).label, 'cup');
      expect(const UnitOption(flOz).label, 'fl oz');
      expect(const UnitOption(g), const UnitOption(g));
      expect(const UnitOption(g), isNot(const UnitOption(kg)));
    });
  });

  group('MeasureOption', () {
    const potato = Measure(id: 'm1', label: 'potato, large', amount: 299);

    test('says what one comes to, in the basis unit of the row', () {
      expect(const MeasureOption(potato).label, 'potato, large (299 g)');
      expect(
        const MeasureOption(Measure(id: 'm3', label: 'jar', amount: 340)).label,
        'jar (340 g)',
      );
    });

    test('says the size once — a word that already states it keeps it', () {
      // The household's own style puts the size IN the word where a container
      // comes in two of them, and appending would say it twice in two unit
      // systems (`can (14.5 oz) (411 g)`). The rule is
      // [measureWordWithSize]'s, and lifting the option out of the ingredient
      // feature did not leave it behind.
      expect(
        const MeasureOption(
          Measure(
            id: 'm2',
            label: 'can (400 ml)',
            amount: 400,
            basis: MacrosBasis.perMl,
          ),
        ).label,
        'can (400 ml)',
      );
      expect(
        const MeasureOption(
          Measure(id: 'm4', label: 'can (14.5 oz)', amount: 411),
        ).label,
        'can (14.5 oz)',
      );
      // Brackets that are not a size still take the weight.
      expect(
        const MeasureOption(
          Measure(id: 'm5', label: 'can (drained)', amount: 411),
        ).label,
        'can (drained) (411 g)',
      );
    });

    test('identity is the row, not the words on it', () {
      // The label follows a rename; the chip a stored line reopens on must
      // not, or an edit to the word would orphan every line saying it.
      expect(
        const MeasureOption(potato),
        const MeasureOption(Measure(id: 'm1', label: 'spud', amount: 1)),
      );
      expect(
        const MeasureOption(potato),
        isNot(
          const MeasureOption(
            Measure(id: 'm2', label: 'potato, large', amount: 299),
          ),
        ),
      );
    });
  });

  group('RecipeMeasureOption', () {
    const blob = RecipeMeasure(
      id: 'r1',
      recipeId: 'aioli',
      label: 'blob',
      perBatch: 20,
    );

    test('carries the bare word — what one comes to is said elsewhere', () {
      expect(const RecipeMeasureOption(blob).label, 'blob');
    });

    test('identity is the row, so a re-stated word keeps its chip', () {
      expect(
        const RecipeMeasureOption(blob),
        const RecipeMeasureOption(
          RecipeMeasure(
            id: 'r1',
            recipeId: 'aioli',
            label: 'blob',
            perBatch: 24,
          ),
        ),
      );
    });

    test("an ingredient's door refuses one rather than inventing a unit", () {
      expect(() => notAWordForAnIngredient(blob), throwsStateError);
    });
  });

  test('a choice is one of the sealed kinds — a switch stays exhaustive', () {
    String kindOf(UnitChoice choice) => switch (choice) {
      UnitOption() => 'unit',
      MeasureOption() => 'measure',
      RecipeMeasureOption() => 'recipe measure',
    };
    expect(kindOf(const UnitOption(g)), 'unit');
    expect(
      kindOf(const MeasureOption(Measure(id: 'm', label: 'clove', amount: 3))),
      'measure',
    );
    expect(
      kindOf(
        const RecipeMeasureOption(
          RecipeMeasure(id: 'r', recipeId: 'a', label: 'blob', perBatch: 20),
        ),
      ),
      'recipe measure',
    );
  });
}
