import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:mise/core/theme/mise_theme.dart';
import 'package:mise/features/planning/data/planning_providers.dart';
import 'package:mise/features/planning/domain/planning.dart';
import 'package:mise/features/planning/domain/planning_repository.dart';
import 'package:mise/features/planning/presentation/week_view.dart';
import 'package:mise/features/recipes/data/recipe_providers.dart';
import 'package:mise/features/recipes/domain/recipe.dart';
import 'package:mise/features/recipes/domain/recipe_repository.dart';

/// A canned planner: emits [week] for the current week and [last] as the
/// reference week, with two members. Mutations are inert.
class _FakePlanningRepo implements PlanningRepository {
  _FakePlanningRepo({this.week, this.last});

  final WeekPlan? week;
  final WeekPlan? last;

  @override
  Stream<WeekPlan?> watchWeek(DateTime weekStart) => Stream.value(week);

  @override
  Future<WeekPlan?> mostRecentWeekBefore(DateTime weekStart) async => last;

  @override
  Future<List<Member>> members() async => const [
    Member(id: 'm1', displayName: 'Ada'),
    Member(id: 'm2', displayName: 'Jun'),
  ];

  @override
  Future<String> addEntry({
    required DateTime weekStart,
    required int dayOfWeek,
    required String mealSlot,
    required String recipeId,
    required List<String> eaterIds,
    int? portions,
  }) async => 'e';

  @override
  Future<void> setEaters(String entryId, List<String> eaterIds) async {}

  @override
  Future<void> removeEntry(String entryId) async {}

  @override
  Future<int> copyLastWeek(DateTime weekStart) async => 0;
}

class _NoRecipesRepo implements RecipeRepository {
  @override
  Stream<List<RecipeSummary>> watchRecipes() => Stream.value(const []);
  @override
  Stream<Recipe?> watchRecipe(String id) => Stream.value(null);
  @override
  Future<void> saveRecipe(Recipe recipe) async {}
  @override
  Future<void> deleteRecipe(String id) async {}
}

Widget _host(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    home: FTheme(data: miseThemeData(), child: const WeekView()),
  ),
);

void main() {
  testWidgets('empty week shows the blank-week CTA', (tester) async {
    await tester.pumpWidget(
      _host([
        planningRepositoryProvider.overrideWithValue(_FakePlanningRepo()),
        recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
      ]),
    );
    await tester.pump();

    expect(find.text('A blank week'), findsOneWidget);
    expect(find.text('Plan a meal'), findsOneWidget);
    // With no earlier week, the copy affordance is absent.
    expect(find.text('Copy last week'), findsNothing);
  });

  testWidgets('empty week with an earlier week offers "copy last week"', (
    tester,
  ) async {
    final last = WeekPlan(
      id: 'w0',
      weekStart: DateTime.utc(2026, 8, 17),
      entries: const [
        PlanEntry(
          id: 'e0',
          dayOfWeek: 0,
          mealSlot: 'Dinner',
          recipeId: 'r1',
          recipeTitle: 'Ragu',
          eaterIds: ['m1'],
        ),
      ],
    );
    await tester.pumpWidget(
      _host([
        planningRepositoryProvider.overrideWithValue(
          _FakePlanningRepo(last: last),
        ),
        recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
      ]),
    );
    await tester.pump();

    expect(find.text('Copy last week'), findsOneWidget);
    expect(find.text('Last week, for reference'), findsOneWidget);
  });

  testWidgets('a planned week renders the day grid with the meal', (
    tester,
  ) async {
    final week = WeekPlan(
      id: 'w',
      weekStart: DateTime.utc(2026, 8, 24),
      entries: const [
        PlanEntry(
          id: 'e1',
          dayOfWeek: 3,
          mealSlot: 'Dinner',
          recipeId: 'r1',
          recipeTitle: 'Weeknight Chicken Curry',
          eaterIds: ['m1', 'm2'],
        ),
      ],
    );
    await tester.pumpWidget(
      _host([
        planningRepositoryProvider.overrideWithValue(
          _FakePlanningRepo(week: week),
        ),
        recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
      ]),
    );
    await tester.pump();

    expect(find.text('Thursday'), findsOneWidget);
    expect(find.text('Weeknight Chicken Curry'), findsOneWidget);
    // Every day still offers a dashed add-a-meal button.
    expect(find.text('＋ Add a meal'), findsWidgets);
    // The Shared/Per-person lens is present on a populated week.
    expect(find.text('Per-person'), findsOneWidget);
  });
}
