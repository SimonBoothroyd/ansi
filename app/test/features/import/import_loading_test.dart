/// The loading screen while the one `import-recipe` call is in flight: one
/// spinner, and a sentence that MOVES.
///
/// The call runs several server stages behind a single non-streaming POST, and
/// a photo import can spend well over a minute in it. A frozen "Reading the
/// recipe…" through all of that reads as a hang, so the screen climbs the
/// ladder in `domain/import_stage.dart` — which is why these tests pump time
/// rather than settle.
// The pumped scope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'dart:async';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/import/data/import_providers.dart';
import 'package:ansi/features/import/domain/commit_payload.dart';
import 'package:ansi/features/import/domain/import_repository.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/import/presentation/import_view.dart';
import 'package:ansi/features/import/presentation/import_view_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_book_repository.dart';
import '../../helpers/forui_semantics.dart';

/// An edge function that never answers — the state under test is the wait.
class _HangingImportRepo implements ImportRepository {
  @override
  Future<ReconciliationPayload> startImport(ImportSource source) =>
      Completer<ReconciliationPayload>().future;

  @override
  Future<String> commit(CommitPayload payload) async => 'recipe-1';
}

Widget _host(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: ansiHostTheme(),
    home: FTheme(
      data: ansiThemeData(),
      child: const FToaster(child: ImportView()),
    ),
  ),
);

/// Pumps the import screen with a hung import already running, and hands back
/// a teardown that unmounts it — the ladder holds a periodic timer, so the
/// tree has to come down inside the test body.
Future<Future<void> Function()> _importing(
  WidgetTester tester,
  ImportSource source,
) async {
  final container = ProviderContainer(
    overrides: [
      importRepositoryProvider.overrideWithValue(_HangingImportRepo()),
      bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
    ],
  );
  await tester.pumpWidget(_host(container));
  unawaited(
    container.read(importControllerProvider.notifier).startImport(source),
  );
  await tester.pump();
  return () async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  };
}

void main() {
  testWidgets('a link import climbs fetch → read → still reading → match', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    final done = await _importing(tester, const ImportFromUrl('https://x/y'));

    expect(find.text('Fetching the page…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Reading the recipe…'), findsOneWidget);
    expect(find.text('Fetching the page…'), findsNothing);
    await tester.pump(const Duration(seconds: 20));
    expect(find.textContaining('Still reading'), findsOneWidget);
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Matching the ingredients…'), findsOneWidget);

    await done();
  });

  testWidgets('a photo import names the vision pass first — it is the stage a '
      'link import does not have', (tester) async {
    filterForuiSemanticsAssertions();
    final done = await _importing(tester, const ImportFromPhotos(['/tmp/a']));

    expect(find.text('Sending the photos…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Reading the photos…'), findsOneWidget);
    // Past the point a link import would already have given up on: the photo
    // path is two model calls, and the ladder keeps moving through both.
    await tester.pump(const Duration(seconds: 60));
    expect(find.text('Writing out the recipe…'), findsOneWidget);

    await done();
  });
}
