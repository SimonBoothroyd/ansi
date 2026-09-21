/// Riverpod wiring for the import data layer.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/env.dart';
import '../../../core/sync/database.dart';
import '../../../core/sync/session.dart';
import '../domain/commit_payload.dart';
import '../domain/import_repository.dart';
import '../domain/reconciliation_payload.dart';
import 'import_repository_impl.dart';
import 'remote_import_repository.dart';

part 'import_providers.g.dart';

/// The import repository the app uses.
///
/// `commit` is always the local writer ([SqliteImportRepository]). With
/// Supabase configured ([Env.isConfigured]) extraction runs against the edge
/// function ([EdgeImportRepository]); unconfigured it fails loudly
/// ([_UnconfiguredImport]) rather than serving the canned payload. Tests get
/// the canned repository by naming [SqliteImportRepository] directly.
@Riverpod(keepAlive: true)
ImportRepository importRepository(Ref ref) {
  final local = SqliteImportRepository(
    ref.watch(databaseProvider),
    householdId: ref.watch(currentHouseholdIdProvider),
  );
  if (!Env.isConfigured) return _UnconfiguredImport(local);
  return EdgeImportRepository(
    functions: ref.watch(supabaseClientProvider).functions,
    commitDelegate: local,
  );
}

/// Extraction with no backend. `commit` still writes locally; [startImport]
/// refuses.
class _UnconfiguredImport implements ImportRepository {
  const _UnconfiguredImport(this._commit);

  final ImportRepository _commit;

  @override
  Future<ReconciliationPayload> startImport(
    ImportSource source, {
    void Function(ImportProgress)? onProgress,
  }) async {
    throw const ImportException(
      'importing needs a connection to the Ansi backend, and this build has '
      'none configured — sign in against a configured backend to import',
    );
  }

  @override
  Future<String> commit(CommitPayload payload) => _commit.commit(payload);
}
