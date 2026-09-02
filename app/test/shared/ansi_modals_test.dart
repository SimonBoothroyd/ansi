/// The modal contract (`lib/shared/ansi_modals.dart`): every sheet and dialog
/// opens on the ROOT navigator, above the tab shell — and the structural rule
/// that keeps Forui's branch-local defaults from creeping back into the views.
library;

import 'dart:io';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/shared/ansi_modals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

/// A two-branch shell whose branch pages open a modal, mirroring the app's own
/// shape: a `StatefulShellRoute` with a footer that must end up OUTSIDE the
/// modal's barrier.
({GoRouter router, GlobalKey<NavigatorState> root}) _shellApp({
  required Future<void> Function(BuildContext) open,
}) {
  final root = GlobalKey<NavigatorState>(debugLabel: 'root');
  Widget page(String label, BuildContext context) => Scaffold(
    body: Column(
      children: [
        Text(label),
        TextButton(onPressed: () => open(context), child: const Text('open')),
      ],
    ),
  );

  final router = GoRouter(
    navigatorKey: root,
    initialLocation: '/',
    routes: [
      StatefulShellRoute(
        builder: (context, state, shell) => Column(
          children: [
            Expanded(child: shell),
            const Text('nav bar'),
          ],
        ),
        navigatorContainerBuilder: (context, shell, children) =>
            IndexedStack(index: shell.currentIndex, children: children),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/', builder: (c, _) => page('home', c))],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/week', builder: (c, _) => page('week', c)),
            ],
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  return (router: router, root: root);
}

Widget _host(GoRouter router) => FTheme(
  data: ansiThemeData(),
  child: MaterialApp.router(routerConfig: router),
);

/// The branch Navigator the tapped page lives in — the one Forui would have
/// used by default, and the one the modal must NOT be pushed onto.
NavigatorState _branchNavigator(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator).last);

void main() {
  group('showAnsiSheet', () {
    testWidgets('opens on the root navigator, not the branch', (tester) async {
      String? popped;
      final app = _shellApp(
        open: (context) async => popped = await showAnsiSheet<String>(
          context: context,
          builder: (sheetContext) => TextButton(
            onPressed: () => Navigator.of(sheetContext).pop('ok'),
            child: const Text('done'),
          ),
        ),
      );
      await tester.pumpWidget(_host(app.router));
      await tester.pumpAndSettle();
      expect(app.root.currentState!.canPop(), isFalse);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The sheet is a route of the ROOT navigator: that is what puts its
      // barrier over the nav bar instead of beside it.
      expect(app.root.currentState!.canPop(), isTrue);
      expect(_branchNavigator(tester).canPop(), isFalse);
      expect(find.text('done'), findsOneWidget);

      // And `Navigator.of(context)` from inside still pops the SHEET, with its
      // result — not the branch page underneath.
      await tester.tap(find.text('done'));
      await tester.pumpAndSettle();
      expect(popped, 'ok');
      expect(app.root.currentState!.canPop(), isFalse);
      expect(find.text('home'), findsOneWidget);
      expect(find.text('nav bar'), findsOneWidget);
    });
  });

  group('showAnsiDialog', () {
    testWidgets('opens on the root navigator, not the branch', (tester) async {
      bool? popped;
      final app = _shellApp(
        open: (context) async => popped = await showAnsiDialog<bool>(
          context: context,
          builder: (dialogContext, style, animation) => FDialog(
            animation: animation,
            title: const Text('Delete?'),
            actions: [
              FButton(
                onPress: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(_host(app.router));
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(app.root.currentState!.canPop(), isTrue);
      expect(_branchNavigator(tester).canPop(), isFalse);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(popped, isTrue);
      expect(app.root.currentState!.canPop(), isFalse);
      expect(find.text('home'), findsOneWidget);
    });
  });

  group('structural', () {
    /// The only file allowed to call Forui's own modal functions.
    const wrapper = 'lib/shared/ansi_modals.dart';

    /// `showFSheet<Foo>(`, `showFDialog(`, `showFPersistentSheet<Bar>(` —
    /// the type argument is optional and may itself be nested (`Set<String>`),
    /// so it is matched as a balanced-enough run of non-paren characters.
    final bare = RegExp(
      r'\bshowF(Sheet|Dialog|PersistentSheet)\s*(<[^(]*>)?\s*\(',
    );

    /// Line comments blanked, so the wrapper's own prose and a doc comment
    /// naming `showFSheet(` cannot trip the check. A `//` inside a string
    /// truncates that line — which can hide a call, never invent one.
    String stripComments(String source) => source
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i < 0 ? l : l.substring(0, i);
        })
        .join('\n');

    test('modals go through showAnsiSheet/showAnsiDialog', () {
      final files =
          Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where(
                (f) =>
                    f.path.endsWith('.dart') &&
                    !f.path.endsWith('.g.dart') &&
                    !f.path.endsWith('.freezed.dart') &&
                    f.path != wrapper,
              )
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(files, isNotEmpty, reason: 'no lib sources found — broken glob?');

      final violations = <String>[];
      var wrapped = 0;

      for (final file in files) {
        final source = stripComments(file.readAsStringSync());
        wrapped += RegExp(
          r'\bshowAnsi(Sheet|Dialog)\s*(<[^(]*>)?\s*\(',
        ).allMatches(source).length;
        for (final m in bare.allMatches(source)) {
          final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
          violations.add('${file.path}:$line — ${m.group(0)}');
        }
      }

      expect(
        wrapped,
        greaterThan(0),
        reason: 'found no showAnsiSheet/showAnsiDialog calls — renamed?',
      );
      expect(
        violations,
        isEmpty,
        reason:
            "a modal is opened with Forui's own function, which defaults to "
            'useRootNavigator: false. Under the tab shell that pushes it into '
            'the BRANCH navigator, so its barrier stops at the branch bounds '
            'and the bottom nav bar stays tappable beside it. Use '
            'showAnsiSheet/showAnsiDialog ($wrapper):\n'
            '${violations.join('\n')}',
      );
    });

    test('the wrapper still sets useRootNavigator on both forms', () {
      final source = File(wrapper).readAsStringSync();
      expect(
        RegExp(r'useRootNavigator:\s*true').allMatches(source).length,
        2,
        reason:
            '$wrapper must pass useRootNavigator: true for sheet AND '
            'dialog — that is the whole point of the wrapper',
      );
    });
  });
}
