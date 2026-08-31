/// Riverpod wiring for the import data layer (step 8).
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/env.dart';
import '../../../core/sync/database.dart';
import '../../../core/sync/session.dart';
import '../domain/import_repository.dart';
import 'import_repository_impl.dart';
import 'remote_import_repository.dart';

part 'import_providers.g.dart';

/// The import repository the app uses.
///
/// `commit` is always the local PowerSync writer ([SqliteImportRepository]).
/// The extract→match step is what varies: with Supabase configured
/// ([Env.isConfigured]) it runs for real against the `import-recipe` edge
/// function ([EdgeImportRepository]); unconfigured (dev/offline, and tests) it
/// falls back to the canned/fake repository so the flow still exercises end to
/// end without a backend.
@Riverpod(keepAlive: true)
ImportRepository importRepository(Ref ref) {
  final local = SqliteImportRepository(
    ref.watch(databaseProvider),
    householdId: ref.watch(currentHouseholdIdProvider),
  );
  if (!Env.isConfigured) return local;
  return EdgeImportRepository(
    functions: ref.watch(supabaseClientProvider).functions,
    commitDelegate: local,
  );
}
