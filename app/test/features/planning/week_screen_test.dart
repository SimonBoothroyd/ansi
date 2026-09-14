import 'dart:async';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/account/data/household_providers.dart';
import 'package:ansi/features/cook_plan/data/cook_plan_providers.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan_repository.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/domain/planning_repository.dart';
import 'package:ansi/features/planning/presentation/meal_fields.dart';
import 'package:ansi/features/planning/presentation/week_format.dart';
import 'package:ansi/features/planning/presentation/week_header.dart';
import 'package:ansi/features/planning/presentation/week_view.dart';
import 'package:ansi/features/planning/presentation/week_widgets.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:ansi/features/recipes/domain/recipe_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/fake_cook_plan_repository.dart';
import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/fake_planning_repository.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/fake_week_variant_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/macro_line.dart';
import '../../helpers/pump_app.dart';

/// A canned planner: emits [week] for the current week and [last] as the
/// reference week, with two members. Mutations are inert.
class _FakePlanningRepo extends FakePlanningRepository {
  _FakePlanningRepo({
    this.week,
    this.last,
    this.onCopy,
    List<Member> roster = const [
      Member(id: 'm1', displayName: 'Ada'),
      Member(id: 'm2', displayName: 'Jun'),
    ],
  }) : super(roster);

  final WeekPlan? week;
  final WeekPlan? last;
  final void Function(DateTime weekStart)? onCopy;

  @override
  Stream<WeekPlan?> watchWeek(DateTime weekStart) => Stream.value(week);

  @override
  Future<WeekPlan?> mostRecentWeekBefore(DateTime weekStart) async => last;

  @override
  Future<CopyLastWeekResult> copyLastWeek(DateTime weekStart) async {
    onCopy?.call(weekStart);
    return (meals: 0, variantsLeftBehind: const <VariantLeftBehind>[]);
  }
}

/// A planner whose writes are REAL to the stream: `removeEntry` re-emits the
/// week without the entry and `addEntry` re-emits it with one, which is what
/// lets a test watch the `−` and its undo round-trip (E3).
class _LivePlanningRepo extends _FakePlanningRepo {
  _LivePlanningRepo(WeekPlan week) : _week = week, super(week: week);

  WeekPlan _week;
  final _ctrl = StreamController<WeekPlan?>.broadcast();

  @override
  Stream<WeekPlan?> watchWeek(DateTime weekStart) async* {
    yield _week;
    yield* _ctrl.stream;
  }

  @override
  Future<void> removeEntry(String entryId) async {
    _week = _week.copyWith(
      entries: [..._week.entries.where((e) => e.id != entryId)],
    );
    _ctrl.add(_week);
  }

  @override
  Future<void> setMealSlot(String entryId, String mealSlot) async {
    await super.setMealSlot(entryId, mealSlot);
    _week = _week.copyWith(
      entries: [
        for (final e in _week.entries)
          if (e.id == entryId) e.copyWith(mealSlot: mealSlot) else e,
      ],
    );
    _ctrl.add(_week);
  }

  @override
  Future<String> addEntry({
    required DateTime weekStart,
    required int dayOfWeek,
    required String mealSlot,
    required String recipeId,
    required List<String> eaterIds,
    int? portions,
  }) async {
    // A NEW id, as the real repository gives: the undo puts the meal back, it
    // does not resurrect the row.
    final id = 'e${_week.entries.length + 1}-undone';
    _week = _week.copyWith(
      entries: [
        ..._week.entries,
        PlanEntry(
          id: id,
          dayOfWeek: dayOfWeek,
          mealSlot: mealSlot,
          recipeId: recipeId,
          recipeTitle: 'Weeknight Chicken Curry',
          eaterIds: eaterIds,
          portions: portions,
        ),
      ],
    );
    _ctrl.add(_week);
    return id;
  }
}

/// A library of one recipe, with whatever macro summary the test needs — the
/// week reads `RecipeSummary.macros`, the same figure the picker rows show.
FakeRecipeRepository _recipesRepo(RecipeMacroSummary? macros) =>
    FakeRecipeRepository(
      summaries: [
        RecipeSummary(
          id: 'r1',
          title: 'Weeknight Chicken Curry',
          servingsBase: 2,
          macros: macros,
        ),
      ],
    );

