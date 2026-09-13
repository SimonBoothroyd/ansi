/// `ansiBack` (`lib/shared/ansi_back.dart`) — what the chevron on a pushed page
/// does, for both arrivals a pushed page has.
///
/// The bug this was written for: on a 1440 window the wide sidebar's Account
/// footer door used `go`, which replaces the whole match list instead of
/// stacking a page on it. `/account` was then the only page on the shell
/// navigator, `canPop()` was false, and the page's bare `context.pop()` threw
/// `GoError('There is nothing to pop')` inside a pointer handler — reported to
/// `FlutterError.onError` and swallowed. The chevron did nothing, and on the
/// web there is no system back gesture behind it.
///
/// Three claims, in three groups: the door pushes; every pushed route's chevron
/// lands somewhere real from a push AND from a cold deep link; and no view pops
/// on its own again.
library;

import 'dart:async';
import 'dart:io';

import 'package:ansi/core/router/app_router.dart';
import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/shared/ansi_back.dart';
import 'package:ansi/shared/ansi_bottom_nav.dart';
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

/// One pushed page: the route as the router declares it, a location that opens
/// it, and the `home:` its real view hands [ansiBack].
typedef Pushed = ({String path, String open, String home, String view});

/// Every page pushed over the tab shell, with the home its view states.
///
/// The `home` column is the same literal the view passes — it is repeated here
/// on purpose, so a change to where a page believes it belongs has to be made
/// twice and read once. The `path` column is checked against the router's own
/// source by the structural test below, so the table cannot quietly fall behind
/// a new route.
const pushedPages = <Pushed>[
  (path: '/account', open: '/account', home: '/', view: 'account_view.dart'),
  (path: '/import', open: '/import', home: '/', view: 'import_view.dart'),
  (
    path: '/books/:id',
    open: '/books/b2',
    home: '/',
    view: 'book_page_view.dart',
  ),
  (
    path: '/ingredients',
    open: '/ingredients',
    home: '/',
    view: 'ingredient_list_view.dart',
  ),
  (
    path: '/ingredients/new',
    open: '/ingredients/new',
    home: '/ingredients',
    view: 'ingredient_detail_view.dart',
  ),
  // The reading posture at expanded IS the manager's two panes
  // (`_IngredientPage`), so the page drawing the chevron there is the list, and
  // its home is the Library.
  (
    path: '/ingredients/:id',
    open: '/ingredients/i7',
    home: '/',
    view: 'ingredient_list_view.dart',
  ),
  // The editing posture is the row's own form at every width: a row is a detail
  // OF the vocabulary, so it goes back to the manager.
  (
    path: '/ingredients/:id',
    open: '/ingredients/i7?edit=1',
    home: '/ingredients',
    view: 'ingredient_detail_view.dart',
  ),
  (
    path: '/recipes/new',
    open: '/recipes/new',
    home: '/',
    view: 'recipe_editor_view.dart',
  ),
  (
    path: '/recipes/:id',
    open: '/recipes/9',
    home: '/',
    view: 'recipe_view.dart',
  ),
  // The one page that knows its referring tab: `?week=` says this recipe is
  // being read as the week plans it.
  (
    path: '/recipes/:id',
    open: '/recipes/9?week=2026-09-14',
    home: '/week',
    view: 'recipe_view.dart',
  ),
  (
    path: '/recipes/:id/edit',
    open: '/recipes/9/edit',
    home: '/recipes/9',
    view: 'recipe_editor_view.dart',
  ),
  (
    path: '/recipes/:id/edit',
    open: '/recipes/9/edit?week=2026-09-14',
    home: '/recipes/9?week=2026-09-14',
    view: 'week_variant_editor.dart',
  ),
];

