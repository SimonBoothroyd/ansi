/// The component copy every 8.6 surface speaks (step 8.6, board frames b · d).
/// A share of a batch is either stated or refused — never a guessed `1×`.
library;

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
      expect(batchShareText(0.25), '0.25 of a batch');
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
        '0.25 cup = 0.25 of a batch · makes 1 cup',
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
        '0.25 cup · 0.25 of a batch',
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

  test('usedInTabLabel carries the count (D9)', () {
    expect(usedInTabLabel(2), 'Used in · 2');
  });

  test('deleteRefusalText names the count, the way 8.5 does (D5)', () {
    expect(
      deleteRefusalText(recipes: 2, lines: 3),
      'Used in 2 recipes (3 lines). Change those lines first.',
    );
    expect(
      deleteRefusalText(recipes: 1, lines: 1),
      'Used in 1 recipe (1 line). Change those lines first.',
    );
  });
}
