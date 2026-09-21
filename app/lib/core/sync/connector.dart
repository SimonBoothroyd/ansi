/// The PowerSync to Supabase connector: provides credentials and drains the
/// local write queue through PostgREST.
///
/// The access token's `household_id` claim scopes what syncs down. Deletes
/// are soft tombstones, so a stray DELETE op is uploaded as a soft delete.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import 'dropped_write.dart';

/// Whether a PostgREST error means the write is invalid, so retrying cannot
/// help and the transaction is dropped. 22xxx = data exceptions, 23xxx =
/// integrity, 42xxx = access/undefined.
bool isFatalPostgrestError(PostgrestException e) {
  final code = e.code;
  if (code == null) return false;
  return code.startsWith('22') ||
      code.startsWith('23') ||
      code.startsWith('42');
}

/// The server's `jsonb` columns a client writes, per table, held in lockstep
/// with the migrations by `test/structure/jsonb_columns_test.dart`.
///
/// Local SQLite stores JSON as TEXT. Uploaded as-is it becomes a jsonb
/// string, which breaks every reader and every server-side `?` test, so these
/// columns are decoded before upload.
const Map<String, Set<String>> jsonbColumnsByTable = {
  'recipe': {'steps'},
  'plan_entry': {'eaters', 'macros'},
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
/// PowerSync queues a local DELETE + re-INSERT as DELETE-then-PUT and a PUT
/// omits null columns, so without the explicit null the tombstone would stay.
/// A local `deleted_at` in the op still wins.
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

  /// Where a discarded transaction is reported to the user.
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
        // Dropping keeps one bad write from wedging the queue, but the two
        // sides now diverge, so it is never silent.
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
