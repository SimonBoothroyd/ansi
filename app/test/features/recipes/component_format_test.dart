/// The component copy every 8.6 surface speaks (step 8.6, board frames b · d).
/// A share of a batch is either stated or refused — never a guessed `1×`.
library;

import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:ansi/features/recipes/presentation/component_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('batchShareText', () {
    test('whole runs count as batches', () {
      expect(batchShareText(1), '1 batch');
      expect(batchShareText(2), '2 batches');
    });

    test('a fraction reads as a share of one', () {
      expect(batchShareText(0.25), '¼ of a batch');
    });
  });

  group('yieldPillLabels', () {
    test('nothing stated, nothing said', () {
      expect(yieldPillLabels(const []), isEmpty);
    });

    test('one denomination is one pill', () {
      expect(yieldPillLabels([(qty: 1, unit: cup)]), ['makes 1 cup']);
    });

    test('the second pill continues the sentence', () {
      expect(yieldPillLabels([(qty: 250, unit: g), (qty: 16, unit: tbsp)]), [
        'makes 250 g',
        '· 16 tbsp',
      ]);
    });
  });

  group('componentConversionLine', () {
    test('resolves against the yield it went through', () {
      expect(
        componentConversionLine(
          quantity: 0.25,
          unit: cup,
          yields: [(qty: 1, unit: cup)],
        ),
        '¼ cup = ¼ of a batch · makes 1 cup',
      );
    });

    test('a batch-denominated line needs no line at all', () {
      expect(
        componentConversionLine(quantity: 1, unit: batches, yields: const []),
        isNull,
      );
    });

    test('no yield refuses honestly, and never assumes one batch', () {
      final line = componentConversionLine(
        quantity: 2,
        unit: tbsp,
        yields: const [],
      );
      expect(line, '2 tbsp — no yield set');
      expect(line, isNot(contains('1 batch')));
    });

    test('a family the yield does not state says which two sides it has', () {
      expect(
        componentConversionLine(
          quantity: 2,
          unit: tbsp,
          yields: [(qty: 250, unit: g)],
        ),
        '2 tbsp — unresolved — the yield is in mass, this line in volume',
      );
    });
  });

  group('usedInAmountLine', () {
    test('prints the amount and its share', () {
      expect(
        usedInAmountLine(
          quantity: 0.25,
          unit: cup,
          amount: const ResolvedComponentAmount(
            0.25,
            against: (qty: 1, unit: cup),
          ),
        ),
        '¼ cup · ¼ of a batch',
      );
    });

    test('a batch line says it once', () {
      expect(
        usedInAmountLine(
          quantity: 1,
          unit: batches,
          amount: const ResolvedComponentAmount(1),
        ),
        '1 batch',
      );
    });

    test('an unresolved use says why', () {
      expect(
        usedInAmountLine(
          quantity: 2,
          unit: tbsp,
          amount: const ComponentYieldMissing(),
        ),
        '2 tbsp · no yield set',
      );
    });
  });

  test('usedInTabLabel carries the count', () {
    expect(usedInTabLabel(2), 'Used in · 2');
  });

  test('deleteRefusalText names the count, and the one way out of it', () {
    expect(
      deleteRefusalText(recipes: 2, lines: 3),
      'Used in 2 recipes (3 lines). Change those lines first.',
    );
    expect(
      deleteRefusalText(recipes: 1, lines: 1),
      'Used in 1 recipe (1 line). Change those lines first.',
    );
  });

  group("a component said in the recipe's own word", () {
    const blob = RecipeMeasure(
      id: 'blob',
      recipeId: 'aioli',
      label: 'blob',
      amount: 15,
      unit: g,
    );

    /// "makes 300 g" — the aioli, weighed, so its words resolve.
    const weighed = [(qty: 300.0, unit: g)];

    test('a line prints the word, singular, always', () {
      expect(componentAmountText(3, null, measureLabel: 'blob'), '3 blob');
      expect(componentAmountText(20, null, measureLabel: 'blob'), '20 blob');
      expect(componentAmountText(1, null, measureLabel: 'loaf'), '1 loaf');
      expect(componentAmountText(0.5, null, measureLabel: 'blob'), '½ blob');
      expect(componentAmountText(null, null, measureLabel: 'blob'), 'blob');
    });

    test('the Cook demand card shows its middle step', () {
      // What was said, what that comes to, what that is a share of — the
      // second is the fact the word carries, and the one a cook checks.
      expect(
        componentDemandLine(quantity: 3, measure: blob, batches: 0.15),
        '3 blob → 45 g → 0.15 of a batch',
      );
      expect(
        componentDemandLine(
          quantity: 1,
          measure: const RecipeMeasure(
            id: 'l',
            recipeId: 'r',
            label: 'loaf',
            amount: 900,
            unit: g,
          ),
          batches: 1,
        ),
        '1 loaf → 900 g → 1 batch',
      );
    });

    test('a line saying no word gets no arrow from a thing to itself', () {
      expect(
        componentDemandLine(quantity: 1, measure: null, batches: 1),
        isNull,
      );
      expect(
        componentDemandLine(quantity: null, measure: blob, batches: 1),
        isNull,
      );
    });

    test('the word reads in a list as the ingredient side reads one', () {
      expect(recipeMeasureListText(blob), 'blob · 15 g');
      expect(recipeMeasureAmountText(blob), '15 g');
      expect(recipeMeasureChipText(blob), 'blob (15 g)');
      expect(recipeMeasureRateText(blob), 'a blob is 15 g');
      expect(
        recipeMeasureListText(
          const RecipeMeasure(
            id: 'l',
            recipeId: 'r',
            label: 'ladle',
            amount: 180,
            unit: ml,
          ),
        ),
        'ladle · 180 ml',
      );
    });

    test('a word that already states its size does not say it twice', () {
      expect(
        recipeMeasureChipText(
          const RecipeMeasure(
            id: 'j',
            recipeId: 'r',
            label: 'jar (340 g)',
            amount: 340,
            unit: g,
          ),
        ),
        'jar (340 g)',
      );
    });

    test('the dock says the share and the rate that gave it', () {
      expect(
        componentConversionLine(
          quantity: 3,
          unit: null,
          yields: weighed,
          recipeMeasureId: 'blob',
          measures: const [blob],
        ),
        '3 blob = 0.15 of a batch · a blob is 15 g',
      );
    });

    test('and a word the recipe can no longer hold names the gap', () {
      // A `makes` restated into cups leaves the 15 g blob with nothing to be a
      // share of — the ordinary family mismatch, said in the ordinary words.
      expect(
        componentConversionLine(
          quantity: 3,
          unit: null,
          yields: const [(qty: 1.0, unit: cup)],
          recipeMeasureId: 'blob',
          measures: const [blob],
        ),
        '3 blob — unresolved — the yield is in volume, this line in mass',
      );
      expect(
        componentConversionLine(
          quantity: 3,
          unit: null,
          yields: const [],
          recipeMeasureId: 'blob',
          measures: const [blob],
        ),
        '3 blob — no yield set',
      );
    });

    test('and a word that has gone keeps the number, loses the rest', () {
      expect(
        componentConversionLine(
          quantity: 3,
          unit: null,
          yields: const [(qty: 8.0, unit: pieces)],
          // No measures handed in at all: the word is gone.
          recipeMeasureId: 'blob',
        ),
        '3 — its measure is gone',
      );
      expect(
        unresolvedComponentText(const ComponentMeasureMissing('blob')),
        'its measure is gone',
      );
    });

    test('the "used in" row reads the word off the resolved amount', () {
      expect(
        usedInAmountLine(
          quantity: 3,
          unit: null,
          amount: resolveComponentAmount(
            quantity: 3,
            unit: null,
            yields: weighed,
            recipeMeasureId: 'blob',
            measures: const [blob],
          ),
        ),
        '3 blob · 0.15 of a batch',
      );
    });
  });

  group('retiring a word', () {
    test('the refusal is a pure function of the counts', () {
      expect(
        recipeMeasureDeleteRefusalText(label: 'blob', lines: 3, recipes: 2),
        'Can’t delete “blob” yet · 3 lines still say it, in 2 recipes.',
      );
      expect(
        recipeMeasureDeleteRefusalText(label: 'ladle', lines: 1, recipes: 1),
        'Can’t delete “ladle” yet · 1 line still says it, in 1 recipe.',
      );
    });
  });

  group('warning before a Save that orphans a word', () {
    const blob = RecipeMeasure(
      id: 'b',
      recipeId: 'aioli',
      label: 'blob',
      amount: 15,
      unit: g,
    );
    const ladle = RecipeMeasure(
      id: 'l',
      recipeId: 'aioli',
      label: 'ladle',
      amount: 180,
      unit: ml,
    );

    test('nothing orphaned says nothing, so it is its own condition', () {
      expect(recipeMeasuresOrphanedWarning(const []), '');
    });

    test('one word: it names the word, its size, and the way back', () {
      expect(
        recipeMeasuresOrphanedWarning(const [blob]),
        '“blob” (15 g) has nothing left to be a share of after this. Nothing '
        'is deleted — but every line saying it goes unresolved until MAKES '
        'says what a batch comes to in the same kind of unit again.',
      );
    });

    test('two words agree with the count', () {
      expect(
        recipeMeasuresOrphanedWarning(const [blob, ladle]),
        '“blob” (15 g), “ladle” (180 ml) have nothing left to be a share of '
        'after this. Nothing is deleted — but every line saying them goes '
        'unresolved until MAKES says what a batch comes to in the same kind '
        'of unit again.',
      );
    });
  });
}
