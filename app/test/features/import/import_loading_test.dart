/// The reading screen while `import-recipe` is in flight: a vertical checklist
/// of the stages the SERVER said it would walk, each row carrying the time it
/// really took.
///
/// A photo import is two model calls and can run well past a minute. What makes
/// this screen honest rather than merely reassuring is that it claims nothing
/// the server has not said — so these tests drive it through a repository that
/// reports stages exactly as the stream does, and pump time to watch the
/// running row tick.
// The pumped scope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'dart:async';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/import/data/import_providers.dart';
import 'package:ansi/features/import/domain/commit_payload.dart';
import 'package:ansi/features/import/domain/import_repository.dart';
import 'package:ansi/features/import/domain/import_stage.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/import/presentation/import_view.dart';
import 'package:ansi/features/import/presentation/import_view_models.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_book_repository.dart';
import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/forui_semantics.dart';

/// An edge function that never finishes — the state under test is the wait —
/// but whose progress callback the test drives by hand, the way the stream
/// would.
class _NarratingImportRepo implements ImportRepository {
  void Function(ImportProgress)? _sink;

  /// Reports [progress] the way an arriving SSE frame does.
  void say(ImportProgress progress) => _sink?.call(progress);

  @override
  Future<ReconciliationPayload> startImport(
    ImportSource source, {
    void Function(ImportProgress)? onProgress,
  }) {
    _sink = onProgress;
    return Completer<ReconciliationPayload>().future;
  }

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

class _Running {
  _Running(this.repo, this.tester);

  final _NarratingImportRepo repo;
  final WidgetTester tester;

