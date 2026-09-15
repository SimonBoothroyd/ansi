/// The recipe page at `AnsiLayout.expanded`: Ingredients and Method as two
/// columns read together, no tab bar, and the per-serving panel closing the
/// ingredients column with the back-links under it.
///
/// Every assertion here is about PLACEMENT. What a line, a step, a panel or a
/// week's answer says is already pinned by the phone's own suites, and this
/// layout shares those widgets rather than restating them — so a test that
/// re-asserted their words would only prove the sharing twice.
library;

import 'dart:io';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/week_recipe_band.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:ansi/features/recipes/domain/recipe_repository.dart';
import 'package:ansi/features/recipes/presentation/ingredient_line.dart';
import 'package:ansi/features/recipes/presentation/recipe_macro_panel.dart';
import 'package:ansi/features/recipes/presentation/recipe_view.dart';
import 'package:ansi/shared/ansi_layout.dart';
import 'package:ansi/shared/ansi_stepper_row.dart';
import 'package:ansi/shared/incomplete_macros.dart';
import 'package:ansi/shared/method_step_text.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/fake_planning_repository.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/fake_week_variant_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/pump_app.dart';

const _weekKey = '2026-09-14';
final _monday = DateTime.utc(2026, 9, 14);

const _complete = RecipeMacroSummary(
  perServing: Macros(kcal: 611.6, protein: 41.4, carb: 17.7, fat: 38.5),
);

const _refusing = RecipeMacroSummary(
  stubLines: 1,
  notes: [
    (
      lineId: 'l2',
      name: 'Tofu',
      reason: MacroLineReason.stubIngredient,
      unit: null,
    ),
  ],
);

Recipe _recipe({RecipeMacroSummary? macros = _complete}) => Recipe(
  id: 'r1',
  title: 'Harissa Chicken & Butter Beans',
  servingsBase: 4,
  macros: macros,
  steps: const ['Brown the chicken in a wide pan.', 'Simmer until thick.'],
  groups: const [
    IngredientGroup(
      id: 'g1',
      name: 'for the pan',
      items: [
        LineItem(
          id: 'l1',
          ingredientId: 'i-chicken',
          ingredientName: 'Chicken thigh',
          unit: g,
          quantity: 600,
        ),
        LineItem(
          id: 'l2',
          ingredientId: 'i-tofu',
          ingredientName: 'Tofu',
          unit: g,
          quantity: 200,
        ),
      ],
    ),
  ],
);

/// The same recipe with a tokenized method, so the right column has chips in
/// it. The chip labels are lower case, and so tell themselves apart from the
/// ingredient names the left column is drawing at the same time.
Recipe _tokenized() => _recipe().copyWith(
  steps: const [],
  methodSteps: const [
    MethodStep(
      tokens: [
        MethodText(s: 'Brown the '),
        MethodRef(refs: ['l1'], label: 'chicken'),
        MethodText(s: ' in a wide pan.'),
      ],
    ),
  ],
);

/// The ink one method chip's word is painted in.
TextStyle _chipStyle(WidgetTester tester, String label) => tester
    .widget<Text>(
      find.descendant(
        of: find.byWidgetPredicate((w) => w is MethodChip && w.label == label),
        matching: find.text(label),
      ),
    )
    .style!;

class _Repo extends FakeRecipeRepository {
  _Repo({super.recipe, this.uses = const []});

  final List<RecipeUse> uses;

  @override
  Future<List<RecipeUse>> usedIn(String recipeId) async => uses;
}

/// The week that cooks it on Tuesday, leaving the tofu out.
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
          recipeTitle: 'Harissa Chicken & Butter Beans',
          eaterIds: ['m1'],
        ),
      ],
    ),
  );
}

