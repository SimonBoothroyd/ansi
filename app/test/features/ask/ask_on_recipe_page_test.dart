/// Ask Ansi from the recipe page (plan 0053, slice 1): the sheet sees the
/// recipe at the stepper's servings, the tools run against the page's own
/// rows, and an action lands on the page — the stepper moves, a step's timer
/// starts. A spoken question is sent on the pause and its answer read aloud.
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ask/data/ask_providers.dart';
import 'package:ansi/features/ask/data/ask_voice.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/recipe_view.dart';
import 'package:ansi/features/recipes/presentation/recipe_view_models.dart';
import 'package:ansi/features/timers/data/timer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_ask.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/fake_timer_platform.dart';
import '../../helpers/forui_semantics.dart';

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
        MethodText(s: 'Simmer for '),
        MethodToken.timer(lowSeconds: 1200, highSeconds: 1500),
        MethodText(s: '.'),
      ],
    ),
  ],
);

void main() {
  late ProviderContainer container;
  late FakeAskVoice voice;

  Future<void> openAsk(WidgetTester tester, List<AskScript> script) async {
    // Opening a Forui sheet with semantics live trips a framework assertion
    // that is not this code's (see the helper).
    filterForuiSemanticsAssertions();
    voice = FakeAskVoice();
    container = ProviderContainer(
      overrides: [
        recipeRepositoryProvider.overrideWithValue(
          FakeRecipeRepository(recipe: _ragu),
        ),
        askRepositoryProvider.overrideWithValue(ScriptedAskRepository(script)),
        askVoiceProvider.overrideWithValue(voice),
        ...timerOverrides(
          platform: FakeTimerPlatform(),
          clock: () => tester.binding.clock.now(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          // Above the navigator, as the app has it, so the sheet's route sees
          // the theme and the toaster too.
          builder: (context, child) => FTheme(
            data: ansiThemeData(),
            child: FToaster(child: child!),
          ),
          home: const RecipeView(recipeId: 'r1'),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Ask Ansi about this recipe'));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String words) async {
    await tester.enterText(find.byType(EditableText), words);
    await tester.pump();
    await tester.tap(find.byIcon(FLucideIcons.arrowUp));
    await tester.pumpAndSettle();
  }

  /// Every held timer stopped, so no tick outlives the test.
  Future<void> stopTimers(WidgetTester tester) async {
    for (final id in container.read(cookTimersProvider).byId.keys.toList()) {
      container.read(cookTimersProvider.notifier).stop(id);
    }
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet sees the recipe at the servings on screen', (
    tester,
  ) async {
    await openAsk(tester, const []);
    expect(find.text('Ask Ansi'), findsOneWidget);
    expect(find.text('On: Ragù · serves 4'), findsOneWidget);
    // Its ✕ asks from nowhere instead.
    await tester.tap(find.bySemanticsLabel('Ask without this screen'));
    await tester.pump();
    expect(find.text('Asking about nothing on screen'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('"how much tamari?" is answered from the page\'s own line', (
    tester,
  ) async {
    await openAsk(tester, [
      (_) => askToolCall('recipe_lines', {
        'recipe_id': 'r1',
        'servings': null,
        'ingredient': 'tamari',
        'for_week': null,
      }),
      (sent) {
        // The amount was written by the app, at the stepper's servings.
        expect(lastToolResult(sent), contains('"amount":"2 tbsp"'));
        return askSays('2 tbsp tamari — Ragù, serves 4.');
      },
    ]);
    await type(tester, 'how much tamari?');
    expect(find.text('how much tamari?'), findsOneWidget);
    expect(find.text('2 tbsp tamari — Ragù, serves 4.'), findsOneWidget);
    // A typed question is not read aloud.
    expect(voice.spoken, isEmpty);
  });

  testWidgets('"make it 8 servings" moves the page\'s stepper', (tester) async {
    await openAsk(tester, [
      (_) => askToolCall('set_servings', {'servings': 8}),
      (_) => askSays('Ragù now serves 8.'),
    ]);
    await type(tester, 'make it 8 servings');
    expect(container.read(recipeServingsProvider('r1')), 8);
    expect(find.text('✓ Ragù now serves 8'), findsOneWidget);
    expect(find.text('On: Ragù · serves 8'), findsOneWidget);
  });

  testWidgets('"start the simmer timer" starts the step\'s own timer', (
    tester,
  ) async {
    await openAsk(tester, [
      (_) => askToolCall('start_step_timer', {
        'recipe_id': 'r1',
        'step': 1,
        'timer': null,
      }),
      (_) => askSays('Started the 20–25 minute simmer.'),
    ]);
    await type(tester, 'start the simmer timer');
    expect(container.read(cookTimersProvider).byId, hasLength(1));
    expect(find.text('✓ Started step 1’s timer · 20–25 min'), findsOneWidget);
    await stopTimers(tester);
  });

  testWidgets('a spoken question is sent on the pause and answered aloud', (
    tester,
  ) async {
    await openAsk(tester, [(_) => askSays('2 tbsp tamari — Ragù, serves 4.')]);
    voice.heard = 'how much tamari';
    await tester.tap(find.bySemanticsLabel('Speak'));
    await tester.pumpAndSettle();
    expect(find.text('how much tamari'), findsOneWidget);
    expect(voice.spoken, ['2 tbsp tamari — Ragù, serves 4.']);
  });

  testWidgets('a refused mic says how to fix it', (tester) async {
    await openAsk(tester, const []);
    voice.available = false;
    await tester.tap(find.bySemanticsLabel('Speak'));
    await tester.pumpAndSettle();
    expect(find.textContaining('allow the microphone'), findsOneWidget);
  });
}
