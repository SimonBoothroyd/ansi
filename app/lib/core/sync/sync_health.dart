/// Whether this device's writes are reaching the server, as one provider.
///
/// The only reader of PowerSync's status and upload queue; every readout
/// watches [syncHealthProvider]. Four states ([SyncHealth]). A queue is the
/// offline-first design working, so waiting is never styled as a problem and
/// the app never says "offline".
library;

import 'dart:async';

import 'package:powersync/powersync.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'database.dart';
import 'dropped_write.dart';

part 'sync_health.g.dart';

/// How long uploads must have been failing before the app says so. Minutes,
/// because token refreshes and backgrounding cause errors that heal in
/// seconds.
const stallThreshold = Duration(minutes: 5);

/// How often the provider re-derives with nothing new to go on, so a stall
/// crosses [stallThreshold] without waiting for the next sync event.
const _tick = Duration(seconds: 20);

/// Where this device stands with the server.
sealed class SyncHealth {
  const SyncHealth();
}

/// Nothing queued and nothing wrong.
final class SyncSettled extends SyncHealth {
  const SyncSettled(this.lastSyncedAt);

  final DateTime? lastSyncedAt;
}

/// Writes are queued and nothing is wrong. Not an error: rendered muted,
/// never red.
final class SyncWaiting extends SyncHealth {
  const SyncWaiting({
    required this.queued,
    this.uploading = false,
    this.lastSyncedAt,
  });

  final int queued;

  /// PowerSync is pushing right now. A display detail, not a fifth state.
  final bool uploading;
  final DateTime? lastSyncedAt;
}

/// Uploads have been getting nowhere for longer than [stallThreshold].
/// Retryable in principle; it just hasn't been working.
final class SyncStalled extends SyncHealth {
  const SyncStalled({required this.queued, required this.since});

  final int queued;

  /// When the writes stopped landing; see [deriveSyncHealth].
  final DateTime since;
}

/// A transaction was refused and discarded. Data loss; bypasses the
/// threshold.
final class SyncRefused extends SyncHealth {
  const SyncRefused(this.drops);

  final List<DroppedWrite> drops;
}

/// Turns the three inputs into one state. Pure, so it is unit-testable.
///
/// `ps_crud` carries no timestamps, so the stall clock is the earlier of
/// [lastSyncedAt] and [uploadFailingSince]: a cold start with an old queue
/// stalls at once, while healthy downloads leave the failing-uploads clock
/// in charge.
SyncHealth deriveSyncHealth({
  required int queued,
  required DateTime? lastSyncedAt,
  required DateTime? uploadFailingSince,
  required DateTime now,
  List<DroppedWrite> drops = const [],
  bool uploading = false,
  Duration threshold = stallThreshold,
}) {
  // Loss outranks everything: waiting cannot resolve it.
  if (drops.isNotEmpty) return SyncRefused(drops);
  if (queued == 0) return SyncSettled(lastSyncedAt);
  if (uploadFailingSince != null) {
    final since =
        lastSyncedAt == null || uploadFailingSince.isBefore(lastSyncedAt)
        ? uploadFailingSince
        : lastSyncedAt;
    if (now.difference(since) >= threshold) {
      return SyncStalled(queued: queued, since: since);
    }
  }
  return SyncWaiting(
    queued: queued,
    uploading: uploading,
    lastSyncedAt: lastSyncedAt,
  );
}

/// The app's single answer to "are my changes getting through?". Keep-alive
/// so the "since" timestamp survives a tab switch.
@Riverpod(keepAlive: true)
Stream<SyncHealth> syncHealth(Ref ref) {
  final db = ref.watch(powerSyncDatabaseProvider);
  final drops = ref.watch(droppedWritesProvider);
  return watchSyncHealth(db, drops: drops, onDispose: ref.onDispose);
}

/// Whether the sync connection is live right now.
///
/// Not a health state and never rendered as one. It exists for the one
/// control that needs the server: changing the household's week start. Leads
/// with the current status, then follows every change.
@Riverpod(keepAlive: true)
Stream<bool> serverReachable(Ref ref) =>
    watchServerReachable(ref.watch(powerSyncDatabaseProvider));

/// [serverReachableProvider]'s body, with the database passed in for tests.
Stream<bool> watchServerReachable(PowerSyncDatabase db) async* {
  var last = db.currentStatus.connected;
  yield last;
  await for (final status in db.statusStream) {
    if (status.connected == last) continue;
    last = status.connected;
    yield last;
  }
}

/// [syncHealthProvider]'s body, with the database passed in for tests.
Stream<SyncHealth> watchSyncHealth(
  PowerSyncDatabase db, {
  List<DroppedWrite> drops = const [],
  void Function(void Function())? onDispose,
  DateTime Function() clock = DateTime.now,
}) {
  final out = StreamController<SyncHealth>.broadcast();
  DateTime? uploadFailingSince;
  var closed = false;

  Future<void> emit() async {
    if (closed) return;
    final status = db.currentStatus;
    // The clock runs from the start of a run of failures; a cleared error
    // resets it.
    if (status.uploadError != null) {
      uploadFailingSince ??= clock();
    } else {
      uploadFailingSince = null;
    }
    final stats = await db.getUploadQueueStats();
    if (closed) return;
    out.add(
      deriveSyncHealth(
        queued: stats.count,
        lastSyncedAt: status.lastSyncedAt,
        uploadFailingSince: uploadFailingSince,
        uploading: status.uploading,
        drops: drops,
        now: clock(),
      ),
    );
  }

  // Three reasons to re-derive. `ps_crud` changes do not come through
  // statusStream, and neither does the passage of time.
  final subscriptions = <StreamSubscription<void>>[
    db.statusStream.listen((_) => unawaited(emit())),
    db
        .onChange(const [
          'ps_crud',
        ], throttle: const Duration(milliseconds: 300))
        .listen((_) => unawaited(emit())),
    Stream<void>.periodic(_tick).listen((_) => unawaited(emit())),
  ];

  void dispose() {
    closed = true;
    for (final s in subscriptions) {
      unawaited(s.cancel());
    }
    unawaited(out.close());
  }

  out.onCancel = dispose;
  onDispose?.call(dispose);
  unawaited(emit());
  return out.stream;
}
