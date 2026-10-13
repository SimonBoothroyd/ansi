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

  testWidgets('Undo still taps through the swipe', (tester) async {
    var undone = 0;
    await showUndo(tester, onUndo: () => undone++);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(find.text('Removed salt.'), findsNothing);
  });
}
