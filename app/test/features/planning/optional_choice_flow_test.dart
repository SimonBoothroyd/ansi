/// Optional ingredients, chosen in the recipe while a meal is added: the door
/// on Add to plan, the recipe's quotes, the greyed method, Done back to the
/// sheet, and the write with Add and never before it.
library;

import 'package:ansi/core/units/units.dart';
import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/account/data/household_providers.dart';
import 'package:ansi/features/cook_plan/data/cook_plan_providers.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/confirm_meal_sheet.dart';
import 'package:ansi/features/planning/presentation/optional_door.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/optional_section.dart';
import 'package:ansi/features/recipes/presentation/recipe_view.dart';
import 'package:ansi/shared/method_step_text.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_cook_plan_repository.dart';
import '../../helpers/fake_leftover_repository.dart';
import '../../helpers/fake_planning_repository.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/fake_week_variant_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/pump_app.dart';

final _monday = WeekShape.monday.weekStartOf(DateTime.now());
const _summary = RecipeSummary(id: 'r', title: 'Curry', servingsBase: 4);

Recipe _curry({int others = 2, bool linked = true}) => Recipe(
  id: 'r',
  title: 'Curry',
  servingsBase: 4,
  steps: linked ? const [] : const ['Finish with lime and coriander.'],
  groups: [
    IngredientGroup(
      id: 'g',
      items: [
        for (var i = 0; i < others; i++)
          LineItem(
            id: 'o$i',
            ingredientId: 'i-o$i',
            ingredientName: 'Staple $i',
            quantity: 100,
            unit: g,
          ),
        const LineItem(
          id: 'lime',
          ingredientId: 'i-lime',
          ingredientName: 'Lime',
          quantity: 2,
          unit: pieces,
          note: 'to serve',
          optional: true,
        ),
        const LineItem(
          id: 'coriander',
          ingredientId: 'i-coriander',
          ingredientName: 'Coriander',
          quantity: 15,
          unit: g,
          optional: true,
        ),
      ],
    ),
  ],
  methodSteps: !linked
      ? null
      : const [
          MethodStep(
            tokens: [
              MethodText(s: 'Off the heat, squeeze over the '),
              MethodRef(refs: ['lime'], label: 'lime'),
              MethodText(s: ' and scatter with '),
              MethodRef(refs: ['coriander'], label: 'coriander'),
              MethodText(s: '.'),
            ],
          ),
        ],
);