/// Every host wires a cook-plan repo, because the Week reads its markers back
/// off the plan (D6) — no test should reach for a real database to draw a row.
List<Override> _withCook(List<Override> extra, CookPlanRepository? cook) => [
  cookPlanRepositoryProvider.overrideWithValue(
    cook ?? FakeCookPlanRepository(),
  ),
  // Since step 8.14 the add door searches the VOCABULARY as well as the
  // recipes (C-D1), so every host here answers for it — with nothing, which
  // is the honest answer for a suite about dishes.
  ingredientRepositoryProvider.overrideWithValue(
    const ReadOnlyIngredientRepo(),
  ),
  // Planning an ingredient opens the quantity sheet, which draws the row's
  // measure chips off this repository. Every host answers for it, with no
  // measures — the sheet then opens on the row's own default unit.
  measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
  // No recipe is varied for this week unless a test says so — the week then
  // reads exactly the Library's per-recipe figures.
  weekVariantRepositoryProvider.overrideWithValue(FakeWeekVariantRepository()),
  ...extra,
];

Widget _host(List<Override> overrides, {CookPlanRepository? cook}) =>
    ProviderScope(
      overrides: _withCook(overrides, cook),
      child: MaterialApp(
        home: FTheme(data: ansiThemeData(), child: const WeekView()),
      ),
    );

/// The same view inside a real router, so a tap's destination is observable.
/// `expose` hands the router back for the test to read the location from.
Widget _routedHost(List<Override> overrides, void Function(GoRouter) expose) =>
    routedHost(
      initial: '/week',
      overrides: _withCook(overrides, null),
      expose: expose,
      routes: {
        '/week': (_, state) => WeekView(
          weekKey: state.uri.queryParameters['week'],
          dayKey: state.uri.queryParameters['day'],
        ),
        '/recipes/:id': (_, state) =>
            FScaffold(child: Text('recipe ${state.pathParameters['id']}')),
      },
    );

/// Pumps the Week over a planner and a recipe library, then settles.
///
/// Every test in this file wires the same two repositories and the same
/// cook-plan fake; what varies is the week the planner holds, so that is the
/// only argument most of them pass. [expose] switches to the routed host and
/// hands the router back, for the tests that follow a tap somewhere else.
Future<void> _pumpWeek(
  WidgetTester tester, {
  PlanningRepository? planning,
  RecipeRepository? recipes,
  CookPlanRepository? cook,
  WeekShape shape = WeekShape.monday,
  void Function(GoRouter)? expose,
}) async {
  final overrides = [
    planningRepositoryProvider.overrideWithValue(
      planning ?? _FakePlanningRepo(),
    ),
    recipeRepositoryProvider.overrideWithValue(
      recipes ?? FakeRecipeRepository(),
    ),
    weekShapeProvider.overrideWithValue(shape),
  ];
  await tester.pumpWidget(
    expose == null
        ? _host(overrides, cook: cook)
        : _routedHost(overrides, expose),
  );
  await tester.pumpAndSettle();
}

WeekPlan _plannedWeek({int? portions, List<String> eaters = const ['m1']}) =>
    WeekPlan(
      id: 'w',
      weekStart: DateTime.utc(2026, 8, 24),
      entries: [
        PlanEntry(
          id: 'e1',
          dayOfWeek: 3,
          mealSlot: 'Dinner',
          recipeId: 'r1',
          recipeTitle: 'Weeknight Chicken Curry',
          eaterIds: eaters,
          portions: portions,
        ),
      ],
    );

/// A week holding one SNACK — a bare ingredient, not a dish (step 8.14). Its
/// vocab numbers ride on the entry, as the repository loads them.
WeekPlan _snackWeek({
  List<String> eaters = const ['m1'],
  double? quantity = 1,
  Unit? unit = pieces,
  Measure? measure = const Measure(id: 'mz', label: 'bar', amount: 60),
  Macros? macros = const Macros(kcal: 350, protein: 33, carb: 30, fat: 11),
}) => WeekPlan(
  id: 'w',
  weekStart: DateTime.utc(2026, 8, 24),
  entries: [
    PlanEntry(
      id: 'e1',
      dayOfWeek: 3,
      mealSlot: 'Snack',
      ingredientId: 'i1',
      ingredientName: 'Protein bar',
      quantity: quantity,
      unit: unit,
      measureId: measure?.id,
      measure: measure,
      nutrition: (
        macros: macros,
        basis: MacrosBasis.perG,
        densityGPerMl: null,
        pieceBasisAmount: null,
      ),
      eaterIds: eaters,
    ),
  ],
);

