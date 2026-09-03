/// Sim smoke — AUTH: the sign-in gate → /connecting → the Library with the
/// synced household. Local gate only (`make test-sim FILE=auth`), never CI.
/// Needs the local backend running (`make db-up`) and the usual
/// `--dart-define`s (the Makefile passes them from `.env.local`).
///
/// This is the ONE file that drives the gate: it starts its stack signed out
/// and types the provisioned credentials into the real form. Every other
/// file signs in programmatically in `setUpAll` (see `support/stack.dart`).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/drive.dart';
import 'support/stack.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SmokeStack stack;

  setUpAll(() async => stack = await SmokeStack.start(signIn: false));
  tearDownAll(() => stack.dispose());

  testWidgets('auth: signs in and reaches the synced Library', (tester) async {
    ignoreForuiSemanticsAssertion();
    final db = stack.db;
    await stack.pumpApp(tester);

    // Signed out → the router holds everything behind /sign-in.
    await pumpUntilFound(tester, find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, stack.email);
    await tester.enterText(find.byType(EditableText).at(1), smokePassword);
    await tester.pump();
    await tester.tap(find.text('Sign in'));

    // /connecting runs onboarding + first sync; then the Library with the
    // default book the session controller ensures.
    await pumpUntilFound(
      tester,
      find.text('Our Cookbook'),
      timeout: const Duration(seconds: 90),
    );

    // The synced household reached the local database: both members and the
    // cloned ingredient vocab (reachable-through-the-picker is the editor
    // file's business).
    final members = await db.getAll(
      'SELECT display_name FROM household_member ORDER BY sort_order',
    );
    expect(members.map((r) => r['display_name']).toList(), ['Ada', 'Jun']);
    final vocab = await db.get('SELECT COUNT(*) AS c FROM ingredient');
    expect(vocab['c'] as int, greaterThan(100));
    // …and the starter measures cloned with it (step 7.6): "clove (3 g)" on
    // Garlic is what the editor file picks in the quantity sheet.
    final measures = await db.get(
      'SELECT COUNT(*) AS c FROM ingredient_measure',
    );
    expect(measures['c'] as int, greaterThan(10));
  });
}
