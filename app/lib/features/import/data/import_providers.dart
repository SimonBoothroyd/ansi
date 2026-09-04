/// Riverpod wiring for the import data layer (step 8).
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
/// `commit` is always the local PowerSync writer ([SqliteImportRepository]).
/// The extract→match step is what varies: with Supabase configured
/// ([Env.isConfigured]) it runs for real against the `import-recipe` edge
/// function ([EdgeImportRepository]).
///
/// Unconfigured, extraction has nowhere to run, so it FAILS LOUDLY
/// ([_UnconfiguredImport]) rather than falling through to the canned demo
/// payload, which would have a misconfigured build silently answer "import this
/// URL" with somebody else's spaghetti recipe. Tests and the on-device smoke
/// test get the canned repository by naming [SqliteImportRepository] directly,
/// never by accident.
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

/// Extraction with no backend to extract with. `commit` still works — a recipe
/// already reconciled writes locally — but `startImport` refuses rather than
/// inventing a recipe.
class _UnconfiguredImport implements ImportRepository {
  const _UnconfiguredImport(this._commit);

  final ImportRepository _commit;

  @override
  Future<ReconciliationPayload> startImport(ImportSource source) async {
    throw const ImportException(
      'importing needs a connection to the Ansi backend, and this build has '
      'none configured — sign in against a configured backend to import',
    );
  }

  @override
  Future<String> commit(CommitPayload payload) => _commit.commit(payload);
}
