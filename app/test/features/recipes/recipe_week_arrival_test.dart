/// The recipe page reached FROM a week that plans it: the band under its
/// title, the second door in its ⋯ menu, and the week's own lines.
///
/// The variant shipped with one door, at the foot of the meal editor sheet.
/// These are the other two arrivals — the Week's dish row and the Cook card —
/// and the guard that keeps a stale `?week=` from offering a week the person
/// has left.
///
/// The page then draws what that week cooks, read-only, in week mode's own
/// grammar — and its `optional` tag becomes the switch that answers *this
/// time, yes*. From the Library every one of those facts is absent: the page
/// is byte-for-byte the one it has always been.
library;

import 'dart:io';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/week_recipe_band.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:ansi/features/recipes/presentation/ingredient_line.dart';
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
  macros: RecipeMacroSummary(
    perServing: Macros(kcal: 520, protein: 34, carb: 48, fat: 19),
  ),
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
        LineItem(
          id: 'l2',
          ingredientId: 'i-onions',
          ingredientName: 'Pickled Red Onions',
          unit: pieces,
          quantity: 1,
          optional: true,
        ),
        LineItem(
          id: 'l3',
          ingredientId: 'i-parmesan',
          ingredientName: 'Parmesan',
          unit: g,
          quantity: 30,
        ),
      ],
    ),
  ],
);

/// The week's answer on one line, in the shape the repository stores.
LineOverride _override(
  LineOverrideAction action, {
  String? lineId,
  String id = 'ov1',
  String? ingredientId,
  String ingredientName = '',
  double? quantity,
  Unit? unit,
}) => LineOverride(
  id: id,
  action: action,
  recipeLineItemId: lineId,
  ingredientId: ingredientId,
  ingredientName: ingredientName,
  quantity: quantity,
  unit: unit,
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
  required FakeWeekVariantRepository variants,
  bool plansIt = true,
}) => [
  recipeRepositoryProvider.overrideWithValue(
    FakeRecipeRepository(recipe: _recipe),
  ),
  planningRepositoryProvider.overrideWithValue(_Planner(plansIt: plansIt)),
  weekVariantRepositoryProvider.overrideWithValue(variants),
];

