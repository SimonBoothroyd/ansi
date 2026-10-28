import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/account/data/household_providers.dart';
import 'package:ansi/features/planning/presentation/week_recipe_band.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/shared/week_strip.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/pump_app.dart';

List<int> _cooked(WeekStrip strip) => [
  for (final (i, d) in strip.days.indexed)
    if (d.fill == WeekStripFill.cooked) i,
];

List<int> _eats(WeekStrip strip) => [
  for (final (i, d) in strip.days.indexed)
    if (d.eats) i,
];

void main() {
  testWidgets('with the recipe, only the cook days are underlined and a meal '
      'from the fridge is a dot', (tester) async {
    await tester.pumpApp(
      const PlannedThisWeekBand(days: [1, 3], edited: true, recipeId: 'r1'),
      overrides: [
        weekShapeProvider.overrideWithValue(WeekShape.monday),
        recipeRepositoryProvider.overrideWithValue(
          FakeRecipeRepository(
            summaries: const [
              RecipeSummary(
                id: 'r1',
                title: 'Ragù',
                servingsBase: 4,
                keepsForDays: 4,
              ),
            ],
          ),
        ),
      ],
    );
    await tester.pumpAndSettle();
    final strip = tester.widget<WeekStrip>(find.byType(WeekStrip));
    expect(strip.size, WeekStripSize.line);
    expect(_cooked(strip), [1]);
    expect(_eats(strip), [1, 3]);
    expect(find.text('edited for this week'), findsOneWidget);
  });

  testWidgets('without the recipe, every planned day is drawn as a cook', (
    tester,
  ) async {
    await tester.pumpApp(
      const PlannedThisWeekBand(days: [1, 5], edited: false),
      overrides: [weekShapeProvider.overrideWithValue(WeekShape.monday)],
    );
    final strip = tester.widget<WeekStrip>(find.byType(WeekStrip));
    expect(_cooked(strip), [1, 5]);
    expect(find.text('edited for this week'), findsNothing);
  });
}
