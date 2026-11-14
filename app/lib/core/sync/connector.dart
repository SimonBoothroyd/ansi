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

/// Tables whose rows a phone only ever inserts whole and then patches: a PUT
/// is a birth, and two phones can birth one row under one id (a cooking
/// named by its group's first meal, a carried-over change). The second
/// upload must not overwrite what the first said, so it is an insert that
/// leaves an existing row alone.
const Set<String> insertOnceTables = {'cooking', 'cooking_change'};

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

/// The tables the server holds unique on a NATURAL key as well as the id,
/// and that key's columns, held in lockstep with the migrations by
/// `test/structure/natural_keys_test.dart`.
///
/// Two phones can each make the row for one key offline, under two ids: the
/// second PUT, an upsert by id, then hits the key (`23505`). It is not
/// dropped: it is written onto the row that holds the key, keeping that
/// row's id (last writer wins), and the losing id is re-pointed at the
/// winner for the rest of the upload ([AnsiConnector]). The phone's own row
/// under the losing id is on no server bucket, so the next sync, once the
/// queue is empty, removes it locally and brings the winner down: both
/// phones converge on one row with no client clean-up.
///
/// A key with a null column cannot collide (NULLs are distinct in a unique
/// index), so an override `add` row (no recipe line) never merges.
const Map<String, List<String>> naturalKeysByTable = {
  'week_plan': ['household_id', 'week_start_date'],
  'week_recipe_line_override': [
    'week_plan_id',
    'recipe_id',
    'recipe_line_item_id',
  ],
};

/// Columns that point at a row of a [naturalKeysByTable] table, by the table
/// they point at: a write that names a losing id is re-pointed at the winner.
const Map<String, String> naturalKeyParents = {'week_plan_id': 'week_plan'};

/// What the connector asks of the server: PostgREST in the app
/// ([AnsiConnector.new]), a stand-in with the server's constraints in tests.
abstract interface class UploadTarget {
  /// An upsert by id; with [ignoreDuplicates], an insert that leaves a row
  /// already there alone.
  Future<void> upsert(
    String table,
    Map<String, dynamic> row, {
    required bool ignoreDuplicates,
  });

  /// Updates the row [id] of [table] with [values].
  Future<void> update(String table, String id, Map<String, dynamic> values);

  /// The id of the row of [table] whose columns equal [key], live or not,
  /// or null when there is none.
  Future<String?> idWhere(String table, Map<String, Object> key);
}

class _PostgrestTarget implements UploadTarget {
  const _PostgrestTarget(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<void> upsert(
    String table,
    Map<String, dynamic> row, {
    required bool ignoreDuplicates,
  }) => _supabase.from(table).upsert(row, ignoreDuplicates: ignoreDuplicates);

  @override
  Future<void> update(String table, String id, Map<String, dynamic> values) =>
      _supabase.from(table).update(values).eq('id', id);

  @override
  Future<String?> idWhere(String table, Map<String, Object> key) async {
    var query = _supabase.from(table).select('id');
    for (final MapEntry(:key, :value) in key.entries) {
      query = query.eq(key, value);
    }
    final rows = await query.limit(1);
    return rows.isEmpty ? null : rows.first['id'] as String?;
  }
}

class AnsiConnector extends PowerSyncBackendConnector {
  AnsiConnector(SupabaseClient supabase, {DroppedWriteSink? onDropped})
    : this.withTarget(
        _PostgrestTarget(supabase),
        supabase: supabase,
        onDropped: onDropped,
      );

  /// A connector writing to its target; [supabase] only signs it in.
  @visibleForTesting
  AnsiConnector.withTarget(
    this._target, {
    SupabaseClient? supabase,
    DroppedWriteSink? onDropped,
  }) : _supabase = supabase,
       _onDropped = onDropped ?? const NoopDroppedWriteSink();

  final SupabaseClient? _supabase;
  final UploadTarget _target;

  /// Where a discarded transaction is reported to the user.
  final DroppedWriteSink _onDropped;

