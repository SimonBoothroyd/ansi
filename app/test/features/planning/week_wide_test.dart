// The Week at a wide surface: today drawn large in the day pane, the whole week
// as a scrolling agenda beside it, one macro line per meal, and the batch story
// staying out of the right-hand pane.
//
// The window is set with `tester.view.physicalSize`, not `setSurfaceSize`:
// `AnsiLayout.of` reads `MediaQuery.sizeOf`, which follows the view, while
// `setSurfaceSize` moves only the render surface — a test written with it draws
// the phone list at 1440 and proves nothing.
//
// The fixture is built around the REAL today rather than a pinned clock:
// `ViewedWeekStart` seeds itself from `DateTime.now()`, so a fixed clock would
// put the week on screen and the week containing "today" in two different
// places — and then nothing would be today at all. So the days are named
// through the shape, exactly as the screen names them.
import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/account/data/household_providers.dart';
import 'package:ansi/features/cook_plan/data/cook_plan_providers.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/week_format.dart';
import 'package:ansi/features/planning/presentation/week_view.dart';
import 'package:ansi/features/planning/presentation/week_wide.dart';
import 'package:ansi/features/planning/presentation/week_widgets.dart';
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

/// 300 kcal a serving over two eaters, so a meal reads 600 and a two-meal day
/// 1 200 — one figure over the thousand, which is what puts the thin thousands
/// separator under test too.
const _complete = RecipeMacroSummary(
  perServing: Macros(kcal: 300, protein: 30, carb: 40, fat: 20),
);

const _shape = WeekShape.monday;
final _weekStart = _shape.weekStartOf(DateTime.now());
final _todayOffset = _shape.offsetOf(DateTime.now());

/// A second day of the same week, never today and always adjacent to it — so
/// one batch can honestly cover both.
final _otherDay = _todayOffset == 0 ? 1 : _todayOffset - 1;
final _cookDay = _todayOffset < _otherDay ? _todayOffset : _otherDay;

PlanEntry _meal(
  String id,
  int day,
  String slot, {
  String title = 'Weeknight Chicken Curry',
  List<String> eaters = const ['m1', 'm2'],
}) => PlanEntry(
  id: id,
  dayOfWeek: day,
  mealSlot: slot,
  recipeId: 'r1',
  recipeTitle: title,
  eaterIds: eaters,
);

/// Two meals on today (a breakfast and a dinner) and one on the day beside it.
WeekPlan _week() => WeekPlan(
  id: 'w',
  weekStart: _weekStart,
  entries: [
    _meal('e1', _todayOffset, 'Breakfast', title: 'Buttermilk Pancakes'),
    _meal('e2', _todayOffset, 'Dinner'),
    _meal('e3', _otherDay, 'Dinner'),
  ],
);

/// The session behind the two dinners: one pot on the earlier day, covering
/// both — so there is a batch sentence for the pane to print.
FakeCookPlanRepository _batched() => FakeCookPlanRepository.of([
  PlannedRecipe(
    recipeId: 'r1',
    title: 'Weeknight Chicken Curry',
    servingsBase: 2,
    keepsForDays: 6,
    meals: [
      CoveredMeal(dayOfWeek: _cookDay, mealSlot: 'Dinner', portions: 2),
      CoveredMeal(
        dayOfWeek: _cookDay == _todayOffset ? _otherDay : _todayOffset,
        mealSlot: 'Dinner',
        portions: 2,
      ),
    ],
  ),
]);

/// Pumps the Week. [window] defaults to a 1440 × 1000 desk, where the screen is
/// the day pane beside the agenda; pass null for the default test window
/// (800 × 600 — `medium`, where the phone list is still the layout).
Future<void> _pumpWeek(
  WidgetTester tester, {
  WeekPlan? week,
  WeekPlan? last,
  RecipeMacroSummary? macros = _complete,
  FakeCookPlanRepository? cook,
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
        cookPlanRepositoryProvider.overrideWithValue(
          cook ?? FakeCookPlanRepository(),
        ),
        ingredientRepositoryProvider.overrideWithValue(
          const ReadOnlyIngredientRepo(),
        ),
        measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
        weekVariantRepositoryProvider.overrideWithValue(
          FakeWeekVariantRepository(),
        ),
        weekShapeProvider.overrideWithValue(_shape),
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

/// The day pane's heading — the one 38 px serif on the screen.
Finder _paneHeading(int dayOfWeek) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      w.data == _shape.labelFull(dayOfWeek) &&
      w.style?.fontSize == 38,
  description: 'the day pane’s heading for day $dayOfWeek',
);

/// One agenda heading — 20 px, against the pane's 38.
Finder _agendaHeading(int dayOfWeek) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      w.data == _shape.labelFull(dayOfWeek) &&
      w.style?.fontSize == 20,
  description: 'the agenda heading for day $dayOfWeek',
);

