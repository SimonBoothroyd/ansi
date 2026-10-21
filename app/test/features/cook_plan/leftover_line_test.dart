/// The week's leftovers in one line, and one batch's answer in words.
library;

import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/cook_plan/presentation/cook_view.dart';
import 'package:ansi/features/cook_plan/presentation/cook_view_models.dart';
import 'package:flutter_test/flutter_test.dart';

PlannedRecipe _recipe(String id, int day, {double eaten = 0}) => PlannedRecipe(
  recipeId: id,
  title: id,
  servingsBase: 2,
  meals: [
    CoveredMeal(
      dayOfWeek: day,
      mealSlot: 'Dinner',
      portions: 2,
      entryId: '$id-$day',
      eatenPortions: eaten,
    ),
  ],
);

void main() {
  final plan = buildCookPlan([
    _recipe('ragu', 1),
    _recipe('curry', 2, eaten: 1),
    _recipe('soup', 5),
  ]);

  test('answered batches by what became of them, the rest as left', () {
    expect(
      leftoverLineFor(
        plan,
        answers: {'ragu-1': (kept: 0, binned: 2, eaten: 0)},
        daysPassed: 3,
      ),
      '2 portions binned · 1 left',
    );
  });

  test('a batch with days to come is not counted yet', () {
    expect(leftoverLineFor(plan, answers: const {}, daysPassed: 0), isNull);
  });

  test('an answer said in words', () {
    expect(
      leftoverAnswerLine((kept: 1, binned: 0, eaten: 0)),
      '1 portion kept',
    );
    expect(
      leftoverAnswerLine((kept: 1, binned: 0.5, eaten: 0)),
      '1 kept · ½ binned',
    );
  });
}
