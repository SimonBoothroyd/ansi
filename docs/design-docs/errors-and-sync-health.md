# Errors & sync health

How Ansi tells you something went wrong — and, just as deliberately, everything
it stays quiet about.

The front that produced this doc started from an audit of **83 error paths**
across nine features. Eleven were honest: the user learned something true and
could act on it. Seventy-two were not — swallowed, logged to a console no phone
has, rendered as a reasonless sentence, or, worst, rendered as a **fact** (an
empty list, a zero) that the rest of the app then believed.

The app was never careless; it was inconsistent. Six surfaces were already
excellent — the barcode failure panel, the import intake form, the ingredient
delete refusal with its count, the connecting screen, the measure editor's
inline refusal, the USDA lookup's four outcome sentences. Every one was built
when a *specific* failure was designed for. What was missing was the
**default**: what happens to a failure nobody designed for.

---

## The rule

> **A toast reports an act. A banner reports a state.**
>
> If the user did something and it didn't happen — **toast**, with Retry.
> If something is *currently* wrong and stays wrong until acted on —
> **banner**, until it isn't wrong any more.

| event | surface |
|---|---|
| a user-initiated write threw | **toast**, destructive, with Retry |
| a screen's data didn't load | **the shared error state**: what · why · Try again |
| writes are queued, nothing wrong | **the quiet line only** — this is not an error |
| uploads stalled past the threshold | **banner**, plus the quiet lines turn amber |
| a write was refused and discarded | **banner**, red, with the detail behind it |
| an unhandled exception | **toast**, quiet, primary, with Copy details |
| offline | **nothing.** See "What we don't say". |

---

## One door for every write

`app/lib/shared/write.dart`. Every repository write reached from a widget goes
through `ref.write(context, what, action)`.

```dart
onPress: () => ref.write(
  context,
  'delete that section',
  () => repo.deleteSection(section.id),
),
```

It awaits the action and returns its value; on a throw it shows
*"Couldn't &lt;what&gt;."* with a Retry that **re-runs** the action, and returns
null. It never rethrows, so adopting it changed control flow nowhere. `writeOk`
is the same door for a `Future<void>` whose caller must still branch — closing
the sheet it was started from, navigating on — because `T?` cannot carry success
when `T` is `void`, and a sheet that pops on a write that never landed is the
exact confusion this front exists to end.

**It takes a closure, not a future**, and that is the whole reason Retry can
exist: a future is already running and can only be awaited again.

`what` is a lowercase verb phrase in the user's own noun completing
*"Couldn't ___."* — "save the recipe", "add Tuesday's meal", "tick Paper
towels". Never a table name, never a method name, never an exception.

**The rule is mechanical.** `app/test/structure/no_bare_repo_write_test.dart`
derives the write set from the `domain/*_repository.dart` interfaces — so a
method added tomorrow is covered the day it is *declared* — and fails the build
on a bare `repo.foo()` under any `features/*/presentation/`. Deliberate
exceptions live in an allow-list with a one-line reason each. The check is a
regex over source text and says so in its own doc comment: it exists to stop the
ordinary omission, the one that happened 37 times, not a determined author.

---

## Sync health: four states, one provider

`app/lib/core/sync/sync_health.dart`. PowerSync has always published
`connected · uploading · lastSyncedAt · uploadError`, and `getUploadQueueStats()`
has always known the queue depth. Before this front, nothing in the app read any
of it.

| state | what it means | what it says |
|---|---|---|
| `SyncSettled` | the queue is empty | *Synced · just now* / *Synced · 14:32* |
| `SyncWaiting` | writes are queued, nothing wrong | *3 changes waiting* · *Sending…* |
| `SyncStalled` | uploads getting nowhere past the threshold | *Changes aren't reaching the other phone · since 14:02* |
| `SyncRefused` | a write was refused and **discarded** | *One change couldn't be saved to the server* |

The distinction that carries the whole design is **waiting** vs **stalled**.
This app is offline-first by construction — the session connects from cache with
no round-trip — so a queue is the system working, and styling it as a problem
would be the one thing Ansi must never do. It is muted, never red, never a
warning icon, and there are no per-row pending marks anywhere.

**The threshold is five minutes.** Minutes, not seconds: a token refresh, a
backgrounded app and a lift ride all produce upload errors that heal themselves,
and a banner for those is a banner nobody reads. A threshold rather than a
count, because one op failing for an hour is worse than fifty queued for ten
seconds.

**Which clock it runs on** took the most thought. `ps_crud` carries no
timestamps, so the age of the oldest queued op is not knowable. Two things are:
`lastSyncedAt` (when anything last got through) and when the current run of
upload errors began. The stall clock takes the **earlier** of the two, which
gets both cases right — a cold start with a three-day-old queue shows the banner
immediately rather than five minutes after launch, and an app whose downloads
are healthy keeps refreshing `lastSyncedAt` so the failing-uploads clock governs
and the threshold does its job.

### The refused write

`connector.dart` discards a transaction the server refuses with a fatal
PostgREST code (22xxx data, 23xxx integrity, 42xxx access — `42501` is RLS
denied). Dropping is the right engineering call: a poison write must not wedge
the queue forever. But it is the **one place in Ansi where data is genuinely
lost** — the row is on this phone, on no server and on no other device — and it
used to be a `debugPrint` beside a comment reading *"never let it be silent"*.

It now also reports to a `DroppedWriteSink`, persisted, because a divergence
that vanishes when you close the app is still silent. The banner's *What
happened* names the table, the operation and the server's code: the same string
the console line carries, shown to the person it happened to.

