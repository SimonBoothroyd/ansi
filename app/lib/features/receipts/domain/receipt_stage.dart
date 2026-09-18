/// The stages the scan screen shows while `import-receipt` is running — PURE
/// DART (invariant 2).
///
/// Four rows, the same four a photographed recipe walks, with the third
/// renamed for what it writes: the photos arrive, the vision tier reads them
/// into one joined strip, the model writes the receipt out, and the lines are
/// matched against the household's vocabulary. The ids are the wire contract
/// (`supabase/functions/import-receipt/index.ts`); the wording is here,
/// because copy belongs where the screen is.
///
/// Everything else about the checklist — the tenses, the clocks, the frozen
/// elapsed times, the `m:ss` — is `import/domain/import_stage.dart`'s and is
/// shared rather than copied ([PipelineStage]).
library;

import '../../import/domain/import_stage.dart';

/// One stage of the receipt pipeline.
///
/// A receipt only ever arrives as photos, so there is no second wording to
/// hold: `fromPhotos` is answered the same way whichever way it is asked.
enum ReceiptStage implements PipelineStage {
  /// The photos are in hand — however many megabytes of them.
  received(
    'received',
    running: 'Receiving the photos…',
    done: 'Photos received',
  ),

  /// The vision tier read the pages and joined them into one strip.
  read('read', running: 'Reading the photos…', done: 'Photos read'),

  /// The model turned the strip into a structured receipt.
  written(
    'written',
    running: 'Writing the receipt out…',
    done: 'Receipt written out',
  ),

  /// Every line was matched against the household's ingredients.
  matched('matched', running: 'Matching the lines…', done: 'Lines matched');

  const ReceiptStage(this.id, {required String running, required String done})
    : _running = running,
      _done = done;

  @override
  final String id;

  final String _running;
  final String _done;

  @override
  String label({required bool fromPhotos, required StageStatus status}) =>
      status == StageStatus.active ? _running : _done;

  /// The stage with this wire [id], or null for one this build does not know
  /// — which is dropped rather than drawn as a blank row.
  static ReceiptStage? byId(String id) {
    for (final stage in ReceiptStage.values) {
      if (stage.id == id) return stage;
    }
    return null;
  }
}

/// Something the server said while a receipt was being read.
sealed class ReceiptProgress {
  const ReceiptProgress();
}

/// The stage list this scan will walk, sent before any of it has happened.
class ReceiptPlanned extends ReceiptProgress {
  const ReceiptPlanned(this.stages);
  final List<ReceiptStage> stages;
}

/// A stage finished. [elapsed] is the server's own clock, from the moment the
/// request reached it — so `received` covers the upload.
class ReceiptStageDone extends ReceiptProgress {
  const ReceiptStageDone(this.stage, this.elapsed);
  final ReceiptStage stage;
  final Duration elapsed;
}