  Future<void> say(ImportProgress progress) async {
    repo.say(progress);
    await tester.pump();
  }
}

/// Pumps the import screen with an import already running, and hands back the
/// handle plus a teardown that unmounts it — the screen holds a periodic timer,
/// so the tree has to come down inside the test body.
Future<(_Running, Future<void> Function())> _importing(
  WidgetTester tester,
  ImportSource source,
) async {
  final repo = _NarratingImportRepo();
  final container = ProviderContainer(
    overrides: [
      importRepositoryProvider.overrideWithValue(repo),
      bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
      ingredientRepositoryProvider.overrideWithValue(
        const ReadOnlyIngredientRepo(),
      ),
      measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
    ],
  );
  await tester.pumpWidget(_host(container));
  unawaited(
    container.read(importControllerProvider.notifier).startImport(source),
  );
  await tester.pump();
  return (
    _Running(repo, tester),
    () async {
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );
}

const _photoPlan = ImportPlanned([
  ImportStage.received,
  ImportStage.transcribed,
  ImportStage.sanitised,
  ImportStage.matched,
]);

void main() {
  testWidgets('before the server has said anything, the screen claims no '
      'stages at all', (tester) async {
    filterForuiSemanticsAssertions();
    final (_, done) = await _importing(tester, const ImportFromPhotos(['/a']));

    // No checklist invented ahead of the plan — just that something was sent.
    expect(find.text('Sending…'), findsOneWidget);
    expect(find.text('Photos read'), findsNothing);

    await done();
  });

  testWidgets('the plan draws every stage at once: done, running, pending', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    final (run, done) = await _importing(
      tester,
      const ImportFromPhotos(['/a']),
    );
    await run.say(_photoPlan);

    // All four rows are there from the moment the plan lands, so the wait has
    // a visible shape rather than one sentence at a time. The running row is
    // the only one in the present tense; the rest are the plan, still to come.
    expect(find.text('Receiving the photos…'), findsOneWidget);
    expect(find.text('Photos read'), findsOneWidget);
    expect(find.text('Recipe written out'), findsOneWidget);
    expect(find.text('Ingredients matched'), findsOneWidget);
    expect(find.text('Photos received'), findsNothing);
    // Nothing finished yet: only the running row shows a clock.
    expect(find.text('0:00'), findsOneWidget);

    await done();
  });

  testWidgets('a finished stage freezes at the time the SERVER reported, and '
      'the running one ticks', (tester) async {
    filterForuiSemanticsAssertions();
    final (run, done) = await _importing(
      tester,
      const ImportFromPhotos(['/a']),
    );
    await run.say(_photoPlan);
    await run.say(
      const ImportStageDone(ImportStage.received, Duration(seconds: 3)),
    );
    // The upload took three seconds and says so — the client's own clock has
    // barely moved, and the server's number is the one that is true.
    expect(find.text('0:03'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    // The received row is frozen; the transcribe row is counting.
    expect(find.text('0:03'), findsOneWidget);
    expect(find.text('0:05'), findsOneWidget);

    await run.say(
      const ImportStageDone(ImportStage.transcribed, Duration(seconds: 25)),
    );
    // 25s cumulative minus the 3s `received` ended at: the row owns 22s.
    expect(find.text('0:22'), findsOneWidget);
    // …and the next row starts from zero rather than from the total.
    expect(find.text('0:00'), findsOneWidget);

    await done();
  });

  testWidgets('a link import is told a different plan, and never shows a '
      'transcribe row it does not have', (tester) async {
    filterForuiSemanticsAssertions();
    final (run, done) = await _importing(
      tester,
      const ImportFromUrl('https://x/y'),
    );
    await run.say(
      const ImportPlanned([
        ImportStage.received,
        ImportStage.fetched,
        ImportStage.sanitised,
        ImportStage.matched,
      ]),
    );

    expect(find.text('Receiving the request…'), findsOneWidget);
    expect(find.text('Page fetched'), findsOneWidget);
    expect(find.text('Photos read'), findsNothing);
    expect(find.text('Receiving the photos…'), findsNothing);

    await done();
  });

  testWidgets('a stage id this build does not know is ignored, not drawn as a '
      'blank row', (tester) async {
    filterForuiSemanticsAssertions();
    final (run, done) = await _importing(
      tester,
      const ImportFromPhotos(['/a']),
    );
    // The plan itself is filtered in the repository; what the screen must
    // survive is a plan shorter than the pipeline it is narrating.
    await run.say(const ImportPlanned([ImportStage.received]));
    expect(find.text('Receiving the photos…'), findsOneWidget);
    expect(find.text('Ingredients matched'), findsNothing);

    await done();
  });

  testWidgets('the running row says what is happening, and flips to the past '
      'tense the moment the server says it finished', (tester) async {
    filterForuiSemanticsAssertions();
    final (run, done) = await _importing(
      tester,
      const ImportFromPhotos(['/a']),
    );
    await run.say(_photoPlan);

    // Two rows, two tenses: the upload is under way and the transcription has
    // not started, so only one of them may speak in the present.
    expect(find.text('Receiving the photos…'), findsOneWidget);
    expect(find.text('Reading the photos…'), findsNothing);

    await run.say(
      const ImportStageDone(ImportStage.received, Duration(seconds: 3)),
    );

    // The claim arrives with the event that earns it, never before.
    expect(find.text('Photos received'), findsOneWidget);
    expect(find.text('Receiving the photos…'), findsNothing);
    expect(find.text('Reading the photos…'), findsOneWidget);
    expect(find.text('Photos read'), findsNothing);

    await done();
  });

  testWidgets('the running marker spins in place — the spinner is as big as '
      'its own glyph, never squeezed into a smaller box', (tester) async {
    filterForuiSemanticsAssertions();
    final (run, done) = await _importing(
      tester,
      const ImportFromPhotos(['/a']),
    );
    await run.say(_photoPlan);

    // The spinner is a `Transform.rotate` about its centre over an icon glyph.
    // A box tighter than the glyph shrinks the BOX, not the ink: the pivot
    // then sits off the glyph's own centre and the marker turns like a cam.
    // So the marker's box has to be the size the glyph is actually drawn at —
    // which is the icon theme the spinner's own variant resolved.
    final spinner = find.byType(FCircularProgress);
    expect(spinner, findsOneWidget);
    final glyph = tester.widget<IconTheme>(
      find.descendant(of: spinner, matching: find.byType(IconTheme)).first,
    );
    final box = tester.getRect(spinner);
    expect(box.width, glyph.data.size);
    expect(box.height, glyph.data.size);
    // …and the gutter it sits in is still wide enough to hold it.
    expect(box.width, lessThanOrEqualTo(22));

    await done();
  });
}
