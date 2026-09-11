/// The stages the import screen shows while `import-recipe` is running — PURE
/// DART (invariant 2).
///
/// The server runs several stages behind one call: a URL import fetches the
/// page, extracts with the model, then matches the lines; a photo import
/// transcribes the pages with the vision tier first, so it makes TWO model
/// calls before matching. The call answers as a `text/event-stream` and names
/// each stage as it completes, so **none of this is estimated**: the list comes
/// from the server's first event and every finished row carries the server's
/// own elapsed time.
///
/// The ids are the wire contract (`supabase/functions/import-recipe/index.ts`);
/// the wording is here, because copy belongs where the screen is.
library;

import 'package:meta/meta.dart';

/// One stage of the server pipeline, as named on the wire.
enum ImportStage {
  /// The request — for photos, however many megabytes of it — is in hand.
  received('received', 'Photos received', 'Request received'),

  /// The page was fetched and its recipe markup or text pulled out.
  fetched('fetched', 'Page fetched', 'Page fetched'),

  /// The vision tier read the pages into text (photos only).
  transcribed('transcribed', 'Photos read', 'Photos read'),

  /// The model turned that into a structured recipe.
  sanitised('sanitised', 'Recipe written out', 'Recipe written out'),

  /// Every line was matched against the household's ingredients.
  matched('matched', 'Ingredients matched', 'Ingredients matched');

  const ImportStage(this.id, this._photoLabel, this._urlLabel);

  /// The id the server sends. Never shown.
  final String id;

  final String _photoLabel;
  final String _urlLabel;

  /// What the checklist row reads. Only `received` differs by door — from a
  /// link there is nothing to upload, so naming photos there would be a lie.
  String label({required bool fromPhotos}) =>
      fromPhotos ? _photoLabel : _urlLabel;

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

  final ImportStage stage;
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

/// The checklist as the screen draws it, built from what the server has said so
/// far plus the clock.
///
/// [plan] is the server's stage list, in order. [finished] maps each completed
/// stage to the server's elapsed time **since the request arrived** — so a
/// stage's own duration is the difference between consecutive entries, and the
/// running stage's is [elapsed] (the client's clock) minus the last finished
/// one. Stages the server has not reached are `pending`.
///
/// When every planned stage is done the last row stays `done`: the payload is
/// already on its way and there is nothing left to tick.
List<StageProgress> stageChecklist({
  required List<ImportStage> plan,
  required Map<ImportStage, Duration> finished,
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

/// `m:ss` — the shape a stage row prints. Minutes are not zero-padded; a stage
/// that runs past an hour would print its minutes as a running total, which is
/// the honest thing for a wait nobody should be having.
String formatStageDuration(Duration d) {
  final seconds = d.inSeconds;
  final minutes = seconds ~/ 60;
  return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
}
