# Exec plan: this week's variant — a recipe edited for one planned week

- **Status:** active
- **Owner:** agent (build lane `week-variant`)
- **Roadmap step:** — (backlog row "Per-week recipe override")
- **Created:** 2026-09-10

## Goal

A recipe can be cooked differently for one week without being edited. From the
meal editor sheet, the recipe editor opens in **week mode** and saves a **diff**
against the recipe — a swap, an amount, an addition, an exclusion, an optional
line ticked in. One variant per `(week, recipe)`, so every day that plans the
recipe shares one pot. The recipe itself, its page and the Library are
unchanged; every surface that *has* a week reads the variant and says so.

Owner's words: **"one variant of each recipe per week, all days use it."**

## Acceptance criteria

- [x] `week_recipe_line_override` exists (migration `0040`), RLS-fenced, in the
      `powersync` publication, in both sync-rule YAMLs and in
      `app/lib/core/sync/schema.dart`.
- [x] The meal editor sheet's last row states the variant's own scope and opens
      `/recipes/:id/edit?week=YYYY-MM-DD`.
- [x] Week mode draws the line list and nothing else: no header form, no
      method, no grip, no group controls. One inert strip states the recipe's
      serves / step count / title.
- [x] Save recomputes the whole override set for `(week, recipe)` and writes it
      in one transaction. A line edited back to the recipe's value leaves no
      row.
- [x] Every changed line carries one tag in the `optional` badge's voice and
      its own reset; the footer states the count it would drop.
- [x] `effectiveLines` applies the week's overrides — the ONE seam, so the
      shopping list and the week's macros cannot disagree about what this week
      cooks.
- [x] The week's macro lens re-sums a VARIED recipe over the week's effective
      lines, and keeps borrowing the Library's figure for every recipe it
      leaves alone.
- [x] The shop's provenance line carries the week's reason; an excluded line
      takes the optional echo row.
- [x] Every planned day of the recipe reads "edited for this week"; the cook
      card's sub-line says it once.
- [x] Copy last week does not carry the variant, and reports what it left.
- [x] Tests: the diff per action, the seam per action, an override never leaks
      into another week, the repository on a real PowerSync db, pgTAP for the
      constraints, widget tests for week mode / the tag / the footer / the door
      row / the dish row / the shop segment, and a `week_variant` smoke flow.
- [x] Docs: this plan, the board (`recipe-editor` · `week` · `cook-shop`),
      `docs/generated/db-schema.md`, the backlog row retired, a roadmap row.

## Approach

1. **The table.** `0040_week_recipe_line_override.sql` — the D6 checklist, the
   0005 RLS trio, the 0033 amount checks, the 0017 target XOR. Sync rules in
   `docker/powersync.yaml` and `docker/powersync-cloud.streams.yaml`; the local
   table in `core/sync/schema.dart`. pgTAP under `supabase/tests`.
2. **The domain.** `recipes/domain/line_override.dart` — the entity, the diff
   (`diffLineOverrides`), and the two vocabularies that name a change (the
   editor's tag, the shop's segment). `effectiveLines` takes the overrides and
   applies them; `LineDropReason.thisWeek` joins `optional`.
3. **The repository.** `WeekVariantRepository` — watch a week's overrides by
   recipe, load one recipe's set, replace a set whole; and re-sum the recipes
   the week varies over their effective lines.
4. **The editor.** `?week=` on the existing route, branched in the router so
   `recipe_editor_view.dart` is untouched; the week-mode view owns its own
   draft, rows, tags, resets and Save.
5. **The door.** One row at the foot of the meal editor sheet.
6. **The week.** The dish row's second mark, the cook card's sub-line, and the
   macro lens reading the week's own summaries.
7. **The shop.** The week key through `_deriveCookContributions`, one extra
   provenance segment, and the exclusion on the optional echo row.
8. **Copy last week.** A second count, and the words for it.

## Decision log

The rulings below are the owner's sign-off on the design lane's frames
(`week-variant.html`, frames a1 · b · b2 · c · d · e · f · g · h). They are
recorded here because the board draws pixels and does not hold decisions.

- 2026-09-10 — **D1 · The door is a row at the foot of the meal editor sheet**,
  not a fourth target on the dish row and not a Week-header menu item. The
  sheet is per-*meal* and the variant per-*(week, recipe)*, so the row states
  its own scope — "a change covers every day this week — Tue and Sat". Without
  that sub-line the row lies about what a tap changes. No new route: the week
  is a query param, exactly as `initialTitle` already is.
