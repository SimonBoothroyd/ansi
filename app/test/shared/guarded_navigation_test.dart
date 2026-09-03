/// The tap-guard contract (`lib/shared/guarded_navigation.dart`) and the
/// structural rule that keeps the unguarded forms from creeping back into the
/// views.
library;

import 'dart:io';

import 'package:ansi/shared/ansi_modals.dart';
import 'package:ansi/shared/guarded_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A three-route app that hands the most recently built page's [BuildContext]
/// back to the test, so a call can be made exactly where a widget would make
/// it — from the page the user is looking at.
///
/// The recipe page pops itself with its id when tapped, so a returning push
/// has something to hand back.
({GoRouter router, BuildContext Function() top}) _app() {
  late BuildContext top;
  Widget page(BuildContext context, String label, {String? pops}) {
    top = context;
    return Scaffold(
      body: pops == null
          ? Text(label)
          : TextButton(onPressed: () => context.pop(pops), child: Text(label)),
    );
  }

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (c, _) => page(c, 'home')),
      GoRoute(
        path: '/recipes/:id',
        builder: (c, s) => page(
          c,
          'recipe ${s.pathParameters['id']}',
          pops: s.pathParameters['id'],
        ),
      ),
      GoRoute(path: '/week', builder: (c, _) => page(c, 'week')),
    ],
  );
  addTearDown(router.dispose);
  return (router: router, top: () => top);
}

/// How many pages the router is holding. The initial location counts as one.
int _stackDepth(GoRouter router) =>
    router.routerDelegate.currentConfiguration.matches.length;

