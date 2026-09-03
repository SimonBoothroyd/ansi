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

- [ ] Lane A — `currentWeekStartProvider` re-fires at local midnight; tested with an injected clock.
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
