/// The tap-guard contract (`lib/shared/guarded_navigation.dart`) and the
/// structural rule that keeps the unguarded forms from creeping back into the
/// views.
library;

import 'dart:io';

import 'package:ansi/shared/guarded_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A three-route app that hands the most recently built page's [BuildContext]
/// back to the test, so a call can be made exactly where a widget would make
/// it — from the page the user is looking at.
({GoRouter router, BuildContext Function() top}) _app() {
  late BuildContext top;
  Widget page(BuildContext context, String label) {
    top = context;
    return Scaffold(body: Text(label));
  }

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (c, _) => page(c, 'home')),
      GoRoute(
        path: '/recipes/:id',
        builder: (c, s) => page(c, 'recipe ${s.pathParameters['id']}'),
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
    const exceptions = <String, String>{
      'lib/features/import/presentation/import_view.dart':
          'the ImportCommitted hop is a ref.listen reaction, not a tap',
      'lib/features/recipes/presentation/recipe_view.dart':
          'returns to the library after the recipe is deleted',
      'lib/features/recipes/presentation/recipe_editor_view.dart':
          'post-save navigation to the recipe just written',
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

      final bare = RegExp(r'\bcontext\.(push|go|pushNamed|goNamed)\s*\(');
      final violations = <String>[];
      var guardedCalls = 0;

      for (final file in files) {
        final source = stripComments(file.readAsStringSync());
        guardedCalls += RegExp(
          r'\bcontext\.(pushOnce|goOnce)\s*\(',
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
            r'\bcontext\.(push|go)\s*\(',
          ).hasMatch(stripComments(file.readAsStringSync())),
          isTrue,
          reason: '$path no longer navigates bare ($why) — drop the exception',
        );
      }
    });
  });
}
