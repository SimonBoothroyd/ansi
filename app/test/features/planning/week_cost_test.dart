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
      membersById: _members,
    );
    expect(cost.cents, 300);
  });

  test('an unpriced recipe is out, and its lines are named', () {
    final cost = sumPlannedCost(
      [_meal('e1'), _meal('e2', recipeId: 'r2', title: 'Sliders')],
      costFor: (id) => id == 'r1' ? _cost(100) : _unpriced,
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
      membersById: _members,
    );
    expect(cost.cents, isNull);
    expect(cost.unpriced, ['Chopped tomatoes']);
  });

  test('nothing resolved is no figure at all, never a zero', () {
    final cost = sumPlannedCost(
      [_meal('e1')],
      costFor: (_) => _unpriced,
      membersById: _members,
    );
    expect(cost.cents, isNull);
    expect(cost.counted, 0);
  });

  test('an empty week has no figure and nothing to name', () {
    final cost = sumPlannedCost(const [], costFor: (_) => _cost(100));
    expect(cost.cents, isNull);
    expect(cost.unpriced, isEmpty);
    expect(cost.considered, 0);
  });

  test('a recipe this device cannot resolve is named, not skipped', () {
    final cost = sumPlannedCost(
      [_meal('e1', title: null)],
      costFor: (_) => _cost(100),
      membersById: _members,
    );
    expect(cost.cents, isNull);
    expect(cost.unpriced, ['(deleted recipe)']);
  });

  test('a bare ingredient meal is named rather than silently uncosted', () {
    final cost = sumPlannedCost(
      [_meal('e1', ingredientId: 'i1', title: 'Greek Yoghurt')],
      costFor: (_) => _cost(100),
      membersById: _members,
    );
    expect(cost.cents, isNull);
    expect(cost.unpriced, ['Greek Yoghurt']);
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
        lensMemberId: 'm1',
        membersById: _members,
      );
      expect(cost.cents, 100);
    });
  });
}
