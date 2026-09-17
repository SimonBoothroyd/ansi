// The Week at a wide surface: the week as a compact agenda at LEFT, one day
// drawn as a page at right, every meal of a day in one run, one macro strip per
// day, the week's band at the agenda's foot — and the batch story staying out
// of the agenda.
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
import 'package:ansi/features/planning/presentation/week_macro_widgets.dart';
import 'package:ansi/features/planning/presentation/week_view.dart';
import 'package:ansi/features/planning/presentation/week_wide.dart';
import 'package:ansi/features/planning/presentation/week_widgets.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
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

/// A week whose today holds one meal eaten OUT beside a dish.
WeekPlan _outWeek({
  Macros? macros = const Macros(kcal: 620, protein: 42, carb: 55, fat: 24),
}) => WeekPlan(
  id: 'w',
  weekStart: _weekStart,
  entries: [
    PlanEntry(
      id: 'o1',
      dayOfWeek: _todayOffset,
      mealSlot: 'Lunch',
      label: 'Office lunch',
      macros: macros,
      eaterIds: const ['m1', 'm2'],
    ),
    _meal('e2', _todayOffset, 'Dinner'),
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
/// The Week under the REAL router, at [initial].
///
/// A router rather than a bare `home:` because the day the pane stands on now
/// lives in the location (`/week?day=…`): the agenda's `›` restates the URL and
/// the pane reads the day back off it, so there is nothing to observe without
/// one. [expose] hands the router back for a test that reads the location.
Future<void> _pumpWeek(
  WidgetTester tester, {
  WeekPlan? week,
  WeekPlan? last,
  RecipeMacroSummary? macros = _complete,
  FakeCookPlanRepository? cook,
  Size? window = const Size(1440, 1000),
  String initial = '/week',
  void Function(GoRouter router)? expose,
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
      child: MaterialApp.router(
        theme: ansiHostTheme(),
        routerConfig: _router(initial, expose),
        builder: (context, child) => FTheme(
          data: ansiThemeData(),
          child: FToaster(child: child!),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// `/week`, reading its two query params exactly as `app_router.dart` does.
GoRouter _router(String initial, void Function(GoRouter router)? expose) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/week',
        builder: (context, state) => WeekView(
          weekKey: state.uri.queryParameters['week'],
          dayKey: state.uri.queryParameters['day'],
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  expose?.call(router);
  return router;
}

/// The day pane's heading — the one title-sized serif on the screen.
Finder _paneHeading(int dayOfWeek) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      w.data == _shape.labelFull(dayOfWeek) &&
      w.style?.fontSize == AnsiType.title,
  description: 'the day pane’s heading for day $dayOfWeek',
);

/// One agenda heading — the small role, against the pane's title.
Finder _agendaHeading(int dayOfWeek) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      w.data == _shape.labelFull(dayOfWeek) &&
      w.style?.fontSize == AnsiType.small,
  description: 'the agenda heading for day $dayOfWeek',
);

/// One day's meals as the agenda draws them: ONE run, spoken.
Finder _run(String text) => find.byWidgetPredicate(
  (w) => w is Text && w.textSpan != null && spokenText(w.textSpan!) == text,
  description: 'the agenda run "$text"',
);

/// The agenda's own pane, the 340 column the whole week is drawn in.
Finder _agendaColumn() => find.byWidgetPredicate(
  (w) => w is SizedBox && w.width == 340,
  description: 'the 340 agenda column',
);

/// `600 kcal · 60P 80C 40F` — one meal served to two eaters, in the strip both
/// panes now speak. It is a day's line too, on the day that holds one meal.
const _mealStrip = '600 kcal · 60P 80C 40F';

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

  testWidgets('the agenda is the left pane, at 340, with the day beside it', (
    tester,
  ) async {
    await _pumpWeek(tester, week: _week());

    // The 340 column is the FIRST child of the row, and the day pane takes
    // whatever is left of the window — the swap the owner asked for.
    final agenda = tester.getRect(_agendaColumn());
    expect(agenda.width, 340);
    expect(tester.getTopLeft(find.text('THE WEEK')).dx, lessThan(agenda.right));
    expect(
      tester.getTopLeft(_paneHeading(_todayOffset)).dx,
      greaterThanOrEqualTo(agenda.right),
    );
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
  });

  testWidgets('the agenda names every meal of a day in ONE run', (
    tester,
  ) async {
    await _pumpWeek(tester, week: _week());

    // Today's two meals are one line, whole names, a faint `·` between them —
    // not two rows, and nothing shortened.
    expect(
      _run('Buttermilk Pancakes · Weeknight Chicken Curry'),
      findsOneWidget,
    );
    // The day beside it holds one meal and says exactly that one.
    expect(_run('Weeknight Chicken Curry'), findsOneWidget);
    // A day that holds nothing says so, and never `0 kcal`.
    expect(find.text('nothing planned'), findsNWidgets(5));
  });

  testWidgets(
    'a meal that is not for everyone carries its initial in the run',
    (tester) async {
      await _pumpWeek(
        tester,
        week: WeekPlan(
          id: 'w',
          weekStart: _weekStart,
          entries: [
            _meal(
              'e1',
              _todayOffset,
              'Breakfast',
              title: 'Buttermilk Pancakes',
            ),
            _meal('e2', _todayOffset, 'Dinner', eaters: const ['m1']),
          ],
        ),
      );

      // The mark rides on the name it belongs to, and only on that one: the
      // pancakes both eat carry nothing.
      expect(
        _run('Buttermilk Pancakes · Weeknight Chicken CurryA'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a tap anywhere on a day moves it into the pane', (tester) async {
    await _pumpWeek(tester, week: _week());

    await tester.tap(_agendaHeading(_otherDay));
    await tester.pumpAndSettle();

    // That day is now the one drawn as a page, and the pane's TODAY eyebrow is
    // gone with it — the pane is not on today any more, and says so by not
    // saying so.
    expect(_paneHeading(_otherDay), findsOneWidget);
    expect(_paneHeading(_todayOffset), findsNothing);
    expect(find.text('TODAY'), findsOneWidget);

    // The run is a target too, not only the heading: the whole day is the door.
    await tester.tap(_run('Buttermilk Pancakes · Weeknight Chicken Curry'));
    await tester.pumpAndSettle();
    expect(_paneHeading(_todayOffset), findsOneWidget);
  });

  testWidgets('the day the pane stands on is in the URL, and comes back from '
      'it', (tester) async {
    // What the owner asked for: refresh on a day and land on that day. A tap
    // restates the location; a cold start at that location opens the same pane.
    late GoRouter router;
    await _pumpWeek(tester, week: _week(), expose: (r) => router = r);

    await tester.tap(_agendaHeading(_otherDay));
    await tester.pumpAndSettle();

    final day = isoDateOf(_shape.dateFor(_weekStart, _otherDay));
    expect(
      router.state.uri.toString(),
      '/week?week=${isoDateOf(_weekStart)}&day=$day',
    );
    // A restate, not a push: nothing to press back through, so back leaves the
    // week rather than walking the days that were read.
    expect(router.canPop(), isFalse);

    // Cold, at exactly that location: the same day is the one drawn as a page.
    await _pumpWeek(
      tester,
      week: _week(),
      initial: '/week?week=${isoDateOf(_weekStart)}&day=$day',
    );
    expect(_paneHeading(_otherDay), findsOneWidget);
    expect(_paneHeading(_todayOffset), findsNothing);
  });

  testWidgets('a `?day=` from another week does not point at a day this one '
      'has not got', (tester) async {
    // The pane falls back to its default rather than obeying a stale link.
    final stale = isoDateOf(
      _shape.dateFor(_weekStart.add(const Duration(days: 7)), _otherDay),
    );
    await _pumpWeek(tester, week: _week(), initial: '/week?day=$stale');

    expect(_paneHeading(_todayOffset), findsOneWidget);
  });

  testWidgets('there is ONE add door, and it is in the day pane', (
    tester,
  ) async {
    await _pumpWeek(tester, week: _week());

    // The owner's call: the agenda has nowhere honest for seven doors, so it
    // has none at all and the pane keeps the one.
    expect(find.text('add a meal'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('add a meal')).dx,
      greaterThanOrEqualTo(tester.getRect(_agendaColumn()).right),
    );
    // And none of the agenda's furniture came with it: the slot label is the
    // pane's, and so is every `−` — the run carries none.
    expect(find.text('BREAKFAST'), findsOneWidget);
    expect(find.byType(RemoveTarget), findsNWidgets(2));
    for (final remove in tester.widgetList(find.byType(RemoveTarget))) {
      expect(
        tester.getTopLeft(find.byWidget(remove)).dx,
        greaterThanOrEqualTo(tester.getRect(_agendaColumn()).right),
      );
    }
  });

  testWidgets('every meal in the pane carries its own served macros, and every '
      'day its own strip', (tester) async {
    await _pumpWeek(tester, week: _week());

    // Today's two meals: the recipe's per-serving figure MULTIPLIED by the
    // portions planned, in the strip the phone already speaks — twice in the
    // pane, and once more as the agenda's line for the day that holds one meal.
    expect(macroText(_mealStrip), findsNWidgets(3));
    // Today's own line is the sum of exactly those two meals, drawn once, in
    // the agenda — the parts and the whole read one function, so they cannot
    // disagree.
    expect(macroText('1 200 kcal · 120P 160C 80F'), findsOneWidget);
    // The ledger under the pane keeps the words, with its mandatory
    // denominator: it is the one place with the room to spell the grams out.
    expect(macroText('1 200 kcal · 2 meals'), findsOneWidget);
    expect(find.text('protein 120 g · carbs 160 g · fat 80 g'), findsOneWidget);
    expect(find.textContaining('carbs'), findsOneWidget);
  });

  group('a meal eaten out', () {
    testWidgets('the day pane draws it at the third weight, with its tag and '
        'its figures, and no cook marker', (tester) async {
      await _pumpWeek(tester, week: _outWeek(), cook: _batched());

      expect(find.text('Office lunch'), findsWidgets);
      expect(find.byType(OutTag), findsOneWidget);
      expect(find.text('620 kcal · 42P \u2014 as stated'), findsOneWidget);
      // The dish beside it still has its batch sentence, so an absent marker
      // on this row is the kind's own rule.
      expect(find.byType(CookMarkerLine), findsOneWidget);
    });

    testWidgets('the agenda marks it with a hollow dot, in the run\u2019s own '
        'voice', (tester) async {
      await _pumpWeek(tester, week: _outWeek());

      // Spoken, the mark reads as the words it stands in for — which is both
      // what a screen reader hears and what the run says.
      expect(
        _run('eaten out Office lunch · Weeknight Chicken Curry'),
        findsOneWidget,
      );
    });

    testWidgets('its kcal join the day only when they were stated', (
      tester,
    ) async {
      await _pumpWeek(tester, week: _outWeek());
      // 620 × 2 eaters + the dish's 600 for the same two — the day's own
      // strip, and the week band under it, which is this one day.
      expect(macroTextContaining('144P 190C 88F'), findsWidgets);

      await _pumpWeek(tester, week: _outWeek(macros: null));
      expect(macroText(_mealStrip), findsWidgets);
      expect(
        find.textContaining('Office lunch · macros not stated'),
        findsWidgets,
      );
      // The day still states its own denominator rather than a bare number.
      expect(find.textContaining('1 of 2 meals'), findsWidgets);
    });
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
    // A refused day draws NO strip, on either side, and the week's band none
    // either — there is no number to draw.
    expect(find.byType(MacroStrip), findsNothing);
    // It NAMES what it left out rather than counting it: the pane's ledger,
    // today's agenda line and the week's band.
    expect(
      find.textContaining('Buttermilk Pancakes · 1 stub line'),
      findsNWidgets(3),
    );
    expect(macroTextContaining('kcal'), findsNothing);
    expect(find.textContaining('kcal'), findsNothing);
    expect(find.textContaining('carbs'), findsNothing);
  });

  testWidgets('each agenda day states what it holds at its heading', (
    tester,
  ) async {
    await _pumpWeek(tester, week: _week());

    // The count is the heading's, because the figures are the strip under it.
    expect(find.text('2 meals'), findsOneWidget);
    expect(find.text('1 meal'), findsOneWidget);
    // The five empty days say so, and not one of them says nought.
    expect(find.text('no meals'), findsNWidgets(5));
    expect(macroText('0 kcal · 0 meals'), findsNothing);
  });

  testWidgets('the week band is drawn at the agenda’s foot', (tester) async {
    await _pumpWeek(tester, week: _week());

    final band = tester.getRect(find.byType(WeekFootBand));
    final agenda = tester.getRect(_agendaColumn());
    // In the agenda's column, at its bottom — under the seventh day, not
    // beside the day pane.
    expect(band.left, agenda.left);
    expect(band.right, agenda.right);
    expect(band.bottom, agenda.bottom);
    // The week's total in the days' own strip, and the average with both of
    // its denominators under it.
    expect(macroText('1 800 kcal · 180P 240C 120F'), findsOneWidget);
    expect(find.text('avg 900 · 2 of 7 days'), findsOneWidget);
  });

  testWidgets('the batch story stays out of the agenda', (tester) async {
    await _pumpWeek(tester, week: _week(), cook: _batched());

    // The pane says it once, for the day it is drawing — `cooks today · batch
    // of 4` on the cook day, `from <day>'s batch` on the day it feeds.
    expect(find.textContaining('batch'), findsOneWidget);
    // And the agenda says nothing about it: no marker, no fresh→gone bar, on
    // any of the seven days. That is the trade the owner took — the
    // relationship moved to the pane rather than being repeated seven times.
    expect(find.byType(MiniFreshBar), findsOneWidget);
  });

  testWidgets('an empty week draws seven headings, one door and the copy '
      'chip', (tester) async {
    await _pumpWeek(tester, last: _week());

    for (var d = 0; d < 7; d++) {
      expect(_agendaHeading(d), findsOneWidget);
    }
    // Seven agenda days saying a day holds nothing, and the pane's one door
    // saying it of the day it is on.
    expect(find.text('nothing planned'), findsNWidgets(8));
    expect(find.text('add a meal'), findsNothing);
    expect(find.text('copy last week'), findsOneWidget);
    // The phone's primary is not drawn twice: the pane already has the door.
    expect(find.text('Add the first meal'), findsNothing);
    // Eight absences — seven headings and the pane's ledger — and no zero.
    expect(find.text('no meals'), findsNWidgets(8));
    expect(macroTextContaining('kcal'), findsNothing);
    // The band draws NOTHING on a week with nothing in it: seven days already
    // said so, and an eighth absence under them says nothing new.
    expect(tester.getSize(find.byType(WeekFootBand)).height, 0);
  });

  testWidgets('an iPad in landscape holds the same two panes', (tester) async {
    // 1180 × 820: the agenda keeps its 340 and the day pane gives up the 260,
    // absorbing it in reading slack rather than in type — and nothing
    // overflows (the harness fails the test if anything does).
    await _pumpWeek(tester, week: _week(), window: const Size(1180, 820));

    expect(tester.getRect(_agendaColumn()).width, 340);
    expect(_paneHeading(_todayOffset), findsOneWidget);
    expect(_agendaHeading(_otherDay), findsOneWidget);
    expect(
      _run('Buttermilk Pancakes · Weeknight Chicken Curry'),
      findsOneWidget,
    );
    expect(macroText(_mealStrip), findsNWidgets(3));
    expect(macroText('1 200 kcal · 2 meals'), findsOneWidget);
  });

  testWidgets('a narrower window still gets the phone list, untouched', (
    tester,
  ) async {
    await _pumpWeek(tester, week: _week(), window: null);

    // The phone's own day card: its dense glyph strip whole, its `nothing
    // planned` door, and not one of the wide form's words or marks.
    expect(macroText('600 kcal · 60P 80C 40F'), findsWidgets);
    expect(find.text('nothing planned'), findsWidgets);
    expect(find.text('THE WEEK'), findsNothing);
    expect(find.textContaining('carbs'), findsNothing);
    expect(find.byType(WeekFootBand), findsNothing);
  });
}
