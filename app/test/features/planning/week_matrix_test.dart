// The Week at a wide surface: the matrix, its derived slot rows, the one add
// door per column, and the two halves of a day's macro line.
//
// The window is set with `tester.view.physicalSize`, not `setSurfaceSize`:
// `AnsiLayout.of` reads `MediaQuery.sizeOf`, which follows the view, while
// `setSurfaceSize` moves only the render surface — a test written with it draws
// the phone list at 1440 and proves nothing.
import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/account/data/household_providers.dart';
import 'package:ansi/features/cook_plan/data/cook_plan_providers.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/week_matrix.dart';
import 'package:ansi/features/planning/presentation/week_view.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_cook_plan_repository.dart';
import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/fake_planning_repository.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/fake_week_variant_repository.dart';
import '../../helpers/macro_line.dart';

/// A canned planner: emits [week], with [last] behind it as the week a copy
/// would come from. Mutations are inert.
class _Planner extends FakePlanningRepository {
  _Planner({this.week, this.last})
    : super(const [
        Member(id: 'm1', displayName: 'Ada'),
        Member(id: 'm2', displayName: 'Jun'),
      ]);

  final WeekPlan? week;
  final WeekPlan? last;

  @override
  Stream<WeekPlan?> watchWeek(DateTime weekStart) => Stream.value(week);

  @override
  Future<WeekPlan?> mostRecentWeekBefore(DateTime weekStart) async => last;
}

/// 300 kcal a serving, so a two-meal day reads 600 and no figure on screen
/// reaches the thousands separator.
const _complete = RecipeMacroSummary(
  perServing: Macros(kcal: 300, protein: 30, carb: 40, fat: 20),
);

PlanEntry _meal(String id, int day, String slot) => PlanEntry(
  id: id,
  dayOfWeek: day,
  mealSlot: slot,
  recipeId: 'r1',
  recipeTitle: 'Weeknight Chicken Curry',
  eaterIds: const ['m1'],
);

/// A breakfast on the first day and two dinners on the fourth — the second
/// spelled `dinner`, which must share Dinner's row rather than open a second.
WeekPlan _week() => WeekPlan(
  id: 'w',
  weekStart: DateTime.utc(2026, 8, 24),
  entries: [
    _meal('e1', 0, 'Breakfast'),
    _meal('e2', 3, 'Dinner'),
    _meal('e3', 3, 'dinner'),
  ],
);

