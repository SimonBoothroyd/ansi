/// The sentences the import screen shows while the one `import-recipe` call is
/// in flight — PURE DART (invariant 2).
///
/// The server runs several stages behind that call: a URL import fetches the
/// page, extracts with the model, then matches the lines; a photo import
/// transcribes the pages with the vision tier first, so it makes TWO model
/// calls before matching. The call itself is a single non-streaming POST, so
/// the client is never told which stage the server reached. The ladder is
/// therefore driven by elapsed time: the rungs name the real server stages in
/// the order they actually run, and their thresholds come from the extraction
/// eval's measured latencies.
///
/// It is an estimate of where the request has got to, never a claim of fact, so
/// every rung is written to stay true when the estimate runs early or late —
/// "Still reading" is honest at any moment after it, and no rung promises that
/// a stage has finished.
library;

/// One rung of the loading ladder: [label] shows from [after] until the next
/// rung's [after], and the last rung shows until the call returns.
class ImportStage {
  const ImportStage(this.after, this.label);

  /// Elapsed time from the start of the call at which this rung takes over.
  final Duration after;

  /// The sentence under the spinner.
  final String label;
}

/// The rungs for a URL import: fetch the page, one model call, then match.
const urlImportStages = <ImportStage>[
  ImportStage(Duration.zero, 'Fetching the page…'),
  ImportStage(Duration(seconds: 5), 'Reading the recipe…'),
  ImportStage(
    Duration(seconds: 25),
    'Still reading — a long recipe takes a '
    'while…',
  ),
  ImportStage(Duration(seconds: 55), 'Matching the ingredients…'),
];

/// The rungs for a photo import. Two model calls, not one — the pages are
/// transcribed before the recipe is written out — so it is roughly twice the
/// URL path's budget, and the upload of the (already downscaled) pages is a
/// stage of its own.
const photoImportStages = <ImportStage>[
  ImportStage(Duration.zero, 'Sending the photos…'),
  ImportStage(Duration(seconds: 5), 'Reading the photos…'),
  ImportStage(Duration(seconds: 35), 'Writing out the recipe…'),
  ImportStage(
    Duration(seconds: 75),
    'Still working — a multi-page recipe '
    'takes a while…',
  ),
  ImportStage(Duration(seconds: 110), 'Matching the ingredients…'),
];

/// The ladder [fromPhotos] selects.
List<ImportStage> importStages({required bool fromPhotos}) =>
    fromPhotos ? photoImportStages : urlImportStages;

/// The rung showing at [elapsed]. Identity-stable: the same rung of the same
/// ladder is the same instance, so a caller can skip a rebuild with
/// [identical].
ImportStage importStageAt(Duration elapsed, {required bool fromPhotos}) {
  final stages = importStages(fromPhotos: fromPhotos);
  var current = stages.first;
  for (final stage in stages) {
    if (elapsed < stage.after) break;
    current = stage;
  }
  return current;
}
