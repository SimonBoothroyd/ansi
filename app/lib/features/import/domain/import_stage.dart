/// The stages the import screen shows while `import-recipe` runs. Pure Dart.
///
/// The call answers as a `text/event-stream` and names each stage as it
/// completes, so nothing is estimated: the list comes from the server's first
/// event and every finished row carries the server's elapsed time. The ids are
/// the wire contract (`supabase/functions/import-recipe/index.ts`); the wording
/// lives here.
library;

import 'package:meta/meta.dart';

/// One stage of a server pipeline that narrates itself. [ImportStage] is the
/// recipe pipeline's; `features/receipts` has its own for `import-receipt`. The
/// checklist arithmetic below is shared.
abstract interface class PipelineStage {
  /// The id the server sends. Never shown.
  String get id;

  /// What the checklist row reads, in the tense the row is in.
  String label({required bool fromPhotos, required StageStatus status});
}

/// One stage of the server pipeline, as named on the wire. Each carries its
/// wording in both tenses: what is happening while it runs, and what happened
/// once done.
enum ImportStage implements PipelineStage {
  /// The request — for photos, however many megabytes of it — is in hand.
  received(
    'received',
    running: 'Receiving the photos…',
    done: 'Photos received',
    urlRunning: 'Receiving the request…',
    urlDone: 'Request received',
  ),

  /// The page was fetched and its recipe markup or text pulled out.
  fetched('fetched', running: 'Fetching the page…', done: 'Page fetched'),

  /// The vision tier read the pages into text (photos only).
  transcribed(
    'transcribed',
    running: 'Reading the photos…',
    done: 'Photos read',
  ),

  /// The model turned that into a structured recipe.
  sanitised(
    'sanitised',
    running: 'Writing the recipe out…',
    done: 'Recipe written out',
  ),

  /// Every line was matched against the household's ingredients.
  matched(
    'matched',
    running: 'Matching ingredients…',
    done: 'Ingredients matched',
  );

  /// Only `received` words the link and photo doors differently (a link uploads
  /// nothing). Other stages leave the `url…` pair off.
  const ImportStage(
    this.id, {
    required String running,
    required String done,
    String? urlRunning,
    String? urlDone,
  }) : _running = running,
       _done = done,
       _urlRunning = urlRunning ?? running,
       _urlDone = urlDone ?? done;

  /// The id the server sends. Never shown.
  @override
  final String id;

  final String _running;
  final String _done;
  final String _urlRunning;
  final String _urlDone;

  /// What the checklist row reads, in the row's tense: a running stage says
  /// what is happening (with an ellipsis), a finished one what happened. A
  /// pending row borrows the finished wording, drawn muted.
  @override
  String label({required bool fromPhotos, required StageStatus status}) =>
      switch ((status, fromPhotos)) {
        (StageStatus.active, true) => _running,
        (StageStatus.active, false) => _urlRunning,
        (_, true) => _done,
        (_, false) => _urlDone,
      };

  /// The stage with this wire [id], or null for one this build does not know.
  static ImportStage? byId(String id) {
    for (final stage in ImportStage.values) {
      if (stage.id == id) return stage;
    }
    return null;
  }
}

/// How far along one row of the checklist is.
enum StageStatus {
  /// Finished — [StageProgress.elapsed] is how long it took.
  done,

  /// Running now — [StageProgress.elapsed] is ticking.
  active,

  /// Not started; nothing to show but its name.
  pending,
}

/// One row of the reading screen's checklist.
@immutable
class StageProgress {
  const StageProgress({
    required this.stage,
    required this.status,
    required this.elapsed,
  });

  final PipelineStage stage;
  final StageStatus status;

  /// How long this stage took (`done`), or has been running (`active`). Null
  /// while `pending` — a stage that has not started has no honest duration.
  final Duration? elapsed;

  @override
  bool operator ==(Object other) =>
      other is StageProgress &&
      other.stage == stage &&
      other.status == status &&
      other.elapsed == elapsed;

  @override
  int get hashCode => Object.hash(stage, status, elapsed);

  @override
  String toString() => 'StageProgress(${stage.id}, $status, $elapsed)';
}

/// The checklist as the screen draws it, from what the server has said so far
/// plus the clock.
///
/// [plan] is the server's stage list, in order. [finished] maps each completed
/// stage to the server's elapsed time since the request arrived, so a stage's
/// duration is the difference between consecutive entries, and the running
/// stage's is [elapsed] (the client's clock) minus the last finished one. When
/// every planned stage is done the last row stays `done`.
List<StageProgress> stageChecklist({
  required List<PipelineStage> plan,
  required Map<PipelineStage, Duration> finished,
  required Duration elapsed,
}) {
  final rows = <StageProgress>[];
  var previousEnd = Duration.zero;
  var reachedRunning = false;
  for (final stage in plan) {
    final end = finished[stage];
    if (end != null) {
      rows.add(
        StageProgress(
          stage: stage,
          status: StageStatus.done,
          // Never negative: a clock that jumped backwards must not print a
          // negative duration at somebody mid-import.
          elapsed: end < previousEnd ? Duration.zero : end - previousEnd,
        ),
      );
      previousEnd = end;
      continue;
    }
    if (!reachedRunning) {
      reachedRunning = true;
      rows.add(
        StageProgress(
          stage: stage,
          status: StageStatus.active,
          elapsed: elapsed < previousEnd
              ? Duration.zero
              : elapsed - previousEnd,
        ),
      );
      continue;
    }
    rows.add(
      StageProgress(stage: stage, status: StageStatus.pending, elapsed: null),
    );
  }
  return rows;
}

/// `m:ss`, as a stage row prints it. Minutes are not zero-padded and run past
/// 59 as a total.
String formatStageDuration(Duration d) {
  final seconds = d.inSeconds;
  final minutes = seconds ~/ 60;
  return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
}
