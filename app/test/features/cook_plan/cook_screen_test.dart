import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/cook_plan/data/cook_plan_providers.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/cook_plan/presentation/cook_format.dart';
import 'package:ansi/features/cook_plan/presentation/cook_sheet.dart';
import 'package:ansi/features/cook_plan/presentation/cook_view.dart';
import 'package:ansi/features/planning/presentation/week_format.dart';
import 'package:ansi/features/planning/presentation/week_header.dart';
import 'package:ansi/features/planning/presentation/week_view_models.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/fake_cook_plan_repository.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/pump_app.dart';

/// The recipe list the component card reads its target's yield off.
FakeRecipeRepository _recipeRepo({double? yieldQty, Unit? yieldUnit}) =>
    FakeRecipeRepository(
      summaries: [
        RecipeSummary(
          id: 'aioli',
          title: 'Romesco Aioli',
          servingsBase: 4,
          yieldQty: yieldQty,
          yieldUnit: yieldUnit,
        ),
      ],
    );

Widget _host(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    home: FTheme(data: ansiThemeData(), child: const CookView()),
  ),
);

/// The same view inside a real router, so a tap's destination is observable.
Widget _routedHost(List<Override> overrides, void Function(GoRouter) expose) =>
    routedHost(
      initial: '/cook',
      overrides: overrides,
      expose: expose,
      routes: {
        '/cook': (_, _) => const CookView(),
        '/recipes/:id': (_, state) =>
            FScaffold(child: Text('recipe ${state.pathParameters['id']}')),
      },
    );

PlannedRecipe _recipe(
  String title,
  Map<int, num> days, {
  String? id,
  int? keeps,
  bool freezable = false,
}) => PlannedRecipe(
  recipeId: id ?? title,
  title: title,
  servingsBase: 2,
  keepsForDays: keeps,
  freezable: freezable,
  meals: [
    for (final e in days.entries)
      CoveredMeal(
        dayOfWeek: e.key,
        mealSlot: 'Dinner',
        portions: e.value.toDouble(),
      ),
  ],
);

