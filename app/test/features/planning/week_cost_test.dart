import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/domain/week_cost.dart';
import 'package:ansi/features/recipes/domain/recipe_cost.dart';
import 'package:flutter_test/flutter_test.dart';

PlanEntry _meal(
  String id, {
  String? recipeId = 'r1',
  String? title = 'Curry',
  List<String> eaters = const ['m1', 'm2'],
  int? portions,
  String? ingredientId,
}) => PlanEntry(
  id: id,
  dayOfWeek: 0,
  mealSlot: 'Dinner',
  recipeId: ingredientId == null ? recipeId : null,
  ingredientId: ingredientId,
  recipeTitle: ingredientId == null ? title : null,
  ingredientName: ingredientId == null ? null : title,
  eaterIds: eaters,
  portions: portions,
);

/// A household that has never paid for anything — the reading every case
/// about RECIPES takes, so a snack's own rules are the only thing the snack
/// cases are asserting.
PriceObservation? _noPrice(String ingredientId) => null;

/// A bare-ingredient meal: `quantity` of `unit` (or of `measure`) of a row
/// this device knows the dimension of.
PlanEntry _snack(
  String id, {
  String title = 'Greek Yoghurt',
  double? quantity = 150,
  Unit? unit = g,
  Measure? measure,
  String? measureId,
  MacrosBasis basis = MacrosBasis.perG,
  double? densityGPerMl,
  double? pieceBasisAmount,
  bool known = true,
  List<String> eaters = const ['m1'],
}) => PlanEntry(
  id: id,
  dayOfWeek: 0,
  mealSlot: 'Snack',
  ingredientId: 'i1',
  ingredientName: title,
  quantity: quantity,
  unit: unit,
  measure: measure,
  measureId: measureId ?? measure?.id,
  nutrition: known
      ? (
          macros: null,
          basis: basis,
          densityGPerMl: densityGPerMl,
          pieceBasisAmount: pieceBasisAmount,
        )
      : null,
  eaterIds: eaters,
);

/// `$3.49` for 454 g — 77¢ / 100 g, the board's own example.
PriceObservation _price({
  int cents = 349,
  double pack = 454,
  MacrosBasis basis = MacrosBasis.perG,
}) => PriceObservation(
  lineId: 'l1',
  receiptId: 'r1',
  cents: cents,
  packBasisAmount: pack,
  basis: basis,
  store: "TJ's",
  purchasedAt: DateTime.utc(2026, 9, 13),
);

RecipeCostSummary _cost(double perServing) =>
    RecipeCostSummary(totalCents: perServing * 4, perServingCents: perServing);

const _unpriced = RecipeCostSummary(
  unpriced: [
    (
      lineId: 'li-1',
      name: 'Chopped tomatoes',
      reason: CostLineReason.noPrice,
      unit: null,
    ),
  ],
);

final _members = {
  'm1': const Member(id: 'm1', displayName: 'A'),
  'm2': const Member(id: 'm2', displayName: 'J'),
};

