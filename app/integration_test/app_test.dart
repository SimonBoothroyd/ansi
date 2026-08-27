/// End-to-end smoke on a real device/simulator: the whole app over a real
/// PowerSync database, driven through the UI.
///
/// Repository tests cover the SQL; this covers the wiring the host VM can't —
/// the on-device extension, the router, and the provider lifecycle across the
/// async mutation gaps that crashed the Library in step 3. Local gate only
/// (`make test-sim`), never CI.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mise/app.dart';
import 'package:mise/core/sync/database.dart';
import 'package:mise/core/sync/schema.dart';
import 'package:mise/features/books/data/book_repository_impl.dart';
import 'package:powersync/powersync.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late PowerSyncDatabase db;
  late Directory dir;

  /// Opening a Forui dialog while the accessibility tree is live trips a
  /// semantics assertion inside the framework — it reproduces in a plain widget
  /// test with `ensureSemantics()`, and forui is already pinned at the newest
  /// 0.22.x (tech-debt tracker, 2026-08-27). Drop only that assertion; every
  /// other error still fails the test.
  void ignoreForuiSemanticsAssertion() {
    final reportError = FlutterError.onError!;
    FlutterError.onError = (details) {
      if ('${details.exception}'.contains('semantics.dart')) return;
      reportError(details);
    };
    addTearDown(() => FlutterError.onError = reportError);
  }

  setUp(() async {
    // A throwaway database rather than the app's own file, so a rerun starts
    // from the same empty Library every time.
    dir = Directory.systemTemp.createTempSync('mise_smoke');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/smoke.db');
    await db.initialize();
    await SqliteBookRepository(db).ensureDefaultBook();
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  testWidgets('files a new recipe under a new section', (tester) async {
    ignoreForuiSemanticsAssertion();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MiseApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Our Cookbook'), findsOneWidget);

    await tester.tap(find.textContaining('new section'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, 'Weeknight');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Weeknight'), findsOneWidget);

    await tester.tap(find.byIcon(FLucideIcons.plus));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New recipe'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText).first, 'Chicken Curry');
    await tester.pumpAndSettle();

    // The filing picker starts on the book's Unsectioned bucket; open it and
    // pick the section created above.
    await tester.tap(find.text('Unsectioned'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weeknight').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('OUR COOKBOOK · WEEKNIGHT'), findsOneWidget);
    expect(find.text('Chicken Curry'), findsOneWidget);
  });
}
