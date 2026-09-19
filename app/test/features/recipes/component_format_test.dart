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
      perBatch: 20,
    );

    test('a line prints the word, singular, always', () {
      expect(componentAmountText(3, null, measureLabel: 'blob'), '3 blob');
      expect(componentAmountText(20, null, measureLabel: 'blob'), '20 blob');
      expect(componentAmountText(1, null, measureLabel: 'loaf'), '1 loaf');
      expect(componentAmountText(0.5, null, measureLabel: 'blob'), '½ blob');
      expect(componentAmountText(null, null, measureLabel: 'blob'), 'blob');
    });

    test('the Cook demand card: what was said, then what it comes to', () {
      expect(
        componentDemandLine(quantity: 3, measureLabel: 'blob', batches: 0.15),
        '3 blob → 0.15 of a batch',
      );
      expect(
        componentDemandLine(quantity: 1, measureLabel: 'loaf', batches: 1),
        '1 loaf → 1 batch',
      );
    });

    test('a line saying no word gets no arrow from a thing to itself', () {
      expect(
        componentDemandLine(quantity: 1, measureLabel: null, batches: 1),
        isNull,
      );
      expect(
        componentDemandLine(quantity: null, measureLabel: 'blob', batches: 1),
        isNull,
      );
    });

    test('the word reads in a list as the one sentence it is', () {
      expect(recipeMeasureListText(blob), 'blob · a batch makes 20');
      expect(recipeMeasureRateText(blob), 'a batch makes 20 blob');
      expect(
        recipeMeasureListText(
          const RecipeMeasure(
            id: 'l',
            recipeId: 'r',
            label: 'loaf',
            perBatch: 1,
          ),
        ),
        'loaf · a batch makes 1',
      );
    });

    test('the dock says the share and the rate that gave it', () {
      expect(
        componentConversionLine(
          quantity: 3,
          unit: null,
          yields: const [(qty: 1.0, unit: cup)],
          recipeMeasureId: 'blob',
          measures: const [blob],
        ),
        '3 blob = 0.15 of a batch · a batch makes 20 blob',
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
            yields: const [],
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
}
