/// The recipe page reached FROM a week that plans it: the band under its
/// title, and the second door in its ⋯ menu.
///
/// The variant shipped with one door, at the foot of the meal editor sheet.
/// These are the other two arrivals — the Week's dish row and the Cook card —
/// and the guard that keeps a stale `?week=` from offering a week the person
/// has left.
library;

import 'dart:io';

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/week_recipe_band.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/recipe_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/fake_planning_repository.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/fake_week_variant_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/pump_app.dart';

const _weekKey = '2026-09-14';
final _monday = DateTime.utc(2026, 9, 14);

const _recipe = Recipe(
  id: 'r1',
  title: 'Slow-Cooker Beef Ragù',
  servingsBase: 4,
  steps: ['Brown the meat.'],
  groups: [
    IngredientGroup(
      id: 'g1',
      name: 'for the ragù',
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

/// The week that plans the recipe on Tuesday and Saturday — or, [plansIt]
/// false, the same week after the meals were removed: the stale-link case.
WeekPlan _week({bool plansIt = true}) => WeekPlan(
  id: 'wp1',
  weekStart: _monday,
  entries: plansIt
      ? const [
          PlanEntry(
            id: 'e1',
            dayOfWeek: 1,
            mealSlot: 'Dinner',
            recipeId: 'r1',
            recipeTitle: 'Slow-Cooker Beef Ragù',
            eaterIds: ['m1'],
          ),
          PlanEntry(
            id: 'e2',
            dayOfWeek: 5,
            mealSlot: 'Dinner',
            recipeId: 'r1',
            recipeTitle: 'Slow-Cooker Beef Ragù',
            eaterIds: ['m1'],
          ),
        ]
      : const [],
);

class _Planner extends FakePlanningRepository {
  _Planner({this.plansIt = true})
    : super(const [Member(id: 'm1', displayName: 'Ada')]);

  final bool plansIt;

  @override
  Stream<WeekPlan?> watchWeek(DateTime weekStart) =>
      Stream.value(_week(plansIt: plansIt));
}

List<Override> _overrides({
  bool plansIt = true,
  Map<String, List<LineOverride>> variant = const {},
}) => [
  recipeRepositoryProvider.overrideWithValue(
    FakeRecipeRepository(recipe: _recipe),
  ),
  planningRepositoryProvider.overrideWithValue(_Planner(plansIt: plansIt)),
  weekVariantRepositoryProvider.overrideWithValue(
    FakeWeekVariantRepository(overrides: variant),
  ),
];

/// The page under a real router, landed on the way the app lands on it: the
/// `?week=` is read off the location, not handed to the widget.
Future<GoRouter> _pumpPage(
  WidgetTester tester, {
  String? week,
  bool plansIt = true,
  Map<String, List<LineOverride>> variant = const {},
}) async {
  filterForuiSemanticsAssertions();
  late GoRouter router;
  await tester.pumpWidget(
    routedHost(
      initial: week == null ? '/recipes/r1' : '/recipes/r1?week=$week',
      overrides: _overrides(plansIt: plansIt, variant: variant),
      expose: (r) => router = r,
      routes: {
        '/recipes/:id': (_, state) => RecipeView(
          recipeId: state.pathParameters['id']!,
          weekKey: state.uri.queryParameters['week'],
        ),
        '/recipes/:id/edit': (_, _) => const Text('the editor'),
      },
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(FLucideIcons.ellipsis));
  await tester.pumpAndSettle();
}

void main() {
  test('structural: the recipe route reads ?week= exactly as the editor '
      'route does', () {
    final source = File('lib/core/router/app_router.dart').readAsStringSync();
    final start = source.indexOf("path: '/recipes/:id',");
    expect(start, isNot(-1), reason: 'the recipe route should exist');
    final route = source.substring(
      start,
      source.indexOf('),\n      ),', start),
    );
    expect(
      route,
      contains("weekKey: state.uri.queryParameters['week']"),
      reason: 'the page has to be told which week it was opened from',
    );
    expect(route, contains("state.pathParameters['id']"));
  });

  group('a planned arrival', () {
    testWidgets('prints one band saying which days of that week cook it', (
      tester,
    ) async {
      await _pumpPage(tester, week: _weekKey);
      expect(find.byType(PlannedThisWeekBand), findsOneWidget);
      expect(find.text('Planned Tue · Sat this week'), findsOneWidget);
    });

    testWidgets('the band is one line with a calendar glyph and no fill — the '
        'chip row is the only filled shape above the tabs', (tester) async {
      await _pumpPage(tester, week: _weekKey);

      expect(
        find.descendant(
          of: find.byType(PlannedThisWeekBand),
          matching: find.byIcon(FLucideIcons.calendarDays),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(PlannedThisWeekBand),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
      );
    });

    testWidgets('says so in the band when the week varies the recipe', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        week: _weekKey,
        variant: const {
          'r1': [
            LineOverride(
              id: 'ov1',
              action: LineOverrideAction.exclude,
              recipeLineItemId: 'l1',
            ),
          ],
        },
      );
      expect(
        find.text('Planned Tue · Sat this week · edited for this week'),
        findsOneWidget,
      );
    });

    testWidgets('its ⋯ menu holds two doors, named so they read as two', (
      tester,
    ) async {
      await _pumpPage(tester, week: _weekKey);
      await _openMenu(tester);
      expect(find.text('Edit recipe'), findsOneWidget);
      expect(find.text('Edit for this week · Tue & Sat only'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('and the week door opens week mode for that week', (
      tester,
    ) async {
      final router = await _pumpPage(tester, week: _weekKey);
      await _openMenu(tester);
      await tester.tap(find.text('Edit for this week · Tue & Sat only'));
      await tester.pumpAndSettle();
      expect(
        router.state.uri.toString(),
        '/recipes/r1/edit?week=$_weekKey',
        reason: 'the shipped week mode, on the week the link named',
      );
    });
  });

  group('every other arrival is the page it has always been', () {
    testWidgets('from the Library: no band, and one Edit', (tester) async {
      await _pumpPage(tester);
      expect(find.byType(PlannedThisWeekBand), findsNothing);
      await _openMenu(tester);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Edit recipe'), findsNothing);
      expect(find.textContaining('Edit for this week'), findsNothing);
    });

    testWidgets('a week that no longer plans it offers neither — a stale link '
        'must not offer a week the person left', (tester) async {
      await _pumpPage(tester, week: _weekKey, plansIt: false);
      expect(find.byType(PlannedThisWeekBand), findsNothing);
      await _openMenu(tester);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.textContaining('Edit for this week'), findsNothing);
    });

    testWidgets('and a week key that is not a date is simply not a week', (
      tester,
    ) async {
      await _pumpPage(tester, week: 'last-tuesday-ish');
      expect(find.byType(PlannedThisWeekBand), findsNothing);
      await _openMenu(tester);
      expect(find.textContaining('Edit for this week'), findsNothing);
    });
  });
}
