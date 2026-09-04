/// The one place in Ansi where data is genuinely lost, and the record of it.
///
/// `connector.dart` discards a transaction the server refuses with a fatal
/// PostgREST code (22xxx data, 23xxx integrity, 42xxx access — `42501` is RLS
/// denied). Dropping is the right engineering call: a poison write must not
/// wedge the queue forever. But it leaves the row on this phone and on no
/// server and no other device, so it must never be silent.
///
/// [DroppedWriteSink] is where the connector speaks instead. The default
/// implementation persists to the same [SharedPreferences] store the household
/// cache uses, because a divergence that vanishes when you close the app is
/// still silent.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'dropped_write.g.dart';

/// A local write the server refused and the connector discarded — a permanent
/// local/server divergence.
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

/// Where the connector reports a discarded transaction.
///
/// An interface, so a repository test can assert the report without a UI and
/// the connector never needs to know about Riverpod.
// One member today, and deliberately a type rather than a callback: the
// connector is constructed in `session.dart` and tested in isolation, and a
// named interface is what lets both hand it something meaningful.
// ignore: one_member_abstracts
abstract interface class DroppedWriteSink {
  void dropped(DroppedWrite write);
}

/// A sink that keeps nothing. The connector's default when nothing is
/// listening — and what a test passes when the reporting is not what it is
/// checking.
class NoopDroppedWriteSink implements DroppedWriteSink {
  const NoopDroppedWriteSink();

  @override
  void dropped(DroppedWrite write) {}
}

/// Every write this device has lost, oldest first.
///
/// Keep-alive: a drop is terminal, so it must outlive the screen that happened
/// to be open when it landed. Restored from disk on first read, so a relaunch
/// does not quietly forgive it.
@Riverpod(keepAlive: true)
class DroppedWrites extends _$DroppedWrites implements DroppedWriteSink {
  static const _key = 'ansi.dropped_writes';

  /// At most this many are kept. A cascade (a refused parent makes every
  /// child's FK insert fatal too) can produce a lot of them, and the banner
  /// says the same thing after the tenth as after the first.
  static const _cap = 20;

  @override
  List<DroppedWrite> build() {
    unawaited(_restore());
    return const [];
  }

  /// The platform store, or null where there is none.
  ///
  /// Reaching it needs a Flutter binding, which a plain unit test does not
  /// have. Losing the *record* of a drop is not losing the write, so this
  /// degrades to in-memory rather than throwing out of a provider's build.
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

  /// Forgets every recorded drop — the "I have seen this" action behind the
  /// banner's detail sheet. It does not undo the loss; it retires the notice.
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