### Three readouts, one provider

They cannot disagree, because there is nothing to disagree about.

- **The shell's banner** — hosted once by `ansi_tab_shell.dart`, above the
  routed child, never per screen. That is what makes "changes aren't reaching
  the other phone" a fact about the app rather than about whichever tab is open.
- **The Library `⋯` menu's footer line** — findable when wondered about,
  invisible when not, which is the right weight for a fact that is boring 99.9%
  of the time. It moves to `/account` whole the day a second thing wants to live
  there.
- **The Shop list's own line**, under the header and outside the scroll. Shop is
  the one screen two phones drive simultaneously, in a supermarket, walking
  apart — a tick that has not reached the other phone is the feature failing in
  the aisle, in exactly the place where connectivity is worst. Same provider,
  same thresholds; only the **noun** changes, to *ticks*, because on that screen
  the thing at stake is a check-off and the other person is already in the
  user's head. After the queue drains it says *Synced · just now* for a few
  seconds and retires itself; a grocery list does not carry a status bar.

---

## One error state

`app/lib/shared/ansi_error_state.dart` replaced six copies of *"Could not load
the X."* — each of which threw the exception it had been handed into a
`debugPrint` and offered no reason and no way out. It says three things, in the
order a person asks them in:

```
Couldn't load the week.
the server didn't answer in time
[Try again]  [Copy details]
```

The reason is **mapped** (`describe_failure.dart`), never a raw `toString()`:
that is a developer's sentence in a user's face. The raw text is kept, behind
Copy details, where it is useful to whoever is being texted about the problem.

### Emptiness that is load-bearing

> `asData?.value ?? const []` is banned where the emptiness is load-bearing.
> If "empty" and "we don't know" lead the user to different conclusions, the
> screen must distinguish them.

This class has already shipped as a real bug once. Four sites were load-bearing
and are now real error states — the "used in" back-links (whose count the delete
refusal speaks), the stub badge on the Library's Ingredients item, and the
per-ingredient measures in two places, where an errored stream silently narrowed
which units a line may be written in. The rest are decorative and keep their
fallback, each with a one-line comment saying why, so the next reader knows the
difference was weighed rather than skipped.

---

## Unhandled exceptions

`app/lib/core/observability/crash_sink.dart`. The zone handler used to be a
`debugPrint` under a `TODO(observability)`; on a phone in release there is no
console, so it was functionally `catch {}`.

Making it visible is only tolerable *after* the write sweep: whatever still
reaches the handler is a genuine bug rather than an ordinary failure. It shows a
quiet, primary toast — *"Something went wrong. Ansi kept going. [Copy
details]"* — rate-limited to one per ten seconds. The *reports* are not
limited, only the toasts: Copy details is read when it is tapped, so one toast
carries a whole burst.

**No reporting service, deliberately.** Sentry or Crashlytics is a network
dependency, a privacy surface, a build-time key and a vendor, for a two-person
household where the two people can text each other. Adding one later is a third
`CrashSink` implementation and one provider override in `bootstrap.dart`;
nothing else in the app moves.

---

## What we don't say

Written down so the next sweep doesn't over-correct into a nagging app.

1. **The word "offline".** Being offline is not a state this app reports. It
   reports *waiting* (fine) and *stalled* (not fine), and both are true whether
   the cause is a tunnel, an expired token or a 502. A test enforces this.
2. **A non-empty queue.** Per the rule above: the quiet line states it; nothing
   announces it, no row is greyed, no badge appears.
3. **Form validation the form already shows inline.** The measure editor's
   *"g must be a positive number"*, the ingredient form's *"Enter all four
   macros, or leave them all blank"*, the import review's per-line issues. These
   are correct where they are. No toast. Where a repository *refusal* and a
   repository *failure* can both happen — the measures editor — the refusal is
   turned into a value inside the guard's closure so both surfaces survive.
4. **PowerSync's reconnect chatter.** `connecting`, a transient `downloadError`
   during a token refresh, the isolate's routine warnings. Only the thresholds
   above escalate, and only for *upload*: a download hiccup in an app whose reads
   all come from local SQLite is not a user's problem.
5. **A probe or lookup that found nothing.** The USDA probe answering null, an
   enrichment returning "no answer". The app already has honest sentences for
   these and they are not errors.
6. **Deliberate degradations already documented in code.** The photo downscaler
   returning original bytes, `_openSettings` swallowing a `PlatformException`,
   malformed jsonb parsing to null (invariant 3). All correct.
7. **Success.** No "Saved!" toasts — a checkbox that ticks is its own
   confirmation. The two textual confirmations on the ingredient form stay,
   because that form has no other visible change to show.

---

## Where things live

```
app/lib/
  core/
    observability/crash_sink.dart   the seam under the zone handler
    sync/sync_health.dart           the four states, derived
    sync/dropped_write.dart         the record of a discarded write
    sync/connector.dart             reports a drop beside the debugPrint
  shared/
    write.dart                      guardedWrite + ref.write / ref.writeOk
    ansi_toast.dart                 the two toasts, and the zone's anchor
    ansi_error_state.dart           what · why · Try again · Copy details
    describe_failure.dart           one honest sentence per failure family
    sync_words.dart                 the copy, written once
    sync_banner.dart                the persistent state, hosted by the shell
    sync_health_row.dart            the Library ⋯ footer line
    sync_status_line.dart           the Shop list's line
app/test/
  structure/no_bare_repo_write_test.dart   the invariant, mechanically
  shared/sync_readouts_test.dart           the words, pinned
```
