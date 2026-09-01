import 'package:ansi/core/theme/mise_theme.dart';
import 'package:ansi/features/cook_plan/data/cook_plan_providers.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan_repository.dart';
import 'package:ansi/features/cook_plan/presentation/cook_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

/// A canned cook plan: emits a fixed plan built from [recipes].
class _FakeCookPlanRepo implements CookPlanRepository {
  _FakeCookPlanRepo(this.recipes);

  final List<PlannedRecipe> recipes;

  @override
  Stream<CookPlan> watchCookPlan(DateTime weekStart) =>
      Stream.value(buildCookPlan(recipes));
}

Widget _host(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    home: FTheme(data: miseThemeData(), child: const CookView()),
  ),
);

PlannedRecipe _recipe(
  String title,
  Map<int, int> days, {
  int? keeps,
  bool freezable = false,
}) => PlannedRecipe(
  recipeId: title,
  title: title,
  servingsBase: 2,
  keepsForDays: keeps,
  freezable: freezable,
  meals: [
    for (final e in days.entries)
      CoveredMeal(dayOfWeek: e.key, mealSlot: 'Dinner', portions: e.value),
  ],
);

void main() {
  testWidgets('an empty plan shows the blank state', (tester) async {
    await tester.pumpWidget(
      _host([
        cookPlanRepositoryProvider.overrideWithValue(
          _FakeCookPlanRepo(const []),
        ),
      ]),
    );
    await tester.pump();

    expect(find.text('Nothing to cook yet'), findsOneWidget);
    expect(find.text('Plan the week'), findsOneWidget);
  });

  testWidgets('a split recipe renders its sessions and split note', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        cookPlanRepositoryProvider.overrideWithValue(
          // Mon + Sat, keeps 3 → two batches.
          _FakeCookPlanRepo([
            _recipe('Chicken Curry', {0: 2, 5: 2}, keeps: 3),
          ]),
        ),
      ]),
    );
    await tester.pump();

    expect(find.text('Chicken Curry'), findsOneWidget);
    expect(find.text('Cook Mon'), findsOneWidget);
    expect(find.text('Cook Sat'), findsOneWidget);
    expect(find.textContaining('cook it again, fresh'), findsOneWidget);
  });

  testWidgets('a freezable far meal shows the freezer note', (tester) async {
    await tester.pumpWidget(
      _host([
        cookPlanRepositoryProvider.overrideWithValue(
          // Tue + Sat, keeps 3, freezable → one batch, Saturday frozen.
          _FakeCookPlanRepo([
            _recipe('House Ragù', {1: 2, 5: 2}, keeps: 3, freezable: true),
          ]),
        ),
      ]),
    );
    await tester.pump();

    expect(find.text('Cook Tue'), findsOneWidget);
    expect(find.textContaining('freezes'), findsOneWidget);
    expect(find.textContaining("Saturday's share"), findsOneWidget);
  });
}