/// Ada eats a portion, Jun three-quarters of one (plan 0027).
const _factoredRoster = [
  Member(id: 'm1', displayName: 'Ada'),
  Member(id: 'm2', displayName: 'Jun', portionFactor: 0.75),
];

/// The same recipe twice, inside one fridge window — the shape that gives a
/// dish row something to say on its second line.
WeekPlan _batchedWeek() => WeekPlan(
  id: 'w',
  weekStart: DateTime.utc(2026, 8, 24),
  entries: const [
    PlanEntry(
      id: 'e1',
      dayOfWeek: 0,
      mealSlot: 'Dinner',
      recipeId: 'r1',
      recipeTitle: 'Weeknight Chicken Curry',
      eaterIds: ['m1', 'm2'],
    ),
    PlanEntry(
      id: 'e2',
      dayOfWeek: 2,
      mealSlot: 'Dinner',
      recipeId: 'r1',
      recipeTitle: 'Weeknight Chicken Curry',
      eaterIds: ['m1', 'm2'],
    ),
  ],
);

void main() {
  group('the week switcher', () {
    final monday = WeekShape.monday.weekStartOf(DateTime.now());
    String titleFor(int weeksAhead) {
      final t = formatWeekTitle(
        monday.add(Duration(days: 7 * weeksAhead)),
        monday,
        WeekShape.monday,
      );
      return t.date == null ? t.label : '${t.label} · ${t.date}';
    }

    testWidgets('names this week, and the chevrons step off it', (
      tester,
    ) async {
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(week: _plannedWeek()),
      );

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

    testWidgets('another week shows no banner and no pill — the switcher in '
        'every header is the signal, and its menu is the way '
        'home', (tester) async {
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(week: _plannedWeek()),
      );

      // The menu speaks in this tab's derivation for the week on screen.
      await tester.tap(find.text(titleFor(0)));
      await tester.pumpAndSettle();
      expect(find.text('1 meal'), findsOneWidget);
      await tester.tap(find.text('Next week'));
      await tester.pumpAndSettle();
      expect(find.text(titleFor(1)), findsOneWidget);

      // Retired, not reworded: Cook and Shop carry the same switcher now.
      expect(find.textContaining('Cook and Shop follow it too'), findsNothing);
      expect(find.text('this week'), findsNothing);

      await tester.tap(find.text(titleFor(1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('This week'));
      await tester.pumpAndSettle();
      expect(find.text(titleFor(0)), findsOneWidget);
    });

    testWidgets('the title menu jumps weeks and owns "copy last week"', (
      tester,
    ) async {
      final copied = <DateTime>[];
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(
          week: _plannedWeek(),
          last: _plannedWeek(),
          onCopy: copied.add,
        ),
      );

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

  group('the empty week is a state of this screen, not a page', () {
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

    testWidgets('everything a full week has still renders, with nothing in '
        'it', (tester) async {
      await _pumpWeek(tester, planning: _FakePlanningRepo());

      // The blank-week PAGE is gone, and with it the widget doing a
      // navigation's job.
      expect(find.text('A blank week'), findsNothing);
      expect(find.text('Last week, for reference'), findsNothing);

      // The chrome the old page hid — above all the switcher, the one control
      // that gets you OUT of an empty week.
      expect(find.byType(WeekSwitcher), findsOneWidget);
      // E1: no `Edit` — the mode is gone, so there is no chrome for it.
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Everyone'), findsOneWidget);

      // Seven day cards, each with its own quiet add door, plus the one
      // primary at the top.
      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('nothing planned'), findsWidgets);
      expect(find.text('Add the first meal'), findsOneWidget);

      // With no earlier week, the copy affordance is absent.
      expect(find.text('copy last week'), findsNothing);
    });

    testWidgets('the week band says so rather than adding up to zero', (
      tester,
    ) async {
      await _pumpWeek(tester, planning: _FakePlanningRepo());
      await tester.dragUntilVisible(
        find.text('no meals yet — nothing to add up'),
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(find.text('no meals yet — nothing to add up'), findsOneWidget);
      expect(macroTextContaining('kcal'), findsNothing);
    });

    testWidgets('"copy last week" is offered inline ONLY while the week is '
        'empty', (tester) async {
      await _pumpWeek(tester, planning: _FakePlanningRepo(last: last));
      expect(find.text('copy last week'), findsOneWidget);

      // The same week with a meal on it: the chip is gone, and the switcher
      // menu is its permanent home.
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(week: _plannedWeek(), last: last),
      );
      expect(find.text('copy last week'), findsNothing);
      expect(find.text('Add the first meal'), findsNothing);
    });

    testWidgets('removing the last meal does NOT change what screen you are '
        'on', (tester) async {
      // The old branch fired on entries.isEmpty too, so one removal teleported
      // you off the grid mid-edit. Now the day card is still there and simply
      // shows its quiet line.
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(week: _plannedWeek()),
      );
      expect(find.text('Thursday'), findsOneWidget);

      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(
          week: WeekPlan(id: 'w', weekStart: DateTime.utc(2026, 8, 24)),
        ),
      );
      expect(find.text('Thursday'), findsOneWidget);
      expect(find.text('nothing planned'), findsWidgets);
    });
  });

  group('honest macros', () {
    const complete = RecipeMacroSummary(
      perServing: Macros(kcal: 500, protein: 30, carb: 40, fat: 20),
    );
    const incomplete = RecipeMacroSummary(stubLines: 1);

    testWidgets('a resolved day shows its cells AND its denominator', (
      tester,
    ) async {
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(week: _plannedWeek()),
        recipes: _recipesRepo(complete),
      );

      // One eater × 500 kcal/serving, in the dense line's grammar.
      expect(macroText('500 kcal · 30P 40C 20F'), findsWidgets);
      // The denominator is mandatory — a bare number is never drawn.
      expect(find.text('1 meal'), findsWidgets);
      // A day with nothing on it shows its quiet add door instead of a macro
      // line — and NEVER a zero.
      expect(find.text('nothing planned'), findsWidgets);
      expect(macroText('0 kcal · 0P 0C 0F'), findsNothing);
    });

    testWidgets('a day whose only meal is incomplete draws NO number', (
      tester,
    ) async {
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(week: _plannedWeek()),
        recipes: _recipesRepo(incomplete),
      );

      // The badge and the reason, in incompleteNote's exact words.
      expect(find.text('incomplete'), findsWidgets);
      expect(
        find.textContaining('Weeknight Chicken Curry \u00b7 1 stub line'),
        findsWidgets,
      );
      // …and not one kcal figure anywhere on the screen (the week is that one
      // meal, so the band refuses too).
      expect(macroTextContaining('kcal'), findsNothing);
    });

    testWidgets('the week band is labelled PLANNED and refuses a target '
        'reading', (tester) async {
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(week: _plannedWeek()),
        recipes: _recipesRepo(complete),
      );
      await tester.dragUntilVisible(
        find.text('PLANNED \u00b7 WEEK \u00b7 EVERYONE'),
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 of 7 days'), findsOneWidget);
      expect(
        find.textContaining('over the 1 day that counted'),
        findsOneWidget,
      );
      expect(find.textContaining('not a daily target'), findsOneWidget);
    });

    testWidgets('an empty week says so rather than adding up to zero', (
      tester,
    ) async {
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(week: _plannedWeek()),
        recipes: _recipesRepo(complete),
      );
      // The lens picks a member who eats nothing on this week.
      await tester.tap(find.text('Jun'));
      await tester.pumpAndSettle();
      expect(find.text('no meals for Jun'), findsWidgets);
      expect(macroTextContaining('kcal'), findsNothing);
    });

    testWidgets('the lens DIMS rather than removes', (tester) async {
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(week: _plannedWeek()),
        recipes: _recipesRepo(complete),
      );

      expect(find.text('Everyone'), findsOneWidget); // was "Shared"
      await tester.tap(find.text('Jun'));
      await tester.pumpAndSettle();

      // Ada-and-Jun's meal is not Jun's… but it is STILL on screen, dimmed —
      // a day somebody else cooks for themselves is not an empty day.
      expect(find.text('Weeknight Chicken Curry'), findsOneWidget);
      final opacity = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.text('Weeknight Chicken Curry'),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, lessThan(1));
    });
  });

  testWidgets('the confirm sheet still opens when the Week is gone under the '
      'picker (the keyboard-shrinks-the-list case)', (tester) async {
    // The picker's search brings the keyboard, which shrinks the week's list:
    // the day card whose door opened the flow can be unmounted by the time a
    // recipe is tapped. The confirm sheet opens from a context that outlives
    // the card (`hostContextOf`) — a `context.mounted` bail used to drop the
    // pick here.
    filterForuiSemanticsAssertions();
    final show = ValueNotifier(true);
    addTearDown(show.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: _withCook([
          planningRepositoryProvider.overrideWithValue(
            _FakePlanningRepo(week: _plannedWeek()),
          ),
          recipeRepositoryProvider.overrideWithValue(_recipesRepo(null)),
        ], null),
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, visible, _) =>
                visible ? const WeekView() : const SizedBox.shrink(),
          ),
          builder: (context, child) =>
              FTheme(data: ansiThemeData(), child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('add a meal').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Search recipes and ingredients'),
      findsOneWidget,
      reason: 'the picker',
    );

    show.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(WeekView), findsNothing);

    await tester.tap(find.text('Weeknight Chicken Curry').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Add to plan'), findsOneWidget, reason: 'confirm sheet');
  });

  group('the confirm sheet asks only the slot', () {
    /// Drives the add flow from Thursday — the day [week] plans (by default
    /// `_plannedWeek`), and so the only card whose add line reads `add a
    /// meal` — to the confirm sheet.
    Future<void> openConfirm(WidgetTester tester, {WeekPlan? week}) async {
      filterForuiSemanticsAssertions();
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(week: week ?? _plannedWeek()),
        recipes: _recipesRepo(null),
      );
      await tester.tap(find.text('add a meal').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weeknight Chicken Curry').last);
      await tester.pumpAndSettle();
    }

    testWidgets('the day it was opened from is stated, never asked', (
      tester,
    ) async {
      await openConfirm(tester);
      expect(find.text('Add to plan'), findsOneWidget);
      // The day arrived with the flow: subtitle above, button below.
      expect(find.text('to · Thursday'), findsOneWidget);
      expect(find.text('Add to Thursday'), findsOneWidget);
      // And no day control: the 49-item `Day · Slot` menu is gone, with every
      // `<day> · <slot>` pair it used to offer.
      expect(find.textContaining('Thursday · '), findsNothing);
      expect(find.textContaining('Monday · '), findsNothing);
      expect(find.byType(MealSlotPicker), findsOneWidget);
    });

    testWidgets("the slot is the one question, and it opens on the day's "
        'next unfilled default', (tester) async {
      // Thursday holds only a dinner, so the next meal nobody has planned is
      // its breakfast — not Dinner again.
      await openConfirm(tester);
      expect(find.text('SLOT'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MealSlotPicker),
          matching: find.text('Breakfast'),
        ),
        findsWidgets,
      );
      expect(find.text('to · Thursday'), findsOneWidget);
    });

    testWidgets('a day with its breakfast and lunch planned opens on Dinner', (
      tester,
    ) async {
      await openConfirm(
        tester,
        week: WeekPlan(
          id: 'w',
          weekStart: DateTime.utc(2026, 8, 24),
          entries: const [
            PlanEntry(
              id: 'e1',
              dayOfWeek: 3,
              mealSlot: 'Breakfast',
              recipeId: 'r1',
              recipeTitle: 'Weeknight Chicken Curry',
              eaterIds: ['m1'],
            ),
            PlanEntry(
              id: 'e2',
              dayOfWeek: 3,
              mealSlot: 'lunch',
              recipeId: 'r1',
              recipeTitle: 'Weeknight Chicken Curry',
              eaterIds: ['m1'],
            ),
          ],
        ),
      );
      expect(
        find.descendant(
          of: find.byType(MealSlotPicker),
          matching: find.text('Dinner'),
        ),
        findsWidgets,
      );
    });

    testWidgets('the custom-slot escape survives the split', (tester) async {
      await openConfirm(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(MealSlotPicker),
          matching: find.byIcon(FLucideIcons.plus),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Custom meal'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Brunch');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(MealSlotPicker),
          matching: find.text('Brunch'),
        ),
        findsWidgets,
      );
    });
  });

  testWidgets('one state: no Edit, and every day carries its add line', (
    tester,
  ) async {
    await _pumpWeek(tester, planning: _FakePlanningRepo(week: _plannedWeek()));

    expect(find.text('Thursday'), findsOneWidget);
    expect(find.text('Weeknight Chicken Curry'), findsOneWidget);
    // E1: the mode and its one control are gone — there is nothing to toggle.
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Done'), findsNothing);
    // E5: one line per day, in two wordings — the day with the meal invites
    // another, the days without say they are empty. Both are the same door.
    expect(find.text('add a meal'), findsWidgets);
    expect(find.text('nothing planned'), findsWidgets);
    // v2's dashed edit-only door is not resurrected under a new name.
    expect(find.text('Add a meal'), findsNothing);
  });

  testWidgets('the portions chip appears only when portions differ from the '
      'eater count', (tester) async {
    await _pumpWeek(tester, planning: _FakePlanningRepo(week: _plannedWeek()));
    // _plannedWeek()'s entry has two eaters and no override.
    expect(find.text('2 portions'), findsNothing);

    await _pumpWeek(
      tester,
      planning: _FakePlanningRepo(week: _plannedWeek(portions: 3)),
    );
    expect(find.text('3 portions'), findsOneWidget);
  });

  testWidgets(
    'the cook marker is read off the cook plan, and a single-meal cook gets '
    'none',
    (tester) async {
      // One recipe, two meals two days apart, keeping 4 days → ONE session
      // covering both: Monday cooks, Wednesday comes out of that batch.
      final plan = FakeCookPlanRepository.of([
        const PlannedRecipe(
          recipeId: 'r1',
          title: 'Weeknight Chicken Curry',
          servingsBase: 2,
          keepsForDays: 4,
          meals: [
            CoveredMeal(dayOfWeek: 0, mealSlot: 'Dinner', portions: 2),
            CoveredMeal(dayOfWeek: 2, mealSlot: 'Dinner', portions: 2),
          ],
        ),
      ]);
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(week: _batchedWeek()),
        cook: plan,
      );

      expect(find.textContaining('batch of 4'), findsOneWidget);
      expect(find.text('from Monday\u2019s batch'), findsOneWidget);

      // A week whose only meal cooks for itself says nothing — "cooks today" on
      // every row would be noise.
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(week: _plannedWeek()),
      );
      expect(find.textContaining('batch of'), findsNothing);
    },
  );

  testWidgets('the row has three targets: title \u2192 recipe, cluster \u2192 '
      'editor, \u2212 \u2192 gone', (tester) async {
    filterForuiSemanticsAssertions();
    late GoRouter router;
    await _pumpWeek(
      tester,
      planning: _FakePlanningRepo(week: _plannedWeek()),
      expose: (r) => router = r,
    );

    // E2 — the title opens the recipe it names, with no mode in the way, and
    // carries the week it is planned in: that is what lets the recipe page
    // offer "Edit for this week" beside its own Edit.
    await tester.tap(find.text('Weeknight Chicken Curry'));
    await tester.pumpAndSettle();
    expect(
      router.state.uri.toString(),
      '/recipes/r1?week=${WeekShape.monday.keyOf(DateTime.now())}',
    );
    expect(find.text('recipe r1'), findsOneWidget);

    router.go('/week');
    await tester.pumpAndSettle();

    // E7 — the avatar/portions cluster opens the editor, and the editor holds
    // the facts the row prints and nothing else: its slot (the gutter label),
    // who's eating and the portions. No day — a row's position is its day —
    // no route to the recipe and no remove: those are the row's other two
    // targets, not this sheet's job.
    await tester.tap(find.byType(EaterAvatarStack).first);
    await tester.pumpAndSettle();
    // Still the Week: the cluster opens a sheet, it does not navigate. The
    // path, not the whole location — the Week names the week on screen in its
    // own `?week=` (`week_in_the_location.dart`).
    expect(router.state.uri.path, '/week');
    expect(find.text('SLOT'), findsOneWidget);
    expect(find.text("WHO'S EATING"), findsOneWidget);
    expect(find.text('PORTIONS'), findsOneWidget);
    expect(find.text('DAY'), findsNothing);
    expect(find.text('DAY \u00b7 SLOT'), findsNothing);
    expect(find.text('Remove from the week'), findsNothing);
    expect(find.textContaining('Open '), findsNothing);
  });

  testWidgets("the editor's Slot field moves the meal in place: Lunch writes "
      'through, and the row re-sorts under LUNCH', (tester) async {
    filterForuiSemanticsAssertions();
    final repo = _LivePlanningRepo(_plannedWeek());
    await _pumpWeek(tester, planning: repo, expose: (_) {});
    expect(find.text('DINNER'), findsOneWidget);
    expect(find.text('LUNCH'), findsNothing);

    await tester.tap(find.byType(EaterAvatarStack).first);
    await tester.pumpAndSettle();
    expect(find.text('Thursday · dinner'), findsOneWidget);
    expect(find.text('SLOT'), findsOneWidget);

    // `FSelect.rich` builds a private subclass, so the select is found by
    // predicate rather than by type — as the ingredient form's tests do.
    await tester.tap(find.byWidgetPredicate((w) => w is FSelect<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lunch').last);
    await tester.pumpAndSettle();

    // Written through on the pick, like the other two fields — no Save.
    expect(repo.slotWrites, [('e1', 'Lunch')]);
    // The sheet re-reads the live row, so it names the new slot itself…
    expect(find.text('Thursday · lunch'), findsOneWidget);
    // …and the row underneath has moved to the LUNCH gutter.
    expect(find.text('LUNCH'), findsOneWidget);
    expect(find.text('DINNER'), findsNothing);
  });

  testWidgets('the \u2212 removes the meal and the toast puts it '
      'back', (tester) async {
    filterForuiSemanticsAssertions();
    await _pumpWeek(
      tester,
      planning: _LivePlanningRepo(_plannedWeek()),
      expose: (_) {},
    );
    expect(find.text('Weeknight Chicken Curry'), findsOneWidget);

    // No confirm dialog stands between the tap and the removal (E3 refuses
    // one): the meal goes, and the undo is what makes that safe.
    await tester.tap(find.byIcon(FLucideIcons.minus).first);
    await tester.pumpAndSettle();
    expect(find.text('Weeknight Chicken Curry'), findsNothing);
    expect(find.text('Add the first meal'), findsOneWidget);

    // The toast names what went and what would come back — an undo you
    // cannot audit is a promise, not a control.
    expect(
      find.text('Removed Weeknight Chicken Curry from Thursday.'),
      findsOneWidget,
    );
    expect(find.textContaining('dinner'), findsWidgets);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Weeknight Chicken Curry'), findsOneWidget);
  });

  group('the portion factor, said everywhere', () {
    const complete = RecipeMacroSummary(
      perServing: Macros(kcal: 500, protein: 30, carb: 40, fat: 20),
    );

    // E7: the editor is opened by tapping the avatar/portions cluster, not
    // by tapping the meal — the row's title is the recipe's door now.
    Future<void> openEntrySheet(WidgetTester tester, {int? portions}) async {
      filterForuiSemanticsAssertions();
      late GoRouter router;
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(
          week: _plannedWeek(eaters: const ['m1', 'm2'], portions: portions),
          roster: _factoredRoster,
        ),
        expose: (r) => router = r,
      );
      router.go('/week');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(EaterAvatarStack).first);
      await tester.pumpAndSettle();
      expect(find.text("WHO'S EATING"), findsOneWidget);
    }

    testWidgets('the Portions row says the fraction and who makes it up', (
      tester,
    ) async {
      await openEntrySheet(tester);
      expect(find.text('1¾ portions'), findsOneWidget);
      expect(find.text('Ada 1 · Jun ¾ — their usual'), findsOneWidget);
      // The stepper's box reads the same fraction — never 1.75.
      expect(find.text('1¾'), findsOneWidget);
      expect(find.textContaining('1.75'), findsNothing);
    });

    testWidgets('an override stays whole and its small print names the figure '
        'it replaced', (tester) async {
      await openEntrySheet(tester, portions: 3);
      // Twice: the grid's chip behind the sheet, and the sheet's own row.
      expect(find.text('3 portions'), findsNWidgets(2));
      expect(
        find.text('overrides the eaters’ 1¾ — Ada 1 · Jun ¾'),
        findsOneWidget,
      );
    });

    testWidgets('the grid’s portions chip is the override, absent while the '
        'eaters’ own fraction is the demand', (tester) async {
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(
          week: _plannedWeek(eaters: const ['m1', 'm2']),
          roster: _factoredRoster,
        ),
      );
      expect(find.byType(PortionsChip), findsNothing);
    });

    testWidgets('the lens weights by the factor and names its denominator', (
      tester,
    ) async {
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(
          week: _plannedWeek(eaters: const ['m1', 'm2']),
          roster: _factoredRoster,
        ),
        recipes: _recipesRepo(complete),
      );

      // Everyone: 1¾ servings × 500, and the meal count alone.
      expect(macroTextContaining('875 kcal'), findsWidgets);
      expect(find.text('1 meal'), findsWidgets);
      expect(find.textContaining('of 1¾ portions'), findsNothing);

      await tester.tap(find.text('Jun'));
      await tester.pumpAndSettle();
      // Jun: ¾ × 500, and the denominator named beside the meal count.
      expect(macroTextContaining('375 kcal'), findsWidgets);
      expect(find.text('1 meal · Jun · ¾ of 1¾ portions'), findsWidgets);
      expect(macroTextContaining('875 kcal'), findsNothing);
    });
  });

  // --- A row that is visibly not a recipe (step 8.14 / A-D5) ----------------

  group('a snack row', () {
    testWidgets('prints its amount where a cook marker would sit, and draws '
        'no shelf-life chip or batch hint', (tester) async {
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(week: _snackWeek()),
        recipes: _recipesRepo(null),
        // A plan that WOULD mark a recipe row, so an absent marker is the
        // snack's own rule and not an empty derivation.
        cook: FakeCookPlanRepository(),
      );

      expect(find.text('Protein bar'), findsOneWidget);
      expect(find.text('1 bar · 60 g'), findsOneWidget);
      expect(find.byType(CookMarkerLine), findsNothing);
      expect(find.textContaining('keeps'), findsNothing);
      expect(find.textContaining('batch'), findsNothing);
    });

    testWidgets('counts in the day total, multiplied by its eaters', (
      tester,
    ) async {
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(week: _snackWeek(eaters: ['m1', 'm2'])),
        recipes: _recipesRepo(null),
      );
      // 60 g of a 350 kcal/100 g bar = 210 per portion, two eaters.
      expect(macroTextContaining('420 kcal'), findsWidgets);
    });

    testWidgets('a stub row draws no number and says so in a stub '
        'line’s own words', (tester) async {
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(week: _snackWeek(macros: null)),
        recipes: _recipesRepo(null),
      );
      expect(macroTextContaining('0 kcal'), findsNothing);
      expect(find.textContaining('stub ingredient'), findsWidgets);
    });

    testWidgets('an amount-less snack names that state rather than nothing', (
      tester,
    ) async {
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(
          week: _snackWeek(quantity: null, unit: null, measure: null),
        ),
        recipes: _recipesRepo(null),
      );
      expect(find.text('no amount'), findsOneWidget);
      expect(find.textContaining('no amount'), findsWidgets);
    });
  });

  group('the household first day of the week', () {
    /// One meal at [offset] of the viewed week — the same fixture under both
    /// shapes, so what moves is the shape and nothing else.
    WeekPlan weekWithMealAt(int offset) => WeekPlan(
      id: 'w',
      weekStart: DateTime.utc(2026, 8, 23),
      entries: [
        PlanEntry(
          id: 'e1',
          dayOfWeek: offset,
          mealSlot: 'Dinner',
          recipeId: 'r1',
          recipeTitle: 'Weeknight Chicken Curry',
          eaterIds: const ['m1'],
        ),
      ],
    );

    /// The day card for a full weekday name — its nearest enclosing Column,
    /// the same handle the smoke driver uses.
    Finder dayCardOf(String day) =>
        find.ancestor(of: find.text(day), matching: find.byType(Column)).first;

    testWidgets('a Sunday-start household heads the week with Sunday, and '
        "puts that Sunday's dinner in it", (tester) async {
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(week: weekWithMealAt(0)),
        shape: WeekShape.sunday,
      );

      // Offset 0 is the top card, and under this shape offset 0 is a Sunday —
      // so the meal the shop was done for that morning heads its own week
      // instead of trailing the one that is ending.
      expect(find.text('Sunday'), findsOneWidget);
      expect(
        find.descendant(
          of: dayCardOf('Sunday'),
          matching: find.text('Weeknight Chicken Curry'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('Sunday')).dy,
        lessThan(tester.getTopLeft(find.text('Monday')).dy),
      );
    });

    testWidgets('a Monday-start household reads exactly as it did', (
      tester,
    ) async {
      await _pumpWeek(
        tester,
        planning: _FakePlanningRepo(week: weekWithMealAt(3)),
      );

      // The top card is Monday, and offset 3 is still Thursday.
      expect(find.text('Monday'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Monday')).dy,
        lessThan(tester.getTopLeft(find.text('Tuesday')).dy),
      );
      await tester.dragUntilVisible(
        find.text('Thursday'),
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: dayCardOf('Thursday'),
          matching: find.text('Weeknight Chicken Curry'),
        ),
        findsOneWidget,
      );
    });
  });
}
