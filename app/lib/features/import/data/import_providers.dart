/// Riverpod wiring for the import data layer (step 8).
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/sync/database.dart';
import '../../../core/sync/session.dart';
import '../domain/import_repository.dart';
import 'import_repository_impl.dart';

part 'import_providers.g.dart';

@Riverpod(keepAlive: true)
ImportRepository importRepository(Ref ref) => SqliteImportRepository(
  ref.watch(databaseProvider),
  householdId: ref.watch(currentHouseholdIdProvider),
);
