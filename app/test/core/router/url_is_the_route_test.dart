/// **The URL is the route.** What the browser's address bar says, per
/// navigation, asserted where the app actually says it: the
/// `routeInformationUpdated` call Flutter makes on
/// `SystemChannels.navigation`. That channel message IS the address bar — the
/// engine's url strategy writes exactly what arrives here — so a test that
/// reads it is reading the bar without a browser.
///
/// The bug this was written for: the owner's screenshot showed a bare
/// `127.0.0.1:8792` while `/recipes/:id/edit` was on screen. go_router reports
/// the location of the *matched* route list and ignores anything reached
/// through `push` unless `GoRouter.optionURLReflectsImperativeAPIs` is set —
/// and every page above the four tab roots in this app is pushed. So the bar
/// kept reporting `/`, and Flutter's hash strategy omits the `#` for `/`.
/// Back and forward still worked (each push got a history entry, with the match
/// list serialised into `history.state`); a refresh, which can only read the
/// URL, did not. [ansiUrlFollowsEveryPush] is the fix, and this file is what
/// holds it.
///
/// Four claims:
/// 1. every pushed page reports its own location, path and query — driven off
///    the SAME table `ansi_back_test.dart` keeps, so a new pushed route cannot
///    land without URL coverage;
/// 2. a pop reports what it went back to, and the four destinations report
///    theirs;
/// 3. the gate carries a deep link through `?from=` and returns to it, so a
///    refresh on a pushed page lands there once the session is restored;
/// 4. the app really flips the flag, and the three week tabs really read their
///    query (structural).
library;

import 'dart:async';
import 'dart:io';

import 'package:ansi/core/router/app_router.dart';
import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/shared/ansi_back.dart';
import 'package:ansi/shared/ansi_modals.dart';
import 'package:ansi/shared/ansi_tab_shell.dart';
import 'package:ansi/shared/ansi_wide_shell.dart';
import 'package:ansi/shared/guarded_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/ansi_back_test.dart' show pushedPages;

/// The app's real route SHAPE — the outer `ShellRoute` around the tab shell and
/// the pushed pages — with stand-in bodies. What is under test is which
/// location gets reported, and no screen's content takes part in that.
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
          for (final page in pushedPages)
            if (declared.add(page.path))
              GoRoute(
                path: page.path,
                builder: (context, state) => FScaffold(
                  header: FHeader.nested(
                    title: Text('page ${state.uri}'),
                    prefixes: [
                      FHeaderAction.back(onPress: () => ansiBack(context)),
                    ],
                  ),
                  child: Text('body ${state.uri}'),
                ),
              ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  return router;
}

/// Every location Flutter has reported to the engine, newest last, each with
/// whether it asked for a new history entry (`replace: false`) or rewrote the
/// one standing (`replace: true`).
({List<String> uris, List<bool> replaced}) _bar(WidgetTester tester) {
  final uris = <String>[];
  final replaced = <bool>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.navigation,
    (call) async {
      if (call.method == 'routeInformationUpdated') {
        final args = call.arguments as Map<Object?, Object?>;
        uris.add(args['uri']! as String);
        replaced.add(args['replace']! as bool);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.navigation,
      null,
    ),
  );
  return (uris: uris, replaced: replaced);
}

