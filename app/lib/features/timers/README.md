# Feature: timers

**Plan:** [0050 — timers on the recipe page](../../../../docs/exec-plans/active/0050-recipe-timers.md).

Kitchen timers, started from a method step's timer chip on the recipe page and
held by the app, not the page: a batch afternoon runs the ragù's simmer while
the aioli is open. Nothing here is stored in the database or synced — a timer
is this device's.

## Layout

```
timers/
  domain/         PURE DART
    cook_timer.dart       CookTimer (held by its END TIME, never a ticking
                          count) · dockOrder · formatTimerClock
    timer_platform.dart   TimerPlatform (notifications, chime, buzz, wake
                          lock) · CookTimerStore — both faked in tests
  data/
    timer_providers.dart  CookTimers (the one set, ticking once a second
                          while any is held) · KeepScreenOn ·
                          MethodStepFocus · TimerOpenRequest · WebTabNote
    local_timer_platform.dart   flutter_local_notifications, audioplayers,
                          wakelock_plus; browser_alarm(_web).dart on the web
    shared_prefs_cook_timer_store.dart
  presentation/
    timer_chrome.dart     TimerFrame · TimerBand · TimerDock · TimerRow ·
                          showTimerList · TimerSideList · TimerTabTitle
    timer_sheet.dart      a held timer's sheet
```

The chip itself is drawn by `shared/method_step_text.dart` on
`shared/timer_wash.dart`, the ground every timer is drawn on in its four
states: ready (the recipe's words), running (a herb wash draining), paused
(dashed), due (Gone red, counting overtime).

## The rules

- **A range runs to its middle.** `20–25 min` starts at `22:30`; ±1 min on the
  sheet leans either way. A due timer given +1 min runs a fresh minute.
- **One timer per chip** (`<recipe>:s<step>:t<ordinal>`): tapping a running
  chip opens its sheet rather than starting a second.
- **The end time is the timer.** Every reading takes `now`; the tick only moves
  `now` on screen. The set is kept in `SharedPreferences` so a killed app finds
  it again, and swept on sign-out.
- **It rings for a minute** ([kTimerRingFor]), with one haptic beat as it
  falls due, then stays red and counts its overtime until Stop. A step is never
  struck for you, and the page's ticks are not kept for a timer: they go when
  the page closes, as they always have.
- **Where it shows.** One dock row — the timer that needs you first, as step ·
  the recipe's whole title · count — and **+N** for the rest, which opens the
  list (titles wrap to two lines; one verb each). Above the bar on a tab, at the
  screen's foot on a pushed page (`TimerFrame`, around the shell navigator),
  hidden while the keyboard is up. At `rail` the dock sits at the pane's foot;
  in the full sidebar the list is held open above Account. A due timer raises
  the band at the top of the pane. A title is cut at its end, never shortened
  to a word.

## The device

- **Android:** each running timer schedules a notification at its end (exact
  when the exact-alarm permission is granted, else inexact), insistent for a
  minute on the alarm stream, with +1 min and Stop. One quiet ongoing
  notification counts the soonest down with the OS chronometer. With
  notifications granted the device does the ringing; otherwise the app chimes
  while it runs.
- **iOS:** the same scheduled notification, sounded once; in the foreground the
  app chimes for the minute instead.
- **The web:** nothing can be scheduled. Starting a timer turns Keep screen on
  on (the Screen Wake Lock, taken again when the tab comes back), the tab's
  title counts the soonest down, a hidden tab shows a browser notification when
  one falls due, and the dock says once that a closed tab can't ring.
- Permission is asked on the **first timer started**, never at launch, and
  never twice.
- **Keep screen on** is a session posture in the recipe page's `⋯` menu, with
  a sun beside the `⋯` (and on the dock) while it holds.
