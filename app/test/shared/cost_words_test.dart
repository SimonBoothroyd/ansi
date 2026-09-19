import 'package:ansi/core/units/macros.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/recipes/domain/recipe_cost.dart';
import 'package:ansi/shared/cost_words.dart';
import 'package:flutter_test/flutter_test.dart';

PriceObservation _price({
  int cents = 110,
  double pack = 100,
  String store = "TJ's",
  DateTime? on,
  String? packLabel,
}) => PriceObservation(
  lineId: 'rl-1',
  receiptId: 'r-1',
  cents: cents,
  packBasisAmount: pack,
  basis: MacrosBasis.perG,
  store: store,
  purchasedAt: on ?? DateTime.utc(2026, 9, 3),
  packLabel: packLabel,
);

void main() {
  group('the two spellings', () {
    test('a summed estimate wears the ≈, a read figure does not', () {
      expect(approxMoney(242), r'≈ $2.42');
      expect(
        lineCostText(CostLine(cents: 658, price: _price())),
        startsWith(r'$6.58 ·'),
      );
    });

    test('a derived figure rounds once, at the edge', () {
      expect(approxMoney(241.6), r'≈ $2.42');
      expect(approxMoney(76.4), '≈ 76¢');
    });
  });

  group('a line prints its whole chain', () {
    test('a plain pack reads per 100 of the basis', () {
      expect(
        lineCostText(CostLine(cents: 1316, price: _price())),
        r"$13.16 · $1.10 / 100 g · TJ's, Sep",
      );
    });

    test('a named pack reads as that pack — you buy a can', () {
      expect(
        lineCostText(
          CostLine(cents: 516, price: _price(cents: 129, packLabel: 'can')),
        ),
        r"$5.16 · $1.29 a can · TJ's, Sep",
      );
    });

    test('the scaler moves the figure, never the unit price', () {
      expect(
        lineCostText(CostLine(cents: 658, price: _price()), factor: 2),
        startsWith(r'$13.16 · $1.10 / 100 g'),
      );
    });

    test('a component line prints its figure alone', () {
      expect(lineCostText(const CostLine(cents: 250)), r'$2.50');
    });
  });

  group('what the strip is waiting on', () {
    const unpriced = RecipeCostSummary(
      unpriced: [
        (
          lineId: 'li-1',
          name: 'Chopped tomatoes',
          reason: CostLineReason.noPrice,
          unit: null,
        ),
      ],
    );

    test('UNPRICED names the line and says what is missing', () {
      expect(unpricedNames(unpriced), 'Chopped tomatoes · no price yet');
    });

    test('the refusal counts the lines', () {
      expect(costRefusal(unpriced), '1 line unpriced');
      expect(
        costRefusal(const RecipeCostSummary(noLines: true)),
        'no ingredients yet',
      );
      expect(
        costRefusal(const RecipeCostSummary(nothingCountable: true)),
        'nothing to price yet',
      );
    });

    test('the floor wears the words on both halves', () {
      const partly = RecipeCostSummary(
        pricedCents: 660,
        pricedPerServingCents: 165,
        lineCosts: {'li-2': CostLine(cents: 660)},
        unpriced: [
          (
            lineId: 'li-1',
            name: 'Chopped tomatoes',
            reason: CostLineReason.noPrice,
            unit: null,
          ),
        ],
      );
      expect(
        costFloor(partly),
        r'at least $1.65 a serving · at least $6.60 the recipe',
      );
    });

    test('there is no floor to print without one priced line', () {
      expect(costFloor(unpriced), isNull);
      expect(
        costFloor(
          const RecipeCostSummary(totalCents: 660, perServingCents: 165),
        ),
        isNull,
      );
    });

    test('nothing unpriced draws no row', () {
      expect(unpricedNames(const RecipeCostSummary()), isNull);
      expect(oldestPriceLine(const RecipeCostSummary()), isNull);
    });

    test('OLDEST names the line and where its price came from', () {
      final summary = RecipeCostSummary(
        totalCents: 100,
        perServingCents: 50,
        oldest: (
          name: 'Smoked paprika',
          price: _price(store: 'Whole Foods', on: DateTime.utc(2026, 7, 11)),
        ),
      );
      expect(oldestPriceLine(summary), 'Smoked paprika · Whole Foods, Jul');
    });

    test('NOT COUNTED keeps the word the source printed', () {
      const summary = RecipeCostSummary(
        notCounted: [
          (
            lineId: 'li-2',
            name: 'Parsley',
            reason: CostLineReason.imprecise,
            unit: 'handful',
          ),
          (
            lineId: 'li-3',
            name: 'Lime',
            reason: CostLineReason.optional,
            unit: null,
          ),
        ],
      );
      expect(impreciseCostNames(summary), 'Parsley · handful');
      expect(optionalCostNames(summary), 'Lime');
    });
  });

  group('the aggregate lines', () {
    test('a whole week is an estimate; one with a gap is a floor (owner)', () {
      // A meal with one unpriced line is out of the sum WHOLE, so the figure
      // is short by meals rather than rounded — it says so itself, and does
      // not also wear the `≈` that hedges the arithmetic.
      expect(
        weekCostLine(cents: 7123, unpriced: 3),
        r'at least $71 to cook · 3 lines unpriced',
      );
      expect(weekCostLine(cents: 7123), r'≈ $71 to cook');
      expect(weekCostLine(unpriced: 1), '1 line unpriced');
      expect(weekCostLine(), isNull);
    });

    test('the trip estimate says nothing when nothing can be priced', () {
      expect(tripEstimate((cents: 5800, unpriced: 0)), r'≈ $58 still to buy');
      expect(tripEstimate((cents: null, unpriced: 3)), isNull);
    });

    test('a walk with a row nothing can price is a floor too (owner)', () {
      expect(
        tripEstimate((cents: 5800, unpriced: 2)),
        r'at least $58 still to buy · 2 rows unpriced',
      );
      expect(
        tripEstimate((cents: 5800, unpriced: 1)),
        r'at least $58 still to buy · 1 row unpriced',
      );
    });
  });
}