Future<void> _pump(WidgetTester tester, GoRouter router) async {
  tester.view.physicalSize = const Size(1440, 900);
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

void main() {
  setUp(ansiUrlFollowsEveryPush);
  // A global, so it is put back: another test file that builds a router must
  // not inherit this one's answer.
  tearDown(() => GoRouter.optionURLReflectsImperativeAPIs = false);

  group('a pushed page reports its own location', () {
    for (final page in pushedPages) {
      testWidgets('the bar says ${page.open}', (tester) async {
        final bar = _bar(tester);
        final router = _router('/');
        await _pump(tester, router);

        unawaited(router.push(page.open));
        await tester.pumpAndSettle();

        expect(find.text('body ${page.open}'), findsOneWidget);
        expect(
          bar.uris.last,
          page.open,
          reason:
              "this is the bug: with go_router's default the bar still said "
              'the tab root the push landed on, so a refresh lost the page',
        );
      });
    }

    testWidgets('and a pop reports what it went back to', (tester) async {
      final bar = _bar(tester);
      final router = _router('/');
      await _pump(tester, router);

      unawaited(router.push('/recipes/9'));
      await tester.pumpAndSettle();
      unawaited(router.push('/recipes/9/edit?week=2026-09-14'));
      await tester.pumpAndSettle();
      expect(bar.uris.last, '/recipes/9/edit?week=2026-09-14');

      router.pop();
      await tester.pumpAndSettle();
      expect(bar.uris.last, '/recipes/9');

      router.pop();
      await tester.pumpAndSettle();
      expect(bar.uris.last, '/');
    });

    testWidgets('every push is one history entry, so back walks them', (
      tester,
    ) async {
      final bar = _bar(tester);
      final router = _router('/');
      await _pump(tester, router);

      unawaited(router.push('/books/b2'));
      await tester.pumpAndSettle();

      expect(
        bar.replaced.last,
        isFalse,
        reason:
            'a pushed page is somewhere the browser Back should return from',
      );
    });
  });

  group('restating a location leaves the page and its modals alone', () {
    testWidgets('a sheet open over a tab survives the tab renaming itself', (
      tester,
    ) async {
      // `restateOnce` goes through `replace`, which swaps a PAGE. Every sheet
      // in the app is pageless and opens on the SHELL navigator (§4), while a
      // tab root's route lives on its branch navigator — so the two do not
      // touch. Worth pinning: a week tab restates its `?week=` whenever the
      // week moves, and a sheet that vanished mid-edit because the bar updated
      // would be a bad trade for a correct URL.
      final bar = _bar(tester);
      final router = _router('/week');
      await _pump(tester, router);

      final page = tester.element(find.text('week screen'));
      unawaited(
        showAnsiSheet<void>(
          context: page,
          builder: (_) =>
              const Text('a sheet', textDirection: TextDirection.ltr),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('a sheet'), findsOneWidget);

      tester.element(find.text('week screen')).restateOnce('/week?week=x');
      await tester.pumpAndSettle();

      expect(bar.uris.last, '/week?week=x');
      expect(bar.replaced.last, isTrue);
      expect(find.text('a sheet'), findsOneWidget);
      expect(find.text('week screen'), findsOneWidget);
    });
  });

  group('the four tab roots report theirs', () {
    for (final (label, location) in const [
      ('Week', '/week'),
      ('Cook', '/cook'),
      ('Shop', '/shop'),
    ]) {
      testWidgets('$label is $location in the bar', (tester) async {
        final bar = _bar(tester);
        await _pump(tester, _router('/'));

        await tester.tap(find.text(label));
        await tester.pumpAndSettle();

        expect(bar.uris.last, location);
      });
    }
  });

  group('the gate never loses a deep link', () {
    /// The gate's answer for one location — null to let it through, or the
    /// location to redirect to.
    ///
    /// Pumped once per case so the real route table has MATCHED the location
    /// first: the gate reads `state.matchedLocation`, and that is only right
    /// when the routes it came from are the app's own shapes.
    Future<String?> ask(
      WidgetTester tester,
      String location, {
      required bool signedIn,
      required bool ready,
    }) async {
      late GoRouterState seen;
      final router = GoRouter(
        initialLocation: location,
        redirect: (context, state) {
          seen = state;
          return null;
        },
        routes: [
          for (final path in const [
            '/sign-in',
            '/connecting',
            '/',
            '/recipes/:id',
            '/recipes/:id/edit',
            '/books/:id',
            '/week',
          ])
            GoRoute(path: path, builder: (_, _) => const SizedBox()),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      return ansiGate(seen, signedIn: signedIn, ready: ready);
    }

    testWidgets('a cold deep link is carried through both gates and returned '
        'to', (tester) async {
      const deep = '/recipes/9/edit?week=2026-09-14';

      // Signed out while the session is still coming back: the gate does not
      // rewrite the location away, it carries it.
      expect(
        await ask(tester, deep, signedIn: false, ready: false),
        '/sign-in?from=%2Frecipes%2F9%2Fedit%3Fweek%3D2026-09-14',
      );
      // Signed in, still connecting: carried again, from the first gate.
      expect(
        await ask(
          tester,
          '/sign-in?from=%2Frecipes%2F9%2Fedit%3Fweek%3D2026-09-14',
          signedIn: true,
          ready: false,
        ),
        '/connecting?from=%2Frecipes%2F9%2Fedit%3Fweek%3D2026-09-14',
      );
      // Ready: back to the page that was asked for, query and all.
      expect(
        await ask(
          tester,
          '/connecting?from=%2Frecipes%2F9%2Fedit%3Fweek%3D2026-09-14',
          signedIn: true,
          ready: true,
        ),
        deep,
      );
    });

    testWidgets('a ready session at a deep link is let straight through', (
      tester,
    ) async {
      expect(
        await ask(tester, '/books/b2', signedIn: true, ready: true),
        isNull,
      );
      expect(
        await ask(tester, '/week?week=2026-09-28', signedIn: true, ready: true),
        isNull,
      );
    });

    testWidgets('nothing asked for means the Library', (tester) async {
      expect(await ask(tester, '/', signedIn: false, ready: false), '/sign-in');
      expect(
        await ask(tester, '/sign-in', signedIn: true, ready: true),
        '/',
        reason: 'no ?from= to return to',
      );
    });
  });

  group('structural', () {
    final source = File('lib/core/router/app_router.dart').readAsStringSync();

    test('the app flips the flag that makes a push show up in the URL', () {
      expect(
        source,
        contains('GoRouter.optionURLReflectsImperativeAPIs = true'),
        reason:
            'without it every pushed page reports the tab root underneath it '
            "and a browser refresh loses the page — the owner's bug",
      );
      expect(
        source.indexOf('ansiUrlFollowsEveryPush();'),
        greaterThan(source.indexOf('GoRouter router(Ref ref)')),
        reason: 'the router provider must actually call it',
      );
    });

    test('the three week tabs read the week off their own query', () {
      for (final (path, param) in const [
        ('/week', 'week'),
        ('/week', 'day'),
        ('/cook', 'week'),
        ('/shop', 'week'),
      ]) {
        final start = source.indexOf("path: '$path',");
        expect(start, isNot(-1), reason: '$path should be declared');
        final route = source.substring(
          start,
          source.indexOf('\n          ),', start),
        );
        expect(
          route,
          contains("queryParameters['$param']"),
          reason:
              '$path must read ?$param= or a refresh loses it '
              '(week_in_the_location.dart)',
        );
      }
    });
  });
}
