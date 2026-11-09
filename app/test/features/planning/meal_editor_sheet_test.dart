/// The meal's sheet: its batch strip, cooked on the day the ticks say and
/// kept live; what the meal that cooks for next week says; a leftover meal's
/// line; and *Cook fresh instead* with its Undo.
library;

import 'dart:async';

import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/account/data/household_providers.dart';
import 'package:ansi/features/cook_plan/data/cook_plan_providers.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan_repository.dart';
import 'package:ansi/features/cook_plan/domain/leftovers.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/meal_editor_sheet.dart';
import 'package:ansi/features/planning/presentation/week_view_models.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/shared/week_strip.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/fake_leftover_repository.dart';
import '../../helpers/fake_planning_repository.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/pump_app.dart';

/// This week's Monday: the week on screen.
final _monday = WeekShape.monday.weekStartOf(DateTime.now());

DateTime _on(int day, [int hour = 0]) =>
    DateTime(_monday.year, _monday.month, _monday.day + day, hour);

PlanEntry _entry(int day, {String? fromLeftover}) => PlanEntry(
  id: 'e$day',
  dayOfWeek: day,
  mealSlot: 'Dinner',
  recipeId: 'hh',
  recipeTitle: 'Hamburger Helper',
  eaterIds: const ['m1', 'm2'],
  fromLeftover: fromLeftover,
);

class _Planner extends FakePlanningRepository {
  _Planner(this.entries)
    : super(const [
        Member(id: 'm1', displayName: 'Ada'),
        Member(id: 'm2', displayName: 'Jun'),
      ]);

  final List<PlanEntry> entries;

  @override
  Stream<WeekPlan?> watchWeek(DateTime weekStart) =>
      Stream.value(WeekPlan(id: 'w', weekStart: _monday, entries: entries));
}

/// A cook plan that can change while the sheet is open, as a tick moves it.
class _LivePlan implements CookPlanRepository {
  final _plans = StreamController<CookPlan>.broadcast();
  CookPlan _last = const CookPlan();

  void emit(CookPlan plan) {
    _last = plan;
    _plans.add(plan);
  }

  @override
  Stream<CookPlan> watchCookPlan(DateTime weekStart) async* {
    yield _last;
    yield* _plans.stream;
  }
}

/// Hamburger Helper of 8, Wed, Fri and Sat (keeps 3, freezes), with [eaten]
/// ticked portions by day, and [nextWeek] meals folded in (days 7..13).
CookPlan _helper(Map<int, double> eaten, {List<int> nextWeek = const []}) =>
    buildCookPlan([
      PlannedRecipe(
        recipeId: 'hh',
        title: 'Hamburger Helper',
        servingsBase: 8,
        keepsForDays: 3,
        freezable: true,
        meals: [
          for (final d in [2, 4, 5])
            CoveredMeal(
              dayOfWeek: d,
              mealSlot: 'Dinner',
              portions: 2,
              entryId: 'e$d',
              eatenPortions: eaten[d] ?? 0,
            ),
        ],
        nextWeek: [
          for (final d in nextWeek)
            CoveredMeal(
              dayOfWeek: d,
              mealSlot: 'Dinner',
              portions: 2,
              entryId: 'next$d',
            ),
        ],
      ),
    ]);

Future<_Planner> _open(
  WidgetTester tester, {
  required PlanEntry entry,
  required DateTime now,
  CookPlanRepository? plan,
  List<Override> extra = const [],
}) async {
  filterForuiSemanticsAssertions();
  final planner = _Planner([entry]);
  // Under a real router, the toaster above it as in the app: an Undo's
  // toast is raised through the root overlay.
  await tester.pumpWidget(
    routedHost(
      initial: '/',
      routes: {
        '/': (context, _) => Builder(
          builder: (context) => GestureDetector(
            onTap: () => showMealEditorSheet(context, entry: entry),
            child: const Text('open'),
          ),
        ),
      },
      overrides: [
        clockProvider.overrideWithValue(() => now),
        weekShapeProvider.overrideWithValue(WeekShape.monday),
        planningRepositoryProvider.overrideWithValue(planner),
        cookPlanRepositoryProvider.overrideWithValue(plan ?? _LivePlan()),
        recipeRepositoryProvider.overrideWithValue(FakeRecipeRepository()),
        ...extra,
      ],
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return planner;
}

int _cookedDay(WidgetTester tester) => tester
    .widget<WeekStrip>(find.byType(WeekStrip))
    .days
    .indexWhere((d) => d.fill == WeekStripFill.cooked);

void main() {
  testWidgets('the strip is cooked on the day the ticks say, and follows a '
      'tick while the sheet is open', (tester) async {
    // Saturday: Wednesday skipped, Friday ticked. Friday cooked it.
    final plan = _LivePlan()..emit(_helper({4: 2}));
    await _open(tester, entry: _entry(5), now: _on(5, 10), plan: plan);
    expect(_cookedDay(tester), 4);
    expect(find.text('from Friday’s batch'), findsOneWidget);
    expect(find.text('from Wednesday’s batch'), findsNothing);

    // Somebody ticks Wednesday after all: it was cooked then.
    plan.emit(_helper({2: 2, 4: 2}));
    await tester.pumpAndSettle();
    expect(_cookedDay(tester), 2);
    expect(find.text('from Wednesday’s batch'), findsOneWidget);
  });

  testWidgets('the meal that cooks for next week says so', (tester) async {
    final plan = _LivePlan()..emit(_helper(const {}, nextWeek: [3]));
    // Monday morning: Wednesday is the cook day.
    await _open(tester, entry: _entry(2), now: _on(0, 9), plan: plan);
    expect(find.text('cook it all · freeze 2 for next Thu'), findsOneWidget);
  });

  testWidgets('a leftover meal says where it is from, its words apart', (
    tester,
  ) async {
    final leftover = Leftover(
      id: 'lo',
      place: LeftoverPlace.fridge,
      recipeId: 'hh',
      title: 'Hamburger Helper',
      since: _on(4),
      goodUntil: _on(7),
      portions: 0,
      planned: 2,
      freezable: true,
      meals: [
        LeftoverMeal(
          entryId: 'e6',
          day: _on(9),
          portions: 2,
          place: LeftoverPlace.freezer,
          freezeBy: _on(7),
        ),
      ],
    );
    await _open(
      tester,
      entry: _entry(6, fromLeftover: 'lo'),
      now: _on(5, 10),
      extra: [
        leftoverRepositoryProvider.overrideWithValue(
          FakeLeftoverRepository(
            [leftover],
            const {},
            {'e6': leftover.meals.single},
          ),
        ),
      ],
    );
    expect(find.text('cooked Fri · freeze by Mon'), findsOneWidget);
  });

  testWidgets('Cook fresh instead says so, and its Undo eats from the '
      'leftover again', (tester) async {
    final planner = await _open(
      tester,
      entry: _entry(6, fromLeftover: 'lo'),
      now: _on(5, 10),
      extra: [
        leftoverRepositoryProvider.overrideWithValue(FakeLeftoverRepository()),
      ],
    );
    await tester.tap(find.text('Cook fresh instead'));
    await tester.pumpAndSettle();
    expect(planner.cookedFresh, ['e6']);
    expect(find.text('Cooking Hamburger Helper fresh on Sunday.'), findsOne);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(planner.eatenFromLeftoverAgain, [('e6', null, 'lo')]);
  });
}
