/// A kitchen timer started from a method step's timer chip. Pure Dart.
///
/// A timer is held by its **end time**, never by a ticking count: every
/// reading takes `now`, so a slept or killed app reads the right number when
/// it wakes. A range runs to its middle (`20–25 min` starts at `22:30`); the
/// cook leans either way with [CookTimer.adjust].
library;

import 'package:meta/meta.dart';

/// How long a due timer sounds before it falls silent. It stays due, and
/// keeps counting its overtime, until it is stopped.
const kTimerRingFor = Duration(minutes: 1);

/// What [CookTimer.adjust] moves a timer by.
const kTimerNudge = Duration(minutes: 1);

/// Where a timer stands at a given moment.
enum CookTimerState { running, paused, due }

@immutable
class CookTimer {
  const CookTimer({
    required this.recipeId,
    required this.recipeTitle,
    required this.step,
    required this.ordinal,
    required this.lowSeconds,
    required this.highSeconds,
    required this.total,
    this.endsAt,
    this.pausedLeft,
  }) : assert(
         (endsAt == null) != (pausedLeft == null),
         'a timer is either running toward an end or paused with time left',
       );

  /// Starts the chip's timer at the middle of its range.
  factory CookTimer.start({
    required String recipeId,
    required String recipeTitle,
    required int step,
    required int ordinal,
    required int lowSeconds,
    required int highSeconds,
    required DateTime now,
  }) {
    final total = Duration(seconds: midpointSeconds(lowSeconds, highSeconds));
    return CookTimer(
      recipeId: recipeId,
      recipeTitle: recipeTitle,
      step: step,
      ordinal: ordinal,
      lowSeconds: lowSeconds,
      highSeconds: highSeconds,
      total: total,
      endsAt: now.add(total),
    );
  }

  factory CookTimer.fromJson(Map<String, Object?> json) {
    final endsAt = json['endsAt'] as int?;
    final pausedLeft = json['pausedLeft'] as int?;
    return CookTimer(
      recipeId: json['recipeId']! as String,
      recipeTitle: json['recipeTitle']! as String,
      step: json['step']! as int,
      ordinal: json['ordinal']! as int,
      lowSeconds: json['low']! as int,
      highSeconds: json['high']! as int,
      total: Duration(milliseconds: json['total']! as int),
      endsAt: endsAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(endsAt, isUtc: true),
      pausedLeft: pausedLeft == null
          ? null
          : Duration(milliseconds: pausedLeft),
    );
  }

  final String recipeId;

  /// The recipe's title when the timer started: the dock names a timer by
  /// it, including after the recipe page is gone.
  final String recipeTitle;

  /// The step's index in the method, from 0.
  final int step;

  /// The timer's place among the step's timer chips, from 0. One step can
  /// print several.
  final int ordinal;

  /// The range the recipe printed, kept so the chip can go back to its words.
  final int lowSeconds;
  final int highSeconds;

  /// What the timer counts down from: the middle of the range, moved by
  /// every [adjust]. The progress wash drains against it.
  final Duration total;

  /// When it is due. Set while it runs; null while paused.
  final DateTime? endsAt;

  /// What was left at the pause. Set while paused; null while it runs.
  final Duration? pausedLeft;

  /// One timer per chip: starting a running chip again opens it instead.
  String get id => timerIdFor(recipeId, step, ordinal);

  bool get paused => pausedLeft != null;

  /// The time left, which goes negative once due: that is the overtime.
  Duration left(DateTime now) => pausedLeft ?? endsAt!.difference(now);

  CookTimerState stateAt(DateTime now) {
    if (paused) return CookTimerState.paused;
    return left(now) <= Duration.zero
        ? CookTimerState.due
        : CookTimerState.running;
  }

  /// Due, and inside its first [kTimerRingFor]: the stretch it sounds.
  bool ringingAt(DateTime now) =>
      stateAt(now) == CookTimerState.due && -left(now) < kTimerRingFor;

  /// The share of [total] still to go, from 1 at the start to 0 when due.
  double remainingShare(DateTime now) {
    if (total <= Duration.zero) return 0;
    final share = left(now).inMilliseconds / total.inMilliseconds;
    return share.clamp(0, 1).toDouble();
  }

