/// The words for [SyncHealth], shared by the Library and the Shop list. Only
/// the noun differs: "changes" in the Library menu, "ticks" on the list.
///
/// The copy never says "offline" or "failed": it reports waiting and stalled,
/// whatever the cause.
library;

import '../core/sync/sync_health.dart';
import '../core/words.dart';

/// How loud a readout of [SyncHealth] should be.
enum SyncTone {
  /// Everything is up. Muted; a fact, not a status.
  calm,

  /// Something is queued or in flight. Muted, never styled as an error.
  busy,

  /// Stalled past the threshold. Amber, and worth a tap.
  warn,

  /// A write was refused and discarded. The only red one.
  bad,
}

/// One line of copy for [health], in [noun]'s plural where it needs one.
/// `text` is null when there is nothing to say.
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
  // Turns a brief "2 ticks waiting" flicker into visible progress.
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

/// "just now" · "6 min ago" · "14:32" · "yesterday": minutes at first, a wall
/// clock for today, a plain word beyond that.
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
