/// PowerSync <-> Supabase backend connector: provides credentials and drains
/// the local write queue up to Supabase.
///
/// `fetchCredentials` hands PowerSync the sync-service endpoint plus the
/// signed-in user's Supabase access token (whose `household_id` claim — added
/// by the `add_household_claim` hook, migration 0007 — scopes what syncs down).
///
/// `uploadData` applies each queued local change to Supabase via PostgREST.
/// Ansi never hard-deletes (deletes are soft tombstones, spec §3), so repos
/// only ever emit inserts and updates; a stray delete is mapped to a soft
/// delete rather than a DELETE the RLS grants would reject anyway.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import 'dropped_write.dart';

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

/// The server's `jsonb` columns, per table — held in lockstep with
/// `supabase/migrations` by `test/structure/jsonb_columns_test.dart`, which
/// derives the set from the migrations (0002 `ingredient.macros`, 0003
/// `recipe.steps`, 0005 `plan_entry.eaters`, 0012 `ingredient.allowed_units`)
/// and fails the build when this map falls behind.
///
/// PowerSync's local SQLite stores JSON values as TEXT, so a queued op carries
/// e.g. `steps` as the *string* `'["step one"]'`. Uploading that string as-is
/// makes Postgres store a jsonb **string** (`jsonb_typeof` = `string`), and
/// when the row syncs back down every reader that expects an array/object
/// crashes — or, quieter and worse, every server-side rule that asks
/// `allowed_units ? unit` answers false. `allowed_units` was missing from this
/// map from 0012 until 2026-09-03 (found by pgTAP over smoke-created rows;
/// repaired server-side by 0028). Decode these columns to native structures
/// before upload.
const Map<String, Set<String>> jsonbColumnsByTable = {
  'recipe': {'steps'},
  'plan_entry': {'eaters'},
  'ingredient': {'macros', 'allowed_units'},
};

/// Returns [data] with any [jsonbColumnsByTable] columns of [table] decoded
/// from their local TEXT form to native JSON. Absent columns stay absent and
/// null stays null; a value that is already structured passes through.
Map<String, dynamic> _decodeJsonbColumns(
  String table,
  Map<String, dynamic> data,
) {
  final jsonbColumns = jsonbColumnsByTable[table];
  if (jsonbColumns == null) return data;
  final decoded = Map<String, dynamic>.of(data);
  for (final column in jsonbColumns) {
    final value = decoded[column];
    if (value is String) decoded[column] = jsonDecode(value);
  }
  return decoded;
}

/// The PostgREST upsert payload for a PUT op: the row image with jsonb columns
/// decoded, the row id, and `deleted_at` defaulted to null.
///
/// The explicit null matters: a PUT's opData omits null columns, and PowerSync
/// queues a local DELETE + re-INSERT of the same id as DELETE-then-PUT. The
/// connector maps the DELETE to a server-side tombstone, so without
/// `deleted_at: null` the following upsert would leave the tombstone in place
/// and the row would stay deleted on every other device. A PUT means the row
/// is live locally, so clearing the tombstone is always correct (and it
/// self-heals rows tombstoned by the old behaviour). An explicit local
/// `deleted_at` value in the op still wins over the default.
@visibleForTesting
Map<String, dynamic> putPayload(CrudEntry op) => {
  'deleted_at': null,
  ..._decodeJsonbColumns(op.table, op.opData ?? const {}),
  'id': op.id,
};

/// The PostgREST update payload for a PATCH op: just the changed columns, with
/// jsonb columns decoded.
@visibleForTesting
Map<String, dynamic> patchPayload(CrudEntry op) =>
    _decodeJsonbColumns(op.table, op.opData ?? const {});

class AnsiConnector extends PowerSyncBackendConnector {
  AnsiConnector(this._supabase, {DroppedWriteSink? onDropped})
    : _onDropped = onDropped ?? const NoopDroppedWriteSink();

  final SupabaseClient _supabase;

  /// Where a discarded transaction is reported. The `debugPrint` below stays
  /// beside it, not instead of it — a console line is for whoever is attached,
  /// and this is for the person it happened to.
  final DroppedWriteSink _onDropped;

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

    CrudEntry? current;
    try {
      for (final op in transaction.crud) {
        current = op;
        final table = _supabase.from(op.table);
        switch (op.op) {
          case UpdateType.put:
            await table.upsert(putPayload(op));
          case UpdateType.patch:
            await table.update(patchPayload(op)).eq('id', op.id);
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
        // Discarding keeps a single bad write from wedging the whole queue,
        // but it is a permanent local/server divergence — never let it be
        // silent.
        debugPrint(
          'sync: DROPPING crud transaction after fatal PostgREST error on '
          '${current?.table}/${current?.op.name} id=${current?.id} '
          '(code=${e.code}): ${e.message}',
        );
        _onDropped.dropped(
          DroppedWrite(
            table: current?.table ?? '?',
            op: current?.op.name ?? '?',
            rowId: current?.id ?? '?',
            code: e.code ?? '?',
            message: e.message,
            at: DateTime.now(),
          ),
        );
        await transaction.complete();
      } else {
        rethrow; // transient — PowerSync retries with backoff
      }
    }
  }
}
