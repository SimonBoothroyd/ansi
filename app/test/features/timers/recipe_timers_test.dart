/// Timers on the recipe page: a timer chip's tap starts it at the middle of
/// its range and the chip counts where it stands; a running chip opens its
/// sheet; a struck step never rules its timer; and the ticks go with the
/// page even while a timer runs.
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/theme/ansi_tokens.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/recipe_view.dart';
import 'package:ansi/features/timers/data/timer_providers.dart';
import 'package:ansi/features/timers/domain/cook_timer.dart';
import 'package:ansi/shared/method_step_text.dart';
import 'package:ansi/shared/timer_wash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/fake_timer_platform.dart';

const _harissa = Recipe(
  id: 'h1',
  title: 'Harissa Chicken & Butter Beans',
  servingsBase: 4,
  groups: [
    IngredientGroup(
      id: 'g1',
      items: [
        LineItem(
          id: 'i1',
          ingredientId: 'onion',
          ingredientName: 'Red onion',
          unit: pieces,
          quantity: 2,
        ),
      ],
    ),
  ],
  methodSteps: [
    MethodStep(
      tokens: [
        MethodText(s: 'Soften the '),
        MethodRef(refs: ['i1'], label: 'red onion'),
        MethodText(s: ', about '),
        MethodToken.timer(lowSeconds: 480, highSeconds: 600),
        MethodText(s: '.'),
      ],
    ),
    MethodStep(
      tokens: [
        MethodText(s: 'Simmer uncovered for '),
        MethodToken.timer(lowSeconds: 1200, highSeconds: 1500),
        MethodText(s: '.'),
      ],
    ),
  ],
);

/// The style a method step's prose is set in.
TextStyle _stepStyle(WidgetTester tester, int step) => tester
    .widget<Text>(
      find
          .descendant(
            of: find.byType(MethodStepText).at(step),
            matching: find.byType(Text),
          )
          .first,
    )
    .textSpan!
    .style!;

void main() {
  late FakeTimerPlatform platform;
  late ProviderContainer container;

  setUp(() => platform = FakeTimerPlatform());

  /// The page under one container the test holds, so it can be closed and
  /// opened again with the timers still there. [show] false closes it.
  Future<void> pump(WidgetTester tester, {bool show = true}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: FTheme(
            data: ansiThemeData(),
            child: show
                ? const RecipeView(recipeId: 'h1')
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> openMethod(WidgetTester tester) async {
    container = ProviderContainer(
      overrides: [
        recipeRepositoryProvider.overrideWithValue(
          FakeRecipeRepository(recipe: _harissa),
        ),
        ...timerOverrides(
          platform: platform,
          clock: () => tester.binding.clock.now(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await pump(tester);
    await tester.tap(find.text('Method'));
    await tester.pumpAndSettle();
  }

  /// Every held timer stopped, so no tick outlives the test, then the taps'
  /// own gesture timers run out.
  Future<void> stopAll(WidgetTester tester) async {
    final timers = container.read(cookTimersProvider);
    for (final id in timers.byId.keys.toList()) {
      container.read(cookTimersProvider.notifier).stop(id);
    }
    await tester.pumpAndSettle();
  }

  Finder chip(String words) => find.byWidgetPredicate(
    (w) => w is MethodChip && w.timer && w.label == words,
  );

  testWidgets('a timer chip starts at the middle of its range and counts '
      'where it stands', (tester) async {
    await openMethod(tester);

    expect(find.text('20–25 min'), findsOneWidget);
    await tester.tap(find.text('20–25 min'));
    await tester.pump();

    expect(find.text('20–25 min'), findsNothing);
    expect(find.text('22:30'), findsOneWidget);
    final held = container.read(cookTimersProvider)[timerIdFor('h1', 1, 0)];
    expect(held?.recipeTitle, 'Harissa Chicken & Butter Beans');

    await tester.pump(const Duration(minutes: 1));
    expect(find.text('21:30'), findsOneWidget);
    expect(
      tester
          .widget<TimerWash>(
            find.descendant(
              of: chip('20–25 min'),
              matching: find.byType(TimerWash),
            ),
          )
          .state,
      CookTimerState.running,
    );
    await stopAll(tester);
  });

  testWidgets('a struck step rules its prose, never its timer', (tester) async {
    await openMethod(tester);
    await tester.tap(find.text('8–10 min'));
    await tester.pump();
    // The step's number is its own row's tap.
    await tester.tap(find.text('1'));
    await tester.pump();

    expect(_stepStyle(tester, 0).decoration, TextDecoration.lineThrough);
    final count = tester.widget<Text>(find.text('9:00'));
    expect(count.style?.decoration, isNot(TextDecoration.lineThrough));
    expect(count.style?.color, AnsiColors.herbDeep);
    await stopAll(tester);
  });

  testWidgets('a running chip opens its sheet: pause, nudge, cancel', (
    tester,
  ) async {
    await openMethod(tester);
    await tester.tap(find.text('20–25 min'));
    await tester.pump();

    await tester.tap(find.text('22:30'));
    await tester.pumpAndSettle();
    expect(find.text('Harissa Chicken & Butter Beans'), findsWidgets);
    expect(find.textContaining('the middle of 20–25 min'), findsOneWidget);

    await tester.tap(find.text('+1 min'));
    await tester.pump();
    expect(find.text('23:30'), findsWidgets);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('Resume'), findsOneWidget);
    expect(
      container.read(cookTimersProvider)[timerIdFor('h1', 1, 0)]!.paused,
      isTrue,
    );

    await tester.tap(find.text('Cancel · back to 20–25 min'));
    await tester.pumpAndSettle();
    expect(container.read(cookTimersProvider).isEmpty, isTrue);
    // The sheet went with the timer, and the chip has its words back.
    expect(find.text('Resume'), findsNothing);
    expect(find.text('20–25 min'), findsOneWidget);
  });

  testWidgets('the ticks go with the page, even while its timer runs', (
    tester,
  ) async {
    await openMethod(tester);
    await tester.tap(find.text('20–25 min'));
    await tester.pump();
    await tester.tap(find.text('1'));
    await tester.pump();
    bool firstStepStruck() =>
        _stepStyle(tester, 0).decoration == TextDecoration.lineThrough;
    expect(firstStepStruck(), isTrue);

    await pump(tester, show: false);
    await pump(tester);
    await tester.tap(find.text('Method'));
    await tester.pump();
    // The timer is still held, and the step is not struck.
    expect(
      container.read(cookTimersProvider)[timerIdFor('h1', 1, 0)],
      isNotNull,
    );
    expect(firstStepStruck(), isFalse);
    await stopAll(tester);
  });

  testWidgets('Keep screen on is the menu item, and the sun is its way off', (
    tester,
  ) async {
    await openMethod(tester);
    await tester.tap(find.byIcon(FLucideIcons.ellipsis));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep screen on'));
    await tester.pumpAndSettle();

    expect(platform.awake, isTrue);
    expect(find.byIcon(FLucideIcons.sun), findsOneWidget);

    await tester.tap(find.byIcon(FLucideIcons.sun));
    await tester.pumpAndSettle();
    expect(platform.awake, isFalse);
    expect(find.byIcon(FLucideIcons.sun), findsNothing);
  });
}