- 2026-09-10 — **D2 · Week mode does not draw what it cannot edit.** The whole
  header form and the whole method are absent rather than locked: a control
  drawn and refused has to be explained on every tap. Two carve-outs — serves
  survives as a sentence (every amount is *per serves 4*, so the list is
  unreadable without it) in one inert strip, and the method is gone rather than
  muted because a chip points at a line id that an added line has not got and
  an excluded line would orphan. No grip, inert group headings, no add-group.
  The bin *excludes* a recipe line and *removes* an added one. Save is the
  editor's own — nothing is written until then.
- 2026-09-10 — **D3 · The diff is recomputed whole on save**, against the base
  lines as loaded: a replace when any of ingredient / quantity / unit / measure
  / note differs (absolute values, all of them on one row), an add when there is
  no base id, an exclude when a base line is gone from the edited list, an
  include when an optional base line is kept. Edited back to the recipe's value
  → no row, so no-ops cannot pile up. Reorder and regrouping are ignored in v1
  and therefore not offered — a drag that reverts on reopen is worse than no
  drag.
- 2026-09-10 — **Marking a line optional for the week is an exclusion.** The
  amount sheet's Optional switch is the same control both ways; switching it
  *on* over a line the recipe counts has exactly the effect the bin has (the
  seam drops it), so it stores `exclude` rather than a second column that would
  have to mean the same thing. Switching it *off* over an optional line is the
  `include` the seam was written for.
- 2026-09-10 — **D4 · Both resets.** Per line (the dish row's `−` idiom, muted,
  no confirm) and a footer that states its count — "Back to the recipe · drops
  5 changes". Both are draft actions; Save commits them, so the undo is back.
- 2026-09-10 — **D5 · Amounts are absolute.** The recipe moving 400 g → 500 g
  leaves this week at the 400 g that was asked for. A deleted line cascades (an
  override is *about* a line); a soft-deleted one is simply not found, is
  skipped, and is dropped by the next save. Cascade from `week_plan` too.
  Unplanning the recipe leaves the overrides — re-adding the meal restores the
  variant.
- 2026-09-10 — **D6 · One row per `(week_plan, recipe, line)`**, NULLs distinct
  so many `add` rows are legal. An added line has no group column: it renders at
  the foot of the last group, which is where the editor's own *Add ingredient*
  puts a new line anyway, and no derivation reads a group.
- 2026-09-10 — **D7 · Two call sites thread the week.** The shopping derivation
  already holds the key where lines meet the week, so the overrides join there
  with no refactor. The week's macro lens can no longer borrow the Library's
  per-recipe figure for a VARIED recipe — it re-sums that one over the week's
  own effective lines, and keeps the Library's number for every recipe it
  leaves alone, because that number is still exactly right for them. A week
  with no variant therefore costs nothing and reads as it always did. The
  recipe page and the Library hold no viewed week and are left alone; the
  component
  graph is read household-wide with no week, so sub-recipe swaps are suppressed
  in the picker for v1 (the column ships, the section does not).
- 2026-09-10 — **D8 · Copy last week does not carry the variant, and says so.**
  "Just this week" is the whole promise; carrying it forward is a recipe edit
  made by accretion. A silent drop is the same bug as a silent carry, pointing
  the other way — so the copy returns a second count and names the recipes.
- 2026-09-10 — **The tag prints the ingredient's name as the app stores it.**
  Frame c's tag reads "was 400 g pork sausage"; the app prints "was 400 g Pork
  sausage", because a display name is never rewritten for a sentence (the
  standing naming ruling). The shipped frame carries the app's words.

## Notes / open questions

- Sub-recipe swaps are v1-suppressed, not refused: `sub_recipe_id` is on the
  table so the picker's "Your recipes" section can be unsuppressed once the
  component graph learns about weeks.
- A variant survives unplanning the recipe. Nothing prunes an override whose
  recipe is no longer planned that week; the rows are tiny and re-adding the
  meal is meant to restore the variant.

## Step-done checklist

- [x] Roadmap row added (status stays `active` until the simulator gate runs).
- [x] `ARCHITECTURE.md`'s standing table matches reality for every area
      touched — planning and shopping both still read as written.
- [x] `app/AGENTS.md` "Current focus" and command list still true; the smoke
      file count moved from eight to nine.
- [ ] `make test-sim` run on a booted simulator, result recorded here — the
      orchestrator's gate, not this lane's. `week_variant_test.dart` compiles
      and analyzes clean.
- [x] Tech-debt rows: none added, none retired. The corners cut are recorded
      as rulings above (sub-recipe swaps suppressed, reorder not storable),
      not as debt — neither is a shortcut somebody owes for.
- [ ] Migration `0040` has **not** reached cloud. Append a
      `docs/cloud-setup.md` ledger entry when it does, and deploy the sync
      config with it — a rebuilt database with stale streams starves devices
      of every table added since.
- [x] `make ci` green (`analyze` + `test` + `docs-check`; `ci-full` where the
      local stack was free).
