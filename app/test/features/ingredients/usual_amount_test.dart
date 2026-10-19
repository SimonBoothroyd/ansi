import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/unit_choice.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/default_amount.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/presentation/usual_amount.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/shopping/data/shopping_providers.dart';
import 'package:ansi/features/shopping/domain/shopping_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_measure_repository.dart';
import '../../helpers/fake_planning_repository.dart';

const _yoghurt = Ingredient(
  id: 'i1',
  canonicalName: 'Yoghurt',
  defaultUnit: pieces,
  status: IngredientStatus.complete,
  pieceBasisAmount: 150,
  allowedUnits: [g, pieces],
);

const _pot = Measure(id: 'pot', label: 'pot', amount: 150);

/// A list whose only answer is the last top-up.
class _LastTopUp implements ShoppingRepository {
  _LastTopUp(this.last);
  final LastAmount? last;

  @override
  Future<LastAmount?> lastTopUp(String ingredientId) async => last;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  ProviderContainer containerFor({
    LastAmount? lastMeal,
    LastAmount? lastTopUp,
  }) {
    final planning = FakePlanningRepository();
    if (lastMeal != null) planning.lastAmounts['i1'] = lastMeal;
    final c = ProviderContainer(
      overrides: [
        measureRepositoryProvider.overrideWithValue(FakeMeasureRepo([_pot])),
        planningRepositoryProvider.overrideWithValue(planning),
        shoppingRepositoryProvider.overrideWithValue(_LastTopUp(lastTopUp)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('the snack sheet opens on the last meal of it', () async {
    final usual = await usualAmountOf(
      containerFor(lastMeal: (quantity: 2, unit: pieces, measureId: 'pot')),
      _yoghurt,
      forMeal: true,
    );
    expect(usual!.quantity, 2);
    expect(usual.choice, const MeasureOption(_pot));
    expect(usual.source, DefaultAmountSource.lastTime);
  });

  test('the top-up sheet reads the last top-up, not the last meal', () async {
    final usual = await usualAmountOf(
      containerFor(
        lastMeal: (quantity: 1, unit: pieces, measureId: 'pot'),
        lastTopUp: (quantity: 6, unit: pieces, measureId: 'pot'),
      ),
      _yoghurt,
      forMeal: false,
    );
    expect(usual!.quantity, 6);
  });

  test('never used: one of its word for one', () async {
    final usual = await usualAmountOf(containerFor(), _yoghurt, forMeal: true);
    expect(usual!.quantity, 1);
    expect(usual.source, DefaultAmountSource.wholeMeasure);
  });
}
