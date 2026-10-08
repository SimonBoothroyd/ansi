/// What a timer asks of the device: an alarm that outlives the app, a chime
/// while it is open, a buzz, and a screen kept awake. Pure Dart; the
/// implementation is `data/local_timer_platform.dart` and tests fake it.
library;

import 'cook_timer.dart';

/// What the cook did to a timer's notification.
enum TimerActionKind {
  /// Tapped its body: open the recipe at the step.
  open,

  /// Its Stop button.
  stop,

  /// Its +1 min button.
  addMinute,
}

class TimerAction {
  const TimerAction(this.kind, this.timerId);

  final TimerActionKind kind;
  final String timerId;
}

abstract interface class TimerPlatform {
  /// Running in a browser, where a closed tab cannot ring and a slept screen
  /// is a silent one.
  bool get isWeb;

  /// Whether a due timer sounds through the device's own notification for
  /// the whole ring, so the app must not chime over it. True only where the
  /// notification was granted and can repeat its sound (Android).
  bool get ringsItself;

  /// Prepares the device and reports what the cook does to a notification,
  /// including the one that launched the app.
  Future<void> init({required void Function(TimerAction action) onAction});

  /// Asks for what a timer needs to ring with the phone asleep. Asked on the
  /// first timer started, and never again on this device.
  Future<void> askOnce();

  /// Brings the device's alarms in line with [timers]: each running timer
  /// rings at its end, and every other one is withdrawn — a stopped timer's
  /// notification included, which silences it.
  Future<void> sync(List<CookTimer> timers, DateTime now);

  /// Says a timer just became due where the device cannot have scheduled it
  /// (a hidden browser tab).
  Future<void> announceDue(CookTimer timer);

  /// Starts the in-app chime, repeating until [hush].
  Future<void> chime();

  Future<void> hush();

  /// One haptic beat as a timer becomes due.
  Future<void> buzz();

  Future<void> keepAwake({required bool on});
}

/// Where the timers are kept between launches on this device.
abstract interface class CookTimerStore {
  Future<List<CookTimer>> read();

  Future<void> write(List<CookTimer> timers);
}
