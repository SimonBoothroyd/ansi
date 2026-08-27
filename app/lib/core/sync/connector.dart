/// PowerSync <-> Supabase backend connector: provides credentials and drains
/// the local write queue up to Supabase.
///
/// `fetchCredentials` hands PowerSync the sync-service endpoint plus the
/// signed-in user's Supabase access token (whose `household_id` claim — added
/// by the `add_household_claim` hook, migration 0007 — scopes what syncs down).
///
/// `uploadData` applies each queued local change to Supabase via PostgREST.
/// Mise never hard-deletes (deletes are soft tombstones, spec §3), so repos
/// only ever emit inserts and updates; a stray delete is mapped to a soft
/// delete rather than a DELETE the RLS grants would reject anyway.
library;

import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Whether a PostgREST error means "this write is invalid" — retrying can't
/// help, so we drop the offending transaction rather than block the queue.
/// 22xxx = data exceptions, 23xxx = integrity, 42xxx = access/undefined.
bool isFatalPostgrestError(PostgrestException e) {
  final code = e.code;
  if (code == null) return false;
  return code.startsWith('22') ||
      code.startsWith('23') ||
      code.startsWith('42');
}

class MiseConnector extends PowerSyncBackendConnector {
  MiseConnector(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final session = _supabase.auth.currentSession;
    if (session == null) return null; // not signed in — nothing to sync
    return PowerSyncCredentials(
      endpoint: Env.powersyncUrl,
      token: session.accessToken,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) return;

    try {
      for (final op in transaction.crud) {
        final table = _supabase.from(op.table);
        switch (op.op) {
          case UpdateType.put:
            await table.upsert({...?op.opData, 'id': op.id});
          case UpdateType.patch:
            await table.update(op.opData!).eq('id', op.id);
          case UpdateType.delete:
            // Soft-delete: never issue a hard DELETE (no such grant/policy).
            await table
                .update({
                  'deleted_at': DateTime.now().toUtc().toIso8601String(),
                })
                .eq('id', op.id);
        }
      }
      await transaction.complete();
    } on PostgrestException catch (e) {
      if (isFatalPostgrestError(e)) {
        // Discarding keeps a single bad write from wedging the whole queue.
        await transaction.complete();
      } else {
        rethrow; // transient — PowerSync retries with backoff
      }
    }
  }
}
