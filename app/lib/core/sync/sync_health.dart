/// Whether this phone's writes are reaching the other one — as ONE provider,
/// quiet until it is not.
///
/// PowerSync publishes `connected · uploading · lastSyncedAt · hasSynced ·
/// uploadError · downloadError`, and `getUploadQueueStats()` knows the queue
/// depth. This file is the one place that reads them, so there is exactly one
/// answer anywhere in the app to "has my week left the device".
///
/// **Four states, and only four** ([SyncHealth]). The distinction that matters
/// most is between *waiting* and *stalled*: this app is offline-first by
/// design, so a queue is the system working, and styling it as a problem would
/// be the one thing Ansi must never do. The word "offline" appears nowhere in
/// what any of this renders — being offline is not a state the app reports.
///
/// Every readout — the Library `⋯` menu's footer line, the Shop list's status
/// line, the shell's banner — watches [syncHealthProvider]. They cannot
/// disagree, because there is nothing for them to disagree about.
library;

import 'dart:async';

import 'package:powersync/powersync.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'database.dart';
import 'dropped_write.dart';

part 'sync_health.g.dart';

/// How long uploads must have been getting nowhere before the app says so.
///
/// Deliberately minutes, not seconds: a token refresh, a backgrounded app and
/// a lift ride all produce upload errors that heal themselves within seconds,
/// and a banner for those is a banner nobody reads. And a threshold rather
/// than a count, because one op failing for an hour is worse than fifty ops
/// queued for ten seconds.
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

/// Writes are queued and nothing is wrong. **Not an error**: the app is
/// offline-first, and a queue draining a minute from now is the design working.
/// Rendered muted, never red, never with a warning icon.
final class SyncWaiting extends SyncHealth {
  const SyncWaiting({
    required this.queued,
    this.uploading = false,
    this.lastSyncedAt,
  });

  final int queued;

  /// PowerSync is pushing right now. Not a fifth state — a display flourish,
  /// worth drawing only where someone is standing still watching for it.
  final bool uploading;
  final DateTime? lastSyncedAt;
}

/// Uploads have been getting nowhere for longer than [stallThreshold].
/// Retryable in principle; it just hasn't been working.
final class SyncStalled extends SyncHealth {
  const SyncStalled({required this.queued, required this.since});

  final int queued;

  /// When the writes stopped landing — see [deriveSyncHealth] for why this is
  /// the *earlier* of "last successful sync" and "uploads started failing".
  final DateTime since;
}

/// A transaction was refused and discarded. Data loss, and the only state that
/// bypasses the threshold entirely.
final class SyncRefused extends SyncHealth {
  const SyncRefused(this.drops);

  final List<DroppedWrite> drops;
}

/// Turns the three inputs into one state. Pure, so the words the app says can
/// be pinned by a unit test rather than by a running sync engine.
///
/// **Which clock the stall runs on.** `ps_crud` carries no timestamps, so the
/// age of the oldest queued op is not knowable; two things are. `lastSyncedAt`
/// says when anything last got through, and [uploadFailingSince] says when the
/// current run of upload errors began. The stall clock takes the **earlier**
/// of the two, which is what makes both cases right:
///
/// * A cold start with a three-day-old queue has a three-day-old
///   `lastSyncedAt`, so the banner shows immediately rather than five minutes
///   after launch.
/// * An app whose downloads are healthy keeps refreshing `lastSyncedAt`, so
///   the failing-uploads clock governs and the threshold does its job.
SyncHealth deriveSyncHealth({
  required int queued,
  required DateTime? lastSyncedAt,
  required DateTime? uploadFailingSince,
  required DateTime now,
  List<DroppedWrite> drops = const [],
  bool uploading = false,
  Duration threshold = stallThreshold,
}) {
  // Loss outranks everything: it is the one state waiting cannot resolve.
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

/// The app's single answer to "are my changes getting through?".
///
/// Keep-alive: the banner and the two quiet lines live on different screens,
/// and the "since" timestamp must survive a tab switch.
@Riverpod(keepAlive: true)
Stream<SyncHealth> syncHealth(Ref ref) {
  final db = ref.watch(powerSyncDatabaseProvider);
  final drops = ref.watch(droppedWritesProvider);
  return watchSyncHealth(db, drops: drops, onDispose: ref.onDispose);
}

/// [syncHealthProvider]'s body, with the database passed in so a test can drive
/// it against a real PowerSync queue without a provider container.
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
    // The run of failures, not this one: a cleared error resets the clock, so
    // a token refresh that heals itself never accumulates toward the banner.
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

  // Three reasons to re-derive. `ps_crud` changes do NOT come through
  // statusStream — PowerSync drives its own upload trigger off exactly this
  // watch — and neither does the passage of time, which is what turns waiting
  // into stalled.
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
