/// The timers' chrome under the app's real route shape: the dock above the
/// bar on a tab and at the foot of a pushed page, one row with the recipe's
/// whole title and +N for the rest; the opened list; the band a due timer
/// raises; and on a desk, the list in the sidebar.
library;

import 'dart:async';

import 'package:ansi/core/router/app_router.dart';
import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/features/timers/data/timer_providers.dart';
import 'package:ansi/features/timers/domain/cook_timer.dart';
import 'package:ansi/features/timers/presentation/timer_chrome.dart';
import 'package:ansi/shared/ansi_tab_shell.dart';
import 'package:ansi/shared/ansi_wide_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_timer_platform.dart';

const _harissa = 'Harissa Chicken & Butter Beans';
const _gochujang = 'Sticky Gochujang Pork Belly with Smacked Cucumber';
const _ragu = 'Slow-Cooker Beef Ragù';

void main() {
  late ProviderContainer container;
  late GoRouter router;

  Future<void> pumpApp(WidgetTester tester, {required Size size}) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: timerOverrides(
        platform: FakeTimerPlatform(),
        clock: () => tester.binding.clock.now(),
      ),
    );
    addTearDown(container.dispose);
    Widget tab(String label) => FScaffold(child: Text(label));
    router = GoRouter(
      initialLocation: '/shop',
      routes: [
        ShellRoute(
          navigatorKey: ansiShellNavigatorKey,
          builder: (context, state, child) => AnsiWideShell(
            sidebarExtra: const TimerSideList(),
            child: TimerFrame(child: child),
          ),
          routes: [
            StatefulShellRoute(
              builder: (context, state, shell) =>
                  AnsiTabShell(shell: shell, dock: const TimerDock()),
              navigatorContainerBuilder: crossFadeBranchContainer,
              branches: [
                for (final (path, label) in const [
                  ('/', 'library screen'),
                  ('/week', 'week screen'),
                  ('/cook', 'cook screen'),
                  ('/shop', 'shop screen'),
                ])
                  StatefulShellBranch(
                    routes: [
                      GoRoute(path: path, builder: (_, _) => tab(label)),
                    ],
                  ),
              ],
            ),
            GoRoute(
              path: '/recipes/:id',
              builder: (_, state) => tab(
                'recipe ${state.pathParameters['id']} '
                'step ${state.uri.queryParameters['step']}',
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => FTheme(
            data: ansiThemeData(),
            child: FToaster(child: child!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void start(String recipe, String title, int step, int minutes) => container
      .read(cookTimersProvider.notifier)
      .start(
        recipeId: recipe,
        recipeTitle: title,
        step: step,
        ordinal: 0,
        lowSeconds: minutes * 60,
        highSeconds: minutes * 60,
      );

  Future<void> stopAll(WidgetTester tester) async {
    for (final id in container.read(cookTimersProvider).byId.keys.toList()) {
      container.read(cookTimersProvider.notifier).stop(id);
    }
    await tester.pumpAndSettle();
  }

  const phone = Size(400, 820);

  testWidgets('no timer, no dock', (tester) async {
    await pumpApp(tester, size: phone);
    expect(find.byType(TimerRow), findsNothing);
  });

  testWidgets('on a tab the dock is one row — the whole title — and +N', (
    tester,
  ) async {
    await pumpApp(tester, size: phone);
    start('h1', _harissa, 3, 22);
    start('g1', _gochujang, 2, 3);
    start('s1', _ragu, 1, 72);
    await tester.pump();

    // One row, the one that needs you first: the soonest.
    final row = tester.widget<TimerRow>(find.byType(TimerRow));
    expect(row.timer.recipeTitle, _gochujang);
    expect(find.text(_gochujang), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    // Above the bar, inside the tab shell.
    expect(
      find.descendant(
        of: find.byType(AnsiTabShell),
        matching: find.byType(TimerDock),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('+2'));
    await tester.pumpAndSettle();
    expect(find.text('3 timers'), findsOneWidget);
    for (final title in [_harissa, _gochujang, _ragu]) {
      expect(find.text(title), findsWidgets);
    }

    // A row's title is the door to its step.
    await tester.tap(find.text(_ragu).last);
    await tester.pumpAndSettle();
    expect(find.text('recipe s1 step 1'), findsOneWidget);
    await stopAll(tester);
  });

  testWidgets("on a pushed page the dock sits at the screen's foot, and a "
      'row of that same recipe scrolls instead of pushing', (tester) async {
    await pumpApp(tester, size: phone);
    start('h1', _harissa, 3, 22);
    await tester.pump();
    unawaited(router.push('/recipes/h1'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(TimerFrame),
        matching: find.byType(TimerDock),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byType(TimerRow));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/recipes/h1');
    expect(container.read(methodStepFocusProvider), (
      recipeId: 'h1',
      step: 3,
      serial: 1,
    ));
    await stopAll(tester);
  });

  testWidgets('a due timer raises the band; Stop puts it away', (tester) async {
    await pumpApp(tester, size: phone);
    start('h1', _harissa, 3, 1);
    await tester.pump(const Duration(seconds: 61));

    expect(find.text('Step 4 is done'), findsOneWidget);
    expect(find.text(_harissa), findsWidgets);
    expect(container.read(cookTimersProvider).due, hasLength(1));

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(find.text('Step 4 is done'), findsNothing);
    expect(container.read(cookTimersProvider).isEmpty, isTrue);
  });

  testWidgets('+1 min on the band runs a fresh minute', (tester) async {
    await pumpApp(tester, size: phone);
    start('h1', _harissa, 3, 1);
    await tester.pump(const Duration(seconds: 70));

    await tester.tap(find.text('+1 min'));
    await tester.pump();
    expect(find.text('Step 4 is done'), findsNothing);
    expect(find.text('1:00'), findsOneWidget);
    await stopAll(tester);
  });

  testWidgets('on a desk the list sits in the sidebar and there is no dock', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(1440, 900));
    start('h1', _harissa, 3, 22);
    start('g1', _gochujang, 2, 3);
    await tester.pump();

    expect(find.text('TIMERS · 2'), findsOneWidget);
    expect(find.byType(TimerListRow), findsNWidgets(2));
    expect(find.byType(TimerRow), findsNothing);
    await stopAll(tester);
  });

  testWidgets('a notification tap opens its step', (tester) async {
    await pumpApp(tester, size: phone);
    start('h1', _harissa, 3, 22);
    await tester.pump();
    container
        .read(timerOpenRequestProvider.notifier)
        .ask(container.read(cookTimersProvider)[timerIdFor('h1', 3, 0)]!);
    await tester.pumpAndSettle();
    expect(find.text('recipe h1 step 3'), findsOneWidget);
    expect(container.read(timerOpenRequestProvider), isNull);
    await stopAll(tester);
  });
}