  /// Ids that lost a natural key to another phone's row, and that row's id:
  /// a later write naming the loser goes to the winner. Held for the
  /// session; a write queued behind a merge almost always uploads in it.
  final Map<String, String> _merged = {};

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final session = _supabase?.auth.currentSession;
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
        await _upload(database, op);
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

  /// Uploads one op. A PUT that hits a natural key merges onto the row that
  /// holds it ([naturalKeysByTable]); one that names a parent the server
  /// does not have (`23503`) is re-pointed at the parent's winner, once.
  Future<void> _upload(PowerSyncDatabase database, CrudEntry op) async {
    final id = _merged[op.id] ?? op.id;
    switch (op.op) {
      case UpdateType.put:
        var row = _repointed({...putPayload(op), 'id': id});
        for (var attempt = 0; ; attempt++) {
          try {
            await _target.upsert(
              op.table,
              row,
              ignoreDuplicates: insertOnceTables.contains(op.table),
            );
            return;
          } on PostgrestException catch (e) {
            if (e.code == '23505' && await _mergeOntoKey(op.table, row)) {
              return;
            }
            if (attempt == 0 &&
                e.code == '23503' &&
                await _resolveParents(database, row)) {
              row = _repointed(row);
              continue;
            }
            rethrow;
          }
        }
      case UpdateType.patch:
        await _target.update(op.table, id, _repointed(patchPayload(op)));
      case UpdateType.delete:
        // Soft-delete: never issue a hard DELETE (no such grant/policy).
        await _target.update(op.table, id, {
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
        });
    }
  }

  /// [row] with every [naturalKeyParents] column that names a losing id
  /// pointed at its winner.
  Map<String, dynamic> _repointed(Map<String, dynamic> row) => {
    for (final MapEntry(:key, :value) in row.entries)
      key: naturalKeyParents.containsKey(key) && value is String
          ? _merged[value] ?? value
          : value,
  };

  /// Writes [row] onto the row of [table] that holds its natural key, keeping
  /// that row's id and created_at: the last writer wins. False when [table]
  /// has no natural key, the key has a null part, or no other row holds it.
  Future<bool> _mergeOntoKey(String table, Map<String, dynamic> row) async {
    final columns = naturalKeysByTable[table];
    if (columns == null) return false;
    final key = <String, Object>{};
    for (final column in columns) {
      final value = row[column];
      if (value == null) return false;
      key[column] = value as Object;
    }
    final winner = await _target.idWhere(table, key);
    final loser = row['id'] as String;
    if (winner == null || winner == loser) return false;
    debugPrint(
      'sync: $table $loser lost its key to $winner; written onto $winner',
    );
    await _target.update(table, winner, {
      for (final MapEntry(:key, :value) in row.entries)
        if (key != 'id' && key != 'created_at') key: value,
    });
    _merged[loser] = winner;
    return true;
  }

  /// For each [naturalKeyParents] column of [row] the server has no row for,
  /// finds the parent's winner by the parent's natural key, read from this
  /// phone's own copy. True when one was found (and [_merged] now has it).
  Future<bool> _resolveParents(
    PowerSyncDatabase database,
    Map<String, dynamic> row,
  ) async {
    var found = false;
    for (final MapEntry(key: column, value: parentTable)
        in naturalKeyParents.entries) {
      final parentId = row[column];
      if (parentId is! String || _merged.containsKey(parentId)) continue;
      final columns = naturalKeysByTable[parentTable]!;
      final local = await database.getOptional(
        'SELECT ${columns.join(', ')} FROM $parentTable WHERE id = ?',
        [parentId],
      );
      if (local == null || columns.any((c) => local[c] == null)) continue;
      final winner = await _target.idWhere(parentTable, {
        for (final c in columns) c: local[c] as Object,
      });
      if (winner == null || winner == parentId) continue;
      _merged[parentId] = winner;
      found = true;
    }
    return found;
  }
}
