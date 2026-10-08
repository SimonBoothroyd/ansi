/// The app's timers, held once for every screen: the dock, the chips, the
/// band and the sidebar all read [CookTimers]. Also the method's ticks
/// ([MethodTicks]), which live as long as a recipe has a timer running, and
/// Keep screen on ([KeepScreenOn]).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/sync/device_prefs.dart';
import '../domain/cook_timer.dart';
import '../domain/timer_platform.dart';
import 'local_timer_platform.dart';
import 'shared_prefs_cook_timer_store.dart';

part 'timer_providers.g.dart';

/// The device: notifications, chime, haptics, wake lock.
@Riverpod(keepAlive: true)
TimerPlatform timerPlatform(Ref ref) => LocalTimerPlatform();

/// Where the timers survive a killed app.
@Riverpod(keepAlive: true)
CookTimerStore cookTimerStore(Ref ref) => SharedPrefsCookTimerStore();

/// What time it is. Tests pin it.
@Riverpod(keepAlive: true)
DateTime Function() timerClock(Ref ref) => DateTime.now;

/// Every timer, and the moment they were last read at.
@immutable
class CookTimersState {
  const CookTimersState({required this.byId, required this.now});

  final Map<String, CookTimer> byId;

  /// The tick: every reading of a count takes it, so one rebuild a second
  /// moves every count on screen together.
  final DateTime now;

  bool get isEmpty => byId.isEmpty;

  /// The dock's order: what needs you first.
  List<CookTimer> get docked => dockOrder(byId.values, now);

  /// The ones due and not yet stopped, longest-due first.
  List<CookTimer> get due => [
    for (final t in docked)
      if (t.stateAt(now) == CookTimerState.due) t,
  ];

  CookTimer? operator [](String id) => byId[id];

  bool hasTimersFor(String recipeId) =>
      byId.values.any((t) => t.recipeId == recipeId);
}

/// A request to open a timer's step, from its notification. The shell
/// navigates and clears it.
@Riverpod(keepAlive: true)
class TimerOpenRequest extends _$TimerOpenRequest {
  @override
  CookTimer? build() => null;

  /// A verb rather than a setter, so the call site says what it asks for.
  // ignore: use_setters_to_change_properties
  void ask(CookTimer timer) => state = timer;

  void clear() => state = null;
}

/// A request for a recipe page already on screen to show one of its steps:
/// a dock row tapped on that recipe's own page scrolls rather than pushing
/// the page again. The serial makes a second tap on the same step a new ask.
typedef StepFocus = ({String recipeId, int step, int serial});

@Riverpod(keepAlive: true)
class MethodStepFocus extends _$MethodStepFocus {
  @override
  StepFocus? build() => null;

  void focus(String recipeId, int step) => state = (
    recipeId: recipeId,
    step: step,
    serial: (state?.serial ?? 0) + 1,
  );
}

/// Whether the dock says the web's one limit — a closed tab cannot ring.
/// Said the first time a timer starts in this browser, and not again.
@Riverpod(keepAlive: true)
class WebTabNote extends _$WebTabNote {
  @override
  bool build() => false;

  Future<void> consider() async {
    if (state || !ref.read(timerPlatformProvider).isWeb) return;
    final prefs = await SharedPreferences.getInstance();
    const key = '${DevicePrefs.timerAlarmPrefix}web_note_said';
    if (prefs.getBool(key) ?? false) return;
    await prefs.setBool(key, true);
    if (ref.mounted) state = true;
  }
}

@Riverpod(keepAlive: true)
class CookTimers extends _$CookTimers {
  Timer? _tick;

  /// What was ringing at the last tick, so a timer buzzes once as it falls
  /// due rather than every second after.
  Set<String> _ringing = const {};

  /// Set when the cook acts before the stored timers have come back, so the
  /// restore does not undo it.
  bool _touched = false;

  TimerPlatform get _platform => ref.read(timerPlatformProvider);

  DateTime _now() => ref.read(timerClockProvider)();

  @override
  CookTimersState build() {
    ref.onDispose(() {
      _tick?.cancel();
      _tick = null;
    });
    unawaited(_restore());
    return CookTimersState(byId: const {}, now: _now());
  }

  Future<void> _restore() async {
    await _platform.init(onAction: _onAction);
    final List<CookTimer> stored;
    try {
      stored = await ref.read(cookTimerStoreProvider).read();
      // A device whose storage cannot be read starts with no timers rather
      // than none of the app.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      debugPrint('timers: could not restore: $error');
      return;
    }
    if (!ref.mounted || _touched || stored.isEmpty) return;
    _commit({for (final t in stored) t.id: t}, persist: false);
  }

  /// Starts a chip's timer at the middle of its range. A chip whose timer is
  /// already held is left as it is: its sheet is the door to it.
  void start({
    required String recipeId,
    required String recipeTitle,
    required int step,
    required int ordinal,
    required int lowSeconds,
    required int highSeconds,
  }) {
    final id = timerIdFor(recipeId, step, ordinal);
    if (state.byId.containsKey(id)) return;
    final timer = CookTimer.start(
      recipeId: recipeId,
      recipeTitle: recipeTitle,
      step: step,
      ordinal: ordinal,
      lowSeconds: lowSeconds,
      highSeconds: highSeconds,
      now: _now(),
    );
    _commit({...state.byId, id: timer});
    unawaited(_platform.askOnce());
    // A browser that sleeps is a silent one.
    if (_platform.isWeb) {
      ref.read(keepScreenOnProvider.notifier).hold();
      unawaited(ref.read(webTabNoteProvider.notifier).consider());
    }
  }

