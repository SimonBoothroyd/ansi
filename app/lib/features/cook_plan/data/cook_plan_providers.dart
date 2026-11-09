/// Riverpod wiring for the cook-plan data layer.
library;

import 'package:powersync/powersync.dart' show SyncStatus;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/observability/crash_sink.dart';
import '../../../core/sync/database.dart';
import '../../../core/sync/session.dart';
import '../domain/cook_plan_repository.dart';
import '../domain/leftover_repository.dart';
import 'cook_plan_repository_impl.dart';
import 'cooking_store.dart';
import 'leftover_repository_impl.dart';

part 'cook_plan_providers.g.dart';

@Riverpod(keepAlive: true)
CookPlanRepository cookPlanRepository(Ref ref) =>
    SqliteCookPlanRepository(ref.watch(databaseProvider));

@Riverpod(keepAlive: true)
LeftoverRepository leftoverRepository(Ref ref) => SqliteLeftoverRepository(
  ref.watch(databaseProvider),
  householdId: ref.watch(currentHouseholdIdProvider),
);

/// The carry-over from the last release's fridge rows and answers
/// ([carryOverCookings]): once a session is ready, after this launch's first
/// download has finished, so the cookings the server converted are here
/// before any is born on this phone. Idempotent, so a second run (a sign-in
/// again) changes nothing. Listened from the app's root; it goes with the old
/// tables.
@Riverpod(keepAlive: true)
Future<void> cookingCarryOver(Ref ref) async {
  if (ref.watch(sessionControllerProvider) is! SessionReady) return;
  final householdId = ref.watch(currentHouseholdIdProvider);
  final db = ref.watch(powerSyncDatabaseProvider);
  final launched = DateTime.now();
  bool downloaded(SyncStatus s) =>
      !s.downloading && (s.lastSyncedAt?.isAfter(launched) ?? false);
  if (!downloaded(db.currentStatus)) {
    await db.statusStream.firstWhere(downloaded);
  }
  try {
    await carryOverCookings(
      db,
      householdId: householdId,
      today: DateTime.now(),
    );
  } on Object catch (e, st) {
    ref.read(crashSinkProvider).report(e, st);
  }
}
