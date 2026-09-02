import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/domain/planning_repository.dart';
import 'package:ansi/features/planning/presentation/week_format.dart';
import 'package:ansi/features/planning/presentation/week_view.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

/// A canned planner: emits [week] for the current week and [last] as the
/// reference week, with two members. Mutations are inert.
class _FakePlanningRepo implements PlanningRepository {
  _FakePlanningRepo({this.week, this.last, this.onCopy});

  final WeekPlan? week;
  final WeekPlan? last;
  final void Function(DateTime weekStart)? onCopy;

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
  Future<int> copyLastWeek(DateTime weekStart) async {
    onCopy?.call(weekStart);
    return 0;
  }

  @override
  Stream<Map<String, DateTime>> watchLastPlanned() => Stream.value(const {});
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

  @override
  Future<void> setFavorite(String id, bool favorite) async {}

  @override
  Future<List<RecipeUse>> usedIn(String recipeId) async => const [];

  @override
  Future<bool> componentLinkWouldCycle({
    required String recipeId,
    required String subRecipeId,
  }) async => false;
}

Widget _host(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    home: FTheme(data: ansiThemeData(), child: const WeekView()),
  ),
);

/// The same view inside a real router, so a tap's destination is observable.
/// `expose` hands the router back for the test to read the location from.
Widget _routedHost(List<Override> overrides, void Function(GoRouter) expose) {
  final router = GoRouter(
    initialLocation: '/week',
    routes: [
      GoRoute(path: '/week', builder: (_, _) => const WeekView()),
      GoRoute(
        path: '/recipes/:id',
        builder: (_, state) =>
            FScaffold(child: Text('recipe ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  expose(router);
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => FTheme(data: ansiThemeData(), child: child!),
    ),
  );
}

WeekPlan _plannedWeek() => WeekPlan(
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

void main() {
  group('the week switcher (D2/D3)', () {
    final monday = mondayOf(DateTime.now());
    String titleFor(int weeksAhead) {
      final t = formatWeekTitle(
        monday.add(Duration(days: 7 * weeksAhead)),
        monday,
      );
      return t.date == null ? t.label : '${t.label} · ${t.date}';
    }

    testWidgets('names this week, and the chevrons step off it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host([
          planningRepositoryProvider.overrideWithValue(
            _FakePlanningRepo(week: _plannedWeek()),
          ),
          recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text(titleFor(0)), findsOneWidget);
      // No banner and no return pill while the current week is on screen.
      expect(find.text('this week'), findsNothing);

      await tester.tap(find.byIcon(FLucideIcons.chevronRight).first);
      await tester.pumpAndSettle();
      expect(find.text(titleFor(1)), findsOneWidget);

      await tester.tap(find.byIcon(FLucideIcons.chevronLeft).first);
      await tester.tap(find.byIcon(FLucideIcons.chevronLeft).first);
      await tester.pumpAndSettle();
      expect(find.text(titleFor(-1)), findsOneWidget);
    });

    testWidgets('another week announces that Cook and Shop came too, and '
        'offers one tap home', (tester) async {
      await tester.pumpWidget(
        _host([
          planningRepositoryProvider.overrideWithValue(
            _FakePlanningRepo(week: _plannedWeek()),
          ),
          recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(FLucideIcons.chevronRight).first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Cook and Shop follow it too'),
        findsOneWidget,
      );

      await tester.tap(find.text('this week'));
      await tester.pumpAndSettle();
      expect(find.text(titleFor(0)), findsOneWidget);
      expect(find.textContaining('Cook and Shop follow it too'), findsNothing);
    });

    testWidgets('the title menu jumps weeks and owns "copy last week"', (
      tester,
    ) async {
      final copied = <DateTime>[];
      await tester.pumpWidget(
        _host([
          planningRepositoryProvider.overrideWithValue(
            _FakePlanningRepo(
              week: _plannedWeek(),
              last: _plannedWeek(),
              onCopy: copied.add,
            ),
          ),
          recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(titleFor(0)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last week'));
      await tester.pumpAndSettle();
      expect(find.text(titleFor(-1)), findsOneWidget);

      await tester.tap(find.text(titleFor(-1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy last week into this one'));
      await tester.pumpAndSettle();
      // It copies into the week you are STANDING on, not into today's.
      expect(copied, [monday.subtract(const Duration(days: 7))]);

      await tester.tap(find.text(titleFor(-1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jump to today'));
      await tester.pumpAndSettle();
      expect(find.text(titleFor(0)), findsOneWidget);
    });
  });

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
    await tester.pumpWidget(
      _host([
        planningRepositoryProvider.overrideWithValue(
          _FakePlanningRepo(week: _plannedWeek()),
        ),
        recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
      ]),
    );
    await tester.pump();

    expect(find.text('Thursday'), findsOneWidget);
    expect(find.text('Weeknight Chicken Curry'), findsOneWidget);
    // Every day still offers a dashed add-a-meal button.
    expect(find.text('Add a meal'), findsWidgets);
    // The Shared/Per-person lens is present on a populated week.
    expect(find.text('Per-person'), findsOneWidget);
  });

  testWidgets('tapping a planned dish opens its recipe', (tester) async {
    late GoRouter router;
    await tester.pumpWidget(
      _routedHost([
        planningRepositoryProvider.overrideWithValue(
          _FakePlanningRepo(week: _plannedWeek()),
        ),
        recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
      ], (r) => router = r),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Weeknight Chicken Curry'));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/recipes/r1');
    expect(find.text('recipe r1'), findsOneWidget);
  });

  testWidgets('the dish menu still opens without navigating', (tester) async {
    late GoRouter router;
    await tester.pumpWidget(
      _routedHost([
        planningRepositoryProvider.overrideWithValue(
          _FakePlanningRepo(week: _plannedWeek()),
        ),
        recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
      ], (r) => router = r),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.ellipsis).first);
    await tester.pumpAndSettle();

    expect(find.text('Remove'), findsOneWidget);
    expect(router.state.uri.toString(), '/week');
  });
}