Future<(FakePlanningRepository, FakeWeekVariantRepository)> _open(
  WidgetTester tester, {
  Recipe? recipe,
  List<LineOverride> week = const [],
}) async {
  filterForuiSemanticsAssertions();
  tester.view.physicalSize = const Size(402, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final planner = FakePlanningRepository(const [
    Member(id: 'm1', displayName: 'Ada'),
  ]);
  final variants = FakeWeekVariantRepository(
    overrides: {if (week.isNotEmpty) 'r': week},
  );
  await tester.pumpWidget(
    routedHost(
      initial: '/',
      routes: {
        '/': (context, _) => Builder(
          builder: (context) => GestureDetector(
            onTap: () => showConfirmMealSheet(
              context,
              weekStart: _monday,
              dayOfWeek: 1,
              slot: 'Dinner',
              target: const RecipeMeal(_summary),
            ),
            child: const Text('open'),
          ),
        ),
        '/recipes/:id': (_, state) => RecipeView(
          recipeId: state.pathParameters['id']!,
          weekKey: state.uri.queryParameters['week'],
          choosingDay: int.tryParse(state.uri.queryParameters['choose'] ?? ''),
        ),
      },
      overrides: [
        weekShapeProvider.overrideWithValue(WeekShape.monday),
        planningRepositoryProvider.overrideWithValue(planner),
        cookPlanRepositoryProvider.overrideWithValue(FakeCookPlanRepository()),
        leftoverRepositoryProvider.overrideWithValue(FakeLeftoverRepository()),
        weekVariantRepositoryProvider.overrideWithValue(variants),
        recipeRepositoryProvider.overrideWithValue(
          FakeRecipeRepository(
            summaries: const [_summary],
            recipe: recipe ?? _curry(),
          ),
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (planner, variants);
}

Future<void> _choose(WidgetTester tester) async {
  await tester.tap(find.byType(OptionalInRecipeDoor));
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, String lineId) async {
  await tester.tap(find.byKey(optionalCardKey(lineId)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Add to plan holds no ticks, only the door into the recipe', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('2 optional ingredients'), findsOneWidget);
    expect(find.text('Choose in recipe'), findsOneWidget);
    expect(find.byType(OptionalCard), findsNothing);
  });

  testWidgets('each is read in the step that uses it', (tester) async {
    await _open(tester);
    await _choose(tester);
    expect(find.text('for Tuesday'), findsOneWidget);
    expect(
      find.textContaining('Off the heat, squeeze over the lime…'),
      findsOneWidget,
    );
    expect(find.textContaining('…and scatter with coriander.'), findsOneWidget);
  });

  testWidgets('a method with no links leaves the note to say it', (
    tester,
  ) async {
    await _open(tester, recipe: _curry(linked: false));
    await _choose(tester);
    expect(find.textContaining('Step 1'), findsNothing);
    expect(find.textContaining('to serve'), findsOneWidget);
  });

  testWidgets('Done returns to the sheet, which names the pick, and Add '
      'writes it', (tester) async {
    final (planner, variants) = await _open(tester);
    await _choose(tester);
    await _pick(tester, 'coriander');
    expect(variants.ticked, isEmpty);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('With Coriander'), findsOneWidget);
    expect(variants.ticked, isEmpty);

    await tester.tap(find.text('Add to Tuesday'));
    await tester.pumpAndSettle();
    expect(variants.ticked, [
      (weekStart: _monday, recipeId: 'r', lineId: 'coriander', included: true),
    ]);
    expect(planner.recipeEntries.single.recipeId, 'r');
  });

  testWidgets('closing the sheet drops the picks', (tester) async {
    final (planner, variants) = await _open(tester);
    await _choose(tester);
    await _pick(tester, 'lime');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('With Lime'), findsOneWidget);

    await tester.tapAt(const Offset(200, 10));
    await tester.pumpAndSettle();
    expect(variants.ticked, isEmpty);
    expect(planner.recipeEntries, isEmpty);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('2 optional ingredients'), findsOneWidget);
  });

  testWidgets('a week that already picked one says so on the sheet', (
    tester,
  ) async {
    await _open(
      tester,
      week: const [
        LineOverride(
          action: LineOverrideAction.include,
          recipeLineItemId: 'lime',
        ),
      ],
    );
    expect(find.text('With Lime'), findsOneWidget);
  });

  testWidgets('the method greys what was not picked, and drops its amount', (
    tester,
  ) async {
    await _open(tester);
    await _choose(tester);
    await _pick(tester, 'coriander');
    await tester.tap(find.text('Method'));
    await tester.pumpAndSettle();

    MethodChip chip(String label) => tester.widget<MethodChip>(
      find.byWidgetPredicate((w) => w is MethodChip && w.label == label),
    );
    expect(chip('lime').weekStruck, isTrue);
    expect(chip('coriander').weekStruck, isFalse);
    expect(find.text(' · left out'), findsOneWidget);
    expect(find.text('15 g'), findsOneWidget);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('a long recipe opens on the choice, not above it', (
    tester,
  ) async {
    await _open(tester, recipe: _curry(others: 24));
    await _choose(tester);
    final last = tester.getRect(find.byKey(optionalCardKey('coriander')));
    expect(
      last.bottom,
      lessThanOrEqualTo(tester.getRect(find.text('Done')).top),
    );
    expect(last.top, greaterThanOrEqualTo(0));
  });
}
