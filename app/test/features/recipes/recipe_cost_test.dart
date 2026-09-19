import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:ansi/features/recipes/domain/line_basis.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_cost.dart';
import 'package:flutter_test/flutter_test.dart';

final _sep = DateTime.utc(2026, 9, 3);
final _jul = DateTime.utc(2026, 7, 11);

LineItem _line(
  String ingredientId, {
  double? quantity,
  Unit unit = g,
  Measure? measure,
  String? measureId,
  bool optional = false,
}) => LineItem(
  id: 'li-$ingredientId',
  ingredientId: ingredientId,
  ingredientName: ingredientId,
  unit: measure != null || measureId != null ? pieces : unit,
  quantity: quantity,
  measure: measure,
  measureId: measureId ?? measure?.id,
  optional: optional,
);

/// A price: [cents] paid for [pack] of the row's basis unit.
PriceObservation _price({
  int cents = 500,
  double pack = 1000,
  MacrosBasis basis = MacrosBasis.perG,
  String store = "TJ's",
  DateTime? on,
  String? packLabel,
}) => PriceObservation(
  lineId: 'rl-$store-$cents',
  receiptId: 'r-1',
  cents: cents,
  packBasisAmount: pack,
  basis: basis,
  store: store,
  purchasedAt: on ?? _sep,
  packLabel: packLabel,
);

IngredientPricing? Function(String) _vocab({
  MacrosBasis basis = MacrosBasis.perG,
  double? density,
  double? pieceBasisAmount,
  PriceObservation? price,
  Map<String, PriceObservation?> byId = const {},
}) =>
    (id) => id == 'missing'
    ? null
    : (
        row: (
          basis: basis,
          densityGPerMl: density,
          pieceBasisAmount: pieceBasisAmount,
        ),
        price: byId.containsKey(id) ? byId[id] : price,
      );

/// "a batch makes 20 blob" — the household's own word for the aioli.
RecipeMeasure _blob() => const RecipeMeasure(
  id: 'blob',
  recipeId: 'aioli',
  label: 'blob',
  perBatch: 20,
);

