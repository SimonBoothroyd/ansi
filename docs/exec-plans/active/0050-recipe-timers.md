# Exec plan: Timers on the recipe page

- **Status:** built on `claude/recipe-view-timers-rfva7e` — tests, analyze and the web build pass; the Android and iOS native setup has not been compiled yet (CI builds them only on a release tag) and nothing has run on a phone
- **Owner:** Simon (design and rulings), agents in lanes
- **Roadmap step:** Next 1 — the next idea off the backlog
- **Created:** 2026-10-08

## Goal

Cook from the recipe page that already exists rather than a separate cook
mode. The page already rules steps and chips off while you cook; what it lacks
is the clock. Every method already stores its durations as `timer` tokens
(`lowSeconds`, `highSeconds`), so this needs no prose read and no schema
change.

Drawn, and now built, in
[recipe-page.html](../../product-specs/board/recipe-page.html) (the chip, its
sheet, a timer going off, keeping the screen on) and
[navigation.html](../../product-specs/board/navigation.html) (the dock across
the app, the locked phone, the web, the wide sidebar).

## Rulings so far

- **A range runs to its middle.** `20–25 min` starts at `22:30`. The chip
  prints the recipe's own words until it is tapped; the sheet's `+1 min` and
  `−1 min` are the way to lean either side. *"I think for ranges use the
  middle of the range."* — the owner, 2026-10-08.
- **A timer chip's tap starts it.** It was deliberately inert ("a duration is
  not a thing you add"); that tap is now the start. A tap on a running chip
  opens its sheet. A timer chip is never ruled off, even inside a struck step:
  the cook often strikes "simmer for 20 min" at the moment it starts.
- **Timers belong to the app, not the page.** They outlive the recipe page:
  a batch afternoon runs the ragù's simmer while the aioli is open. Each one
  is labelled by recipe and step, and is held by its **end time**, never by a
  ticking count, so a slept or killed app reads the right number on return.
- **One dock, everywhere — one row, the whole title.** While any timer runs,
  the dock sits at the foot of every screen: above the bar on a tab, at the
  screen's foot on a pushed page. Collapsed it is one full-width row — the
  timer that needs you first (due, else soonest) as step · title · count —
  and **+N** opens a list of every timer, each title whole on up to two
  lines, with Stop or pause beside its count. On wide the sidebar holds that
  list, always open. A title is cut at its end with an ellipsis, never
  shortened to a word: *"most recipe names are pretty long"* — the owner,
  2026-10-08, and *Slow-Cooker* or *Sticky* name nothing. A row's tap opens
  that recipe's Method at that step.
- **A timer survives the phone sleeping.** Native: a scheduled local
  notification at the end time, with *Stop* and *+1 min*; Android also keeps
  one ongoing notification counting the soonest timer down.
- **Keep screen on** is a separate, explicit posture: one item in the recipe
  page's ⋯ menu, a sun glyph in the bar while it holds. *"Keeping this alive
  when sleeping, and also adding a no sleep mode, is definitely a big
  plus."* — the owner, 2026-10-08.
- **Not synced.** A timer is this phone's: two cooks, two kitchens' worth of
  clocks. Nothing is written to the database.

## The web, honestly

A browser cannot ring from a closed tab, and it suspends a page whose screen
has slept. So on the web:

- Starting a timer **turns Keep screen on on by itself** (the Screen Wake
  Lock API, via `wakelock_plus`), re-acquired when the tab becomes visible
  again, because a sleeping screen is a silent timer.
- The tab's title counts the soonest timer down (`⏱ 4:12 · Ansi`), so a
  desk with other tabs open still sees it.
- If the browser grants notifications, a hidden tab shows one at the end
  time. A throttled hidden tab may be up to a minute late; the end time keeps
  the number right regardless.
- The sound is primed by the tap that started the timer, which is the user
  gesture autoplay rules want.
- What the web cannot do is said once, in the dock, the first time: *keep
  this tab open — a closed tab can't ring*. There is no server push to cover
  it; a two-person household does not need a push service for a kitchen
  timer.

## Rulings on the open questions

The owner, 2026-10-08 — first *"yes to all three, go ahead and build it"*,
then, on seeing it built, the first one reversed (*"No they shouldn't"*):

- **The struck set stays the page's.** Crossed-off steps go when the page
  closes, as before this plan, even while one of that recipe's timers runs.
  (It was briefly held per recipe for as long as a timer ran; that was taken
  out.)
- **It rings for a minute**, then the chip and its dock row stay red and keep
  counting overtime silently until Stop.
- **Permission is asked on the first timer started**, not at launch, and never
  twice. On Android the same first start asks for the exact-alarm permission
  when it is not already granted (it opens a system settings page on Android
  14+); without it the ring is scheduled inexactly.

## Decisions made while building

- **Notification actions open the app.** Stop and +1 min are foreground
  actions, so they act on the one set of timers in the running app rather than
  on a copy in a background isolate.
- **Android rings through the notification**: insistent on the alarm stream,
  withdrawn after the minute; the app does not chime over it. Where
  notifications are refused, and on iOS in the foreground, and on the web, the
  app chimes for the minute itself (`assets/sounds/timer_chime.wav`, generated
  for this app).
- **The web does not use the notification plugin's service worker**, which
  would replace the app's own; a hidden tab uses the browser's `Notification`
  directly, and Chrome on Android, which allows only service-worker
  notifications, gets the chime and the tab title.
- **No flash on arrival.** `?step=N` opens the method scrolled to the step; the
  frame's "chip flashing once" was dropped as unneeded.

## Acceptance criteria

Phase one — on the page and across the app:

- [x] A pure-Dart timer model (`features/timers/domain`): start at
      the midpoint, pause, resume, ±1 min, overtime, ordered by end time —
      tested.
- [x] An app-wide store held by end time, persisted locally so a killed app
      restores its timers.
- [x] The chip's four states (ready, running, paused, done) in
      `method_step_text.dart`; the sheet; the done banner with sound and
      haptics.
- [x] The dock in the shell, on every route: the one row, +N, and the
      opened list; a row's tap opens the recipe's Method at the step.
- [x] Keep screen on in the ⋯ menu.

Phase two — asleep and on the web:

- [x] Scheduled local notifications with *Stop* and *+1 min*; the Android
      ongoing notification; the exact-alarm permission handled as Play allows.
- [x] The web: wake lock on start, the counting tab title, the hidden-tab
      notification, the one-time *keep this tab open* line.
- [x] The board's frames move from `proposed` to built; the recipe page's
      "Timers are not tappable" note is deleted with the frames it replaces.

Before this plan moves to `completed/`:

- [ ] The release build compiles the Android setup (desugaring, receivers,
      `ic_stat_timer`) and the iOS one (the notification delegate).
- [ ] On a phone: a timer rings with the screen locked and with the app
      killed; Stop and +1 min work from the notification; the exact-alarm ask
      on Android 14+ reads as reasonable.
- [ ] On the web: the tab title counts, the wake lock holds, the chime sounds
      in a background tab.
