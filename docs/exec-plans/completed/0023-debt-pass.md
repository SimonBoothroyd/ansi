# Exec plan: 0023 — debt pass (durable-data edition)

- **Status:** done — the code and the cloud push both landed; ledger entry in `docs/cloud-setup.md`
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
- [x] Lane B — a monotone `ingredient_measure` rollout (insert-missing, never delete/overwrite), previewable, idempotent, pgTAP-tested; cloud-setup §2b + release.md updated; the canned-tomato tracker rows point at it.
- [x] Lane C — migration `0021` brings `default_allowed_units` / `density_unlocked_units` / the imprecise gate to parity with `allowed_units.dart`; `supabase/tests/unit_admission.sql` mirrors `allowed_units_test.dart`; no removal backfill (ADR-0009).
- [x] Lane D — `molasses`-class words singularize per the comment on BOTH sides (TS + Dart + shared vectors); migration `0022` rewrites affected `match_text` rows in place; `gen_seed.ts` alias-collision check is global.
- [x] Tracker rows retired or narrowed by each lane; `make ci` green on main after each landing.

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

- 2026-09-03 (lane D) — **An explicit invariant-word set, not a regex change.**
  `INVARIANT_WORDS` / `_invariantWords` = `{molasses}` on both sides, checked
  before every suffix rule. Admission rule, written next to the set: a word
  goes in only when it is genuinely singular AND the rules produce a non-word
  for it. Words the rules reduce to a real stem — `brussels` → `brussel` (the
  one such word in the seed vocab), `grits` → `grit` — stay out: the query side
  reduces them identically, so the stored key still matches, and admitting
  them would cost every household a rewrite for no gain. The regex guard
  (`-ss/-us/-is/-ous`) stays as the general rule. Blast radius measured: no
  `vocab.jsonl` row changes (`gen-seed` re-run, byte-identical), five
  `usda_food` rows (`molass` → `molasses`), plus anything a household typed.
  `0022` rewrites all three tables in place, guarded against 0020's template
  unique indexes (raise, never skip). `seed_usda.sql` got the identical
  whole-word rewrite by hand because the FDC bundles are not committed — the
  same precedent as the plan-0022 measure edits — so a fresh reset and a
  migrated database agree. The Deno suite now also reads the shared vector
  file, closing the parity loop from the server side.
- 2026-09-03 (lane D) — **The alias-collision check is one namespace.**
  `gen_seed.ts` now plans the seed through an exported `planSeed(rows)`: every
  ingredient key is claimed first, then every alias, in a single
  match_text → owner map, so an alias landing on another ingredient's key or
  alias is a build failure naming both sides. The tracker's "batch-6
  verification query" is not in the repo (it was a one-off run in a session),
  so the model is the runtime's own reading — the exact tier searches
  ingredient ∪ alias as one surface. Same-ingredient duplicates and an alias
  equal to its own canonical key are still dropped quietly, as before. The
  current vocab passes; `gen-seed` re-run, byte-identical.
- 2026-09-03 — **Lane C, the additive backfill: included, but narrowed to the
  bug's own signature.** `0021` unions `density_unlocked_units(default, basis)`
  into a row only when it carries a density, a mass/volume default, and a
  stored list that does not name that default unit — the shape a D4b
  `clearDensity` (list stripped to `[g, kg]`, `cup` kept as default) leaves
  once a later server-side density (a 0015 rename re-probe) landed and 0014's
  one-argument leg unioned only `g, kg`. No curation and no honest edit
  produces that combination, so it cannot touch a curated removal (pasta's
  `tsp, tbsp`; olive oil's `pinch`) — which a blanket "union the new leg into
  every density-carrying row" would have re-admitted; that blanket variant was
  considered and rejected. Rows touched are counted in a `raise notice` so the
  cloud `db push` log says how many the old rule actually wronged (expected:
  zero or single digits). No removal backfill, per ADR-0009 rule 3. The
  one-argument `density_unlocked_units(text)` is dropped rather than left as
  an overload, so no caller can resolve to the stale rule by accident; its
  only caller (0014's `ingredient_density_extends_allowed_units`) is
  re-created on the new signature.

- 2026-09-03 — **Landing.** All four lanes rebased and fast-forwarded onto
  main in the order A, B, D, C (every conflict was this decision log or the
  tracker; both were resolved by keeping both sides). One defect found only at
  landing, because lanes could not run the shared stack: 0021 appended the
  four imprecise words to `units` as bare literals (`units || 'pinch'`), which
  plpgsql resolves as `text[] || text[]` and so parses `'pinch'` as an array
  literal — `supabase db reset` failed in `seed_curation.sql`'s
  re-materialize. Fixed in place (`array['pinch']`), since 0021 had not been
  pushed or deployed. Gates on main at that point: analyze · docs-check ·
  db-lint clean; `make test-app` 1423; `make test-fns` 155; seed scripts 18;
  `supabase test db` 8 files / 261 assertions. Lane D's flagged adjacent bug
  (`-ses` plurals — `cheeses` → `chees`) is now a tracker row.

## Notes / open questions

- Lane D: the fix for `molasses` is most likely an explicit invariant-word
  set rather than a regex change (`glasses` → `glass` must keep working); the
  lane records the choice.

## Step-done checklist

- [x] Roadmap: a Shipped row names the debt pass.
- [x] `docs/QUALITY.md` grades still true for ingredients / planning / seed.
- [x] `make test-sim` not required (no UI path changed) — lane A is provider-only.
- [x] Tech-debt rows retired/narrowed: midnight, SQL admission mirror, singularizer, alias check, canned-tomato (narrowed to "bundles"), plus a NEW row if any lane cuts a corner.
- [x] Migrations 0021/0022 reach cloud via `deploy-supabase`; ledger entry in cloud-setup.md.
- [x] `make ci` green.
