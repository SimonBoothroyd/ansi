/// The modal contract (`lib/shared/ansi_modals.dart`): every sheet and dialog
/// opens above the tab shell rather than inside a branch, a sheet on a phone is
/// a dialog from medium up with the same return value, and the structural rule
/// that keeps Forui's branch-local defaults from creeping back into the views.
library;

import 'dart:io';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/shared/ansi_modals.dart';
import 'package:ansi/shared/ansi_sheet_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../helpers/source_scan.dart';

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

/// Sets the window the test runs in. `setSurfaceSize` does not move
/// `MediaQuery.sizeOf`, which is the only thing the layout file reads, so the
/// view's own physical size is what decides a band here.
void _window(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const _phone = Size(390, 844);
const _desk = Size(1440, 900);

void main() {
  group('showAnsiSheet', () {
    testWidgets('on a phone it is a sheet, above the shell and not in the '
        'branch', (tester) async {
      _window(tester, _phone);
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

    testWidgets('from medium up the same call is a dialog, and the caller '
        'reads the same value back', (tester) async {
      _window(tester, _desk);
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

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Presented as a dialog rather than risen from the bottom edge — and
      // still a route above the branch, so the bar is not tappable beside it.
      expect(find.byType(FDialog), findsOneWidget);
      expect(_branchNavigator(tester).canPop(), isFalse);
      expect(find.text('done'), findsOneWidget);

      // The contract every one of the call sites stands on: the same builder,
      // the same pop, the same value.
      await tester.tap(find.text('done'));
      await tester.pumpAndSettle();
      expect(popped, 'ok');
      expect(find.text('done'), findsNothing);
    });

    testWidgets('a short sheet is a dialog sized to its content; a tall one is '
        'a fixed pane', (tester) async {
      _window(tester, _desk);
      final app = _shellApp(
        open: (context) async => showAnsiSheet<void>(
          context: context,
          builder: (_) => const AnsiSheetShell(
            title: 'Add to plan',
            children: [SizedBox(height: 80)],
          ),
        ),
      );
      await tester.pumpWidget(_host(app.router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final short = tester.getSize(find.byType(AnsiSheetShell));
      expect(short.width, kAnsiDialogWidth);
      expect(short.height, lessThan(kAnsiDialogHeight));

      // The bottom pad answers a keyboard and a home indicator, and a centred
      // dialog has neither.
      final pad = tester
          .widgetList<Padding>(
            find.descendant(
              of: find.byType(AnsiSheetShell),
              matching: find.byType(Padding),
            ),
          )
          .map((p) => p.padding.resolve(TextDirection.ltr))
          // The shell's own pad is the one holding its 20 of side padding.
          .firstWhere((e) => e.left == 20);
      expect(pad.bottom, 20);

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // A sheet that asks for a share of the SCREEN's height is asking to be a
      // pane rather than a card: on wide that is the dialog's own height, so a
      // long list scrolls inside it instead of pushing the search field off the
      // top.
      final tall = _shellApp(
        open: (context) async => showAnsiSheet<void>(
          context: context,
          builder: (_) => const AnsiSheetShell(
            title: 'Add an ingredient',
            heightFactor: 0.86,
            children: [Expanded(child: SizedBox())],
          ),
        ),
      );
      await tester.pumpWidget(_host(tall.router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(AnsiSheetShell)),
        const Size(kAnsiDialogWidth, kAnsiDialogHeight),
      );
    });

    testWidgets('Esc dismisses the dialog form, and the caller reads the '
        'dismissal', (tester) async {
      _window(tester, _desk);
      var answered = true;
      final app = _shellApp(
        open: (context) async {
          final result = await showAnsiSheet<String>(
            context: context,
            builder: (_) => const AnsiSheetShell(
              title: 'Unit',
              children: [SizedBox(height: 40)],
            ),
          );
          answered = result != null;
        },
      );
      await tester.pumpWidget(_host(app.router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Unit'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Unit'), findsNothing);
      expect(answered, isFalse, reason: 'a dismissal is not an answer');
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

    test('modals go through showAnsiSheet/showAnsiDialog', () {
      final files = dartFiles(
        Directory('lib'),
      ).where((f) => f.path != wrapper).toList();
      expect(files, isNotEmpty, reason: 'no lib sources found — broken glob?');

      final violations = <String>[];
      var wrapped = 0;

      for (final file in files) {
        final source = blankNonCode(file.readAsStringSync());
        wrapped += RegExp(
          r'\bshowAnsi(Sheet|Dialog)\s*(<[^(]*>)?\s*\(',
        ).allMatches(source).length;
        for (final m in bare.allMatches(source)) {
          final line = lineOf(source, m.start);
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

    test('the wrapper still pins the navigator on every form', () {
      final source = File(wrapper).readAsStringSync();
      // Three Forui calls — the sheet, the sheet-as-dialog, and the dialog —
      // and not one of them may take the caller's own navigator: under the tab
      // shell that is the BRANCH, whose bounds the barrier would stop at.
      expect(
        RegExp(
          r'show F(Sheet|Dialog)<T>\('.replaceAll(' ', ''),
        ).allMatches(source).length,
        3,
      );
      expect(
        RegExp(r'context:\s*host\.context').allMatches(source).length,
        3,
        reason:
            '$wrapper must hand every Forui call the shell navigator through '
            '_modalHost — that is the whole point of the wrapper',
      );
      expect(
        RegExp(r'useRootNavigator:\s*host\.root').allMatches(source).length,
        3,
        reason:
            'the root is the fallback for a tree with no shell navigator (a '
            'gate, a test), and it has to be asked for by name',
      );
    });
  });
}