void main() {
  testWidgets('the week switcher is the whole title, and its menu speaks in '
      'cooks', (tester) async {
    await tester.pumpWidget(
      _host([
        cookPlanRepositoryProvider.overrideWithValue(
          FakeCookPlanRepository.of(const []),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    final monday = WeekShape.monday.weekStartOf(DateTime.now());
    String titleFor(int weeksAhead) {
      final t = formatWeekTitle(
        monday.add(Duration(days: 7 * weeksAhead)),
        monday,
        WeekShape.monday,
      );
      return '${t.label} · ${t.date}';
    }

    // No screen name and no pill: the switcher names the week, and the lit
    // tab in the bar is what says "Cook".
    expect(find.byType(WeekSwitcher), findsOneWidget);
    expect(find.text(titleFor(0)), findsOneWidget);
    expect(find.textContaining('Batch cook plan'), findsNothing);
    expect(find.text('this week'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(CookView)),
    );
    container.read(viewedWeekStartProvider.notifier).step(1);
    await tester.pumpAndSettle();
    expect(find.text(titleFor(1)), findsOneWidget);
    expect(find.text('this week'), findsNothing);

    // The menu: this tab's own derivation on the row it has derived, no Week
    // write (D7b), and "This week" as the way home.
    await tester.tap(find.text(titleFor(1)));
    await tester.pumpAndSettle();
    expect(find.text('nothing to cook'), findsOneWidget);
    expect(find.text('Copy last week into this one'), findsNothing);
    await tester.tap(find.text('This week'));
    await tester.pumpAndSettle();
    expect(find.text(titleFor(0)), findsOneWidget);
  });

  testWidgets('a fractional demand reads as a fraction on the session row and '
      'in the whole-batch nudge', (tester) async {
    // A 1 and a ¾ eater of a serves-2 recipe: ×0.88 → cook ×1, ¼ over.
    await tester.pumpWidget(
      _host([
        cookPlanRepositoryProvider.overrideWithValue(
          FakeCookPlanRepository.of([
            _recipe('Curry', {0: 1.75}, keeps: 3),
          ]),
        ),
      ]),
    );
    await tester.pump();

    expect(find.text('covers Mon dinner · 1¾ portions'), findsOneWidget);
    expect(find.text('×⅞'), findsOneWidget);
    expect(
      find.text(
        'cook ×1 instead — covers 2 portions · ¼ portion left over · '
        'shopping still buys ×⅞',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('1.75'), findsNothing);
  });

  testWidgets('an empty plan is a quiet line INSIDE the '
      'screen', (tester) async {
    await tester.pumpWidget(
      _host([
        cookPlanRepositoryProvider.overrideWithValue(
          FakeCookPlanRepository.of(const []),
        ),
      ]),
    );
    await tester.pump();

    // The chrome stays put — header and caption — and the empty body carries
    // the door that would fill it, instead of a full-bleed page with one exit.
    expect(find.byType(WeekSwitcher), findsOneWidget);
    expect(
      find.text('grouped by recipe · split by shelf life'),
      findsOneWidget,
    );
    expect(
      find.textContaining('nothing planned for this week yet'),
      findsOneWidget,
    );
    expect(find.text('plan a meal'), findsOneWidget);
  });

  testWidgets('a split recipe renders its sessions and split note', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        cookPlanRepositoryProvider.overrideWithValue(
          // Mon + Sat, keeps 3 → two batches.
          FakeCookPlanRepository.of([
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
          FakeCookPlanRepository.of([
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

  group('component sessions', () {
    testWidgets('a component card reads in batches, names its parents, and '
        'says what is left over', (tester) async {
      await tester.pumpWidget(
        _host([
          cookPlanRepositoryProvider.overrideWithValue(
            FakeCookPlanRepository(_planWith(yields: [(qty: 1, unit: cup)])),
          ),
          recipeRepositoryProvider.overrideWithValue(
            _recipeRepo(yieldQty: 1, yieldUnit: cup),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Romesco Aioli · for Sausage Sliders'), findsOneWidget);
      expect(
        find.text('derived from a component line · keeps 5 d'),
        findsOneWidget,
      );
      // Ready BY the parent's cook day, denominated in batches.
      expect(find.text('Cook by Sat'), findsOneWidget);
      expect(find.text('×¼ batch'), findsOneWidget);
      expect(
        find.text(
          'covers Sausage Sliders · cook Sat — makes 1 cup, you need ¼',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Nothing here tracks the leftover'),
        findsOneWidget,
      );
    });

    testWidgets('a component with no yield is a named gap, never a ×1', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host([
          cookPlanRepositoryProvider.overrideWithValue(
            FakeCookPlanRepository(_planWith(yields: const [])),
          ),
          recipeRepositoryProvider.overrideWithValue(_recipeRepo()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Romesco Aioli · for Sausage Sliders'), findsOneWidget);
      expect(
        find.text('derived from a component line · yield not set'),
        findsOneWidget,
      );
      expect(find.text('no scale'), findsOneWidget);
      expect(
        find.text('Romesco Aioli doesn’t say how much it makes'),
        findsOneWidget,
      );
      expect(find.text('Set the yield'), findsOneWidget);
      // The refusal this whole state exists to avoid: the only scale on the
      // screen is the sliders' own ×1 — the gap contributes none.
      expect(find.textContaining('×'), findsOneWidget);
      expect(find.text('×1'), findsOneWidget);
      expect(find.text('×1 batch'), findsNothing);
    });
  });

  testWidgets("tapping a card's title opens the recipe it derives from", (
    tester,
  ) async {
    late GoRouter router;
    await tester.pumpWidget(
      _routedHost([
        cookPlanRepositoryProvider.overrideWithValue(
          FakeCookPlanRepository.of([
            _recipe('Chicken Curry', {0: 2}, id: 'r1'),
          ]),
        ),
      ], (r) => router = r),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chicken Curry'));
    await tester.pumpAndSettle();

    // The week rides along (`?week=`), so the recipe page can offer the week
    // door. Cook itself stays read-only — it carries the week, it does not
    // write it.
    expect(
      router.state.uri.toString(),
      '/recipes/r1?week=${WeekShape.monday.keyOf(DateTime.now())}',
    );
    expect(find.text('recipe r1'), findsOneWidget);
  });

  group('at a desk', () {
    /// A desk-width window — the band the schedule sheet belongs to. Tall, so
    /// every row is laid out rather than built lazily.
    void deskWidth(WidgetTester tester) {
      tester.view.physicalSize = const Size(1440, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    /// One week, three shelf lives: a batch the window carries to its second
    /// meal, one the window cannot reach (so it cooks twice), and one the
    /// freezer rescues.
    List<Override> threeCooks() => [
      cookPlanRepositoryProvider.overrideWithValue(
        FakeCookPlanRepository.of([
          _recipe('Chicken Curry', {0: 2, 2: 2}, keeps: 2),
          _recipe('House Ragù', {1: 2, 6: 2}, keeps: 2),
          _recipe('Bean Stew', {2: 2, 6: 2}, keeps: 2, freezable: true),
        ]),
      ),
    ];

    /// What one row's track carries on one day of the week.
    CookTrackDay marks(WidgetTester tester, String row, int day) => tester
        .widget<CookTrackCell>(find.byKey(ValueKey('cook-track-$row-$day')))
        .marks;

    testWidgets('the plan is ONE sheet: a row per recipe against a single '
        'seven-day axis, capped and centred', (tester) async {
      deskWidth(tester);
      await tester.pumpWidget(_host(threeCooks()));
      await tester.pump();

      final first = tester.getTopLeft(find.text('Chicken Curry'));
      final second = tester.getTopLeft(find.text('House Ragù'));
      final third = tester.getTopLeft(find.text('Bean Stew'));

      // One row each, down one column — no second column, so no hole under a
      // short row.
      expect(second.dx, first.dx);
      expect(third.dx, first.dx);
      expect(second.dy, greaterThan(first.dy));
      expect(third.dy, greaterThan(second.dy));

      // The axis is drawn ONCE, over all three rows.
      for (final day in ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN']) {
        expect(find.text(day), findsOneWidget, reason: day);
      }
      // …and every row reads against it: a day's cell sits under its own head.
      for (final (day, head) in ['MON', 'TUE', 'WED'].indexed) {
        expect(
          tester
              .getCenter(find.byKey(ValueKey('cook-track-Bean Stew-$day')))
              .dx,
          closeTo(tester.getCenter(find.text(head)).dx, 1),
        );
      }

      // The sheet caps at its 1140 and is centred in the 1440 pane, and the
      // card — with its own per-session timeline — is gone.
      expect(first.dx, closeTo(150, 1));
      expect(find.byType(CookTimeline), findsNothing);
      expect(
        find.text('grouped by recipe · split by shelf life'),
        findsOneWidget,
      );
      // The row still says every word the card said.
      expect(
        find.text('4 portions across the week · keeps 2 d'),
        findsNWidgets(2),
      );
      expect(
        find.text('4 portions across the week · keeps 2 d · freezable'),
        findsOneWidget,
      );
      expect(find.text('Cook Mon ×2'), findsOneWidget);
      expect(find.text('covers Mon + Wed dinner · 4 portions'), findsOneWidget);
    });

    testWidgets('the cook tick stands on the cook day and the keep band runs '
        'the keep window', (tester) async {
      deskWidth(tester);
      await tester.pumpWidget(_host(threeCooks()));
      await tester.pump();

      // One cook, Monday, at ×2 — and the band runs Monday to Wednesday, which
      // is the two days the batch keeps plus the day it is made.
      expect(marks(tester, 'Chicken Curry', 0).cookScale, '×2');
      expect(
        [for (var d = 0; d < 7; d++) marks(tester, 'Chicken Curry', d).keeps],
        [true, true, true, false, false, false, false],
      );
      // Nothing else on the row is a cook.
      expect([
        for (var d = 1; d < 7; d++) marks(tester, 'Chicken Curry', d).cookScale,
      ], everyElement(isNull));
      // The day the window carried it to is a plain eaten dot; the cook day
      // takes the tick and no dot.
      expect(marks(tester, 'Chicken Curry', 2).dot, CookTrackDot.eaten);
      expect(marks(tester, 'Chicken Curry', 0).dot, CookTrackDot.none);

      // A split is two ticks on one row, each with its own band.
      expect(marks(tester, 'House Ragù', 1).cookScale, '×1');
      expect(marks(tester, 'House Ragù', 6).cookScale, '×1');
      expect(
        [for (var d = 0; d < 7; d++) marks(tester, 'House Ragù', d).keeps],
        [false, true, true, true, false, false, true],
      );
    });

    testWidgets('a covered day past the window is the amber dot, and the '
        'warning is said once for the row', (tester) async {
      deskWidth(tester);
      await tester.pumpWidget(_host(threeCooks()));
      await tester.pump();

      // The freezer's far meal: cooked Wednesday, kept to Friday, eaten Sunday.
      expect(marks(tester, 'Bean Stew', 2).cookScale, '×2');
      expect(
        [for (var d = 0; d < 7; d++) marks(tester, 'Bean Stew', d).keeps],
        [false, false, true, true, true, false, false],
      );
      expect(marks(tester, 'Bean Stew', 6).dot, CookTrackDot.pastWindow);

      // Amber is ONLY that: no other day of no other row claims it, the split
      // row's own far meal least of all — it is a second cook, not a stretch.
      for (final row in ['Chicken Curry', 'House Ragù', 'Bean Stew']) {
        for (var day = 0; day < 7; day++) {
          expect(
            marks(tester, row, day).dot == CookTrackDot.pastWindow,
            row == 'Bean Stew' && day == 6,
            reason: '$row day $day',
          );
        }
      }

      // One warning per row that needs one, however many sessions it has.
      expect(
        find.text(
          'A later meal falls past the 2-day window — cook it again, fresh.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining("Sunday's share"), findsOneWidget);
    });

    testWidgets('every door the card offers is on the row: the title, and the '
        'whole-batch nudge the track follows', (tester) async {
      deskWidth(tester);
      late GoRouter router;
      await tester.pumpWidget(
        _routedHost([
          cookPlanRepositoryProvider.overrideWithValue(
            FakeCookPlanRepository.of([
              _recipe('Curry', {0: 1.75}, id: 'r1', keeps: 3),
            ]),
          ),
        ], (r) => router = r),
      );
      await tester.pumpAndSettle();

      // The honest factor is on the row and on its tick.
      expect(find.text('Cook Mon ×⅞'), findsOneWidget);
      expect(marks(tester, 'r1', 0).cookScale, '×⅞');

      // The nudge is the same display toggle, and the tick follows the words.
      await tester.tap(
        find.text(
          'cook ×1 instead — covers 2 portions · ¼ portion left over · '
          'shopping still buys ×⅞',
        ),
      );
      await tester.pump();
      expect(
        find.text('showing the whole batch — tap for the honest ×⅞'),
        findsOneWidget,
      );
      expect(find.text('Cook Mon ×1'), findsOneWidget);
      expect(marks(tester, 'r1', 0).cookScale, '×1');

      // The title is the same door, carrying the same week.
      await tester.tap(find.text('Curry'));
      await tester.pumpAndSettle();
      expect(
        router.state.uri.toString(),
        '/recipes/r1?week=${WeekShape.monday.keyOf(DateTime.now())}',
      );
    });

    testWidgets('a component gap keeps its named reason and its one fix', (
      tester,
    ) async {
      deskWidth(tester);
      await tester.pumpWidget(
        _host([
          cookPlanRepositoryProvider.overrideWithValue(
            FakeCookPlanRepository(_planWith(yields: const [])),
          ),
          recipeRepositoryProvider.overrideWithValue(_recipeRepo()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Romesco Aioli · for Sausage Sliders'), findsOneWidget);
      expect(find.text('no scale'), findsOneWidget);
      expect(
        find.textContaining('Romesco Aioli doesn’t say how much it makes'),
        findsOneWidget,
      );
      expect(find.text('Set the yield'), findsOneWidget);
      // The day a batch is wanted is marked; the scale it has none of is not
      // invented for the track either.
      expect(marks(tester, 'aioli-gap', 5).unscaled, isTrue);
      expect(marks(tester, 'aioli-gap', 5).cookScale, isNull);
      expect(find.text('×1 batch'), findsNothing);
    });

    testWidgets('below expanded the same plan is the phone’s column of cards', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(threeCooks()));
      await tester.pump();

      final first = tester.getTopLeft(find.text('Chicken Curry'));
      final second = tester.getTopLeft(find.text('House Ragù'));
      expect(second.dx, first.dx);
      expect(second.dy, greaterThan(first.dy));
      // The card's own anatomy, unchanged: a timeline per session, the tile's
      // two-line heading — and no shared axis anywhere.
      expect(find.byType(CookTimeline), findsNWidgets(4));
      expect(find.text('Cook Mon'), findsOneWidget);
      expect(find.text('MON'), findsNothing);
      expect(find.byType(CookTrack), findsNothing);
    });
  });
}

/// A week with the sliders planned for Saturday and a ¼-cup aioli component,
/// where the aioli states [yields] (empty ⇒ the gap state).
CookPlan _planWith({required List<YieldDenomination> yields}) => buildCookPlan(
  const [
    PlannedRecipe(
      recipeId: 'sliders',
      title: 'Sausage Sliders',
      servingsBase: 8,
      meals: [CoveredMeal(dayOfWeek: 5, mealSlot: 'Dinner', portions: 8)],
    ),
  ],
  components: {
    'sliders': (
      title: 'Sausage Sliders',
      servingsBase: 8.0,
      keepsForDays: null,
      freezable: false,
      freezerDays: null,
      measures: const <RecipeMeasure>[],
      yields: const <YieldDenomination>[],
      components: [
        (
          id: 'li-aioli',
          subRecipeId: 'aioli',
          quantity: 0.25,
          unit: cup,
          recipeMeasureId: null,
          optional: false,
        ),
      ],
    ),
    'aioli': (
      title: 'Romesco Aioli',
      servingsBase: 4.0,
      keepsForDays: 5,
      freezable: false,
      freezerDays: null,
      measures: const <RecipeMeasure>[],
      yields: yields,
      components: const <ComponentLine>[],
    ),
  },
);
