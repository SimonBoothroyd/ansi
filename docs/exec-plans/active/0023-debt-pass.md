# Exec plan: 0023 — debt pass (durable-data edition)

- **Status:** active
- **Owner:** orchestrator (Claude) + four build lanes; Simon rules any real choice
- **Roadmap step:** between 9 and the stretch steps — no feature; pays tracker rows
- **Created:** 2026-09-03

## Goal

Pay the tracker rows that the 2026-09-03 durability ruling (cloud-setup §2c)
made expensive to leave: the server-side rule divergences that now write into
permanent rows, the missing measures rollout that leaves seed-borne measures
unreachable for existing households, and the one visible app bug (stale
"today" past midnight). Every migration preserves rows.

## Acceptance criteria

- [x] Lane A — `currentWeekStartProvider` re-fires at local midnight; tested with an injected clock.
- [ ] Lane B — a monotone `ingredient_measure` rollout (insert-missing, never delete/overwrite), previewable, idempotent, pgTAP-tested; cloud-setup §2b + release.md updated; the canned-tomato tracker rows point at it.
- [ ] Lane C — migration `0021` brings `default_allowed_units` / `density_unlocked_units` / the imprecise gate to parity with `allowed_units.dart`; `supabase/tests/unit_admission.sql` mirrors `allowed_units_test.dart`; no removal backfill (ADR-0009).
- [ ] Lane D — `molasses`-class words singularize per the comment on BOTH sides (TS + Dart + shared vectors); migration `0022` rewrites affected `match_text` rows in place; `gen_seed.ts` alias-collision check is global.
- [ ] Tracker rows retired or narrowed by each lane; `make ci` green on main after each landing.

## Approach

Four worktree lanes off `main@a47010b`, one conventional commit per slice, no
merges; the orchestrator fast-forwards main and runs `make ci` +
`supabase db reset` + `supabase test db` at each landing (lanes do not touch
the shared local stack — one instance, one port set). Migration numbers are
assigned here, not minted: **0021 = lane C, 0022 = lane D**.

## Decision log

- 2026-09-03 — Scope is the three items Simon ruled "we need to address" plus
  the midnight ticker. The `search_query.dart` move to `core/search/` (tracker
  suggests doing it with the plural fix) is left out to keep lane D's diff
  reviewable; it is the natural next slice.
- 2026-09-03 — Lane A: "today" is a keep-alive `Today` notifier
  (`week_view_models.dart`) holding the local calendar day, re-fired by one
  `Timer` armed for the next local midnight (re-armed by its own callback, so
  DST days just wait longer) AND by an `AppLifecycleListener.onResume`, since
  iOS suspends timers in the background and a phone can wake past several
  midnights; both are released in `onDispose`. The wall clock is a
  `clockProvider` seam (keep-alive, because riverpod_lint requires keep-alive
  dependencies for keep-alive providers) that tests override and drive with
  `fake_async`. `currentWeekStart` is now `mondayOf(today)`; `ViewedWeekStart`
  is untouched and still reads `DateTime.now()` directly — the viewed week must
  not jump at midnight. One consumer moved with it: `week_view.dart`'s TODAY
  pill read `DateTime.now().weekday` inside `build`, which only ever
  re-rendered when the *Monday* changed, so it now watches `todayProvider` —
  a provider-read swap, not a UI path change. The tracker row is retired.
- 2026-09-03 — Lane B: the measures rollout is a **separate file**,
  `supabase/rollout_measure_refresh.sql`, not a third leg of
  `rollout_ingredient_refresh.sql`. That script is an UPDATE of two
  `ingredient` columns whose contract is fill-only/union-only and whose
  footer promises it never touches `ingredient_measure`; the measures leg is
  an INSERT of whole rows into another table (insert-missing). One file each
  keeps both contracts legible. Join key: (ingredient `match_text`, measure
  `label`) — the key `ensure_onboarded` re-associates measures by (0012) and
  the only identity a measure has (the seed guards on it; 0011's read-side
  duplicate merge uses it); label comparison is exact. Copied columns are the
  clone's: `label`, `basis_amount`, `sort_order`, `source`. Two calls made
  conservatively, both open to an owner ruling: (1) the `not exists` guard
  counts tombstoned rows, so a label the household soft-deleted is never
  resurrected (0011's doctrine) — the cost is that a household can never
  regain a seed measure it once deleted except by hand; (2) a household
  ingredient whose `macros_basis` differs from the template's is skipped
  (`basis_mismatch_skipped` in the preview) rather than handed a per-g
  amount on a per-ml row — invariant 3 over coverage; `ensure_onboarded`'s
  clone does not check this. Testing: pgTAP cannot `\i` a file outside
  `tests/`, so `tests/measure_rollout.sql` mirrors the script's statement
  verbatim between `>>>`/`<<<` markers inside a temp function, and
  `make db-lint` diffs the two blocks. The lane could not run the pgTAP
  suite (shared stack is off-limits); the orchestrator's landing gates do.

## Notes / open questions

- Lane D: the fix for `molasses` is most likely an explicit invariant-word
  set rather than a regex change (`glasses` → `glass` must keep working); the
  lane records the choice.

## Step-done checklist

- [ ] Roadmap: no row (debt pass); note in the tracker header date if useful.
- [ ] `docs/QUALITY.md` grades still true for ingredients / planning / seed.
- [ ] `make test-sim` not required (no UI path changed) — lane A is provider-only.
- [ ] Tech-debt rows retired/narrowed: midnight, SQL admission mirror, singularizer, alias check, canned-tomato (narrowed to "bundles"), plus a NEW row if any lane cuts a corner.
- [ ] Migrations 0021/0022 reach cloud via `deploy-supabase`; ledger entry in cloud-setup.md.
- [ ] `make ci` green.
