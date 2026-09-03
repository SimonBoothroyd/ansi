import 'dart:async';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/features/cook_plan/data/cook_plan_providers.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan_repository.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/domain/planning_repository.dart';
import 'package:ansi/features/planning/presentation/week_format.dart';
import 'package:ansi/features/planning/presentation/week_header.dart';
import 'package:ansi/features/planning/presentation/week_view.dart';
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

import '../../helpers/forui_semantics.dart';

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
  Future<void> setDaySlot({
    required String entryId,
    required int dayOfWeek,
    required String mealSlot,
  }) async {}

  @override
  Future<void> setPortions(String entryId, int? portions) async {}

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

/// A planner whose removal is REAL to the stream: `removeEntry` re-emits the
/// week without the entry, which is what makes the entry sheet's own
/// auto-dismiss fire on top of its explicit pop.
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
}

/// A canned cook plan for the week's markers (D6). Empty by default.
class _FakeCookPlanRepo implements CookPlanRepository {
  _FakeCookPlanRepo([this.recipes = const []]);

  final List<PlannedRecipe> recipes;

  @override
  Stream<CookPlan> watchCookPlan(DateTime weekStart) =>
      Stream.value(buildCookPlan(recipes));
}

/// A library of one recipe, with whatever macro summary the test needs — the
/// week reads `RecipeSummary.macros`, the same figure the picker rows show.
class _RecipesRepo implements RecipeRepository {
  _RecipesRepo(this.macros);

  final RecipeMacroSummary? macros;

  @override
  Stream<List<RecipeSummary>> watchRecipes() => Stream.value([
    RecipeSummary(
      id: 'r1',
      title: 'Weeknight Chicken Curry',
      servingsBase: 2,
      macros: macros,
    ),
  ]);

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

/// Every host wires a cook-plan repo, because the Week reads its markers back
/// off the plan (D6) — no test should reach for a real database to draw a row.
List<Override> _withCook(List<Override> extra, CookPlanRepository? cook) => [
  cookPlanRepositoryProvider.overrideWithValue(cook ?? _FakeCookPlanRepo()),
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
    overrides: _withCook(overrides, null),
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => FTheme(data: ansiThemeData(), child: child!),
    ),
  );
}

WeekPlan _plannedWeek({int? portions}) => WeekPlan(
  id: 'w',
  weekStart: DateTime.utc(2026, 8, 24),
  entries: [
    PlanEntry(
      id: 'e1',
      dayOfWeek: 3,
      mealSlot: 'Dinner',
      recipeId: 'r1',
      recipeTitle: 'Weeknight Chicken Curry',
      eaterIds: const ['m1'],
      portions: portions,
    ),
  ],
);

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

