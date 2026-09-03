# Exec plan: Field test, round two — the import & macros seam, and the Android inset

- **Status:** active — design phase (frames being drawn for sign-off)
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
- [ ] Migration `0021` additive (data is durable — no reset), backfilled from the curation table; pgTAP.
- [ ] `make ci` green; `make test-sim` scenario 4 re-driven (import with a sized-produce line lands unflagged).
- [ ] The Android fix confirmed on the Pixel from the next Release APK.
- [ ] Docs: ADR-0010 amended by a new ADR only if the rule changes (it does not — a default is a curated fact); product-spec §5; tracker rows.

## Decision log

- 2026-09-03 — Data is durable from here (owner): `0021` is additive with a
  backfill; no reset.
- 2026-09-03 — No tag until this slice lands (owner: "don't tag yet").

## Step-done checklist

- [ ] Roadmap row; QUALITY grades; tracker rows added/retired; `make ci`;
      `make test-sim`; cloud push (`0021` + the reseed button for the
      default-measure curation) and a ledger entry; tag.
