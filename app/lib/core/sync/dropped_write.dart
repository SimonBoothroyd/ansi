/// The record of writes the server refused and the connector discarded.
///
/// `connector.dart` drops a transaction on a fatal PostgREST code so it cannot
/// wedge the queue. The row then exists on this device only, so the drop is
/// reported through [DroppedWriteSink] and persisted in [SharedPreferences].
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'dropped_write.g.dart';

/// A local write the server refused and the connector discarded.
@immutable
class DroppedWrite {
  const DroppedWrite({
    required this.table,
    required this.op,
    required this.rowId,
    required this.code,
    required this.message,
    required this.at,
  });

  factory DroppedWrite.fromJson(Map<String, dynamic> json) => DroppedWrite(
    table: json['table'] as String? ?? '?',
    op: json['op'] as String? ?? '?',
    rowId: json['rowId'] as String? ?? '?',
    code: json['code'] as String? ?? '?',
    message: json['message'] as String? ?? '',
    at:
        DateTime.tryParse(json['at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  /// The server table the write was for — `recipe`, `plan_entry`, …
  final String table;

  /// `put` · `patch` · `delete`, as PowerSync named the operation.
  final String op;
  final String rowId;

  /// The PostgREST/Postgres code that made it fatal (`42501` = RLS denied).
  final String code;
  final String message;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'table': table,
    'op': op,
    'rowId': rowId,
    'code': code,
    'message': message,
    'at': at.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is DroppedWrite &&
      other.table == table &&
      other.op == op &&
      other.rowId == rowId &&
      other.code == code &&
      other.message == message &&
      other.at == at;

  @override
  int get hashCode => Object.hash(table, op, rowId, code, message, at);
}

/// Where the connector reports a discarded transaction. An interface, so the
/// connector needs no Riverpod and a test can assert the report.
// ignore: one_member_abstracts
abstract interface class DroppedWriteSink {
  void dropped(DroppedWrite write);
}

/// A sink that keeps nothing: the connector's default, and a test's.
class NoopDroppedWriteSink implements DroppedWriteSink {
  const NoopDroppedWriteSink();

  @override
  void dropped(DroppedWrite write) {}
}

/// Every write this device has lost, oldest first. Keep-alive and restored
/// from disk, so neither a closed screen nor a relaunch forgets a drop.
@Riverpod(keepAlive: true)
class DroppedWrites extends _$DroppedWrites implements DroppedWriteSink {
  static const _key = 'ansi.dropped_writes';

  /// At most this many are kept; a refused parent can cascade into many.
  static const _cap = 20;

  @override
  List<DroppedWrite> build() {
    unawaited(_restore());
    return const [];
  }

  /// The platform store, or null where there is no Flutter binding (a plain
  /// unit test); the record is then in-memory only.
  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } on Object catch (e) {
      debugPrint('dropped-write store unavailable: $e');
      return null;
    }
  }

  Future<void> _restore() async {
    final stored = (await _prefs())?.getStringList(_key) ?? const [];
    if (stored.isEmpty || !ref.mounted) return;
    state = [
      for (final line in stored)
        DroppedWrite.fromJson(jsonDecode(line) as Map<String, dynamic>),
    ];
  }

  @override
  void dropped(DroppedWrite write) {
    final next = [...state, write];
    state = next.length > _cap ? next.sublist(next.length - _cap) : next;
    unawaited(_persist());
  }

  /// Forgets every recorded drop. It retires the notice, not the loss.
  void acknowledge() {
    state = const [];
    unawaited(_persist());
  }

  Future<void> _persist() async {
    await (await _prefs())?.setStringList(_key, [
      for (final w in state) jsonEncode(w.toJson()),
    ]);
  }
}
