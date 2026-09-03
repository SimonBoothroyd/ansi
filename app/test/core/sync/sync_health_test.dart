/// The four states, derived (`core/sync/sync_health.dart`).
///
/// The distinction the whole design rests on is between **waiting** (the
/// offline-first system working) and **stalled** (the user needs to know), so
/// most of this is about the threshold and the clock it runs on.
library;

import 'package:ansi/core/sync/dropped_write.dart';
import 'package:ansi/core/sync/sync_health.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 2, 14, 30);

DateTime _minutesAgo(int n) => _now.subtract(Duration(minutes: n));

SyncHealth _derive({
  int queued = 0,
  DateTime? lastSyncedAt,
  DateTime? uploadFailingSince,
  bool uploading = false,
  List<DroppedWrite> drops = const [],
}) => deriveSyncHealth(
  queued: queued,
  lastSyncedAt: lastSyncedAt,
  uploadFailingSince: uploadFailingSince,
  uploading: uploading,
  drops: drops,
  now: _now,
);

DroppedWrite _drop() => DroppedWrite(
  table: 'recipe',
  op: 'put',
  rowId: 'r1',
  code: '42501',
  message: 'new row violates row-level security policy',
  at: _minutesAgo(28),
);

void main() {
  test('an empty queue is settled, and carries the last sync', () {
    final health = _derive(lastSyncedAt: _minutesAgo(2));
    expect(health, isA<SyncSettled>());
    expect((health as SyncSettled).lastSyncedAt, _minutesAgo(2));
  });

  test('a queue with nothing wrong is WAITING, not an error', () {
    final health = _derive(queued: 3, lastSyncedAt: _minutesAgo(1));
    expect(health, isA<SyncWaiting>());
    expect((health as SyncWaiting).queued, 3);
  });

  test('an upload error under the threshold is still only waiting', () {
    // A token refresh, a backgrounded app, a lift ride. These heal themselves,
    // and a banner for them is a banner nobody reads.
    final health = _derive(
      queued: 3,
      lastSyncedAt: _minutesAgo(1),
      uploadFailingSince: _minutesAgo(1),
    );
    expect(health, isA<SyncWaiting>());
  });

  test('an upload error past the threshold is stalled', () {
    final health = _derive(
      queued: 7,
      lastSyncedAt: _minutesAgo(3),
      uploadFailingSince: _minutesAgo(6),
    );
    expect(health, isA<SyncStalled>());
    final stalled = health as SyncStalled;
    expect(stalled.queued, 7);
    // The earlier of the two clocks: uploads stopped landing six minutes ago,
    // even though a download refreshed lastSyncedAt three minutes ago.
    expect(stalled.since, _minutesAgo(6));
  });

  test('a cold start with an old queue is stalled immediately', () {
    // The stall clock must NOT start at app launch: a three-day-old queue is
    // three days stale whether or not this process has been up for a second.
    final health = _derive(
      queued: 12,
      lastSyncedAt: _now.subtract(const Duration(days: 3)),
      uploadFailingSince: _now,
    );
    expect(health, isA<SyncStalled>());
    expect(
      (health as SyncStalled).since,
      _now.subtract(const Duration(days: 3)),
    );
  });

  test('an error with an empty queue is not a stall — there is nothing to '
      'lose', () {
    final health = _derive(
      lastSyncedAt: _minutesAgo(90),
      uploadFailingSince: _minutesAgo(90),
    );
    expect(health, isA<SyncSettled>());
  });

  test('a dropped write outranks everything, with no threshold', () {
    // Data loss is the one state waiting cannot resolve.
    final health = _derive(drops: [_drop()]);
    expect(health, isA<SyncRefused>());
    expect((health as SyncRefused).drops.single.code, '42501');
  });

  test('uploading rides on waiting rather than being a fifth state', () {
    final health = _derive(queued: 2, uploading: true);
    expect(health, isA<SyncWaiting>());
    expect((health as SyncWaiting).uploading, isTrue);
  });

  test('a DroppedWrite round-trips through JSON', () {
    // It is persisted, because a divergence that vanishes when you close the
    // app is still silent.
    expect(DroppedWrite.fromJson(_drop().toJson()), _drop());
  });
}