/// The app's real route shape — one outer `ShellRoute` whose builder draws the
/// wide chrome, around the tab shell AND the pushed pages — with the real
/// [AnsiWideShell], the real [AnsiSideNav] and the real [ansiBack]. Only the
/// screens' bodies are stand-ins: what is under test is the stack, the door and
/// the chevron, none of which a screen's content takes part in.
GoRouter _router(String initial) {
  Widget tab(String label) =>
      FScaffold(resizeToAvoidBottomInset: false, child: Text(label));

  final declared = <String>{};
  final router = GoRouter(
    initialLocation: initial,
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
          // One route per declared path; the query variants share it, exactly
          // as they do in the real router, and the page reads its own home off
          // the location the way the real views read their parameters.
          for (final page in pushedPages)
            if (declared.add(page.path))
              GoRoute(
                path: page.path,
                builder: (context, state) =>
                    _PushedPage(location: state.uri.toString()),
              ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  return router;
}

/// A stand-in pushed page: a header with the one real back control.
class _PushedPage extends StatelessWidget {
  const _PushedPage({required this.location});

  final String location;

  String get _home {
    final row = pushedPages.where((p) => p.open == location);
    if (row.isEmpty) throw StateError('no table row opens $location');
    return row.first.home;
  }

  @override
  Widget build(BuildContext context) => FScaffold(
    header: FHeader.nested(
      title: Text('page $location'),
      prefixes: [
        FHeaderAction.back(onPress: () => ansiBack(context, home: _home)),
      ],
    ),
    child: Text('body $location'),
  );
}

const _phone = Size(390, 844);
const _desk = Size(1440, 900);

Future<void> _pump(WidgetTester tester, GoRouter router, Size window) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
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

/// Taps the page's own back chevron.
Future<void> _tapBack(WidgetTester tester) async {
  await tester.tap(find.byType(FHeaderAction).first);
  await tester.pumpAndSettle();
}

/// Records the platform calls Flutter makes to leave the app, so a chevron that
/// silently exits instead of going home is caught rather than missed.
List<String> _recordExits(WidgetTester tester) {
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
  group("the wide sidebar's Account door", () {
    testWidgets('pushes, so the page it opens has something under it', (
      tester,
    ) async {
      final router = _router('/week');
      await _pump(tester, router, _desk);

      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();

      expect(find.text('body /account'), findsOneWidget);
      expect(
        router.canPop(),
        isTrue,
        reason:
            'a `go` here left the page alone on the stack, and its chevron '
            'threw GoError into a pointer handler — silently',
      );
      // The chrome stays, and goes neutral: nothing in the loop is where you
      // are.
      expect(find.byType(AnsiSideNav), findsOneWidget);
    });

    testWidgets('and its back returns the tab you were on', (tester) async {
      final router = _router('/cook');
      final exits = _recordExits(tester);
      await _pump(tester, router, _desk);

      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      await _tapBack(tester);

      expect(find.text('cook screen'), findsOneWidget);
      expect(router.state.uri.toString(), '/cook');
      expect(exits, isEmpty);
    });

    testWidgets("the browser's Back does what the chevron does", (
      tester,
    ) async {
      final router = _router('/shop');
      await _pump(tester, router, _desk);
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();

      // A platform pop — what the browser's Back arrives as.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('shop screen'), findsOneWidget);
      expect(router.state.uri.toString(), '/shop');
    });

    testWidgets('the four destinations still replace, so nothing stacks up', (
      tester,
    ) async {
      final router = _router('/');
      await _pump(tester, router, _desk);

      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cook'));
      await tester.pumpAndSettle();

      expect(find.text('cook screen'), findsOneWidget);
      expect(
        router.canPop(),
        isFalse,
        reason:
            'a destination is where you are, not a page over where you '
            'were — only Account is a page',
      );
    });
  });

  group('every pushed route, pushed over the shell', () {
    for (final page in pushedPages) {
      testWidgets('${page.open} pops back to what opened it', (tester) async {
        final router = _router('/');
        await _pump(tester, router, _desk);
        unawaited(router.push(page.open));
        await tester.pumpAndSettle();
        expect(find.text('body ${page.open}'), findsOneWidget);

        await _tapBack(tester);

        expect(
          router.state.uri.toString(),
          '/',
          reason: 'the Library was under it',
        );
        expect(find.text('library screen'), findsOneWidget);
      });
    }
  });

  group('every pushed route, opened cold', () {
    for (final page in pushedPages) {
      testWidgets('${page.open} goes home to ${page.home}', (tester) async {
        final router = _router(page.open);
        final exits = _recordExits(tester);
        await _pump(tester, router, _desk);
        expect(find.text('body ${page.open}'), findsOneWidget);
        expect(router.canPop(), isFalse, reason: 'nothing is under it');

        await _tapBack(tester);

        expect(router.state.uri.toString(), page.home);
        expect(exits, isEmpty, reason: 'a chevron is not a way out of the app');
      });
    }
  });

  group('the helper itself', () {
    testWidgets('carries a pop result, and drops it when it goes home', (
      tester,
    ) async {
      // The add-new chain: `/ingredients/new` pops with the row it made, and
      // the picker that pushed it is waiting for exactly that.
      final router = _router('/');
      await _pump(tester, router, _desk);

      final pushed = router.push<String>('/ingredients/new');
      await tester.pumpAndSettle();
      final page = tester.element(find.text('body /ingredients/new'));
      ansiBack(page, home: '/ingredients', result: 'the new row');
      await tester.pumpAndSettle();

      expect(await pushed, 'the new row');

      // Cold, there is nobody waiting: the result goes nowhere and the page
      // lands on its home rather than throwing.
      final cold = _router('/ingredients/new');
      await _pump(tester, cold, _desk);
      ansiBack(
        tester.element(find.text('body /ingredients/new')),
        home: '/ingredients',
        result: 'dropped',
      );
      await tester.pumpAndSettle();
      expect(cold.state.uri.toString(), '/ingredients');
    });

    testWidgets('a chevron hit twice is harmless', (tester) async {
      // Two taps in ONE frame, with no pump between them: the first falls back
      // to home, and the second is dropped by `goOnce` rather than navigating
      // again or throwing.
      final router = _router('/account');
      await _pump(tester, router, _desk);

      final chevron = find.byType(FHeaderAction).first;
      await tester.tap(chevron, warnIfMissed: false);
      await tester.tap(chevron, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/');
    });

    testWidgets('the phone is unaffected: the same two answers, no sidebar', (
      tester,
    ) async {
      final router = _router('/');
      await _pump(tester, router, _phone);
      expect(find.byType(AnsiBottomNav), findsOneWidget);
      expect(find.byType(AnsiSideNav), findsNothing);

      // Pushed: pops.
      unawaited(router.push('/account'));
      await tester.pumpAndSettle();
      await _tapBack(tester);
      expect(find.text('library screen'), findsOneWidget);

      // Cold: goes home. The helper reads the stack, never the width.
      final cold = _router('/ingredients/i7?edit=1');
      await _pump(tester, cold, _phone);
      await _tapBack(tester);
      expect(cold.state.uri.toString(), '/ingredients');
    });
  });

  group('structural', () {
    /// Every pushed route the router declares, read off its own source: the
    /// `_page` calls that sit BELOW the tab shell's `StatefulShellRoute`. The
    /// two gates are `_page` calls too, and they sit above it.
    List<String> declaredPushedPaths() {
      final source = blankComments(
        File('lib/core/router/app_router.dart').readAsStringSync(),
      );
      final shell = source.indexOf('StatefulShellRoute');
      expect(shell, isNot(-1), reason: 'the tab shell moved or was renamed');
      return [
        for (final m in RegExp(r"_page\(\s*path: '([^']+)'").allMatches(source))
          if (m.start > shell) m.group(1)!,
      ];
    }

    test('the table above names every pushed route, and no others', () {
      expect(
        pushedPages.map((p) => p.path).toSet(),
        declaredPushedPaths().toSet(),
        reason:
            'a pushed page with no row here is a chevron nobody has checked '
            'for the empty-stack case — add it to `pushedPages` with the home '
            'its view states',
      );
    });

    test('no view pops the router on its own — every back goes through the '
        'helper', () {
      final files = [
        for (final root in const ['lib/shared', 'lib/features'])
          ...dartFiles(Directory(root)).where(
            (f) =>
                f.path.startsWith('lib/shared/') ||
                f.path.contains('/presentation/'),
          ),
      ]..sort((a, b) => a.path.compareTo(b.path));
      expect(files, isNotEmpty, reason: 'no view sources found — broken glob?');

      // go_router's own pop, which is the one that throws on an empty stack.
      // `Navigator.of(context).pop()` is a different call and a correct one:
      // it dismisses the nearest MODAL, which always has the page under it.
      final bare = RegExp(r'\bcontext\.pop\s*\(');
      final violations = <String>[];
      for (final file in files) {
        if (file.path == 'lib/shared/ansi_back.dart') continue;
        final source = blankNonCode(file.readAsStringSync());
        for (final m in bare.allMatches(source)) {
          violations.add('${file.path}:${lineOf(source, m.start)}');
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'context.pop() throws GoError when nothing is under the page, and '
            'inside a pointer handler that is swallowed: the control does '
            'nothing at all. A pushed page arrives with an empty stack from a '
            'cold deep link and from any `go` that reached it. Use '
            'ansiBack(context, home: …) (lib/shared/ansi_back.dart):\n'
            '${violations.join('\n')}',
      );
    });

    test('every pushed view draws its back through the helper', () {
      final missing = <String>[];
      for (final view in pushedPages.map((p) => p.view).toSet()) {
        final matches = dartFiles(
          Directory('lib/features'),
        ).where((f) => f.path.endsWith('/$view')).toList();
        expect(matches, hasLength(1), reason: '$view moved or was renamed');
        final source = blankNonCode(matches.single.readAsStringSync());
        if (!source.contains('ansiBack(')) missing.add(matches.single.path);
      }

      expect(
        missing,
        isEmpty,
        reason:
            'a pushed page is the only thing that can offer its own way back, '
            'and it has to answer the empty stack:\n${missing.join('\n')}',
      );
    });

    test("the wide sidebar's Account door pushes, and its destinations go", () {
      final source = blankNonCode(
        File('lib/shared/ansi_side_nav.dart').readAsStringSync(),
      );
      expect(
        source,
        contains('pushOnce(_accountRoute)'),
        reason:
            'Account is a pushed PAGE like the phone door pushes it; a `go` '
            'here replaces the stack and its chevron has nothing to pop',
      );
      expect(
        source,
        contains('goOnce(d.route)'),
        reason:
            'the four destinations are where you ARE, not pages over where '
            'you were — they must keep replacing',
      );
    });
  });
}
