/// The wide chrome (`lib/shared/ansi_wide_shell.dart`,
/// `lib/shared/ansi_side_nav.dart`): the sidebar beside the content, the icon
/// rail under 1280, nothing lit on a pushed page — and the back rules, asserted
/// again from inside the outer shell that now wraps the whole app.
library;

import 'dart:io';

import 'package:ansi/core/router/app_router.dart';
import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/shared/ansi_bottom_nav.dart';
import 'package:ansi/shared/ansi_layout.dart';
import 'package:ansi/shared/ansi_modals.dart';
import 'package:ansi/shared/ansi_side_nav.dart';
import 'package:ansi/shared/ansi_tab_shell.dart';
import 'package:ansi/shared/ansi_wide_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../helpers/source_scan.dart';

/// The app's real route shape: one outer `ShellRoute` (whose builder draws the
/// chrome) around the tab shell AND the pushed pages. Only the screens are
/// stand-ins.
GoRouter _router() {
  Widget tab(String label) =>
      FScaffold(resizeToAvoidBottomInset: false, child: Text(label));

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        navigatorKey: ansiShellNavigatorKey,
        builder: (context, state, child) => AnsiWideShell(child: child),
        routes: [
          StatefulShellRoute(
            builder: (context, state, shell) => AnsiTabShell(shell: shell),
            navigatorContainerBuilder: crossFadeBranchContainer,
            branches: [
              for (final (path, label) in const [
                ('/', 'library screen'),
                ('/week', 'week screen'),
                ('/cook', 'cook screen'),
                ('/shop', 'shop screen'),
              ])
                StatefulShellBranch(
                  routes: [GoRoute(path: path, builder: (_, _) => tab(label))],
                ),
            ],
          ),
          GoRoute(
            path: '/recipes/:id',
            builder: (context, state) => FScaffold(
              header: FHeader.nested(
                title: const Text('a recipe'),
                prefixes: [FHeaderAction.back(onPress: () => context.pop())],
              ),
              child: const Text('recipe screen'),
            ),
          ),
          GoRoute(
            path: '/account',
            builder: (_, _) => const FScaffold(child: Text('account screen')),
          ),
          GoRoute(
            path: '/ingredients/new',
            builder: (context, state) => FScaffold(
              child: TextButton(
                onPressed: () => context.pop('made'),
                child: const Text('the form'),
              ),
            ),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  return router;
}

const _phone = Size(390, 844);
const _iPad = Size(1100, 834);
const _desk = Size(1440, 900);

Future<void> _pump(WidgetTester tester, GoRouter router, Size window) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    // The shell hosts the sync banner, which reads a provider.
    ProviderScope(
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

/// The sidebar's items, in the order they are drawn.
List<FSidebarItem> _items(WidgetTester tester) =>
    tester.widgetList<FSidebarItem>(find.byType(FSidebarItem)).toList();

String? _labelOf(FSidebarItem item) => (item.label as Text?)?.data;

/// Which destination is lit, by label, or null for the neutral form.
String? _litLabel(WidgetTester tester) {
  final lit = _items(tester).where((i) => i.selected);
  return lit.isEmpty ? null : _labelOf(lit.single);
}

/// Records the platform calls Flutter makes to leave the app, so "back exits"
/// is asserted rather than inferred.
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
  group('the form the chrome takes', () {
    testWidgets('a phone keeps the bar, and the outer shell draws nothing', (
      tester,
    ) async {
      await _pump(tester, _router(), _phone);

      expect(find.byType(AnsiBottomNav), findsOneWidget);
      expect(find.byType(AnsiSideNav), findsNothing);
    });

    testWidgets('a desk window gets the sidebar instead of the bar, with the '
        'four destinations, Account, and the branch lit', (tester) async {
      await _pump(tester, _router(), _desk);

      expect(find.byType(AnsiBottomNav), findsNothing);
      expect(find.byType(AnsiSideNav), findsOneWidget);
      // The loop, in the bar's order, and the household door after it.
      expect(_items(tester).map(_labelOf).toList(), [
        'Library',
        'Week',
        'Cook',
        'Shop',
        'Account',
      ]);
      expect(_litLabel(tester), 'Library');
      expect(find.text('Ansi.'), findsOneWidget, reason: 'the wordmark');

      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      expect(find.text('week screen'), findsOneWidget);
      expect(_litLabel(tester), 'Week');
    });

    testWidgets('1024–1279 is the icon rail: no labels, a tooltip each, 64 '
        'wide', (tester) async {
      await _pump(tester, _router(), _iPad);

      expect(find.byType(AnsiSideNav), findsOneWidget);
      expect(_items(tester).map(_labelOf), everyElement(isNull));
      expect(find.text('Library'), findsNothing);
      expect(tester.getSize(find.byType(FSidebar)).width, kAnsiRailWidth);
      // Five tooltips: the four destinations and the footer door.
      expect(find.byType(FTooltip), findsNWidgets(5));
    });

    testWidgets('the content pane is what the page is measured in', (
      tester,
    ) async {
      await _pump(tester, _router(), _desk);

      // The sidebar takes its width off the left of the window; what is left is
      // the pane the page sits in.
      final pane = tester.getSize(find.byType(AnsiTabShell)).width;
      expect(pane, _desk.width - kAnsiSidebarWidth);
    });
  });

  group('a pushed page', () {
    testWidgets('keeps the chrome and lights nothing, then back returns the '
        'lit destination', (tester) async {
      final router = _router();
      await _pump(tester, router, _desk);
      router.go('/week');
      await tester.pumpAndSettle();

      router.push('/recipes/7');
      await tester.pumpAndSettle();

      // One sidebar, still there, with nothing lit — and the page's own back
      // control in its header.
      expect(find.byType(AnsiSideNav), findsOneWidget);
      expect(_litLabel(tester), isNull);
      expect(find.text('recipe screen'), findsOneWidget);
      expect(find.byType(FHeaderAction), findsOneWidget);

      await tester.tap(find.byType(FHeaderAction));
      await tester.pumpAndSettle();
      expect(find.text('week screen'), findsOneWidget);
      expect(_litLabel(tester), 'Week');
    });

    testWidgets('the browser Back does what the control does', (tester) async {
      final router = _router();
      await _pump(tester, router, _desk);
      router.push('/recipes/7');
      await tester.pumpAndSettle();
      expect(_litLabel(tester), isNull);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('library screen'), findsOneWidget);
      expect(_litLabel(tester), 'Library');
    });

    testWidgets('a destination leaves the pushed page behind', (tester) async {
      final router = _router();
      await _pump(tester, router, _desk);
      router.push('/recipes/7');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();

      expect(find.text('recipe screen'), findsNothing);
      expect(find.text('shop screen'), findsOneWidget);
      expect(router.canPop(), isFalse);
    });

    testWidgets('Account is a door like any other, and the only one on wide', (
      tester,
    ) async {
      final router = _router();
      await _pump(tester, router, _desk);

      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();

      expect(find.text('account screen'), findsOneWidget);
      expect(_litLabel(tester), isNull);
    });
  });

  group('the back rules hold under the outer shell', () {
    testWidgets('on a non-Library tab, back goes to the Library tab', (
      tester,
    ) async {
      final router = _router();
      final exits = _recordSystemNavigation(tester);
      await _pump(tester, router, _desk);
      router.go('/shop');
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/');
      expect(exits, isEmpty, reason: 'the pop was spent on coming home');
    });

    testWidgets('on the Library tab, back leaves the app', (tester) async {
      final router = _router();
      final exits = _recordSystemNavigation(tester);
      await _pump(tester, router, _desk);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(exits, ['SystemNavigator.pop']);
    });

    testWidgets('a cold deep link to a pushed page has nothing behind it', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/recipes/7',
        routes: [
          ShellRoute(
            navigatorKey: ansiShellNavigatorKey,
            builder: (context, state, child) => AnsiWideShell(child: child),
            routes: [
              GoRoute(
                path: '/recipes/:id',
                builder: (_, _) =>
                    const FScaffold(child: Text('recipe screen')),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await _pump(tester, router, _desk);

      // The header's `canPop() ? pop() : go('/')` fallback is doing real work
      // here, and it can only know that if canPop says no.
      expect(router.canPop(), isFalse);
    });
  });

  group('a modal', () {
    testWidgets('opens above the pages, and a page pushed from inside it lands '
        'ON it', (tester) async {
      // The add-new chain: a picker creates a row, pushes the flesh-out form
      // over its own surface, waits for back, and only then resolves. It works
      // only while the modal and the pushed page share a navigator — which is
      // why modals open on the shell navigator and not on the root above it.
      final router = _router();
      await _pump(tester, router, _desk);
      final host = ansiShellNavigatorKey.currentState!.overlay!.context;

      final picked = showAnsiSheet<String>(
        context: host,
        builder: (sheetContext) => TextButton(
          onPressed: () async {
            final made = await sheetContext.push<String>('/ingredients/new');
            Navigator.of(sheetContext).pop(made);
          },
          child: const Text('add new'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('add new'), findsOneWidget);

      await tester.tap(find.text('add new'));
      await tester.pumpAndSettle();
      // The form covers the picker: it is what the user sees and can tap.
      expect(find.text('the form'), findsOneWidget);
      expect(find.text('add new'), findsNothing);

      await tester.tap(find.text('the form'));
      await tester.pumpAndSettle();
      expect(await picked, 'made');
    });
  });

  group('structural', () {
    /// Every route pushed over the shell, and the view that draws it. On wide
    /// the chrome beside a pushed page is neutral, so the page's own header is
    /// the only way back — and each of these already draws one.
    const pushedViews = [
      'lib/features/import/presentation/import_view.dart',
      'lib/features/account/presentation/account_view.dart',
      'lib/features/ingredients/presentation/ingredient_list_view.dart',
      'lib/features/ingredients/presentation/ingredient_detail_view.dart',
      'lib/features/recipes/presentation/recipe_editor_view.dart',
      'lib/features/recipes/presentation/recipe_view.dart',
      'lib/features/planning/presentation/week_variant_editor.dart',
    ];

    test('every pushed page draws its own back control', () {
      final missing = <String>[];
      for (final path in pushedViews) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path moved or was renamed');
        if (!blankNonCode(
          file.readAsStringSync(),
        ).contains('FHeaderAction.back(')) {
          missing.add(path);
        }
      }

      expect(
        missing,
        isEmpty,
        reason:
            'a pushed page is the only thing that can offer its own way back: '
            'the bar is gone on a phone and the sidebar is neutral on wide, so '
            'a page with no back control in its header is a page with no exit '
            'but the browser:\n${missing.join('\n')}',
      );
    });
  });
}