/// Pumps the Week. [window] defaults to a 1440 × 1000 desk, where the screen is
/// a matrix; pass null for the default test window (800 × 600 — `medium`, where
/// the phone list is still the layout).
Future<void> _pumpWeek(
  WidgetTester tester, {
  WeekPlan? week,
  WeekPlan? last,
  RecipeMacroSummary? macros = _complete,
  Size? window = const Size(1440, 1000),
}) async {
  if (window != null) {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        planningRepositoryProvider.overrideWithValue(
          _Planner(week: week, last: last),
        ),
        recipeRepositoryProvider.overrideWithValue(
          FakeRecipeRepository(
            summaries: [
              RecipeSummary(
                id: 'r1',
                title: 'Weeknight Chicken Curry',
                servingsBase: 2,
                macros: macros,
              ),
            ],
          ),
        ),
        cookPlanRepositoryProvider.overrideWithValue(FakeCookPlanRepository()),
        ingredientRepositoryProvider.overrideWithValue(
          const ReadOnlyIngredientRepo(),
        ),
        measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
        weekVariantRepositoryProvider.overrideWithValue(
          FakeWeekVariantRepository(),
        ),
        weekShapeProvider.overrideWithValue(WeekShape.monday),
      ],
      child: MaterialApp(
        theme: ansiHostTheme(),
        home: FTheme(
          data: ansiThemeData(),
          child: const FToaster(child: WeekView()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the rows are the slots the week has', () {
    test('deduped case-insensitively, in the app’s slot order', () {
      expect(slotRowsOf(_week()), ['Breakfast', 'Dinner']);
      // A custom slot sorts after the four defaults, where mealSlotRank puts
      // it — and a week with nothing in it has no rows at all.
      expect(
        slotRowsOf(
          WeekPlan(
            id: 'w',
            weekStart: DateTime.utc(2026, 8, 24),
            entries: [_meal('e1', 1, 'Brunch'), _meal('e2', 2, 'Lunch')],
          ),
        ),
        ['Lunch', 'Brunch'],
      );
      expect(slotRowsOf(null), isEmpty);
    });

    testWidgets('only the slots present get a gutter row', (tester) async {
      await _pumpWeek(tester, week: _week());

      expect(find.text('BREAKFAST'), findsOneWidget);
      expect(find.text('DINNER'), findsOneWidget);
      // Nobody planned these two, so the matrix does not draw them; a fixed
      // four-row grid would.
      expect(find.text('LUNCH'), findsNothing);
      expect(find.text('SNACK'), findsNothing);
      // Three meals, three cards — the second `dinner` shares Dinner's row.
      expect(find.text('Weeknight Chicken Curry'), findsNWidgets(3));
      // The seven day heads, from the household's first day.
      for (final day in [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ]) {
        expect(find.text(day), findsOneWidget);
      }
    });
  });

  testWidgets('every column keeps its one add door, in every state', (
    tester,
  ) async {
    await _pumpWeek(tester, week: _week());

    expect(find.text('add a meal'), findsNWidgets(7));
    // The phone's empty-day wording never appears here: a column foot says
    // `add a meal` whatever its day holds, and the day's emptiness is said by
    // the line under it.
    expect(find.text('nothing planned'), findsNothing);
  });

  testWidgets('the day line splits at its first separator: energy in the '
      'foot, grams in the band', (tester) async {
    await _pumpWeek(tester, week: _week());

    // The foot: the figure and its MANDATORY denominator, nothing else.
    expect(macroText('600 kcal · 2 meals'), findsOneWidget);
    expect(macroText('300 kcal · 1 meal'), findsOneWidget);
    // The band, under the same column: the rest of that same line.
    expect(macroText('60P 80C 40F'), findsOneWidget);
    expect(macroText('30P 40C 20F'), findsOneWidget);
    // And never the whole phone line at this width — it does not fit a column.
    expect(macroText('600 kcal · 60P 80C 40F'), findsNothing);
    // Five days hold nothing. Each says so twice, in its foot and its band,
    // and neither says nought.
    expect(find.text('no meals'), findsNWidgets(10));
    expect(macroText('0 kcal \u00b7 0P 0C 0F'), findsNothing);
  });

  testWidgets('an incomplete day refuses in the phone’s own words', (
    tester,
  ) async {
    await _pumpWeek(
      tester,
      week: _week(),
      macros: const RecipeMacroSummary(stubLines: 1),
    );

    // Two days refuse: the badge in both the foot and the band, the reason
    // named in the band — and not one figure anywhere.
    expect(find.text('no total'), findsNWidgets(2));
    expect(
      find.textContaining('no total — Weeknight Chicken Curry · 1 stub line'),
      findsNWidgets(2),
    );
    expect(macroTextContaining('kcal'), findsNothing);
  });

  testWidgets('an empty week draws the heads, the doors and the copy chip', (
    tester,
  ) async {
    await _pumpWeek(tester, last: _week());

    // No slot rows at all: there is nothing to name.
    for (final slot in ['BREAKFAST', 'LUNCH', 'DINNER', 'SNACK']) {
      expect(find.text(slot), findsNothing);
    }
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('Sunday'), findsOneWidget);
    expect(find.text('add a meal'), findsNWidgets(7));
    expect(find.text('copy last week'), findsOneWidget);
    // The phone's primary is not drawn twice: the seven column feet already
    // carry the add doors.
    expect(find.text('Add the first meal'), findsNothing);
    expect(find.text('no meals'), findsNWidgets(14));
  });

  testWidgets('an iPad in landscape holds the same structure', (tester) async {
    // 1180 × 820: the gutter and every column give up a few pixels and what
    // pays is text, not structure — the seven columns, the slot rows and each
    // column's own door and figures all still stand, and nothing overflows
    // (the harness fails the test if anything does).
    await _pumpWeek(tester, week: _week(), window: const Size(1180, 820));

    expect(find.text('BREAKFAST'), findsOneWidget);
    expect(find.text('DINNER'), findsOneWidget);
    expect(find.text('add a meal'), findsNWidgets(7));
    expect(macroText('600 kcal · 2 meals'), findsOneWidget);
    expect(macroText('60P 80C 40F'), findsOneWidget);
  });

  testWidgets('the week band has no wide home yet, so none is drawn', (
    tester,
  ) async {
    await _pumpWeek(tester, week: _week());

    // Where the week's total, its average and `n of 7 days` sit at this width
    // is still an open question on the wide-screens plan, and an invented
    // answer would be the harder one to take back.
    expect(find.text('PLANNED · WEEK · EVERYONE'), findsNothing);
    expect(find.textContaining('not a daily target'), findsNothing);
  });

  testWidgets('a narrower window still gets the phone list, untouched', (
    tester,
  ) async {
    await _pumpWeek(tester, week: _week(), window: null);

    // A day with nothing on it carries the phone's own `nothing planned` door,
    // no band names the days under the list, and the day's macro line is whole
    // — the split belongs to the matrix and stays there.
    expect(find.text('nothing planned'), findsWidgets);
    expect(find.text('PER DAY'), findsNothing);
    expect(macroText('300 kcal · 30P 40C 20F'), findsOneWidget);
    expect(macroText('300 kcal · 1 meal'), findsNothing);
  });
}
