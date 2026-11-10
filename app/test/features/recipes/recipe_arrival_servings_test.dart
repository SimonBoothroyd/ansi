/// The recipe page opened at a cooking's amount (`?servings=`), as Cook and a
/// Week meal open it: the stepper starts there, the lines scale to it, and the
/// stepper and Ansi move it as ever. Opened any other way, the page is at the
/// recipe's own servings.
library;

import 'dart:io';

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/week_recipe_band.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/recipe_view.dart';
import 'package:ansi/features/recipes/presentation/recipe_view_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_planning_repository.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/fake_week_variant_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/pump_app.dart';

const _weekKey = '2026-09-14';

const _recipe = Recipe(
  id: 'r1',
  title: 'Slow-Cooker Beef Ragù',
  servingsBase: 4,
  steps: ['Brown the meat.'],
  groups: [
    IngredientGroup(
      id: 'g1',
      items: [
        LineItem(
          id: 'l1',
          ingredientId: 'i-sausage',
          ingredientName: 'Pork sausage',
          unit: g,
          quantity: 400,
        ),
      ],
    ),
  ],
);

/// A week that plans the ragù on Tuesday, so `?week=` is a planned arrival.
class _Planner extends FakePlanningRepository {
  @override
  Stream<WeekPlan?> watchWeek(DateTime weekStart) => Stream.value(
    WeekPlan(
      id: 'wp1',
      weekStart: DateTime.utc(2026, 9, 14),
      entries: const [
        PlanEntry(
          id: 'e1',
          dayOfWeek: 1,
          mealSlot: 'Dinner',
          recipeId: 'r1',
          recipeTitle: 'Slow-Cooker Beef Ragù',
          eaterIds: ['m1'],
        ),
      ],
    ),
  );
}

/// The page under a real router, landed on [location] the way the app lands
/// on it: the query is read off the location, as `app_router.dart` reads it.
Future<GoRouter> _pumpAt(WidgetTester tester, String location) async {
  filterForuiSemanticsAssertions();
  late GoRouter router;
  await tester.pumpWidget(
    routedHost(
      initial: location,
      overrides: [
        recipeRepositoryProvider.overrideWithValue(
          FakeRecipeRepository(recipe: _recipe),
        ),
        planningRepositoryProvider.overrideWithValue(_Planner()),
        weekVariantRepositoryProvider.overrideWithValue(
          FakeWeekVariantRepository(),
        ),
      ],
      expose: (r) => router = r,
      routes: {
        '/recipes/:id': (_, state) => RecipeView(
          recipeId: state.pathParameters['id']!,
          weekKey: state.uri.queryParameters['week'],
          arrivalServings: servingsFromQuery(
            state.uri.queryParameters['servings'],
          ),
        ),
      },
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// The servings Ansi would read off the page.
double? _held(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(RecipeView)),
).read(recipeServingsProvider('r1'));

void main() {
  test('structural: the recipe route reads ?servings= through the one '
      'parser', () {
    final source = File('lib/core/router/app_router.dart').readAsStringSync();
    final start = source.indexOf("path: '/recipes/:id',");
    final route = source.substring(
      start,
      source.indexOf("path: '/recipes/:id/edit'", start),
    );
    expect(
      route.replaceAll(RegExp(r'\s'), ''),
      contains(
        'arrivalServings:servingsFromQuery('
        "state.uri.queryParameters['servings'],)",
      ),
    );
  });

  group('recipePageRoute', () {
    test('carries the week and the amount, and drops what is absent', () {
      expect(recipePageRoute('r1'), '/recipes/r1');
      expect(
        recipePageRoute('r1', weekKey: _weekKey),
        '/recipes/r1?week=$_weekKey',
      );
      expect(
        recipePageRoute('r1', weekKey: _weekKey, servings: 6),
        '/recipes/r1?week=$_weekKey&servings=6',
      );
      expect(
        recipePageRoute('r1', servings: 1.75),
        '/recipes/r1?servings=1.75',
      );
      expect(recipePageRoute('r1', servings: 0), '/recipes/r1');
    });

    test('and the page reads back only a positive number', () {
      expect(servingsFromQuery('6'), 6);
      expect(servingsFromQuery('1.75'), 1.75);
      for (final junk in [null, '', 'six', '0', '-2', 'NaN', 'Infinity']) {
        expect(servingsFromQuery(junk), isNull, reason: '$junk');
      }
    });
  });

  testWidgets('a plain open is at the recipe’s own servings', (tester) async {
    await _pumpAt(tester, '/recipes/r1');
    expect(find.text('4 servings'), findsOneWidget);
    expect(find.textContaining('400'), findsWidgets);
    expect(_held(tester), isNull);
  });

  testWidgets('opened at a cooking’s amount, the page is scaled to it', (
    tester,
  ) async {
    await _pumpAt(tester, '/recipes/r1?servings=6');
    expect(find.text('6 servings'), findsOneWidget);
    expect(find.textContaining('600'), findsWidgets);
    expect(find.textContaining('400'), findsNothing);
    // Seeded once, so Ansi reads the number on screen.
    expect(_held(tester), 6);
  });

  testWidgets('and the stepper still moves it', (tester) async {
    await _pumpAt(tester, '/recipes/r1?servings=6');
    await tester.tap(find.byIcon(FLucideIcons.plus));
    await tester.pumpAndSettle();
    expect(find.text('7 servings'), findsOneWidget);
    expect(_held(tester), 7);
  });

  testWidgets('beside ?week=, the week arrival is what it was', (tester) async {
    await _pumpAt(tester, '/recipes/r1?week=$_weekKey&servings=6');
    expect(find.byType(PlannedThisWeekBand), findsOneWidget);
    expect(find.text('6 servings'), findsOneWidget);
  });
}