  void pause(String id) => _update(id, (t, now) => t.pause(now));

  void resume(String id) => _update(id, (t, now) => t.resume(now));

  void adjust(String id, Duration delta) =>
      _update(id, (t, now) => t.adjust(delta, now));

  void stop(String id) {
    if (!state.byId.containsKey(id)) return;
    _commit({...state.byId}..remove(id));
  }

  void _update(String id, CookTimer Function(CookTimer, DateTime) change) {
    final timer = state.byId[id];
    if (timer == null) return;
    _commit({...state.byId, id: change(timer, _now())});
  }

  void _commit(Map<String, CookTimer> byId, {bool persist = true}) {
    _touched = true;
    final now = _now();
    state = CookTimersState(byId: Map.unmodifiable(byId), now: now);
    final timers = byId.values.toList();
    if (persist) {
      unawaited(
        ref
            .read(cookTimerStoreProvider)
            .write(timers)
            .catchError((Object e) => debugPrint('timers: not kept: $e')),
      );
    }
    unawaited(_platform.sync(timers, now));
    _ring(now);
    if (byId.isEmpty) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    }
  }

  void _onTick() {
    final now = _now();
    state = CookTimersState(byId: state.byId, now: now);
    _ring(now);
  }

  /// Buzzes as a timer falls due, and chimes through the ring when the
  /// device will not.
  void _ring(DateTime now) {
    final ringing = {
      for (final t in state.byId.values)
        if (t.ringingAt(now)) t.id,
    };
    for (final id in ringing.difference(_ringing)) {
      unawaited(_platform.buzz());
      unawaited(_platform.announceDue(state.byId[id]!));
    }
    final wasRinging = _ringing.isNotEmpty;
    _ringing = ringing;
    if (ringing.isNotEmpty && !_platform.ringsItself) {
      if (!wasRinging) unawaited(_platform.chime());
    } else if (wasRinging && ringing.isEmpty) {
      unawaited(_platform.hush());
    }
  }

  void _onAction(TimerAction action) {
    final timer = state.byId[action.timerId];
    switch (action.kind) {
      case TimerActionKind.stop:
        stop(action.timerId);
      case TimerActionKind.addMinute:
        adjust(action.timerId, kTimerNudge);
      case TimerActionKind.open:
        if (timer != null) {
          ref.read(timerOpenRequestProvider.notifier).ask(timer);
        }
    }
  }
}

/// What the cook has ticked off in each recipe's method: positional keys,
/// `s2` for a step and `s2:c0` for its first chip.
///
/// Never stored, never synced. A recipe's ticks are dropped when its page
/// closes, unless one of its timers is still held; then they wait for that
/// timer, so coming back through the dock finds the page as it was left.
@Riverpod(keepAlive: true)
class MethodTicks extends _$MethodTicks {
  final Map<String, int> _open = {};

  @override
  Map<String, Set<String>> build() {
    ref.listen(cookTimersProvider, (_, timers) => _release(timers));
    return const {};
  }

  void toggle(String recipeId, String key) {
    final ticks = {...?state[recipeId]};
    if (!ticks.remove(key)) ticks.add(key);
    state = {...state, recipeId: ticks};
  }

  /// A page for [recipeId] has opened.
  void opened(String recipeId) =>
      _open.update(recipeId, (n) => n + 1, ifAbsent: () => 1);

  /// A page for [recipeId] has closed. Called from a widget's teardown,
  /// where a provider must not change, so the drop waits a microtask.
  void closed(String recipeId) {
    final n = (_open[recipeId] ?? 1) - 1;
    if (n <= 0) {
      _open.remove(recipeId);
    } else {
      _open[recipeId] = n;
    }
    scheduleMicrotask(() {
      if (ref.mounted) _release(ref.read(cookTimersProvider));
    });
  }

  void _release(CookTimersState timers) {
    final keep = {
      for (final entry in state.entries)
        if (_open.containsKey(entry.key) || timers.hasTimersFor(entry.key))
          entry.key: entry.value,
    };
    if (keep.length != state.length) state = keep;
  }
}

/// Keep screen on: a posture held for the session, across recipes, until it
/// is turned off or the app closes. On the web a timer's start holds it too.
@Riverpod(keepAlive: true)
class KeepScreenOn extends _$KeepScreenOn {
  AppLifecycleListener? _lifecycle;

  @override
  bool build() {
    // A browser drops the lock whenever the tab is hidden; take it again on
    // the way back.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (!state) return;
        unawaited(ref.read(timerPlatformProvider).keepAwake(on: true));
      },
    );
    ref.onDispose(() => _lifecycle?.dispose());
    return false;
  }

  void toggle() => _set(on: !state);

  void hold() {
    if (!state) _set(on: true);
  }

  void _set({required bool on}) {
    state = on;
    unawaited(ref.read(timerPlatformProvider).keepAwake(on: on));
  }
}