/// The page under a real router, landed on the way the app lands on it: the
/// `?week=` is read off the location, not handed to the widget.
Future<GoRouter> _pumpPage(
  WidgetTester tester, {
  String? week,
  bool plansIt = true,
  FakeWeekVariantRepository? variants,
}) async {
  filterForuiSemanticsAssertions();
  late GoRouter router;
  await tester.pumpWidget(
    routedHost(
      initial: week == null ? '/recipes/r1' : '/recipes/r1?week=$week',
      overrides: _overrides(
        plansIt: plansIt,
        variants: variants ?? FakeWeekVariantRepository(),
      ),
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

/// The rendered row that names [ingredient] — what the week's answer on that
/// line landed on.
RecipeIngredientLine _lineFor(WidgetTester tester, String ingredient) =>
    tester.widget<RecipeIngredientLine>(
      find.byWidgetPredicate(
        (w) => w is RecipeIngredientLine && w.uses.ingredientName == ingredient,
      ),
    );

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
        variants: FakeWeekVariantRepository(
          overrides: {
            'r1': [_override(LineOverrideAction.exclude, lineId: 'l1')],
          },
        ),
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

  group('the page holds the week', () {
    testWidgets('an optional line the week ticked in wears the tag lit', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        week: _weekKey,
        variants: FakeWeekVariantRepository(
          overrides: {
            'r1': [_override(LineOverrideAction.include, lineId: 'l2')],
          },
        ),
      );

      expect(find.text('included'), findsOneWidget);
      expect(find.text('optional'), findsNothing);
      expect(_lineFor(tester, 'Pickled Red Onions').included, isTrue);
    });

    testWidgets('tapping the tag ticks that line in for that week', (
      tester,
    ) async {
      final variants = FakeWeekVariantRepository();
      await _pumpPage(tester, week: _weekKey, variants: variants);

      expect(find.text('optional'), findsOneWidget);
      await tester.tap(find.byType(OptionalTag));
      await tester.pumpAndSettle();

      expect(variants.ticked, [
        (weekStart: _monday, recipeId: 'r1', lineId: 'l2', included: true),
      ]);
    });

    testWidgets('and tapping an included one takes it back out', (
      tester,
    ) async {
      final variants = FakeWeekVariantRepository(
        overrides: {
          'r1': [_override(LineOverrideAction.include, lineId: 'l2')],
        },
      );
      await _pumpPage(tester, week: _weekKey, variants: variants);

      await tester.tap(find.byType(OptionalTag));
      await tester.pumpAndSettle();

      expect(variants.ticked, [
        (weekStart: _monday, recipeId: 'r1', lineId: 'l2', included: false),
      ]);
    });

    testWidgets('a line the week leaves out is struck, and is no door', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        week: _weekKey,
        variants: FakeWeekVariantRepository(
          overrides: {
            'r1': [_override(LineOverrideAction.exclude, lineId: 'l3')],
          },
        ),
      );

      final row = _lineFor(tester, 'Parmesan');
      expect(row.struck, isTrue);
      expect(row.onOpenIngredient, isNull);
      expect(
        tester.widget<Text>(find.text('30 g')).style?.decoration,
        TextDecoration.lineThrough,
      );
      // The line it still cooks is untouched by its neighbour's exclusion.
      expect(_lineFor(tester, 'Pork sausage').struck, isFalse);
    });

    testWidgets("a replaced line prints the week's amount, and it still "
        'scales', (tester) async {
      await _pumpPage(
        tester,
        week: _weekKey,
        variants: FakeWeekVariantRepository(
          overrides: {
            'r1': [
              _override(
                LineOverrideAction.replace,
                lineId: 'l1',
                ingredientId: 'i-sausage',
                ingredientName: 'Pork sausage',
                quantity: 500,
                unit: g,
              ),
            ],
          },
        ),
      );

      expect(find.text('500 g'), findsOneWidget);
      expect(find.text('400 g'), findsNothing);

      await tester.tap(find.byIcon(FLucideIcons.plus));
      await tester.pumpAndSettle();
      expect(find.text('625 g'), findsOneWidget);
    });

    testWidgets('an added line lands after the last group', (tester) async {
      await _pumpPage(
        tester,
        week: _weekKey,
        variants: FakeWeekVariantRepository(
          overrides: {
            'r1': [
              _override(
                LineOverrideAction.add,
                id: 'ov-add',
                ingredientId: 'i-chilli',
                ingredientName: 'Chilli Oil',
                quantity: 2,
                unit: tbsp,
              ),
            ],
          },
        ),
      );

      expect(find.text('Chilli Oil'), findsOneWidget);
      expect(find.text('2 tbsp'), findsOneWidget);
      expect(
        tester.getRect(find.text('Chilli Oil')).top,
        greaterThan(tester.getRect(find.text('Parmesan')).top),
      );
    });

    testWidgets("the panel reads the week's summary, and names what came in", (
      tester,
    ) async {
      await _pumpPage(
        tester,
        week: _weekKey,
        variants: FakeWeekVariantRepository(
          overrides: {
            'r1': [_override(LineOverrideAction.include, lineId: 'l2')],
          },
          variantMacros: const {
            'r1': RecipeMacroSummary(
              perServing: Macros(kcal: 566, protein: 35, carb: 52, fat: 20),
            ),
          },
        ),
      );

      // The week's figure, not the recipe's 520.
      expect(find.text('566'), findsOneWidget);
      expect(find.text('520'), findsNothing);
      expect(find.text('INCLUDED'), findsOneWidget);
      expect(find.text('Pickled Red Onions · for this week'), findsOneWidget);
      // Nothing optional is left out, so no row says there is.
      expect(find.text('OPTIONAL'), findsNothing);
    });

    testWidgets('and names what is still out, which its own notes cannot', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        week: _weekKey,
        variants: FakeWeekVariantRepository(
          overrides: {
            'r1': [_override(LineOverrideAction.exclude, lineId: 'l3')],
          },
          variantMacros: const {
            'r1': RecipeMacroSummary(
              perServing: Macros(kcal: 480, protein: 30, carb: 46, fat: 16),
            ),
          },
        ),
      );

      expect(find.text('OPTIONAL'), findsOneWidget);
      expect(find.text('Pickled Red Onions'), findsWidgets);
      expect(find.text('INCLUDED'), findsNothing);
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

    testWidgets('from the Library the tag stays a tag: nothing to tap, and '
        'nothing it could write', (tester) async {
      await _pumpPage(tester);

      expect(find.text('optional'), findsOneWidget);
      expect(_lineFor(tester, 'Pickled Red Onions').onToggleOptional, isNull);
      expect(
        tester.widget<OptionalTag>(find.byType(OptionalTag)).onToggle,
        isNull,
      );
      expect(
        find.descendant(
          of: find.byType(OptionalTag),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
      expect(find.text('INCLUDED'), findsNothing);
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