void main() {
  test('a meal costs its per-serving figure × the portions planned', () {
    final cost = sumPlannedCost(
      [_meal('e1')],
      costFor: (_) => _cost(254),
      priceFor: _noPrice,
      membersById: _members,
    );
    // Two eaters at factor 1 each.
    expect(cost.cents, 508);
    expect(cost.counted, 1);
    expect(cost.considered, 1);
    expect(cost.unpriced, isEmpty);
  });

  test('a portions override is the demand, as the macros read it', () {
    final cost = sumPlannedCost(
      [_meal('e1', portions: 3)],
      costFor: (_) => _cost(100),
      priceFor: _noPrice,
      membersById: _members,
    );
    expect(cost.cents, 300);
  });

  test('an unpriced recipe is out, and its lines are named', () {
    final cost = sumPlannedCost(
      [_meal('e1'), _meal('e2', recipeId: 'r2', title: 'Sliders')],
      costFor: (id) => id == 'r1' ? _cost(100) : _unpriced,
      priceFor: _noPrice,
      membersById: _members,
    );
    expect(cost.cents, 200);
    expect(cost.counted, 1);
    expect(cost.considered, 2);
    expect(cost.unpriced, ['Chopped tomatoes']);
  });

  test('the same line unpriced in two recipes is one thing to fix', () {
    final cost = sumPlannedCost(
      [_meal('e1'), _meal('e2', recipeId: 'r2', title: 'Sliders')],
      costFor: (_) => _unpriced,
      priceFor: _noPrice,
      membersById: _members,
    );
    expect(cost.cents, isNull);
    expect(cost.unpriced, ['Chopped tomatoes']);
  });

  test('nothing resolved is no figure at all, never a zero', () {
    final cost = sumPlannedCost(
      [_meal('e1')],
      costFor: (_) => _unpriced,
      priceFor: _noPrice,
      membersById: _members,
    );
    expect(cost.cents, isNull);
    expect(cost.counted, 0);
  });

  test('an empty week has no figure and nothing to name', () {
    final cost = sumPlannedCost(
      const [],
      costFor: (_) => _cost(100),
      priceFor: _noPrice,
    );
    expect(cost.cents, isNull);
    expect(cost.unpriced, isEmpty);
    expect(cost.considered, 0);
  });

  test('a recipe this device cannot resolve is named, not skipped', () {
    final cost = sumPlannedCost(
      [_meal('e1', title: null)],
      costFor: (_) => _cost(100),
      priceFor: _noPrice,
      membersById: _members,
    );
    expect(cost.cents, isNull);
    expect(cost.unpriced, ['(deleted recipe)']);
  });

  group('a bare ingredient meal', () {
    test('costs its own amount at its row’s latest price', () {
      final cost = sumPlannedCost(
        [_snack('e1')],
        costFor: (_) => _cost(100),
        priceFor: (_) => _price(),
        membersById: _members,
      );
      // 150 g at 77¢ / 100 g, for one eater at factor 1.
      expect(cost.cents, closeTo(115.3, 0.1));
      expect(cost.counted, 1);
      expect(cost.unpriced, isEmpty);
    });

    test('a snack with only a base price costs what its row costs', () {
      final cost = sumPlannedCost(
        [_snack('e1')],
        costFor: (_) => _cost(100),
        priceFor: (id) => BasePrice(
          ingredientId: id,
          cents: 349,
          packBasisAmount: 454,
          basis: MacrosBasis.perG,
          setAt: DateTime.utc(2026, 9, 13),
        ),
        membersById: _members,
      );
      expect(cost.cents, closeTo(115.3, 0.1));
      expect(cost.unpriced, isEmpty);
    });

    test('multiplies over its eaters, exactly as a dish does', () {
      final cost = sumPlannedCost(
        [
          _snack('e1', eaters: const ['m1', 'm2']),
        ],
        costFor: (_) => _cost(100),
        priceFor: (_) => _price(),
        membersById: _members,
      );
      expect(cost.cents, closeTo(230.6, 0.1));
    });

    test('reaches the basis the way its macros do — through the measure', () {
      final cost = sumPlannedCost(
        [
          _snack(
            'e1',
            quantity: 2,
            unit: pieces,
            measure: const Measure(id: 'm-pot', label: 'pot', amount: 170),
          ),
        ],
        costFor: (_) => _cost(100),
        priceFor: (_) => _price(),
        membersById: _members,
      );
      // 2 × 170 g at 77¢ / 100 g.
      expect(cost.cents, closeTo(261.4, 0.1));
    });

    test('a cross-basis amount crosses only through the density', () {
      PlannedCost costed({double? density}) => sumPlannedCost(
        [_snack('e1', quantity: 100, unit: ml, densityGPerMl: density)],
        costFor: (_) => _cost(100),
        priceFor: (_) => _price(),
        membersById: _members,
      );
      expect(costed(density: 1.03).cents, closeTo(79.2, 0.1));
      final refused = costed();
      expect(refused.cents, isNull);
      expect(refused.unpriced, ['Greek Yoghurt']);
    });

    test('a row nobody has priced is named, and takes no zero with it', () {
      final cost = sumPlannedCost(
        [_meal('e1'), _snack('e2')],
        costFor: (_) => _cost(100),
        priceFor: _noPrice,
        membersById: _members,
      );
      expect(cost.cents, 200, reason: 'the curry still counts');
      expect(cost.unpriced, ['Greek Yoghurt']);
      expect(cost.considered, 2);
    });

    test('a row this device has never synced has no path to a basis', () {
      final cost = sumPlannedCost(
        [_snack('e1', known: false)],
        costFor: (_) => _cost(100),
        priceFor: (_) => _price(),
        membersById: _members,
      );
      expect(cost.cents, isNull);
      expect(cost.unpriced, ['Greek Yoghurt']);
    });

    test('a meal stating no amount is named, never weighed at nothing', () {
      final cost = sumPlannedCost(
        [_snack('e1', quantity: null, unit: null)],
        costFor: (_) => _cost(100),
        priceFor: (_) => _price(),
        membersById: _members,
      );
      expect(cost.cents, isNull);
      expect(cost.unpriced, ['Greek Yoghurt']);
    });

    test('a measure that has not synced in weighs nothing yet', () {
      final cost = sumPlannedCost(
        [_snack('e1', quantity: 1, unit: pieces, measureId: 'm-gone')],
        costFor: (_) => _cost(100),
        priceFor: (_) => _price(),
        membersById: _members,
      );
      expect(cost.cents, isNull);
      expect(cost.unpriced, ['Greek Yoghurt']);
    });

    test('a price recorded against another basis waits for a fresh one', () {
      final cost = sumPlannedCost(
        [_snack('e1', basis: MacrosBasis.perMl, quantity: 100, unit: ml)],
        costFor: (_) => _cost(100),
        priceFor: (_) => _price(),
        membersById: _members,
      );
      expect(cost.cents, isNull);
      expect(cost.unpriced, ['Greek Yoghurt']);
    });

    test('one unpriced row planned twice is one thing to go and price', () {
      final cost = sumPlannedCost(
        [_snack('e1'), _snack('e2')],
        costFor: (_) => _cost(100),
        priceFor: _noPrice,
        membersById: _members,
      );
      expect(cost.unpriced, ['Greek Yoghurt']);
    });
  });

  group('ingredientPortionCost', () {
    test('names the recipe cost’s own reasons, never one of its own', () {
      expect(
        ingredientPortionCost(_snack('e1'), null).reason,
        CostLineReason.noPrice,
      );
      expect(
        ingredientPortionCost(_snack('e1', known: false), _price()).reason,
        CostLineReason.noPathToBasis,
      );
      expect(
        ingredientPortionCost(
          _snack('e1', quantity: 100, unit: ml),
          _price(),
        ).reason,
        CostLineReason.noPathToBasis,
      );
      expect(
        ingredientPortionCost(
          _snack('e1', basis: MacrosBasis.perMl, quantity: 10, unit: ml),
          _price(),
        ).reason,
        CostLineReason.priceOffBasis,
      );
    });

    test('a pack of nothing prices nothing, and says so as no price', () {
      expect(
        ingredientPortionCost(_snack('e1'), _price(pack: 0)).reason,
        CostLineReason.noPrice,
      );
    });

    test('a bare count crosses through the row’s piece weight', () {
      final priced = ingredientPortionCost(
        _snack('e1', quantity: 2, unit: pieces, pieceBasisAmount: 120),
        _price(),
      );
      // 240 g at 77¢ / 100 g.
      expect(priced.cents, closeTo(184.5, 0.1));
      expect(priced.reason, isNull);
    });
  });

  test('a meal eaten out is passed over: not a cost to cook, not a gap', () {
    final cost = sumPlannedCost(
      [
        _meal('e1'),
        const PlanEntry(
          id: 'e2',
          dayOfWeek: 1,
          mealSlot: 'Lunch',
          label: 'Office lunch',
          eaterIds: ['m1'],
        ),
      ],
      costFor: (_) => _cost(100),
      priceFor: _noPrice,
      membersById: _members,
    );
    // Only the curry is counted — two eaters × 100 — and the lunch is neither
    // in the figure nor named against it, nor in the meals considered.
    expect(cost.cents, 200);
    expect(cost.unpriced, isEmpty);
    expect(cost.considered, 1);
  });

  test('nobody eating it is no demand — and no pricing gap either', () {
    final cost = sumPlannedCost(
      [_meal('e1', eaters: const [])],
      costFor: (_) => _cost(100),
      priceFor: _noPrice,
      membersById: _members,
    );
    expect(cost.cents, isNull);
    expect(cost.unpriced, isEmpty);
    expect(cost.considered, 1);
    expect(cost.counted, 0);
  });

  group('under a lens', () {
    test("somebody else's meal is out of scope, not excluded", () {
      final cost = sumPlannedCost(
        [
          _meal('e1', eaters: const ['m2']),
        ],
        costFor: (_) => _cost(100),
        priceFor: _noPrice,
        lensMemberId: 'm1',
        membersById: _members,
      );
      expect(cost.considered, 0);
      expect(cost.cents, isNull);
    });

    test('a lens pays its own share, the way it eats its own macros', () {
      final cost = sumPlannedCost(
        [_meal('e1')],
        costFor: (_) => _cost(100),
        priceFor: _noPrice,
        lensMemberId: 'm1',
        membersById: _members,
      );
      expect(cost.cents, 100);
    });
  });
}
