/// The words for [SyncHealth] — written once, so the Library and the Shop list
/// cannot say different things about the same fact.
///
/// The only thing that differs between the two readouts is the **noun**:
/// "changes" in the Library `⋯` menu, "ticks" on the shopping list, because on
/// that screen the thing at stake is a check-off and the other person is
/// already in the user's head.
///
/// Two words never appear here. **"Offline"** — being offline is not a state
/// this app reports; it reports waiting (fine) and stalled (not fine), and both
/// are true whether the cause is a tunnel, an expired token or a 502. And
/// **"failed"** — a person can act on "aren't reaching the other phone" and
/// cannot act on "failed".
library;

import '../core/sync/sync_health.dart';
import '../core/words.dart';

/// How loud a readout of [SyncHealth] should be.
enum SyncTone {
  /// Everything is up. Muted; a fact, not a status.
  calm,

  /// Something is queued or in flight. Still muted — **never** styled as an
  /// error, because a queue is the offline-first design working.
  busy,

  /// Stalled past the threshold. Amber, and worth a tap.
  warn,

  /// A write was refused and discarded. The only red one.
  bad,
}

/// One line of copy for [health], in [noun]'s plural where it needs one.
///
/// The returned `text` is null where the honest answer is to say nothing at
/// all — a screen with no news should show no line.
({String? text, SyncTone tone}) syncLine(
  SyncHealth health, {
  required DateTime now,
  String noun = 'change',
}) => switch (health) {
  SyncSettled(:final lastSyncedAt) => (
    text: lastSyncedAt == null
        ? 'Not synced yet'
        : 'Synced · ${relativeSyncTime(lastSyncedAt, now)}',
    tone: SyncTone.calm,
  ),
  // Drawn only because the user is standing still watching for it: it turns a
  // half-second flicker of "2 ticks waiting" into something that reads as
  // progress.
  SyncWaiting(uploading: true) => (text: 'Sending…', tone: SyncTone.busy),
  SyncWaiting(:final queued) => (
    text: '$queued ${plural(queued, noun)} waiting',
    tone: SyncTone.busy,
  ),
  SyncStalled(:final since) => (
    text:
        '${_capitalized(plural(2, noun))} aren’t reaching the other phone · '
        'since ${clockTime(since)}',
    tone: SyncTone.warn,
  ),
  SyncRefused(:final drops) => (
    text: drops.length == 1
        ? 'One $noun couldn’t be saved to the server'
        : '${drops.length} ${plural(drops.length, noun)} couldn’t be saved '
              'to the server',
    tone: SyncTone.bad,
  ),
};

/// "just now" · "6 min ago" · "14:32" · "yesterday".
///
/// Minutes while the answer is still "a moment ago", a wall clock for today
/// (which is what someone comparing two phones actually wants), and a plain
/// word beyond that.
String relativeSyncTime(DateTime at, DateTime now) {
  final elapsed = now.difference(at);
  if (elapsed.inSeconds < 60) return 'just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
  if (elapsed.inHours < 24 && at.day == now.day) return clockTime(at);
  if (elapsed.inHours < 48) return 'yesterday';
  return '${elapsed.inDays} days ago';
}

/// 24-hour wall clock, zero-padded: `14:02`.
String clockTime(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';

String _capitalized(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
