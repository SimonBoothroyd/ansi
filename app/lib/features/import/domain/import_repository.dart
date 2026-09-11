/// The import contract — PURE DART (invariant 2). The presentation layer
/// depends only on this; the data layer implements it.
///
/// `startImport` is the "edge function" seam: it runs the server-side
/// extract→match pipeline and returns a [ReconciliationPayload]. In the app it
/// is the real `import-recipe` invoke (`EdgeImportRepository`); the canned
/// `SqliteImportRepository.startImport` is the test/dev stand-in, named
/// explicitly by whoever wants it. `commit` is always real — it writes the
/// resolved recipe through PowerSync.
library;

import 'commit_payload.dart';
import 'import_stage.dart';
import 'reconciliation_payload.dart';

/// What the user handed intake — a URL to fetch or photos to transcribe.
sealed class ImportSource {
  const ImportSource();
}

/// Import from a pasted recipe URL.
class ImportFromUrl extends ImportSource {
  const ImportFromUrl(this.url);
  final String url;
}

/// Import from one or more photos of a recipe (file paths on device).
class ImportFromPhotos extends ImportSource {
  const ImportFromPhotos(this.imagePaths);
  final List<String> imagePaths;
}

/// Something the server said while an import was running (import spec §4.7).
sealed class ImportProgress {
  const ImportProgress();
}

/// The stage list this import will walk, sent before any of it has happened.
/// The server decides it — a photo import transcribes first, a link import
/// fetches — so the screen never has to guess which door it came through.
class ImportPlanned extends ImportProgress {
  const ImportPlanned(this.stages);
  final List<ImportStage> stages;
}

/// A stage finished. [elapsed] is the server's own clock, measured from the
/// moment the request reached it — so `received` covers the upload.
class ImportStageDone extends ImportProgress {
  const ImportStageDone(this.stage, this.elapsed);
  final ImportStage stage;
  final Duration elapsed;
}

abstract interface class ImportRepository {
  /// Runs extraction + matching for [source] and returns the reconciliation
  /// payload the user resolves.
  ///
  /// [onProgress] is called as the server reports each stage. It is optional
  /// because progress is a courtesy, never the result: an implementation that
  /// has nothing to report still returns the same payload.
  Future<ReconciliationPayload> startImport(
    ImportSource source, {
    void Function(ImportProgress)? onProgress,
  });

  /// Writes a fully-resolved [payload] — the recipe, its groups and line items,
  /// any create-new stubs, and correction aliases — through PowerSync in one
  /// transaction, remapping step `line_index` refs to real `line_item_id`s.
  /// Returns the new recipe's id.
  Future<String> commit(CommitPayload payload);
}
