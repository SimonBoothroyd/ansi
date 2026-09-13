/// Week mode at `AnsiLayout.expanded`: ONE column at the measure, with the
/// week's own statement in a column of its own at the row's right end.
///
/// The width buys nothing else here and the frame says so — no header form and
/// no method means there is no second column to make. What it does buy is that
/// every row is one line, so the changes read down an edge and the foot's count
/// is one you can check.
library;

import 'dart:async';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/week_variant_editor.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/recipe_header_form.dart';
import 'package:ansi/shared/ansi_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/fake_planning_repository.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/fake_week_variant_repository.dart';
import '../../helpers/forui_semantics.dart';

const _weekKey = '2026-09-14';
final _monday = DateTime.utc(2026, 9, 14);

const _recipe = Recipe(
  id: 'r1',
  title: 'Slow-Cooker Beef Ragù',
  servingsBase: 4,
  steps: ['Brown the meat.', 'Simmer.'],
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
          note: 'casings removed',
        ),
        LineItem(
          id: 'l2',
          ingredientId: 'i-wine',
          ingredientName: 'Red wine',
          unit: ml,
          quantity: 250,
        ),
      ],
    ),
  ],
);

/// The week that swaps the sausage — so there is a statement to put in the
/// column the measure buys.
const _swapped = {
  'r1': [
    LineOverride(
      id: 'ov1',
      action: LineOverrideAction.replace,
      recipeLineItemId: 'l1',
      ingredientId: 'i-mince',
      ingredientName: 'Beef mince, 5%',
      quantity: 400,
      unit: g,
    ),
  ],
};

class _Planner extends FakePlanningRepository {
  _Planner() : super(const [Member(id: 'm1', displayName: 'Ada')]);

  @override
  Stream<WeekPlan?> watchWeek(DateTime weekStart) => Stream.value(
    WeekPlan(
      id: 'wp1',
      weekStart: _monday,
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

/// Week mode in the cap the router gives it — the measure, not the recipe
/// editor's wider one — inside a window of [surface].
Future<void> _pump(
  WidgetTester tester, {
  required Size surface,
  Map<String, List<LineOverride>> overrides = const {},
}) async {
  filterForuiSemanticsAssertions();
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/edit',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const SizedBox(),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (_, _) => const AnsiMeasure(
              child: WeekVariantEditorView(recipeId: 'r1', weekKey: _weekKey),
            ),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        recipeRepositoryProvider.overrideWithValue(
          FakeRecipeRepository(recipe: _recipe),
        ),
        planningRepositoryProvider.overrideWithValue(_Planner()),
        weekVariantRepositoryProvider.overrideWithValue(
          FakeWeekVariantRepository(overrides: overrides),
        ),
        ingredientRepositoryProvider.overrideWithValue(
          const ReadOnlyIngredientRepo(),
        ),
        measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) => FTheme(
          data: ansiThemeData(),
          child: FToaster(child: child ?? const SizedBox()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Rect _rect(WidgetTester tester, Finder of) => tester.getRect(of);

void main() {
  const desk = Size(1440, 2000);

  testWidgets('one column at the measure — no header form, no method, no '
      'second column', (tester) async {
    await _pump(tester, surface: desk);

    expect(find.byType(RecipeHeaderForm), findsNothing);
    expect(find.text('METHOD'), findsNothing);
    expect(find.text('INGREDIENTS'), findsNothing);

    // The list sits in the 640 measure, centred in the window — not stretched,
    // and not in the recipe editor's wider cap.
    expect(
      _rect(tester, find.textContaining('Pork sausage')).left,
      greaterThan(400),
    );
    expect(
      _rect(tester, find.byType(WeekVariantEditorView)).width,
      lessThanOrEqualTo(640),
    );
  });

  testWidgets("the week's statement is a column of its own, and the row is "
      'one line', (tester) async {
    await _pump(tester, surface: desk, overrides: _swapped);

    final name = _rect(tester, find.textContaining('Beef mince'));
    final tag = _rect(tester, find.text('this week · was 400 g Pork sausage'));
    final reset = _rect(tester, find.text('↺ reset'));

    // Beside the name, not under it: the row is one line.
    expect(tag.left, greaterThan(name.right));
    expect(tag.top, lessThan(name.bottom));
    expect(name.top, lessThan(tag.bottom));
    // …and the statement sets from the row's right end, so the five changes
    // read down one edge.
    expect(reset.right, greaterThan(tag.right - 4));
  });

  testWidgets('below expanded it is the phone’s row — the statement under the '
      'name', (tester) async {
    await _pump(tester, surface: const Size(1000, 2000), overrides: _swapped);

    final name = _rect(tester, find.textContaining('Beef mince'));
    final tag = _rect(tester, find.text('this week · was 400 g Pork sausage'));
    expect(tag.top, greaterThanOrEqualTo(name.bottom));
  });
}
