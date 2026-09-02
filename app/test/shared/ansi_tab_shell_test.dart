/// The tab shell's navigation rules: what back does on each tab (D3-b), what
/// re-tapping the selected tab does, and that a tab keeps its state (D7).
///
/// The shell, the bar and the cross-fade container are the real ones; only the
/// four screens are stand-ins, so the test is about navigation rather than
/// about what any tab renders.
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/shared/ansi_tab_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

/// A counter page: the tap count is [State] held by the branch's Navigator, so
/// it survives a tab switch exactly when the branch subtree stays mounted.
class _CounterPage extends StatefulWidget {
  const _CounterPage(this.label);

  final String label;

  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int count = 0;

  @override
  Widget build(BuildContext context) => FScaffold(
    child: Column(
      children: [
        Text('${widget.label} $count'),
        // Labelled per branch: every branch stays mounted under the shell
        // (that is the point of it), so a bare 'bump' would be ambiguous.
        TextButton(
          onPressed: () => setState(() => count++),
          child: Text('bump ${widget.label}'),
        ),
        if (widget.label == 'week')
          TextButton(
            onPressed: () => context.go('/week/detail'),
            child: const Text('deeper'),
          ),
      ],
    ),
  );
}

GoRouter _router() {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      StatefulShellRoute(
        builder: (context, state, shell) => AnsiTabShell(shell: shell),
        navigatorContainerBuilder: crossFadeBranchContainer,
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const _CounterPage('lib')),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/week',
                builder: (_, _) => const _CounterPage('week'),
                // The app has no route inside a branch today (pushed pages are
                // top-level, D2-a). One here gives the re-tap rule something to
                // return from.
                routes: [
                  GoRoute(
                    path: 'detail',
                    builder: (_, _) =>
                        const FScaffold(child: Text('week detail')),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/cook',
                builder: (_, _) => const _CounterPage('cook'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/shop',
                builder: (_, _) => const _CounterPage('shop'),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  return router;
}

Future<void> _pump(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => FTheme(data: ansiThemeData(), child: child!),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapTab(WidgetTester tester, IconData icon) async {
  await tester.tap(find.byIcon(icon));
  await tester.pumpAndSettle();
}

/// Records the platform calls Flutter makes to leave the app, so "back exits"
/// can be asserted rather than inferred.
List<String> _recordSystemNavigation(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') calls.add(call.method);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

void main() {
  group('back (D3-b)', () {
    testWidgets('on a non-Library tab, back goes to the Library tab', (
      tester,
    ) async {
      final router = _router();
      final exits = _recordSystemNavigation(tester);
      await _pump(tester, router);

      await _tapTab(tester, FLucideIcons.shoppingBasket);
      expect(router.state.uri.toString(), '/shop');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/');
      expect(find.text('lib 0'), findsOneWidget);
      // The pop was SPENT on coming home — it must not also leave the app.
      expect(exits, isEmpty);
    });

    testWidgets('on the Library tab, back leaves the app', (tester) async {
      final router = _router();
      final exits = _recordSystemNavigation(tester);
      await _pump(tester, router);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/');
      expect(exits, ['SystemNavigator.pop']);
    });

    testWidgets('two backs leave from any tab, never more', (tester) async {
      final router = _router();
      final exits = _recordSystemNavigation(tester);
      await _pump(tester, router);

      // A tour of the tabs: the rule is one step home, not a history unwind.
      await _tapTab(tester, FLucideIcons.calendarDays);
      await _tapTab(tester, FLucideIcons.cookingPot);
      await _tapTab(tester, FLucideIcons.shoppingBasket);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), '/');
      expect(exits, isEmpty);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(exits, ['SystemNavigator.pop']);
    });
  });

  group('the bar', () {
    testWidgets('re-tapping the selected tab returns it to its root', (
      tester,
    ) async {
      final router = _router();
      await _pump(tester, router);

      await _tapTab(tester, FLucideIcons.calendarDays);
      await tester.tap(find.text('deeper'));
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), '/week/detail');

      await _tapTab(tester, FLucideIcons.calendarDays);

      expect(router.state.uri.toString(), '/week');
      expect(find.text('week detail'), findsNothing);
    });

    testWidgets('tapping a different tab switches without resetting it', (
      tester,
    ) async {
      final router = _router();
      await _pump(tester, router);

      await _tapTab(tester, FLucideIcons.calendarDays);
      await tester.tap(find.text('deeper'));
      await tester.pumpAndSettle();

      await _tapTab(tester, FLucideIcons.library);
      await _tapTab(tester, FLucideIcons.calendarDays);

      // Coming back restores where the branch was, rather than its root.
      expect(router.state.uri.toString(), '/week/detail');
    });
  });

  group('the tabs you are not looking at', () {
    testWidgets('are offstage — out of the visible tree, still mounted', (
      tester,
    ) async {
      final router = _router();
      await _pump(tester, router);

      // Visit the Week once so its branch is materialised — go_router only
      // builds a branch that has been reached.
      await _tapTab(tester, FLucideIcons.calendarDays);
      expect(find.text('week 0'), findsOneWidget);
      expect(find.text('lib 0'), findsNothing);

      await _tapTab(tester, FLucideIcons.library);
      // Back on the Library, the Week answers for nothing: a default finder
      // skips offstage subtrees, which is what keeps a test (and a hit test,
      // and a screen reader) scoped to the tab on screen.
      expect(find.text('lib 0'), findsOneWidget);
      expect(find.text('week 0'), findsNothing);
      // Mounted all the same — the same finder allowing offstage sees it.
      expect(find.text('week 0', skipOffstage: false), findsOneWidget);
    });

    testWidgets('both branches stay on stage while the fade runs', (
      tester,
    ) async {
      final router = _router();
      await _pump(tester, router);

      await tester.tap(find.byIcon(FLucideIcons.calendarDays));
      await tester.pump();
      await tester.pump(kTabFade ~/ 2);

      // Mid cross-fade there is no "the" tab: the outgoing one is still
      // painting, at a lower opacity.
      expect(find.text('lib 0'), findsOneWidget);
      expect(find.text('week 0'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('lib 0'), findsNothing);
    });
  });

  group('state (D7)', () {
    testWidgets('a tab keeps its state across a switch', (tester) async {
      final router = _router();
      await _pump(tester, router);

      await _tapTab(tester, FLucideIcons.calendarDays);
      await tester.tap(find.text('bump week'));
      await tester.tap(find.text('bump week'));
      await tester.pumpAndSettle();
      expect(find.text('week 2'), findsOneWidget);

      await _tapTab(tester, FLucideIcons.cookingPot);
      await _tapTab(tester, FLucideIcons.calendarDays);

      expect(find.text('week 2'), findsOneWidget);
    });
  });
}
