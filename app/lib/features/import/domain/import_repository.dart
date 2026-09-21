/// The import contract. Pure Dart.
///
/// `startImport` runs the server-side extract→match pipeline and returns a
/// [ReconciliationPayload]. The app uses `EdgeImportRepository`;
/// `SqliteImportRepository.startImport` is the canned stand-in for tests.
/// `commit` always writes the resolved recipe through PowerSync.
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

/// Something the server said while an import was running.
sealed class ImportProgress {
  const ImportProgress();
}

/// The stage list this import will walk, sent first. The server decides it: a
/// photo import transcribes, a link import fetches.
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
  /// Runs extraction and matching for [source] and returns the reconciliation
  /// payload the user resolves. [onProgress] is called as the server reports
  /// each stage; an implementation with nothing to report returns the same
  /// payload.
  Future<ReconciliationPayload> startImport(
    ImportSource source, {
    void Function(ImportProgress)? onProgress,
  });

  /// Writes a fully resolved [payload] (the recipe, its groups and line items,
  /// and correction aliases) through PowerSync in one transaction, remapping
  /// step `line_index` refs to `line_item_id`s. Returns the new recipe's id.
  Future<String> commit(CommitPayload payload);
}
