// The app's toasts swipe away sideways as well as down: Forui alone lets a
// bottom-centre toast go only downward, which a thumb flicking it sideways
// never finds.
import 'package:ansi/shared/ansi_toast.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../helpers/pump_app.dart';

void main() {
  Future<void> showUndo(WidgetTester tester, {VoidCallback? onUndo}) async {
    await tester.pumpAnsiApp(
      Builder(
        builder: (context) => Center(
          child: FButton(
            onPress: () => showAnsiUndoToast(
              context,
              what: 'Removed salt.',
              onUndo: onUndo ?? () {},
            ),
            child: const Text('Go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(find.text('Removed salt.'), findsOneWidget);
  }

  for (final (name, offset) in [
    ('left', const Offset(-300, 0)),
    ('right', const Offset(300, 0)),
    ('down', const Offset(0, 120)),
  ]) {
    testWidgets('a toast swipes away $name', (tester) async {
      await showUndo(tester);
      await tester.drag(find.text('Removed salt.'), offset);
      await tester.pumpAndSettle();
      expect(find.text('Removed salt.'), findsNothing);
    });
  }

  testWidgets('a nudge sideways leaves the toast', (tester) async {
    await showUndo(tester);
    await tester.drag(find.text('Removed salt.'), const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(find.text('Removed salt.'), findsOneWidget);
  });

  testWidgets('an Undo stays about ten seconds', (tester) async {
    await showUndo(tester);
    await tester.pump(const Duration(seconds: 9));
    expect(find.text('Removed salt.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Removed salt.'), findsNothing);
  });

  testWidgets('a tap anywhere on the toast never lands on what is under '
      'it', (tester) async {
    var under = 0;
    await tester.pumpAnsiApp(
      Builder(
        builder: (context) => Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => under++,
              ),
            ),
            Center(
              child: FButton(
                onPress: () => showAnsiUndoToast(
                  context,
                  what: 'Removed salt.',
                  onUndo: () {},
                ),
                child: const Text('Go'),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    final toast = tester.getRect(find.byType(FToast));
    for (final at in [
      tester.getCenter(find.text('Removed salt.')),
      // Its padding, either side of the words and the button.
      toast.centerLeft + const Offset(3, 0),
      toast.topCenter + const Offset(0, 3),
      toast.bottomCenter - const Offset(0, 3),
    ]) {
      await tester.tapAt(at);
      await tester.pump();
    }
    expect(under, 0);
    expect(find.text('Removed salt.'), findsOneWidget);
  });

  testWidgets('a newer Undo replaces the one on screen: no older toast '
      'peeks above it, painted but deaf to a tap', (tester) async {
    var n = 0;
    await tester.pumpAnsiApp(
      Builder(
        builder: (context) => Center(
          child: FButton(
            onPress: () => showAnsiUndoToast(
              context,
              what: 'Removed ${++n}.',
              onUndo: () {},
            ),
            child: const Text('Go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(find.text('Removed 1.'), findsNothing);
    expect(find.text('Removed 2.'), findsOneWidget);
    expect(find.byType(FToast), findsOneWidget);
  });

  testWidgets('Undo still taps through the swipe', (tester) async {
    var undone = 0;
    await showUndo(tester, onUndo: () => undone++);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(find.text('Removed salt.'), findsNothing);
  });
}
