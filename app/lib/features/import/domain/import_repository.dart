/// The import contract — PURE DART (invariant 2). The presentation layer
/// depends only on this; the data layer implements it.
///
/// `startImport` is the "edge function" seam: it runs the server-side
/// extract→match pipeline and returns a `ReconciliationPayload`. Until
/// integration it is faked with a canned gold-derived payload (lane C's first
/// real `functions.invoke` is swapped in at the tail). `commit` is always
/// real — it writes the resolved recipe through PowerSync.
library;

import 'commit_payload.dart';
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

abstract interface class ImportRepository {
  /// Runs extraction + matching for [source] and returns the reconciliation
  /// payload the user resolves. (Faked with a canned payload pre-integration.)
  Future<ReconciliationPayload> startImport(ImportSource source);

  /// Writes a fully-resolved [payload] — the recipe, its groups and line items,
  /// any create-new stubs, and correction aliases — through PowerSync in one
  /// transaction, remapping step `line_index` refs to real `line_item_id`s.
  /// Returns the new recipe's id.
  Future<String> commit(CommitPayload payload);
}