/// The agenda's own `›` marks, told apart from the switcher's 18 px chevron in
/// the header by their size.
Finder _agendaChevrons() => find.byWidgetPredicate(
  (w) => w is Icon && w.icon == FLucideIcons.chevronRight && w.size == 15,
  description: 'the agenda’s › marks',
);

/// `600 kcal · protein 60 g · carbs 80 g · fat 40 g` — one meal's served line.
const _mealLine = '600 kcal · protein 60 g · carbs 80 g · fat 40 g';

void main() {
  group('slot groups', () {
    test('consecutive same-slot meals share one label, case-insensitively', () {
      final groups = slotGroupsOf([
        _meal('a', 0, 'Breakfast'),
        _meal('b', 0, 'Dinner'),
        _meal('c', 0, 'dinner'),
      ]);
      expect(groups.map((g) => g.length), [1, 2]);
      expect(groups.last.first.mealSlot, 'Dinner');
      expect(slotGroupsOf(const []), isEmpty);
    });
  });

  group('the eater mark', () {
    const roster = [
      Member(id: 'm1', displayName: 'Ada'),
      Member(id: 'm2', displayName: 'Jun'),
    ];

    test('prints only where the meal is not for everyone', () {
      // Both eat it: naming them adds nothing, so nothing is named.
      expect(eaterMark(_meal('a', 0, 'Dinner'), roster), isNull);
      // One of the two: the initial is the whole point of the mark.
      expect(eaterMark(_meal('a', 0, 'Dinner', eaters: ['m1']), roster), 'A');
      // Nobody: a real state, in the phone's own word.
      expect(
        eaterMark(_meal('a', 0, 'Dinner', eaters: const []), roster),
        'nobody',
      );
    });
  });

  testWidgets('the day pane opens on TODAY, and the agenda lists the week', (
    tester,
  ) async {
    await _pumpWeek(tester, week: _week());

    // Today is the day drawn large. Nobody chose it and nothing was persisted
    // for it to be right.
    expect(_paneHeading(_todayOffset), findsOneWidget);
    expect(_paneHeading(_otherDay), findsNothing);
    // The pane's eyebrow and the agenda's tag, on the same day.
    expect(find.text('TODAY'), findsNWidgets(2));

    // Seven agenda headings, from the household's first day, with the week's
    // own span over them.
    for (var d = 0; d < 7; d++) {
      expect(_agendaHeading(d), findsOneWidget);
    }
    expect(find.text('THE WEEK'), findsOneWidget);
    expect(find.text(formatWeekSpan(_weekStart)), findsOneWidget);

    // The add door on every day plus the pane's own: two days have meals, five
    // do not, and the pane is on a day that does.
    expect(find.text('add a meal'), findsNWidgets(3));
    expect(find.text('nothing planned'), findsNWidgets(5));
  });

  testWidgets('the agenda heading’s › moves that day into the pane', (
    tester,
  ) async {
    await _pumpWeek(tester, week: _week());

    // The day already open draws no `›`; the other six do.
    expect(_agendaChevrons(), findsNWidgets(6));

    await tester.tap(_agendaHeading(_otherDay));
    await tester.pumpAndSettle();

    // That day is now the one drawn large, and the pane's TODAY eyebrow is
    // gone with it — the pane is not on today any more, and says so by not
    // saying so.
    expect(_paneHeading(_otherDay), findsOneWidget);
    expect(_paneHeading(_todayOffset), findsNothing);
    expect(find.text('TODAY'), findsOneWidget);
    // Still six: the newly-open day gave its `›` up and today took one.
    expect(_agendaChevrons(), findsNWidgets(6));
  });

  testWidgets('every meal in the pane carries its own served macros', (
    tester,
  ) async {
    await _pumpWeek(tester, week: _week());

    // Today's two meals: the recipe's per-serving figure MULTIPLIED by the
    // portions planned, spelt out in words rather than the phone's glyphs.
    expect(find.text(_mealLine), findsNWidgets(2));
    // The ledger under them is the sum of exactly those two lines, with its
    // mandatory denominator — the parts and the whole read one function, so
    // they cannot disagree. Drawn twice: the pane's foot and today's agenda
    // line.
    expect(macroText('1 200 kcal · 2 meals'), findsNWidgets(2));
    expect(find.text('protein 120 g · carbs 160 g · fat 80 g'), findsOneWidget);
  });

  testWidgets('a meal whose recipe is incomplete refuses instead of printing '
      'a number', (tester) async {
    await _pumpWeek(
      tester,
      week: _week(),
      macros: const RecipeMacroSummary(stubLines: 1),
    );

    // Per meal: the badge and the reason in the shared vocabulary — the exact
    // words the recipe panel and the picker row refuse in — and no figure.
    expect(find.text('no total — 1 stub line'), findsNWidgets(2));
    // The day refuses too, and NAMES what it left out rather than counting it:
    // once in the pane's ledger, once on today's agenda line.
    expect(
      find.textContaining('Buttermilk Pancakes · 1 stub line'),
      findsNWidgets(2),
    );
    expect(macroTextContaining('kcal'), findsNothing);
    expect(find.textContaining('kcal'), findsNothing);
    expect(find.textContaining('carbs'), findsNothing);
  });

  testWidgets('each agenda day states its energy and its denominator', (
    tester,
  ) async {
    await _pumpWeek(tester, week: _week());

    // One plain line per day that has meals, under its heading.
    expect(macroText('600 kcal · 1 meal'), findsOneWidget);
    // The five empty days say so, and not one of them says nought.
    expect(find.text('no meals'), findsNWidgets(5));
    expect(macroText('0 kcal \u00b7 0 meals'), findsNothing);
    // The grams stay in the pane: two meal lines and one ledger, and nothing
    // on the right.
    expect(find.textContaining('carbs'), findsNWidgets(3));
  });

  testWidgets('the batch story stays out of the agenda', (tester) async {
    await _pumpWeek(tester, week: _week(), cook: _batched());

    // The pane says it once, for the day it is drawing — `cooks today · batch
    // of 4` on the cook day, `from <day>'s batch` on the day it feeds.
    expect(find.textContaining('batch'), findsOneWidget);
    // And the agenda says nothing about it: no marker, no fresh→gone bar, on
    // any of the seven lines. That is the trade the owner took — the
    // relationship moved to the pane rather than being repeated seven times.
    expect(find.byType(MiniFreshBar), findsOneWidget);
  });

  testWidgets('an empty week draws seven headings, their doors and the copy '
      'chip', (tester) async {
    await _pumpWeek(tester, last: _week());

    for (var d = 0; d < 7; d++) {
      expect(_agendaHeading(d), findsOneWidget);
    }
    // Seven agenda doors and the pane's own, all saying the same thing about a
    // day that holds nothing.
    expect(find.text('nothing planned'), findsNWidgets(8));
    expect(find.text('add a meal'), findsNothing);
    expect(find.text('copy last week'), findsOneWidget);
    // The phone's primary is not drawn twice: the agenda already has the doors.
    expect(find.text('Add the first meal'), findsNothing);
    // Eight absences — seven agenda lines and the pane's ledger — and no zero.
    expect(find.text('no meals'), findsNWidgets(8));
    expect(macroTextContaining('kcal'), findsNothing);
  });

  testWidgets('an iPad in landscape holds the same two panes', (tester) async {
    // 1180 × 820: the day pane keeps its 560 and the agenda gives up the 136,
    // absorbing it in slack rather than in type — and nothing overflows (the
    // harness fails the test if anything does).
    await _pumpWeek(tester, week: _week(), window: const Size(1180, 820));

    expect(_paneHeading(_todayOffset), findsOneWidget);
    expect(_agendaHeading(_otherDay), findsOneWidget);
    expect(find.text(_mealLine), findsNWidgets(2));
    expect(macroText('1 200 kcal · 2 meals'), findsNWidgets(2));
  });

  testWidgets('a narrower window still gets the phone list, untouched', (
    tester,
  ) async {
    await _pumpWeek(tester, week: _week(), window: null);

    // The phone's own day card: its dense glyph strip whole, its `nothing
    // planned` door, and not one of the wide form's words or marks.
    expect(macroText('600 kcal · 60P 80C 40F'), findsOneWidget);
    expect(find.text('nothing planned'), findsWidgets);
    expect(find.text('THE WEEK'), findsNothing);
    expect(find.textContaining('carbs'), findsNothing);
    expect(_agendaChevrons(), findsNothing);
  });
}
