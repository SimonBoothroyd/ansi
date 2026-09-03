# Exec plan: 0024 — Field test, round two — the import & macros seam, and the Android inset

- **Status:** active — **build phase**: frames signed off 2026-09-03 ("lgtm"), one build lane in a worktree
- **Owner:** Simon (rules) + Claude (orchestrator; one design lane, then one build lane)
- **Roadmap step:** follow-up to 8.8 (plan 0022); absorbs the remainder of 8.7
- **Created:** 2026-09-03

## Goal

The first real import after the polish pass (the owner's Pixel, `v0.2.0`)
showed four things the pass had wrong or left out. Fix them as one slice, with
the frames signed off first, then one build, then one tag.

1. **`piece` friction.** Under ADR-0010 `piece` is not offered on a measured
   row, so every onion / pepper / cucumber line arrives flagged "Pick a
   supported unit". The owner's rule (no runtime guessing) stands; what was
   missing is the *curated* fact that removes the tap: a **default count
   measure** per ingredient (D1), preselected on import without flagging (D2),
   plus the single-measure preselect that did not fire on cucumber (D3).
2. **Method read-only at review, "v1".** A stale step-8 string; the review
   screen still uses the read-only fold while the editor v2 step cards exist.
   The review screen edits with the same step cards (D4).
3. **`incomplete · 2 unconvertible` names a count, not the lines.** The panel
   lists the lines with their reasons and the rows carry a marker (D5).
4. **Imprecise lines gate the total.** "to taste", "handful", "pinch" are
   unweighable by nature; they are excluded by rule and named under a total
   that shows anyway (D6) — invariant 3 kept by naming the exclusion.

Plus, from the same session: **the Cook tab cut off on Android** — the tab
roots inside the shell were subtracting the keyboard inset a second time
(fixed `0f8a134`, structural test `tab_root_scaffold_test.dart`; the emulator
did not reproduce the Pixel symptom, so the fix is grounded in code and
proven only when the next APK runs on the phone).

## Decisions (owner-directed 2026-09-03; frames pending sign-off)

| # | Decision | Owner's words |
|---|---|---|
| D1 | A curated `default_measure_id` per ingredient (medium where sizes exist, the sole count measure otherwise, none for fragment sets), editable in the manager | "we need some judgement here" / "manually decide for seeded" |
| D2 | Import preselects the default on a `piece` line, no flag, one tap to change | "now piece isn't an option most things … require users to select a unit" |
| D3 | The single-measure preselect that did not fire is a bug; name and fix it | (cucumber, one measure, flagged) |
| D4 | The review screen edits the method with the editor v2 step cards; the "v1" note goes | "the steps weren't editable and it was mentioning it's still v1?!" |
| D5 | The macro panel names the offending lines with reasons; rows carry a marker | "impossible to know what ingredients need fixing" |
| D6 | Imprecise lines never gate the total; listed as "not counted" | "things that are to taste, or imprecise should[n't] be required or show up in macros" |

## Acceptance criteria

- [ ] Board section "Import & macros seam · v2" signed off.
- [ ] Migration `0023` additive (data is durable — no reset), backfilled from the curation table; pgTAP.
- [ ] `make ci` green; `make test-sim` scenario 4 re-driven (import with a sized-produce line lands unflagged).
- [ ] The Android fix confirmed on the Pixel from a release-workflow rehearsal artifact (no tag).
- [ ] Docs: ADR-0010 amended by a new ADR only if the rule changes (it does not — a default is a curated fact); product-spec §5; tracker rows.

## Decision log

- 2026-09-03 — Data is durable from here (owner): `0021` is additive with a
  backfill; no reset.
- 2026-09-03 — No tag until this slice lands (owner: "don't tag yet", then
  "I want our D1–D6 to land before new release"). The Android inset fix is
  tested on the Pixel from a **release-workflow rehearsal artifact** (no tag,
  no Release), never from a tag.
- 2026-09-03 — Owner confirmed Week and Library were cut off too, i.e. the
  symptom is shell-wide: consistent with one keyboard height subtracted
  twice (the shell's scaffold and the tab root's). Belt and braces landed
  `b2f91a2`: the sign-in page drops the keyboard before it navigates away.
- 2026-09-03 — Owner, after a hard reset on the Pixel: the UI is no longer
  cut off — the shell-wide inset symptom (Cook, Week, Library) is gone with
  `0f8a134` + `b2f91a2` in. Recorded as the field observation; the rehearsal
  artifact walk above stands as the formal check.
- 2026-09-03 — Migration numbering: the debt pass (`0023-debt-pass.md`,
  a parallel session) landed `0021_admission_mirror.sql` and
  `0022_singularize_invariants.sql` on main the same evening, so this plan's
  additive migration is **`0023`**, not `0021` as the entry above says — and
  this plan is **0024**, renamed from 0023 to stop the two plans colliding.

- 2026-09-03 — **Signed off** ("lgtm"): D1–D6 as drawn; the 21 flagged
  defaults as proposed (retail can as the canned default, cauliflower head,
  celery stalk, eggplant unpeeled, flour tortilla single, ginger `piece, 1
  inch`, mint/spinach/broth none, watermelon → melon, cabbages + lettuces
  none, yellow bell pepper gains a borrowed medium). D2 scope: the default
  answers a line that named a number and no thing; a named unit always wins.
  D6: `handful` is excluded with `to taste`.
- 2026-09-03 — For the debt-pass session (it reads this file): migration
  **0023** is this plan's; the seam build lane owns import/**, recipe_macros,
  incomplete_macros, recipe_macro_panel, recipe_view, ingredient_detail_view
  (Counts as), curation_overrides.jsonl + gen_seed.ts, seed regeneration.

- 2026-09-03 — Owner authorised, ahead of the landing: once the seam lane
  lands and `make ci` + `make test-sim` are green, run the cloud push
  (`deploy-supabase` with `reseed_template` ticked — `0023` + the
  default-measure curation; `0021`/`0022` ride along), verify, then **cut
  the release** (`v0.3.0` — a minor, since the release adds the default
  measure and the review step cards).
- 2026-09-03 — **No new ADR for D1, and none for D6 either.** A curated
  default count measure is a *fact under [ADR-0010](../../decisions/0010-piece-is-an-admission-fact.md)*,
  not an amendment to it: `ingredient.default_measure_id` is the second
  stated per-row fact of exactly the kind ADR-0008 §4 established and
  ADR-0010 spends its length defending — decided by hand, recorded with its
  reason in `curation_overrides.jsonl`, nullable because "I don't know" is a
  real answer, and spent at ONE visible moment rather than re-derived. Every
  clause of ADR-0010's decision survives verbatim: `piece` is still not
  offered where a measure names the thing, no size word is read out of
  `raw_amount`, no rule resolves a line at runtime, no stored line is
  rewritten, and consequence 4's "one measure pre-selects" is now TRUE of the
  line rather than only of the sheet (D3 found it was never true of either —
  `preselectedMeasure` seeded the amount sheet and nothing else, so the flag
  stood until somebody opened and confirmed it). D6 is likewise an
  *interpretation* of invariant 3 the invariant already contains — nothing is
  invented, nothing is silent — and the product spec §4/§5 is where it is
  written down, because it changes what a screen shows rather than what the
  system is allowed to believe. If a later change makes a default something
  the machine *derives*, that is the ADR.

## Step-done checklist

- [ ] Roadmap row; QUALITY grades; tracker rows added/retired; `make ci`;
      `make test-sim`; cloud push (`0023` + the reseed button for the
      default-measure curation) and a ledger entry; tag.