void main() {
  group('the price × the amount, in the basis', () {
    test('a mass line costs its grams at the per-100 g price', () {
      final summary = summarizeRecipeCost(
        servingsBase: 2,
        // 50¢/100 g × 250 g = $1.25
        lines: [_line('x', quantity: 250)],
        pricingOf: _vocab(price: _price()),
      );
      expect(summary.incomplete, isFalse);
      expect(summary.totalCents, 125);
      expect(summary.perServingCents, 62.5);
      expect(summary.lineCosts['li-x']!.cents, 125);
    });

    test('a volume line joins a per-100 ml basis with no density', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [_line('x', quantity: 600, unit: ml)],
        pricingOf: _vocab(
          basis: MacrosBasis.perMl,
          price: _price(basis: MacrosBasis.perMl),
        ),
      );
      expect(summary.totalCents, 300);
    });

    test('a cross-basis line converts through the row density', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [_line('x', quantity: 100, unit: ml)],
        pricingOf: _vocab(density: 0.9, price: _price()),
      );
      // 100 ml × 0.9 = 90 g, at 50¢/100 g.
      expect(summary.totalCents, closeTo(45, 1e-9));
    });

    test('a measure line converts through its stored weight', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [
          _line(
            'x',
            quantity: 2,
            measure: const Measure(id: 'can', label: 'can', amount: 400),
          ),
        ],
        pricingOf: _vocab(price: _price()),
      );
      expect(summary.totalCents, 400);
    });

    test('a bare count converts through the row piece weight', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [_line('x', quantity: 3, unit: pieces)],
        pricingOf: _vocab(pieceBasisAmount: 110, price: _price()),
      );
      expect(summary.totalCents, closeTo(165, 1e-9));
    });

    test('the same conversion the macro walk uses, not a second one', () {
      const row = (
        basis: MacrosBasis.perG,
        densityGPerMl: 0.9,
        pieceBasisAmount: null,
      );
      final line = _line('x', quantity: 100, unit: ml);
      final grams = lineAmountInBasis(line, row)!;
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [line],
        pricingOf: _vocab(density: 0.9, price: _price()),
      );
      expect(summary.totalCents, closeTo(grams * 0.5, 1e-9));
    });
  });

  group('a line with no price', () {
    test('is unpriced by name, and takes the recipe figure with it', () {
      final summary = summarizeRecipeCost(
        servingsBase: 2,
        lines: [_line('x', quantity: 250), _line('y', quantity: 100)],
        pricingOf: _vocab(byId: {'x': _price(), 'y': null}),
      );
      expect(summary.incomplete, isTrue);
      expect(summary.totalCents, isNull);
      expect(summary.perServingCents, isNull);
      expect(summary.unpriced.single.name, 'y');
      expect(summary.unpriced.single.reason, CostLineReason.noPrice);
      // The priced line still records what it contributed: the panel's line
      // figures stay honest while the strip refuses.
      expect(summary.lineCosts['li-x']!.cents, 125);
      expect(summary.lineCosts.containsKey('li-y'), isFalse);
    });

    test('a volume line on a gram row with no density has no path', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [_line('x', quantity: 100, unit: ml)],
        pricingOf: _vocab(price: _price()),
      );
      expect(summary.unpriced.single.reason, CostLineReason.noPathToBasis);
    });

    test('a line with no amount has no path', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [_line('x')],
        pricingOf: _vocab(price: _price()),
      );
      expect(summary.unpriced.single.reason, CostLineReason.noPathToBasis);
    });

    test('an ingredient this device does not know has no path', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [_line('missing', quantity: 10)],
        pricingOf: _vocab(price: _price()),
      );
      expect(summary.unpriced.single.reason, CostLineReason.noPathToBasis);
    });

    test('a price against another basis is refused, never re-denominated', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [_line('x', quantity: 10)],
        pricingOf: _vocab(price: _price(basis: MacrosBasis.perMl)),
      );
      expect(summary.unpriced.single.reason, CostLineReason.priceOffBasis);
    });

    test('an unsynced measure leaves the line unpriced, not miscounted', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [_line('x', quantity: 2, measureId: 'not-here')],
        pricingOf: _vocab(price: _price()),
      );
      expect(summary.unpriced.single.reason, CostLineReason.noPathToBasis);
    });
  });

  group('the floor the priced lines reach', () {
    test('is stated while the cost itself stays null', () {
      final summary = summarizeRecipeCost(
        servingsBase: 2,
        lines: [_line('x', quantity: 250), _line('y', quantity: 100)],
        pricingOf: _vocab(byId: {'x': _price(), 'y': null}),
      );
      expect(summary.partlyPriced, isTrue);
      expect(summary.pricedCents, 125);
      expect(summary.pricedPerServingCents, 62.5);
      // The whole point: nothing that asks what the recipe COSTS sees it.
      expect(summary.totalCents, isNull);
      expect(summary.perServingCents, isNull);
    });

    test('is not claimed when nothing is priced', () {
      final summary = summarizeRecipeCost(
        servingsBase: 2,
        lines: [_line('x', quantity: 250)],
        pricingOf: _vocab(byId: {'x': null}),
      );
      expect(summary.partlyPriced, isFalse);
      expect(summary.pricedCents, 0);
    });

    test('is the cost itself when every line is priced', () {
      final summary = summarizeRecipeCost(
        servingsBase: 2,
        lines: [_line('x', quantity: 250)],
        pricingOf: _vocab(price: _price()),
      );
      expect(summary.partlyPriced, isFalse);
      expect(summary.pricedCents, summary.totalCents);
      expect(summary.pricedPerServingCents, summary.perServingCents);
    });

    test('has no per-serving half when the servings are not set', () {
      final summary = summarizeRecipeCost(
        servingsBase: 0,
        lines: [_line('x', quantity: 250), _line('y', quantity: 100)],
        pricingOf: _vocab(byId: {'x': _price(), 'y': null}),
      );
      expect(summary.pricedCents, 125);
      expect(summary.pricedPerServingCents, isNull);
    });
  });

  group('out by the macro rule, and named apart', () {
    test('an imprecise line is not counted and is not unpriced', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [
          _line('x', quantity: 100),
          _line('herb', quantity: 1, unit: handful),
        ],
        pricingOf: _vocab(byId: {'x': _price(), 'herb': null}),
      );
      expect(summary.incomplete, isFalse);
      expect(summary.totalCents, 50);
      expect(summary.unpriced, isEmpty);
      expect(summary.notCounted.single.name, 'herb');
      expect(summary.notCounted.single.reason, CostLineReason.imprecise);
      // The word the source printed, not a category name.
      expect(summary.notCounted.single.unit, handful.label);
    });

    test('an optional line is named once, as optional', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [
          _line('x', quantity: 100),
          // Optional AND unpriceable: the seam drops it first, so it is out
          // by rule rather than named as a gap.
          _line('lime', quantity: 1, unit: pieces, optional: true),
        ],
        pricingOf: _vocab(byId: {'x': _price(), 'lime': null}),
      );
      expect(summary.incomplete, isFalse);
      expect(summary.unpriced, isEmpty);
      expect(summary.notCounted.single.reason, CostLineReason.optional);
    });

    test('a recipe of nothing but imprecise lines refuses', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [_line('herb', quantity: 1, unit: handful)],
        pricingOf: _vocab(price: _price()),
      );
      expect(summary.incomplete, isTrue);
      expect(summary.nothingCountable, isTrue);
      expect(summary.totalCents, isNull);
    });

    test('a recipe with no lines refuses rather than costing nothing', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: const [],
        pricingOf: _vocab(price: _price()),
      );
      expect(summary.noLines, isTrue);
      expect(summary.totalCents, isNull);
    });

    test('a non-positive serving count refuses rather than dividing', () {
      final summary = summarizeRecipeCost(
        servingsBase: 0,
        lines: [_line('x', quantity: 100)],
        pricingOf: _vocab(price: _price()),
      );
      expect(summary.incomplete, isTrue);
      expect(summary.perServingCents, isNull);
    });
  });

  group('the months', () {
    test('prices from reads the newest, and the oldest is named', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [_line('x', quantity: 100), _line('paprika', quantity: 10)],
        pricingOf: _vocab(
          byId: {
            'x': _price(),
            'paprika': _price(on: _jul, store: 'Whole Foods'),
          },
        ),
      );
      expect(summary.newestPrice, _sep);
      expect(summary.oldest!.name, 'paprika');
      expect(summary.oldest!.price.store, 'Whole Foods');
    });

    test('one month across every line names no oldest', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [_line('x', quantity: 100), _line('y', quantity: 10)],
        pricingOf: _vocab(
          byId: {
            'x': _price(),
            'y': _price(on: DateTime.utc(2026, 9, 28)),
          },
        ),
      );
      expect(summary.oldest, isNull);
      expect(summary.newestPrice, DateTime.utc(2026, 9, 28));
    });
  });

  group('the per-line record', () {
    test('carries the price it came from — pack, store and date', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [_line('x', quantity: 100)],
        pricingOf: _vocab(price: _price(packLabel: 'can')),
      );
      final line = summary.lineCosts['li-x']!;
      expect(line.price!.packLabel, 'can');
      expect(line.price!.store, "TJ's");
      expect(line.price!.purchasedAt, _sep);
    });

    test('is at the STORED amount — the surface scales it', () {
      final summary = summarizeRecipeCost(
        servingsBase: 2,
        lines: [_line('x', quantity: 250)],
        pricingOf: _vocab(price: _price()),
      );
      expect(summary.lineCosts['li-x']!.cents, 125);
      // Per serving is scale-invariant: doubling the lines doubles the
      // servings too.
      final doubled = summarizeRecipeCost(
        servingsBase: 4,
        lines: [_line('x', quantity: 500)],
        pricingOf: _vocab(price: _price()),
      );
      expect(doubled.perServingCents, summary.perServingCents);
    });

    test('the lines sum to the total, with nothing left over', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [_line('x', quantity: 250), _line('y', quantity: 100)],
        pricingOf: _vocab(price: _price()),
      );
      final summed = summary.lineCosts.values
          .map((l) => l.cents)
          .reduce((a, b) => a + b);
      expect(summed, closeTo(summary.totalCents!, 1e-9));
    });
  });

  group('a component line', () {
    SubRecipeNode node({
      required List<LineItem> lines,
      double servings = 2,
      List<YieldDenomination> yields = const [(qty: 2, unit: cup)],
      List<RecipeMeasure> measures = const [],
    }) => (
      servingsBase: servings,
      lines: lines,
      measures: measures,
      yields: yields,
    );

    LineItem component(
      String id, {
      double? quantity,
      Unit? unit = cup,
      String? measureId,
    }) => LineItem(
      id: 'li-$id',
      subRecipeId: id,
      ingredientName: '',
      subRecipe: SubRecipeTarget(id: id, title: id),
      unit: measureId == null ? unit : null,
      recipeMeasureId: measureId,
      quantity: quantity,
    );

    test('costs the target whole-recipe × the batches it asks for', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [component('aioli', quantity: 1)],
        pricingOf: _vocab(price: _price()),
        // The target costs 100 g × 50¢/100 g = 50¢ whole; half a batch of it.
        subRecipeOf: (_) => node(lines: [_line('x', quantity: 100)]),
      );
      expect(summary.totalCents, closeTo(25, 1e-9));
      // A component's cost is a recipe's, not a pack's.
      expect(summary.lineCosts['li-aioli']!.price, isNull);
    });

    test('an unpriced target makes the component line unpriced', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [component('aioli', quantity: 1)],
        pricingOf: _vocab(byId: {'x': null}),
        subRecipeOf: (_) => node(lines: [_line('x', quantity: 100)]),
      );
      expect(summary.unpriced.single.reason, CostLineReason.subRecipeUnpriced);
      expect(summary.unpriced.single.name, 'aioli');
    });

    test("a target's own floor never joins the parent's", () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [_line('p', quantity: 100), component('aioli', quantity: 1)],
        pricingOf: _vocab(byId: {'p': _price(), 'x': _price(), 'y': null}),
        subRecipeOf: (_) =>
            node(lines: [_line('x', quantity: 100), _line('y', quantity: 100)]),
      );
      // The component is unpriced, so it contributes nothing at all — the 50¢
      // its own priced line reaches is a floor, and a floor is not a cost.
      expect(summary.unpriced.single.reason, CostLineReason.subRecipeUnpriced);
      expect(summary.pricedCents, 50);
      expect(summary.lineCosts.containsKey('li-aioli'), isFalse);
    });

    test("said in the target's own word: 0.15 × its whole cost", () {
      // A batch makes 20 blob; the line asks for 3 of them.
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [component('aioli', quantity: 3, measureId: 'blob')],
        pricingOf: _vocab(price: _price()),
        // The target costs 100 g × 50¢/100 g = 50¢ whole.
        subRecipeOf: (_) =>
            node(lines: [_line('x', quantity: 100)], measures: [_blob()]),
      );
      expect(summary.totalCents, closeTo(0.15 * 50, 1e-9));
    });

    test('and the word needs no yield to do it', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [component('aioli', quantity: 3, measureId: 'blob')],
        pricingOf: _vocab(price: _price()),
        subRecipeOf: (_) => node(
          lines: [_line('x', quantity: 100)],
          yields: const [],
          measures: [_blob()],
        ),
      );
      expect(summary.totalCents, closeTo(7.5, 1e-9));
    });

    test('a parent cooked twice asks for 6 blob — 0.3 of a batch', () {
      // Scaling multiplies the LINE, so the doubled recipe is the same walk
      // over a line that says 6.
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [component('aioli', quantity: 6, measureId: 'blob')],
        pricingOf: _vocab(price: _price()),
        subRecipeOf: (_) =>
            node(lines: [_line('x', quantity: 100)], measures: [_blob()]),
      );
      expect(summary.totalCents, closeTo(0.3 * 50, 1e-9));
    });

    test('a word the target has lost takes the line out, named', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [
          _line('p', quantity: 100),
          component('aioli', quantity: 3, measureId: 'blob'),
        ],
        pricingOf: _vocab(price: _price()),
        subRecipeOf: (_) => node(lines: [_line('x', quantity: 100)]),
      );
      expect(
        summary.unpriced.single.reason,
        CostLineReason.subRecipeUnresolved,
      );
      expect(summary.unpriced.single.name, 'aioli');
      expect(summary.totalCents, isNull);
      // The floor is the parent's own priced line and nothing of the target's.
      expect(summary.pricedCents, 50);
      expect(summary.lineCosts.containsKey('li-aioli'), isFalse);
    });

    test('a target with no yield does not resolve', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [component('aioli', quantity: 1)],
        pricingOf: _vocab(price: _price()),
        subRecipeOf: (_) =>
            node(lines: [_line('x', quantity: 100)], yields: const []),
      );
      expect(
        summary.unpriced.single.reason,
        CostLineReason.subRecipeUnresolved,
      );
    });

    test('a cycle renders the parent unpriced rather than looping', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [component('self', quantity: 1)],
        pricingOf: _vocab(price: _price()),
        subRecipeOf: (_) => node(lines: [component('self', quantity: 1)]),
      );
      expect(summary.incomplete, isTrue);
      expect(summary.unpriced, hasLength(1));
    });

    test('the nested line is what the OLDEST row names', () {
      final summary = summarizeRecipeCost(
        servingsBase: 1,
        lines: [_line('x', quantity: 100), component('aioli', quantity: 1)],
        pricingOf: _vocab(
          byId: {
            'x': _price(),
            'old': _price(on: _jul, store: 'Whole Foods'),
          },
        ),
        subRecipeOf: (_) => node(lines: [_line('old', quantity: 100)]),
      );
      expect(summary.oldest!.name, 'old');
    });
  });
}
