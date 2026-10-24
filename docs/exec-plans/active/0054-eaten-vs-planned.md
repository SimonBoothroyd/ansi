# Exec plan: Eaten vs planned

- **Status:** active — phases 1–4 and Ask's *had_instead* on main and deployed (migrations, streams and `ask`, run 39765796412); phase 4 (Health Connect) waits on the phone checklist below, Ask on its paid eval run
- **Owner:** Simon (design and rulings), agents in lanes
- **Roadmap step:** Next 5; its leftover question is a first slice of step 11 (anti-waste)
- **Created:** 2026-10-21

## Goal

Each person can say which planned meals they actually ate, or that they had
something else, and the app's eaten figures — the Week band, the day lines,
Ask, and the phone's Health Connect — follow what was eaten instead of
assuming the plan happened. When a cooked batch is over, the household says
what became of the portions nobody ticked, so food waste is a recorded fact.

Today the Week band is labelled **PLANNED** and is honest about it; nothing
anywhere records what happened.

## Rulings

Taken with the owner over five rounds, 2026-10-20/21, against a clickable
canvas ([Eaten vs planned](https://claude.ai/artifact/9UcT3mwVUiEGsbbh3V47FB)).
Each ruling replaced an earlier proposal; the rejected ones are listed under
*Rejected* so nobody re-proposes them blind.

- **You say eaten; nothing is assumed.** A meal counts as eaten for a person
  only when that person ticked it. An unticked past meal is *not ticked* —
  never "skipped", never "didn't eat", and never silently eaten.
- **A tick is on your own avatar.** The row is today's row — title,
  avatars, `−` — unchanged. A ticked avatar shows a tick in place of its
  initial, in the member's colour; a person who had something else shows a
  swap there, and only on their own phone does a line under the title name what
  (`Pizza with work`). Another person's avatar shows a tick or nothing.
- **You can only tick yourself.** No phone sets another member's tick, and
  the server refuses it (RLS on `auth.uid()`), not only the UI.
- **The tick lives in today's meal sheet.** The avatars already open the
  meal editor (slot · who's eating · portions · ingredients). It is kept as
  it is, with **one block on top**: an *I ate this* switch and, while that is
  off, *Had something else ›*. The block appears from the meal's own day on;
  a future meal's sheet is unchanged. The sheet says nothing about anyone
  else's eating.
- **Two taps, not one.** Your own avatar is not a separate one-tap toggle: at
  17 px two avatars are not two reliable targets, and the avatar cluster is
  one target by the Week v3 rule (product spec, *The Week screen*).
- **Had something else is the existing picker.** One search over recipes and
  bare items together, plus the eaten-out row (*"pizza" · eaten out*, macros
  optional). No recipe / ingredient switch: the picker already merges them
  and a row's amount says which it is. The substitute is for the ticking
  person only, counts as eaten, and is never cooked, bought or costed. The
  planned meal keeps its place in its batch.
- **The plan is not edited by eating.** Ticking, unticking or swapping never
  changes `eaters`, `portions` or the batch, so the cook plan, the shop and
  the costs keep showing what was cooked and bought, and the gap is the data.
- **Waste belongs to the batch, asked on Cook.** Once every day a batch
  covers has passed and fewer portions were ticked than planned, its Cook
  card asks *What happened to the other one?* — **Kept · Binned · Eaten**
  (the last for a forgotten tick). Either member can answer; it is about the
  pot, not a person. See *Leftovers* below.
- **Health Connect follows the ticks, at once.** One switch in Account's
  *Health Connect*, *Send my meals*, per phone. A tick sends that member's
  share of the meal; an untick, a swap or a `−` takes it back out; an edit to
  the meal updates the entry rather than adding one. A meal whose macros do
  not resolve is not sent and is named under the switch (`Office lunch has
  no macros · add ›`) — invariant 3; nothing is sent as a zero.
- **A tick's time is when you ticked, and you can change it.** No meal times
  to configure. With *I ate this* on, the sheet shows the time beside it
  (`19:42 ›`); tapping it opens a date-and-time picker. A tick made after the
  meal's day defaults to that day at the tick's clock time, so a late tick
  never lands on the wrong day. Health Connect gets this time.
- **Your share is your usual portion.** The same rule the lens already uses
  (`week_macros.dart`): your `portion_factor` in servings, or a `portions`
  override shared out by the eaters' factors. One function feeds the Week,
  Ask and Health Connect.
- **A meal nobody ate is leftovers.** If it was planned it is assumed bought,
  so every planned portion not ticked — nobody ticked it, or someone had
  something else — is a leftover, not a gap. A meal that was never bought is
  removed with `−` as today, and then it was never there.
- **Switching it off does what Health Connect does.** Sending stops and what
  Ansi already wrote stays, as it does when any app's Health Connect
  permissions are removed; deleting is Health Connect's own job, not Ansi's.
  So there is no warning to give. While the switch is off, one row under it
  — *Manage in Health Connect ›* — opens Health Connect's page for Ansi,
  where the data can be deleted.
- **`−` on a ticked meal is still undone, not confirmed.** It removes every
  member's tick with the meal, so the existing undo toast names it:
  *Removed Ragù · Jun had ticked it*.
- **Minimal words on screen.** No explanatory sentences in the app; a row,
  a badge, a switch. Explanation lives in this plan and the board.

### Leftovers

- **Counted, not asked for.** A batch's leftover is derived: its planned
  portions (Σ demand over the entries it covers) less the portions its
  members ticked, each at their share. Nothing is stored until somebody says
  what became of it.
- **Raw or cooked is the same question.** The app cannot know whether an
  uneaten batch was ever cooked, and does not ask: food bought for a meal
  nobody ate is either still here (*Kept*), thrown away (*Binned*) or was
  eaten after all (*Eaten*). An answer is in portions, so `2 left` can be
  `1 kept · 1 binned`.
- **Unanswered is said as unanswered.** Until the question is answered the
  band says `2 portions left`, never waste; only *Binned* counts as waste.
- **Recipes only.** A bare item planned and not eaten (a yoghurt pot) keeps
  in the fridge and is assumed kept, with no question; a meal eaten out
  bought nothing, so it leaves nothing.
- **What waste costs.** A binned portion is priced by the recipe's own cost
  per serving (ADR-0017), so the band can say `2 portions binned · ≈ $6`; a
  recipe with an unpriced line says `at least`, by the cost rule.
- **Not in v1:** a kept portion offered back in the picker as a leftover to
  eat (which would also answer *Kept → Eaten* on its own), and a kept portion
  taking a meal off the next shop.

### Rejected

- **Swipe left to delete.** Not a drawn target (Week v3), absent on the wide
  agenda and the web, and the `−` with undo already works.
- **Long-press for "only one of us ate it".** The Week has no long-press by
  rule; and per-person ticks make the question disappear.
- **Assume eaten, mark the exceptions.** Rejected by the owner in favour of
  saying eaten.
- **A tick replacing the `−` on every row, and a whole-day "All eaten as
  planned" button.** Looked goofy at row size, and needed a day-confirmed
  state that per-meal ticks made redundant.
- **A "Who ate it" section, editing others' state, Kept/Binned per meal in
  the sheet.** You cannot set another person's state; waste moved to Cook.
- **Batching Health Connect per confirmed day, per-slot clock times, an
  evening reminder.** Ticks are already the right moment; settings were
  too much choice.
- **A recipe / ingredient / eaten-out switch in the instead picker.**

## Approach

Phases land in order; each is shippable alone.

### Phase 0 — the board

1. Draw the frames as `proposed` in their own screen files
   ([board README](../../product-specs/board/README.md)): the badged row and
   the sheet's eaten block in `week.html`; the leftover question in
   `cook-shop.html`; the switch in `account.html`; the instead picker in
   `recipe-picker-confirm.html`. The canvas linked above is the source.

### Phase 1 — ticks and the eaten figures

2. **Migration `0055_meal_eaten.sql`:** `meal_eaten (id, household_id,
   plan_entry_id → plan_entry on delete cascade, member_id →
   household_member, eaten_at timestamptz not null — the tick's time until
   the person changes it, created_at, updated_at, deleted_at)`, one live row per `(plan_entry_id, member_id)`. RLS: read
   household-wide; insert/update/delete only where `member_id` is the caller's
   own member (`household_member.auth_user_id = auth.uid()`). pgTAP: a member
   cannot write another member's row. Add it to both PowerSync stream files and
   the local schema. A separate table rather than a column on `plan_entry`:
   two phones ticking the same meal would otherwise race on one jsonb.
3. **Domain (pure Dart, `planning/domain`):** `eatenBy(entry)`, and an
   `eatenMacros` beside `week_macros.dart` that reuses the lens's share
   function (lifted out, not copied), so the Week and Health Connect cannot
   disagree. Tests mirror it.
4. **Week:** the avatar badge; the band's EATEN / PLANNED lines and the day
   line under a person's lens; the sheet's *I ate this* block from the meal's
   day on, with its time and the date-and-time picker; the `−` toast naming
   lost ticks.

### Phase 2 — had something else

5. **Migration `0056_plan_entry_instead_of.sql`:** `plan_entry.instead_of
   uuid null references plan_entry(id) on delete cascade`, with `eaters` the
   one member who had it. A substitute is an ordinary entry of any of the
   three kinds, so the picker, the kind switch and the macro code are reused.
6. **One choke point excludes substitutes** from the cook plan, the shop and
   the cost (`instead_of is null` where the week's entries are read for
   derivation), pinned by a test per derivation. Eaten macros include them.
7. The sheet's *Had something else ›* opens the planning picker with the
   eaten-out row always offered (today it appears only when nothing matches —
   see *Open questions*). Setting a substitute clears that member's tick, and
   ticking clears the substitute.
8. **Ask:** *I'm eating out* on a past or today's meal records a substitute
   instead of taking the speaker off `eaters`; on a future meal it keeps
   today's behaviour (product spec, Ask section, updated with it).

### Phase 3 — the leftover question

9. **Domain (`cook_plan/domain`):** a session's leftover, derived as in
   *Leftovers* — planned portions less ticked shares — and whether its last
   covered day has passed. Pure, tested on the same fixtures as the cook plan.
10. **Migration `0057_batch_leftover.sql`:** the answer to one batch's
    question, keyed to the batch's cook-day entry (sessions are derived and
    have no row): `kept`, `binned`, `eaten` portion counts. Household-writable.
11. Cook's *Done this week* cards: the tally, the question while open, the
    answer after; the Week band's `2 portions left` / `1 kept · 1 binned ·
    ≈ $3` line.

### Phase 4 — Health Connect (Android)

12. A spike first: the `health` package's nutrition write on Health Connect,
    and `clientRecordId`/version for idempotent updates. Record the finding
    here.
13. A per-phone reconciler (local, never synced): the wanted set is this
    member's eaten meals with resolved macros over a trailing window; the sent
    set is a local table of `(record id, version)`. Any change to entries,
    ticks or substitutes — from either phone, via sync — diffs the two and
    upserts or deletes. That is what makes Ada's `−` remove Jun's entry once
    Jun's phone syncs.
14. Account: the one switch, the permission ask on first turn-on, and the
    not-sent row.
15. The platform and store work in *Privacy and the store* below, before the
    first build that carries the permission.

## Privacy and the store

`PRIVACY.md` describes the app as it works, so each paragraph lands with the
phase that makes it true, not before.

- **Phase 1 — the household sees your ticks.** *What Ansi stores* gains which
  meals each member said they ate, synced like the rest of the household's
  content. The app shows the other members only a tick; the policy says the
  data itself is household-readable, because it is (`meal_eaten` reads
  household-wide).
- **Phase 2 — what you had instead** is household content too, said in the
  same paragraph. If Ask reads ticks or substitutes, its paragraph's list of
  what is sent to Anthropic grows by them.
- **Phase 4 — a Health Connect section:** only when the switch is on; Ansi
  **writes** each member's own eaten meals (energy, protein, carbs, fat, fibre
  when stated, the meal type and a time) to Health Connect on that phone, and
  **reads nothing** from it; nothing read from Health Connect reaches Ansi's
  server or the household. What Ansi wrote stays in Health Connect under the
  person's control after the switch goes off or the account is deleted, and is
  deleted there (see *Rulings*). The deletion section says the same.
- **Write-only, by design.** Request `WRITE_NUTRITION` and no read permission:
  it is all the feature needs, and it keeps Google's Health Connect review and
  the policy's promises small.
- **Android manifest:** the permission; the `<queries>` entry for the Health
  Connect package; and the privacy-policy rationale Android requires of any app
  asking for health permissions — an activity for
  `androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE` (Android 13) and the
  `VIEW_PERMISSION_USAGE` / `HEALTH_PERMISSIONS` alias (14+), showing the
  policy. Without it the permission dialog does not offer the app.
- **Play Console:** the **Health apps declaration** naming nutrition write and
  why; the **Data safety** form revisited — eaten meals now sync to the server,
  and whether that counts as *Health and fitness* data there is to be read off
  Google's current definitions, not guessed. Check whether internal testing is
  gated on the declaration being approved; [release.md](../../release.md)'s
  Play section gains a line either way.
- **The policy needs a URL** the rationale screen and the declaration can
  point at; `PRIVACY.md` in the repo is not one. Serving it from
  `getansi.app/privacy` through the existing Worker is the cheap answer.
- **No HealthKit.** The owner left iOS out; the switch is Android only and
  is not drawn on iOS or the web.

## Acceptance criteria

- [ ] A member can tick, untick and swap only their own meals; the server
      refuses a write for another member (pgTAP).
- [ ] An unticked past meal never counts as eaten anywhere — band, day line,
      Ask, Health Connect.
- [ ] A substitute appears in nobody's cook plan, shop or cost (one test per
      derivation), and in its member's eaten macros.
- [ ] Ticking a meal changes nothing in Cook or Shop.
- [ ] The leftover question appears exactly when a batch's days have passed
      and ticked portions < cooked portions, and its answer reaches the band.
- [ ] Health Connect holds exactly this member's eaten, resolved meals after
      any sequence of ticks, unticks, swaps, edits and removals on either
      phone; an unresolved meal is named, never sent.
- [ ] `PRIVACY.md` true at every phase's release; the Play Console's Health
      apps declaration and Data safety form match what the build does.
- [ ] Tests cover the new logic in `planning/domain`, `cook_plan/domain` and
      the reconciler's diff.
- [ ] Docs updated: product spec (*Meal plan* data model, *The Week screen*,
      Cook, Ask, Account), `docs/generated/db-schema.md`, `docs/SECURITY.md`
      (a table whose writes narrow by member, not only by household), the board
      frames from proposed to built, `ARCHITECTURE.md`'s standing table.

## Decision log

Append-only.

- 2026-10-21 — Plan written from the design rounds above. Phase 0 before any
  code, because the board is where a screen's look is ruled.
- 2026-10-21 — The user-facing word *ingredient* for a protein bar or a
  yoghurt pot is wrong; renaming it everywhere is its own change
  ([backlog](../backlog.md), *Foods, not ingredients*). This plan's screens
  avoid the word rather than wait for it.
- 2026-10-21 — Owner rulings: a tick's time defaults to when it was ticked
  and is changed with a date-and-time picker; a share is weighted by usual
  portion (already the lens's rule in code — the product spec still said
  *even split*, fixed in the same commit); HealthKit is left out; a planned
  meal nobody ate is assumed bought, so it is leftovers, and one never bought
  is removed as today.
- 2026-10-21 — Switching Health Connect off follows the platform: keep what
  was written, delete in Health Connect. Google's help: *"When you remove data
  permissions, you don't remove the stored data"*
  ([Manage connected apps](https://support.google.com/android/answer/12201230)).

- 2026-10-21 — Phase 1 built. Three things the plan did not foresee:
  - **The phone did not know who it is.** `auth_user_id` is kept off the
    wire (0007), and Ask guesses "I" by matching the account's name. Ticks
    need certainty, so the access-token hook now injects `member_id` beside
    `household_id`, from the same membership, and `current_member_id()`
    gives RLS the same answer. A token from before the claim reads as "not
    known" (no tick offered) until it refreshes, within the hour. Ask still
    guesses; moving it onto the claim is a small follow-up.
  - **Undo re-added a removed meal as a new row**, so ticks — a partner's
    included, which this phone may not write — would have been lost. Undo
    now restores the same row (`restoreEntry`).
  - **The day lines stay the plan.** Only the week band (and the wide foot)
    gains the EATEN line, so a day card does not grow a second number.

- 2026-10-21 — Phase 2 built. The one choke point is the week itself: the
  repository hangs each substitute off the meal it replaced (`had`) instead
  of listing it, so every derivation that walks a week's meals passes over it
  without being told; only the cook plan's and the shop's own SQL needed
  `instead_of is null`. The picker keeps today's rule — the eaten-out row
  only when nothing matches — pending the owner's ruling. **Ask is not
  moved yet** (step 8): its *I'm eating out* still takes the speaker off a
  meal's eaters. Moving it is a tool and prompt change that wants its paid
  eval run, so it is its own follow-up.

- 2026-10-21 — Phase 3 built, smaller than *Leftovers* drew it, on
  purpose. **One answer covers the whole leftover** (kept, binned or eaten),
  stored as portions so a split answer can come later without a migration.
  **The waste is not priced yet**: the band says `2 portions binned`, not
  `≈ $6` — that wants the recipe's cost per serving joined in, a follow-up.
  **The wide schedule sheet does not ask**; the phone card does, and the
  board says so.

- 2026-10-21 — Phase 4 built, and built differently from step 12's
  spike. **No `health` package**: every version of it collides with
  something the app pins (the custom_lint stack, `wakelock_plus`'s `win32`,
  `intl`), so `MainActivity.kt` speaks to Google's own
  `androidx.health.connect:connect-client` 1.1.0 over one method channel —
  about a hundred lines, no new Dart dependency, and exact control of the
  `clientRecordId` and version that make a write a replacement. Consequences:
  `MainActivity` is a `FlutterFragmentActivity` (the permission contract
  needs one), and `minSdk` is 26. A meal goes as a one-minute record at its
  time. The window is this week and last; a meal that leaves it stays in
  Health Connect and drops out of the phone's log, so nothing old is ever
  taken back by accident. The log is per phone and swept on sign-out.
  `flutter build apk` (debug and release) passes in the session; nothing has
  run on a device.

- 2026-10-22 — **Ask moved (step 8).** A new change, `had_instead`
  (entry id, and the recipe, ingredient or words of what was had), refused
  for a meal still to come (it points the model at `set_eaters`), for a meal
  the speaker is not eating, and when who is speaking is not known; Confirm
  writes it in the card's one transaction through the same code as the
  Week's sheet. *I* is now the token's `member_id` (falling back to the
  account's name), which closes phase 1's follow-up. The eval set grows a
  `then_tool` / `then_change`: after the week is read, which proposal and
  which change — `eating-out-tonight`, `ate-out-last-night`,
  `partner-had-instead` (no proposal) and `eating-out-friday`, which now
  checks it stays `set_eaters`. The paid run is the owner's.
- 2026-10-24 — **The tick moved into the avatar** (owner, on `v0.32.0`).
  The corner badge sat on the side the next avatar in the stack covers, so a
  tick on the first eater was hidden. It now replaces the initial: full size,
  never covered, whose it is read from the colour and the place in the stack.
  Also from the same look: Cook's Kept · Binned · Eaten are the app's own
  pills (`AnsiChip`), not the list's default button, and the Health Connect
  row reads *Send my meals* in the page's sans, under its own heading.
- 2026-10-24 — **The instead picker always offers the words** (owner: an
  ad-hoc lunch could not be said). Typed words nearly always hit something
  in the vocabulary, so the eaten-out row, shown only when nothing matched,
  never appeared. In *Had instead* it now shows whenever something is typed,
  and the picker has no *new recipe* row. Planning keeps its rule.
- 2026-10-24 — **Health Connect: a meal ticked before the switch went on was
  not sent** (owner's household, one phone). Not reproduced: the runner sends
  such a meal in a test that drives the real providers. Hardened instead:
  a failed pass now says so under the switch (`Not sent`, `2 not sent`,
  `Permission is off in Health Connect`, each with *Try again ›*) where it
  used to only log; it is retried whenever the app comes back to the front;
  a batch Health Connect refuses is resent one meal at a time, so one record
  never holds back the rest; and no pass runs while the recipes' figures are
  still loading (it would have read every meal as having no macros and taken
  back what was sent).
  Later the same day: the meals were in Health Connect all along; it was
  Fitbit that did not show them. Whether Fitbit reads nutrition from Health
  Connect is Fitbit's to say (its read permissions there), not Ansi's.

## Phase 4 — the phone checklist

On an Android 14+ phone (or Android Studio's emulator, API 34+), with a build
from main (migrations `0055`–`0057` are deployed):

1. Account shows *Health Connect* with the switch off and *Manage in Health
   Connect ›*, which opens Health Connect's page for Ansi.
2. Turning the switch on shows Health Connect's own prompt, asking to write
   nutrition only. Refusing leaves the switch off; allowing turns it on.
3. In that prompt, the privacy link opens the policy (needs
   `getansi.app/privacy` to exist — see below).
4. Tick a planned dinner: within a few seconds Health Connect (Data and
   access › Nutrition) shows it, at the tick's time, as a dinner, with your
   share's figures.
5. Change the time in the sheet: the same record moves; no second one.
6. Untick it: the record goes. Tick again, then remove the meal with `−`:
   the record goes; Undo brings it back.
7. Say you had something else: the planned meal's record becomes the
   substitute's.
8. A meal with no macros (a meal eaten out with none stated) is named under
   the switch and does not reach Health Connect.
9. Switch off: nothing in Health Connect changes.
10. On the partner's phone, remove a meal you ticked: once your phone syncs,
    your record goes.

**Before the Play Store sees it:** the share Worker serves the privacy policy
at `getansi.app/privacy` (the rationale screen opens that address) once a
`deploy-supabase` run has redeployed it; then fill in Play Console's Health
apps declaration (nutrition, write) and Data safety, with that address as the
listing's privacy policy.

## Notes / open questions

- ~~**The eaten-out row in the instead picker**~~ — ruled 2026-10-24: always
  offered once something is typed (decision log).
- **A substitute that was another batch's leftover** (ate Monday's spare curry
  instead of the ragù) ideally consumes that batch's kept portion — the
  picker offering kept leftovers, in *Leftovers*' not-in-v1. Revisit if it is
  common.
- **A substitute's row is household-writable** under `plan_entry`'s RLS; only
  the UI keeps it its member's. Narrowing `plan_entry` RLS for one kind of row
  is disproportionate unless it bites.

## Step-done checklist

The code landing is not the step landing. Tick these before setting Status to
done and moving this file to `completed/`.

- [ ] Roadmap row updated: status flipped, one line on what shipped and what was
      deliberately deferred.
- [ ] `ARCHITECTURE.md`'s standing table matches reality for every area touched.
- [ ] `app/AGENTS.md` "Current focus" and command list still true.
- [ ] Feature steps: `make test-sim` run on a booted simulator (the UI paths CI
      can't reach), and the result recorded here.
- [ ] Tech-debt rows **added** for corners knowingly cut, and **retired** (or
      narrowed) for debt this step paid off.
- [ ] New migrations or seed changes? Say in the roadmap row whether they have
      reached **cloud** yet, and append a `docs/cloud-setup.md` ledger entry
      when they do. A "pending cloud push" note nobody clears becomes a false
      claim the moment the push happens.
- [ ] `make ci` green.
