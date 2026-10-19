import 'dart:convert';

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ask/domain/ask_screen.dart';
import 'package:ansi/features/ask/domain/ask_thread.dart';
import 'package:ansi/features/ask/domain/ask_tool_runner.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_ask.dart';

const _ragu = Recipe(
  id: 'r1',
  title: 'Ragù',
  servingsBase: 4,
  groups: [
    IngredientGroup(
      id: 'g1',
      items: [
        LineItem(
          id: 'tamari',
          ingredientId: 'ing-tamari',
          ingredientName: 'Tamari',
          unit: tbsp,
          quantity: 2,
        ),
      ],
    ),
  ],
  methodSteps: [
    MethodStep(
      tokens: [
        MethodText(s: 'Simmer '),
        MethodTimer(lowSeconds: 1200, highSeconds: 1500),
      ],
    ),
  ],
);

AskToolCall _call(String name, Map<String, Object?> input) =>
    AskToolCall(id: 't', name: name, input: input);

void main() {
  late AskScreen screen;
  late List<String> log;

  AskToolRunner runner({AskWeekOfRecipe? week, FakeAskHousehold? household}) =>
      AskToolRunner(
        screen: () => screen,
        loadRecipe: (id) async => id == 'r1' ? _ragu : null,
        listRecipes: () async => [(id: 'r1', title: 'Ragù')],
        weekOf: (recipeId, weekKey) async =>
            week ?? (overrides: const <LineOverride>[], portions: null),
        setServings: (id, servings) => log.add('servings $id $servings'),
        startTimer:
            (
              recipe, {
              required step,
              required ordinal,
              required low,
              required high,
            }) => log.add('timer ${recipe.id} $step $ordinal $low-$high'),
        openRecipe: (id) => log.add('open $id'),
        household: (household ?? FakeAskHousehold()).household,
      );

  setUp(() {
    log = [];
    screen = const AskRecipeScreen(
      recipeId: 'r1',
      title: 'Ragù',
      servings: 6,
      servingsBase: 4,
    );
  });

  String amountOf(String content) =>
      (((jsonDecode(content) as Map)['lines']! as List).first as Map)['amount']!
          as String;

  test('a recipe on screen scales to the servings the stepper shows', () async {
    final out = await runner().run(
      _call('recipe_lines', {'recipe_id': 'r1', 'servings': null}),
    );
    expect(out.isError, isFalse);
    expect(amountOf(out.content), '3 tbsp');
  });

  test('a recipe off screen scales to its own servings', () async {
    screen = const AskNoScreen();
    final out = await runner().run(
      _call('recipe_lines', {'recipe_id': 'r1', 'servings': null}),
    );
    expect(amountOf(out.content), '2 tbsp');
  });

  test(
    "this week's lines need the page to have been opened from a week",
    () async {
      final refused = await runner().run(
        _call('recipe_lines', {'recipe_id': 'r1', 'for_week': true}),
      );
      expect(refused.isError, isTrue);
      expect(refused.content, contains('not opened from a week'));

      screen = const AskRecipeScreen(
        recipeId: 'r1',
        title: 'Ragù',
        servings: 4,
        servingsBase: 4,
        weekKey: '2026-10-19',
      );
      final out = await runner(
        week: (overrides: const <LineOverride>[], portions: 8),
      ).run(_call('recipe_lines', {'recipe_id': 'r1', 'for_week': true}));
      expect(amountOf(out.content), '4 tbsp');
      expect(out.content, contains("this week's plan: 8 portions"));
    },
  );

  test('a step timer starts and says what it started', () async {
    final out = await runner().run(
      _call('start_step_timer', {'recipe_id': 'r1', 'step': 1, 'timer': null}),
    );
    expect(log, ['timer r1 0 0 1200-1500']);
    expect(out.done, 'Started step 1’s timer · 20–25 min');
  });

  test('only the recipe on screen can be scaled', () async {
    final out = await runner().run(_call('set_servings', {'servings': 8}));
    expect(log, ['servings r1 8.0']);
    expect(out.done, 'Ragù now serves 8');

    screen = const AskNoScreen();
    final refused = await runner().run(_call('set_servings', {'servings': 8}));
    expect(refused.isError, isTrue);
    expect(log, hasLength(1));
  });

  test('open_recipe hands the id over; an unknown id is refused', () async {
    final out = await runner().run(_call('open_recipe', {'recipe_id': 'r1'}));
    expect(log, ['open r1']);
    expect(out.done, 'Opening Ragù');
    final refused = await runner().run(
      _call('open_recipe', {'recipe_id': 'nope'}),
    );
    expect(refused.isError, isTrue);
  });

  test('an unknown tool and a missing argument come back as errors', () async {
    expect((await runner().run(_call('plan_week', {}))).isError, isTrue);
    expect((await runner().run(_call('find_recipe', {}))).isError, isTrue);
  });
}