/// Forui's select trips a debug-only semantics assertion when a sheet opens.
/// The sim suite filters the same family; the widget suite needs it wherever a
/// sheet is driven.
void ignoreForuiSemanticsAssertion() {
  final reportError = FlutterError.onError!;
  FlutterError.onError = (details) {
    if ('${details.exception}'.contains('semantics.dart')) return;
    reportError(details);
  };
  addTearDown(() => FlutterError.onError = reportError);
}

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

    testWidgets('another week shows no banner and no pill — the switcher in '
        'every header is the signal, and its menu is the way home (0025 '
        'D7a)', (tester) async {
      await tester.pumpWidget(
        _host([
          planningRepositoryProvider.overrideWithValue(
            _FakePlanningRepo(week: _plannedWeek()),
          ),
          recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
        ]),
      );
      await tester.pumpAndSettle();

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

  group('the empty week is a state of this screen, not a page (D5)', () {
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
      await tester.pumpWidget(
        _host([
          planningRepositoryProvider.overrideWithValue(_FakePlanningRepo()),
          recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
        ]),
      );
      await tester.pumpAndSettle();

      // The blank-week PAGE is gone, and with it the widget doing a
      // navigation's job.
      expect(find.text('A blank week'), findsNothing);
      expect(find.text('Last week, for reference'), findsNothing);

      // The chrome the old page hid — above all the switcher, the one control
      // that gets you OUT of an empty week.
      expect(find.byType(WeekSwitcher), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
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
      await tester.pumpWidget(
        _host([
          planningRepositoryProvider.overrideWithValue(_FakePlanningRepo()),
          recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
        ]),
      );
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('no meals yet — nothing to add up'),
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(find.text('no meals yet — nothing to add up'), findsOneWidget);
      expect(find.textContaining('kcal'), findsNothing);
    });

    testWidgets('"copy last week" is offered inline ONLY while the week is '
        'empty', (tester) async {
      await tester.pumpWidget(
        _host([
          planningRepositoryProvider.overrideWithValue(
            _FakePlanningRepo(last: last),
          ),
          recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('copy last week'), findsOneWidget);

      // The same week with a meal on it: the chip is gone, and the switcher
      // menu is its permanent home.
      await tester.pumpWidget(
        _host([
          planningRepositoryProvider.overrideWithValue(
            _FakePlanningRepo(week: _plannedWeek(), last: last),
          ),
          recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('copy last week'), findsNothing);
      expect(find.text('Add the first meal'), findsNothing);
    });

    testWidgets('removing the last meal does NOT change what screen you are '
        'on', (tester) async {
      // The old branch fired on entries.isEmpty too, so one removal teleported
      // you off the grid mid-edit. Now the day card is still there and simply
      // shows its quiet line.
      await tester.pumpWidget(
        _host([
          planningRepositoryProvider.overrideWithValue(
            _FakePlanningRepo(week: _plannedWeek()),
          ),
          recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Thursday'), findsOneWidget);

      await tester.pumpWidget(
        _host([
          planningRepositoryProvider.overrideWithValue(
            _FakePlanningRepo(
              week: WeekPlan(id: 'w', weekStart: DateTime.utc(2026, 8, 24)),
            ),
          ),
          recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Thursday'), findsOneWidget);
      expect(find.text('nothing planned'), findsWidgets);
    });
  });

  group('honest macros (D4)', () {
    const complete = RecipeMacroSummary(
      perServing: Macros(kcal: 500, protein: 30, carb: 40, fat: 20),
    );
    const incomplete = RecipeMacroSummary(stubLines: 1);

    testWidgets('a resolved day shows its cells AND its denominator', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host([
          planningRepositoryProvider.overrideWithValue(
            _FakePlanningRepo(week: _plannedWeek()),
          ),
          recipeRepositoryProvider.overrideWithValue(_RecipesRepo(complete)),
        ]),
      );
      await tester.pumpAndSettle();

      // One eater × 500 kcal/serving.
      expect(find.text('500 kcal'), findsWidgets);
      // The denominator is mandatory — a bare number is never drawn.
      expect(find.text('1 meal'), findsWidgets);
      // A day with nothing on it shows its quiet add door instead of a macro
      // line — and NEVER a zero.
      expect(find.text('nothing planned'), findsWidgets);
      expect(find.text('0 kcal'), findsNothing);
    });

    testWidgets('a day whose only meal is incomplete draws NO number', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host([
          planningRepositoryProvider.overrideWithValue(
            _FakePlanningRepo(week: _plannedWeek()),
          ),
          recipeRepositoryProvider.overrideWithValue(_RecipesRepo(incomplete)),
        ]),
      );
      await tester.pumpAndSettle();

      // The badge and the reason, in incompleteNote's exact words.
      expect(find.text('incomplete'), findsWidgets);
      expect(
        find.textContaining('Weeknight Chicken Curry \u00b7 1 stub line'),
        findsWidgets,
      );
      // …and not one kcal figure anywhere on the screen (the week is that one
      // meal, so the band refuses too).
      expect(find.textContaining('kcal'), findsNothing);
    });

    testWidgets('the week band is labelled PLANNED and refuses a target '
        'reading', (tester) async {
      await tester.pumpWidget(
        _host([
          planningRepositoryProvider.overrideWithValue(
            _FakePlanningRepo(week: _plannedWeek()),
          ),
          recipeRepositoryProvider.overrideWithValue(_RecipesRepo(complete)),
        ]),
      );
      await tester.pumpAndSettle();
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
      await tester.pumpWidget(
        _host([
          planningRepositoryProvider.overrideWithValue(
            _FakePlanningRepo(week: _plannedWeek()),
          ),
          recipeRepositoryProvider.overrideWithValue(_RecipesRepo(complete)),
        ]),
      );
      await tester.pumpAndSettle();
      // The lens picks a member who eats nothing on this week.
      await tester.tap(find.text('Jun'));
      await tester.pumpAndSettle();
      expect(find.text('no meals for Jun'), findsWidgets);
      expect(find.textContaining('kcal'), findsNothing);
    });

    testWidgets('the lens DIMS rather than removes (D8)', (tester) async {
      await tester.pumpWidget(
        _host([
          planningRepositoryProvider.overrideWithValue(
            _FakePlanningRepo(week: _plannedWeek()),
          ),
          recipeRepositoryProvider.overrideWithValue(_RecipesRepo(complete)),
        ]),
      );
      await tester.pumpAndSettle();

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
          recipeRepositoryProvider.overrideWithValue(_RecipesRepo(null)),
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
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a meal').first);
    await tester.pumpAndSettle();
    expect(find.text('Search recipes'), findsOneWidget, reason: 'the picker');

    show.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(WeekView), findsNothing);

    await tester.tap(find.text('Weeknight Chicken Curry').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Add to plan'), findsOneWidget, reason: 'confirm sheet');
  });

  testWidgets('presentation is the resting state — no add doors, no chevrons', (
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

    expect(find.text('Thursday'), findsOneWidget);
    expect(find.text('Weeknight Chicken Curry'), findsOneWidget);
    // The affordance layer is OFF: no dashed add rows anywhere.
    expect(find.text('Add a meal'), findsNothing);
    expect(find.text('Edit'), findsOneWidget);
    // A day with nothing on it still says so, and that line is its add door.
    expect(find.text('nothing planned'), findsWidgets);
  });

  testWidgets('Edit puts the affordances back and Done takes them away', (
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

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Done'), findsOneWidget);
    // One per day — the ListView only builds the ones on screen.
    expect(find.text('Add a meal'), findsWidgets);
    // The quiet line is a presentation-mode thing; edit has the real door.
    expect(find.text('nothing planned'), findsNothing);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Add a meal'), findsNothing);
  });

  testWidgets('the portions chip appears only when portions differ from the '
      'eater count', (tester) async {
    await tester.pumpWidget(
      _host([
        planningRepositoryProvider.overrideWithValue(
          _FakePlanningRepo(week: _plannedWeek()),
        ),
        recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
      ]),
    );
    await tester.pumpAndSettle();
    // _plannedWeek()'s entry has two eaters and no override.
    expect(find.text('2 portions'), findsNothing);

    await tester.pumpWidget(
      _host([
        planningRepositoryProvider.overrideWithValue(
          _FakePlanningRepo(week: _plannedWeek(portions: 3)),
        ),
        recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('3 portions'), findsOneWidget);
  });

  testWidgets('the cook marker is read off the cook plan, and a single-meal '
      'cook gets none (D6)', (tester) async {
    // One recipe, two meals two days apart, keeping 4 days → ONE session
    // covering both: Monday cooks, Wednesday comes out of that batch.
    final plan = _FakeCookPlanRepo([
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
    await tester.pumpWidget(
      _host([
        planningRepositoryProvider.overrideWithValue(
          _FakePlanningRepo(week: _batchedWeek()),
        ),
        recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
      ], cook: plan),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('batch of 4'), findsOneWidget);
    expect(find.text('from Monday\u2019s batch'), findsOneWidget);

    // A week whose only meal cooks for itself says nothing — "cooks today" on
    // every row would be noise.
    await tester.pumpWidget(
      _host([
        planningRepositoryProvider.overrideWithValue(
          _FakePlanningRepo(week: _plannedWeek()),
        ),
        recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('batch of'), findsNothing);
  });

  testWidgets('the mode decides the tap: recipe in presentation, entry sheet '
      'in edit (D7)', (tester) async {
    ignoreForuiSemanticsAssertion();
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

    router.go('/week');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weeknight Chicken Curry'));
    await tester.pumpAndSettle();

    // The sheet, not the recipe — and it carries what the retired `...` menu
    // and the eaters dialog used to hold, in one place.
    expect(router.state.uri.toString(), '/week');
    expect(find.text('This meal'), findsOneWidget);
    expect(find.text('Remove from the week'), findsOneWidget);
    expect(find.text("WHO'S EATING"), findsOneWidget);
    expect(find.text('DAY \u00b7 SLOT'), findsOneWidget);
  });

  testWidgets('removing the last meal from the sheet pops it exactly once', (
    tester,
  ) async {
    ignoreForuiSemanticsAssertion();
    late GoRouter router;
    await tester.pumpWidget(
      _routedHost([
        planningRepositoryProvider.overrideWithValue(
          _LivePlanningRepo(_plannedWeek()),
        ),
        recipeRepositoryProvider.overrideWithValue(_NoRecipesRepo()),
      ], (r) => router = r),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weeknight Chicken Curry'));
    await tester.pumpAndSettle();
    expect(find.text('Remove from the week'), findsOneWidget);

    // The explicit pop and the "entry is gone" auto-dismiss must not stack:
    // a second pop on the root navigator would take the page under the sheet
    // with it (go_router asserts "popped the last page off the stack"), which
    // pumpAndSettle would surface here as an uncaught error.
    await tester.tap(find.text('Remove from the week'));
    await tester.pumpAndSettle();

    expect(find.text('This meal'), findsNothing);
    expect(find.text('Weeknight Chicken Curry'), findsNothing);
    expect(router.state.uri.toString(), '/week');
    expect(find.text('Add the first meal'), findsOneWidget);
  });
}