void main() {
  group('pushOnce', () {
    testWidgets('pushes when the target is somewhere else', (tester) async {
      final app = _app();
      await tester.pumpWidget(MaterialApp.router(routerConfig: app.router));
      await tester.pumpAndSettle();

      app.top().pushOnce('/recipes/r1');
      await tester.pumpAndSettle();

      expect(app.router.state.uri.toString(), '/recipes/r1');
      expect(_stackDepth(app.router), 2);
      expect(find.text('recipe r1'), findsOneWidget);
    });

    testWidgets('two taps in the same frame open one page', (tester) async {
      final app = _app();
      await tester.pumpWidget(MaterialApp.router(routerConfig: app.router));
      await tester.pumpAndSettle();

      // The double-tap the owner hit: both calls land before a frame is drawn.
      app.top()
        ..pushOnce('/recipes/r1')
        ..pushOnce('/recipes/r1');
      await tester.pumpAndSettle();

      expect(_stackDepth(app.router), 2);
      expect(find.text('recipe r1'), findsOneWidget);
    });

    testWidgets('a different target is never swallowed', (tester) async {
      final app = _app();
      await tester.pumpWidget(MaterialApp.router(routerConfig: app.router));
      await tester.pumpAndSettle();

      app.top()
        ..pushOnce('/recipes/r1')
        ..pushOnce('/recipes/r2');
      await tester.pumpAndSettle();

      expect(_stackDepth(app.router), 3);
      expect(app.router.state.uri.toString(), '/recipes/r2');
    });
  });

  group('pushOnceFor', () {
    testWidgets('resolves with what the pushed page pops', (tester) async {
      final app = _app();
      await tester.pumpWidget(MaterialApp.router(routerConfig: app.router));
      await tester.pumpAndSettle();

      final result = app.top().pushOnceFor<String>('/recipes/r1');
      await tester.pumpAndSettle();
      expect(find.text('recipe r1'), findsOneWidget);

      await tester.tap(find.text('recipe r1'));
      await tester.pumpAndSettle();
      expect(await result, 'r1');
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('the second of two taps pushes nothing and resolves null at '
        'once — the first is the one awaiting the real pop', (tester) async {
      final app = _app();
      await tester.pumpWidget(MaterialApp.router(routerConfig: app.router));
      await tester.pumpAndSettle();

      final first = app.top().pushOnceFor<String>('/recipes/r1');
      final second = app.top().pushOnceFor<String>('/recipes/r1');
      expect(await second, isNull);
      await tester.pumpAndSettle();
      expect(_stackDepth(app.router), 2);

      await tester.tap(find.text('recipe r1'));
      await tester.pumpAndSettle();
      expect(await first, 'r1');
    });

    testWidgets('from inside a root-navigator sheet, the page lands ABOVE the '
        'sheet and pops back to it, still open', (tester) async {
      // The add-new chain stands on this (plan 0025 D3): a picker sheet
      // pushes the flesh-out form, waits for back, and resolves afterwards —
      // which only works if the sheet is what the form returns to. go_router
      // keeps a pageless route above the page it was pushed over and inserts
      // a new page on top of both; this pins that the shape holds.
      late BuildContext inSheet;
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (c, _) => Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(
                  onPressed: () => showAnsiSheet<void>(
                    context: ctx,
                    builder: (sheetContext) {
                      inSheet = sheetContext;
                      return const SizedBox(height: 120, child: Text('sheet'));
                    },
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/form',
            builder: (c, _) => Scaffold(
              body: TextButton(
                onPressed: () => c.pop('done'),
                child: const Text('form'),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('sheet'), findsOneWidget);

      final result = inSheet.pushOnceFor<String>('/form');
      await tester.pumpAndSettle();
      // The form covers the sheet: it is what the user sees and can tap.
      expect(find.text('form'), findsOneWidget);
      expect(find.text('sheet'), findsNothing);

      await tester.tap(find.text('form'));
      await tester.pumpAndSettle();
      expect(await result, 'done');
      // And the sheet is exactly where it was left.
      expect(find.text('sheet'), findsOneWidget);
      expect(router.state.uri.toString(), '/');
    });
  });

  group('goOnce', () {
    testWidgets('replaces the stack, then no-ops on a repeat', (tester) async {
      final app = _app();
      await tester.pumpWidget(MaterialApp.router(routerConfig: app.router));
      await tester.pumpAndSettle();

      app.top().goOnce('/week');
      await tester.pumpAndSettle();
      expect(app.router.state.uri.toString(), '/week');
      expect(_stackDepth(app.router), 1);

      app.top().goOnce('/week');
      await tester.pumpAndSettle();
      expect(_stackDepth(app.router), 1);
      expect(app.router.state.uri.toString(), '/week');
    });
  });

  group('structural', () {
    // The views are the tap sites; a bare push/go there is the double-open bug.
    // Everything else in `lib` (the router config, controllers) is unaffected.
    const scannedRoots = ['lib/shared', 'lib/features'];

    /// Navigations that are NOT tap-driven, where the guard would only add
    /// noise: each fires from a state change or a completed write, and the
    /// location it lands on is never the one already on top.
    ///
    /// All three are the post-action landings from the board's back table. Two
    /// of them replace within the stack so the page below survives; the third
    /// is the one place a stack-flattening `go` is the right answer.
    const exceptions = <String, String>{
      'lib/features/import/presentation/import_view.dart':
          'the ImportCommitted hop is a ref.listen reaction, not a tap; it '
          'replaces the spent import flow with the new recipe',
      'lib/features/recipes/presentation/recipe_view.dart':
          'returns to the Library branch after the recipe is deleted — the '
          'shell is the bottom of the root stack, so `go` lands on it',
      'lib/features/recipes/presentation/recipe_editor_view.dart':
          'the NEW-recipe landing only: Save replaces the editor with the '
          'recipe just created so back returns to where the editor was '
          'opened from; saving an existing recipe pops back onto its page',
    };

    /// Line comments blanked, so a doc comment naming `context.push(` cannot
    /// trip the check. A `//` inside a string literal would truncate the rest
    /// of that line — that can only hide a call, never invent one.
    String stripComments(String source) => source
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i < 0 ? l : l.substring(0, i);
        })
        .join('\n');

    test('views navigate through the tap guard, not bare context.push/go', () {
      final files = [
        for (final root in scannedRoots)
          ...Directory(root)
              .listSync(recursive: true)
              .whereType<File>()
              .where(
                (f) =>
                    f.path.endsWith('.dart') &&
                    !f.path.endsWith('.g.dart') &&
                    !f.path.endsWith('.freezed.dart') &&
                    (f.path.startsWith('lib/shared/') ||
                        f.path.contains('/presentation/')),
              ),
      ]..sort((a, b) => a.path.compareTo(b.path));
      expect(files, isNotEmpty, reason: 'no view sources found — broken glob?');

      // Every unguarded form, replacements included — a tap target can be hit
      // twice whether the call pushes or replaces.
      final bare = RegExp(
        r'\bcontext\.(push|go|replace)(Replacement)?(Named)?\s*\(',
      );
      final violations = <String>[];
      var guardedCalls = 0;

      for (final file in files) {
        final source = stripComments(file.readAsStringSync());
        guardedCalls += RegExp(
          r'\bcontext\.(pushOnce(For)?(<[^>]*>)?|goOnce)\s*\(',
        ).allMatches(source).length;
        if (exceptions.containsKey(file.path)) continue;
        for (final m in bare.allMatches(source)) {
          final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
          violations.add('${file.path}:$line — ${m.group(0)}');
        }
      }

      expect(
        guardedCalls,
        greaterThan(0),
        reason: 'found no pushOnce/goOnce calls — has the helper been renamed?',
      );
      expect(
        violations,
        isEmpty,
        reason:
            'a view navigates with a bare context.push/go. On a phone the tap '
            'target gets hit twice and the page opens twice — use '
            'context.pushOnce/goOnce (lib/shared/guarded_navigation.dart), or '
            "add the file to this test's `exceptions` with a reason:\n"
            '${violations.join('\n')}',
      );
    });

    test('every listed exception still exists and still navigates', () {
      for (final MapEntry(key: path, value: why) in exceptions.entries) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path is gone — drop it');
        expect(
          RegExp(
            r'\bcontext\.(push|go|replace)(Replacement)?(Named)?\s*\(',
          ).hasMatch(stripComments(file.readAsStringSync())),
          isTrue,
          reason: '$path no longer navigates bare ($why) — drop the exception',
        );
      }
    });
  });
}