  CookTimer pause(DateTime now) {
    if (paused || stateAt(now) == CookTimerState.due) return this;
    return _copy(endsAt: null, pausedLeft: left(now));
  }

  CookTimer resume(DateTime now) {
    final left = pausedLeft;
    if (left == null) return this;
    return _copy(endsAt: now.add(left), pausedLeft: null);
  }

  /// Moves the end by [delta], and [total] with it. Taking time off can make
  /// a timer due at once; it never makes one run backwards past zero. A due
  /// timer given more time runs again from now.
  CookTimer adjust(Duration delta, DateTime now) {
    final before = left(now);
    // Overtime is not banked: +1 min on a due timer is one minute from now.
    final from = before < Duration.zero ? Duration.zero : before;
    var after = from + delta;
    if (after < Duration.zero) after = Duration.zero;
    // A due timer given time starts a fresh count, so its wash drains over
    // what it was just given rather than over the whole of the original.
    var total = before <= Duration.zero ? after : this.total + (after - before);
    if (total < after) total = after;
    return paused
        ? _copy(total: total, endsAt: null, pausedLeft: after)
        : _copy(total: total, endsAt: now.add(after), pausedLeft: null);
  }

  Map<String, Object?> toJson() => {
    'recipeId': recipeId,
    'recipeTitle': recipeTitle,
    'step': step,
    'ordinal': ordinal,
    'low': lowSeconds,
    'high': highSeconds,
    'total': total.inMilliseconds,
    if (endsAt != null) 'endsAt': endsAt!.toUtc().millisecondsSinceEpoch,
    if (pausedLeft != null) 'pausedLeft': pausedLeft!.inMilliseconds,
  };

  CookTimer _copy({
    required DateTime? endsAt,
    required Duration? pausedLeft,
    Duration? total,
  }) => CookTimer(
    recipeId: recipeId,
    recipeTitle: recipeTitle,
    step: step,
    ordinal: ordinal,
    lowSeconds: lowSeconds,
    highSeconds: highSeconds,
    total: total ?? this.total,
    endsAt: endsAt,
    pausedLeft: pausedLeft,
  );

  @override
  bool operator ==(Object other) =>
      other is CookTimer &&
      other.recipeId == recipeId &&
      other.recipeTitle == recipeTitle &&
      other.step == step &&
      other.ordinal == ordinal &&
      other.lowSeconds == lowSeconds &&
      other.highSeconds == highSeconds &&
      other.total == total &&
      other.endsAt == endsAt &&
      other.pausedLeft == pausedLeft;

  @override
  int get hashCode => Object.hash(
    recipeId,
    recipeTitle,
    step,
    ordinal,
    lowSeconds,
    highSeconds,
    total,
    endsAt,
    pausedLeft,
  );
}

/// The key one chip's timer is held under.
String timerIdFor(String recipeId, int step, int ordinal) =>
    '$recipeId:s$step:t$ordinal';

/// The middle of a printed range, to the second.
int midpointSeconds(int lowSeconds, int highSeconds) =>
    (lowSeconds + highSeconds) ~/ 2;

/// The order the dock lists timers in: the ones that need you first. Due
/// timers lead, the longest-due first; then running ones, soonest first;
/// paused ones last, least left first.
List<CookTimer> dockOrder(Iterable<CookTimer> timers, DateTime now) {
  int rank(CookTimer t) => switch (t.stateAt(now)) {
    CookTimerState.due => 0,
    CookTimerState.running => 1,
    CookTimerState.paused => 2,
  };
  return [...timers]..sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    final byLeft = a.left(now).compareTo(b.left(now));
    if (byLeft != 0) return byLeft;
    return a.id.compareTo(b.id);
  });
}

/// A count as a clock: `22:30`, `4:05`, `1:12:00`, and overtime as `+0:42`.
/// Whole seconds, rounded up while counting down so a timer reads `0:01`
/// until it is due, never `0:00` early.
String formatTimerClock(Duration left) {
  final over = left < Duration.zero;
  final ms = left.inMilliseconds.abs();
  final seconds = over ? ms ~/ 1000 : (ms + 999) ~/ 1000;
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  final clock = h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  return over ? '+$clock' : clock;
}

/// A wall-clock time as the sheet and the dock say it: `18:47`.
String formatClockTime(DateTime at) {
  final local = at.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
