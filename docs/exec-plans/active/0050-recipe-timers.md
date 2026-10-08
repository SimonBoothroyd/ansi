# Exec plan: Timers on the recipe page

- **Status:** proposed — frames drawn on the board, nothing built
- **Owner:** Simon (design and rulings), agents in lanes
- **Roadmap step:** Next 1 — the next idea off the backlog
- **Created:** 2026-10-08

## Goal

Cook from the recipe page that already exists rather than a separate cook
mode. The page already rules steps and chips off while you cook; what it lacks
is the clock. Every method already stores its durations as `timer` tokens
(`lowSeconds`, `highSeconds`), so this needs no prose read and no schema
change.

Drawn as `proposed` frames in
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
- **One dock, everywhere.** A row of timer pills sits at the foot of every
  screen while any timer runs — above the bar on a tab, at the screen's foot
  on a pushed page, in the sidebar on wide. A pill's tap opens that recipe's
  Method at that step.
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

## Open questions

- **The struck set's lifetime.** Today it is "this reading of this page" and
  clears when the page closes. With timers outliving the page, returning via
  the dock to a running simmer finds every step un-struck. Proposed: hold the
  struck set in memory per recipe while the app runs (still never stored or
  synced), cleared when that recipe has no running timer and its page closes.
- **How long it rings.** Proposed: the sound repeats for a minute, then the
  chip and the pill stay red and keep counting overtime silently.
- **When to ask for notification permission.** Proposed: on the first timer
  started, not at launch.

## Acceptance criteria (a sketch until the rulings settle)

Phase one — on the page and across the app:

- [ ] A pure-Dart timer model (`core/timers` or `recipes/domain`): start at
      the midpoint, pause, resume, ±1 min, overtime, ordered by end time —
      tested.
- [ ] An app-wide store held by end time, persisted locally so a killed app
      restores its timers.
- [ ] The chip's four states (ready, running, paused, done) in
      `method_step_text.dart`; the sheet; the done banner with sound and
      haptics.
- [ ] The dock in the shell, on every route; a pill's tap opens the recipe's
      Method at the step.
- [ ] Keep screen on in the ⋯ menu.

Phase two — asleep and on the web:

- [ ] Scheduled local notifications with *Stop* and *+1 min*; the Android
      ongoing notification; the exact-alarm permission handled as Play allows.
- [ ] The web: wake lock on start, the counting tab title, the hidden-tab
      notification, the one-time *keep this tab open* line.
- [ ] The board's frames move from `proposed` to built; the recipe page's
      "Timers are not tappable" note is deleted with the frames it replaces.