/// A desk-width window. The page sits in the cap the router gives it, so the
/// columns are measured at the width they are really drawn at.
Future<void> _pumpWide(
  WidgetTester tester, {
  Recipe? recipe,
  List<RecipeUse> uses = const [],
  bool fromWeek = false,
  Map<String, List<LineOverride>> overrides = const {},
}) async {
  filterForuiSemanticsAssertions();
  tester.view.physicalSize = const Size(1440, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpAnsiApp(
    AnsiMeasure(
      width: ansiWideMeasureWidth,
      child: RecipeView(recipeId: 'r1', weekKey: fromWeek ? _weekKey : null),
    ),
    overrides: <Override>[
      recipeRepositoryProvider.overrideWithValue(
        _Repo(recipe: recipe ?? _recipe(), uses: uses),
      ),
      if (fromWeek) ...[
        planningRepositoryProvider.overrideWithValue(_Planner()),
        weekVariantRepositoryProvider.overrideWithValue(
          FakeWeekVariantRepository(overrides: overrides),
        ),
      ],
    ],
  );
  await tester.pumpAndSettle();
}

/// The left edge of a column, read off its own heading.
double _columnLeft(WidgetTester tester, String heading) =>
    tester.getTopLeft(find.text(heading)).dx;

void main() {
  test('structural: the router gives the recipe route the wider cap', () {
    final source = File('lib/core/router/app_router.dart').readAsStringSync();
    final start = source.indexOf("path: '/recipes/:id',");
    expect(start, isNot(-1), reason: 'the recipe route should exist');
    // Up to the route declared after it, so the slice does not depend on how
    // deeply the route list happens to be indented.
    final route = source.substring(
      start,
      source.indexOf("path: '/recipes/:id/edit'", start),
    );
    expect(
      route,
      contains('measure: ansiWideMeasureWidth'),
      reason:
          'the two-column page needs a cap wider than the 640 measure, and it '
          'comes from the layout file rather than a number in the router',
    );
  });

  testWidgets('two columns, read together — and no tab bar to choose between '
      'them', (tester) async {
    await _pumpWide(tester);

    // The columns name themselves where the tab bar's underline used to.
    expect(find.text('INGREDIENTS'), findsOneWidget);
    expect(find.text('METHOD'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('METHOD')).dy,
      tester.getTopLeft(find.text('INGREDIENTS')).dy,
    );
    expect(
      _columnLeft(tester, 'METHOD'),
      greaterThan(_columnLeft(tester, 'INGREDIENTS')),
    );
    // The tab bar's own labels are gone: nothing is switched between.
    expect(find.text('Ingredients'), findsNothing);
    expect(find.text('Method'), findsNothing);
    // And both columns are drawn at once — a line on the left, a step on the
    // right, each the widget the phone draws.
    expect(find.byType(RecipeIngredientLine), findsNWidgets(2));
    final step = find.text('Brown the chicken in a wide pan.');
    expect(step, findsOneWidget);
    expect(
      tester.getTopLeft(step).dx,
      greaterThan(_columnLeft(tester, 'INGREDIENTS')),
    );
    expect(
      tester.getTopLeft(step).dx,
      greaterThanOrEqualTo(_columnLeft(tester, 'METHOD')),
    );
  });

  testWidgets('the page is capped and centred, not stretched across the '
      'window', (tester) async {
    await _pumpWide(tester);

    final title = tester.getRect(find.text('Harissa Chicken & Butter Beans'));
    // 1440 wide window, a page of about 1000: the hero starts well inside it.
    expect(title.left, greaterThan(180));
    expect(tester.getRect(find.text('METHOD')).right, lessThan(1440 - 180));
  });

  testWidgets('the per-serving panel closes the ingredients column, at the '
      "column's width", (tester) async {
    await _pumpWide(tester);

    expect(find.byType(RecipeMacroPanel), findsOneWidget);
    final panel = tester.getRect(find.byType(RecipeMacroPanel));
    final lastLine = tester.getRect(find.byType(RecipeIngredientLine).last);
    // Under the lines it sums, not beside them in a rail.
    expect(panel.top, greaterThan(lastLine.bottom));
    expect(panel.left, lastLine.left);
    expect(panel.width, lastLine.width);
    // And inside the column: it never reaches the method beside it.
    expect(panel.right, lessThanOrEqualTo(_columnLeft(tester, 'METHOD')));
  });

  testWidgets('the refusal refuses in the same column, and the method beside '
      'it is untouched', (tester) async {
    await _pumpWide(tester);
    expect(find.byType(IncompleteBadge), findsNothing);

    await _pumpWide(tester, recipe: _recipe(macros: _refusing));

    final badge = tester.getRect(find.byType(IncompleteBadge));
    expect(badge.right, lessThanOrEqualTo(_columnLeft(tester, 'METHOD')));
    expect(find.text('Brown the chicken in a wide pan.'), findsOneWidget);
  });

  group('the back-links', () {
    testWidgets('are absent while nothing points here', (tester) async {
      await _pumpWide(tester);

      expect(find.textContaining('USED IN'), findsNothing);
      expect(find.textContaining('Used in'), findsNothing);
    });

    testWidgets('close the ingredients column with their count once something '
        'does', (tester) async {
      await _pumpWide(
        tester,
        uses: const [
          RecipeUse(
            lineId: 'x1',
            recipeId: 'parent',
            title: 'Sausage Sliders',
            quantity: 1,
            unit: batches,
            amount: ResolvedComponentAmount(1),
          ),
        ],
      );

      expect(find.text('USED IN · 1'), findsOneWidget);
      final heading = tester.getRect(find.text('USED IN · 1'));
      expect(
        heading.top,
        greaterThan(tester.getRect(find.byType(RecipeMacroPanel)).top),
      );
      expect(heading.right, lessThanOrEqualTo(_columnLeft(tester, 'METHOD')));
    });
  });

  testWidgets('from a week, the band and the struck line arrive in the same '
      'two columns', (tester) async {
    await _pumpWide(
      tester,
      fromWeek: true,
      overrides: const {
        'r1': [
          LineOverride(
            id: 'ov1',
            action: LineOverrideAction.exclude,
            recipeLineItemId: 'l2',
          ),
        ],
      },
    );

    // The band sits in the hero, between the title and the chips.
    expect(find.byType(PlannedThisWeekBand), findsOneWidget);
    final band = tester.getRect(find.byType(PlannedThisWeekBand));
    expect(
      band.top,
      greaterThan(
        tester.getRect(find.text('Harissa Chicken & Butter Beans')).top,
      ),
    );
    expect(band.bottom, lessThan(tester.getRect(find.text('INGREDIENTS')).top));
    // The week's answer per line is week mode's own, in the left column.
    final tofu = tester.widget<RecipeIngredientLine>(
      find.byWidgetPredicate(
        (w) => w is RecipeIngredientLine && w.uses.ingredientName == 'Tofu',
      ),
    );
    expect(tofu.struck, isTrue);
    // And the week's second door hangs off the hero's own ⋯.
    await tester.tap(find.byIcon(FLucideIcons.ellipsis));
    await tester.pumpAndSettle();
    expect(find.textContaining('Edit for this week'), findsOneWidget);
    expect(find.text('Edit recipe'), findsOneWidget);
  });

  testWidgets('a method chip ticks off in the two-column layout too — one '
      'page, one set of ticks', (tester) async {
    await _pumpWide(tester, recipe: _tokenized());

    expect(_chipStyle(tester, 'chicken').decoration, isNull);

    await tester.tap(find.text('chicken'));
    await tester.pumpAndSettle();

    expect(
      _chipStyle(tester, 'chicken').decoration,
      TextDecoration.lineThrough,
    );
    // The left column is untouched: a tick is about the method, not the line.
    final line = tester.widget<RecipeIngredientLine>(
      find.byWidgetPredicate(
        (w) =>
            w is RecipeIngredientLine &&
            w.uses.ingredientName == 'Chicken thigh',
      ),
    );
    expect(line.struck, isFalse);
  });

  testWidgets('at a phone width the page is the page it has always been', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    tester.view.physicalSize = const Size(402, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpAnsiApp(
      const AnsiMeasure(
        width: ansiWideMeasureWidth,
        child: RecipeView(recipeId: 'r1'),
      ),
      overrides: <Override>[
        recipeRepositoryProvider.overrideWithValue(_Repo(recipe: _recipe())),
      ],
    );
    await tester.pumpAndSettle();

    // The tabs are back, one pane is showing, and no column names itself.
    expect(find.text('Ingredients'), findsOneWidget);
    expect(find.text('Method'), findsOneWidget);
    expect(find.text('INGREDIENTS'), findsNothing);
    expect(find.text('Brown the chicken in a wide pan.'), findsNothing);
  });

  testWidgets('the servings scaler is one control, not a band across the '
      'measure', (tester) async {
    filterForuiSemanticsAssertions();
    // Medium: the tabs are still drawn, so the scaler sits above the lines
    // rather than in the hero — and the page is already at its 640 measure,
    // which is where an uncapped stepper stretched to.
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpAnsiApp(
      const AnsiMeasure(
        width: ansiWideMeasureWidth,
        child: RecipeView(recipeId: 'r1'),
      ),
      overrides: <Override>[
        recipeRepositoryProvider.overrideWithValue(_Repo(recipe: _recipe())),
      ],
    );
    await tester.pumpAndSettle();

    final scaler = find.byType(AnsiStepperRow);
    expect(scaler, findsOneWidget);
    final rect = tester.getRect(scaler);
    // Capped at the width the hero gives it, rather than spreading its two
    // buttons across the 640 measure.
    expect(rect.width, lessThanOrEqualTo(300));
    // And the buttons are the small ones — Forui's touch `sm`, 40, not the
    // `md` 44 that made this box taller than the title beside it. The box's
    // own height is the buttons' plus its padding, and is left to the font.
    final button = find.descendant(of: scaler, matching: find.byType(FButton));
    expect(button, findsNWidgets(2));
    expect(tester.getRect(button.first).height, 40);
    expect(tester.getRect(button.last).height, 40);
  });
}
