# Exec plan: a plan slot takes an ingredient, not only a recipe

- **Status:** fronts A–C built; awaiting the sim leg and the migration's trip
  to cloud
- **Owner:** Simon (rulings) · agent lane (build)
- **Roadmap step:** 8.14 — field test, round five
- **Created:** 2026-09-04

## Goal

Something you simply *eat* — a protein bar, a yoghurt, an apple — can be
planned into the week without being dressed up as a one-line recipe, and it
counts in the week's macros and on the shopping list like everything else.

This plan's first deliverable is a **design iteration on the board**, which is
what the owner asked for and what the backlog row has always said this needs.

## What is true today

- `plan_entry` carries `recipe_id` and nothing else that could be eaten
  (`app/lib/core/sync/schema.dart:97`). `meal_slot` is **free text, not an
  enum**, so a new slot needs no migration at all.
- The XOR precedent exists and is close by: a recipe line is an ingredient
  **or** a sub-recipe, never both and never neither, enforced by a server check
  (migration 0017). A plan entry pointing at a recipe **or** an ingredient is
  the same shape one table over.
- Week macros already derive from entries (`features/planning/domain/week_macros.dart`),
  and the vocabulary already carries honest per-100 macros, a basis and
  measures — so an ingredient entry has everything it needs to count.
- [backlog: *A plan slot takes a recipe **or** an ingredient*](../backlog.md)
  says the same, and says the trigger: **it wants its own board section first.**

## Fronts

Every frame question below is ruled; Front B is the build.

### Front A — the design iteration (board)

Draw in `week.html` as `proposed`, and answer these on the frames:

- **A-D1** **Ruled: one `snacks` slot per day.** The smaller change, and it
  reads honestly. `meal_slot` is free text, so the slot itself costs no
  migration.
- **A-D2** **Ruled: the shipped quantity sheet**, seeded exactly as a recipe
  line is — including the row's stated default measure (plan 0036 Front A), so
  "1 bar" means a bar.
- **A-D3** **Ruled (owner): a snack carries eaters and multiplies, like any
  other entry** — *"yes, multiple people can have same snack"*. So the entry
  keeps the `eaters` array and the `portions` override it already has, and the
  demand arithmetic (Σ portion factors) is unchanged. This is the ruling that
  makes Front B small: an ingredient entry is a normal entry with a different
  target.
- **A-D4** **Ruled: the cook plan ignores it — it is not cooked — and the
  shopping list includes it.** That is the split the owner named, and it means
  the shopping derivation must walk **entries**, not only cook sessions. That
  is the one real piece of plumbing in this plan.
- **A-D5** As drawn on `week.html`, with no objection recorded: a row that is
  visibly not a recipe —
  no shelf-life chip, no batch hint, no `›` into a recipe page — an ingredient
  detail link at most.

### Front B — the model (after sign-off)

- **B-D1** `plan_entry.ingredient_id` + `quantity` + `unit` + `measure_id`,
  with a server check mirroring migration 0006/0017's XOR: exactly one of
  `recipe_id` / `ingredient_id`. Both sync-rule YAMLs and `schema.dart` gain
  the columns; pgTAP covers the check.
- **B-D2** Every derivation that reads `recipe_id` gets an explicit branch —
  week macros, the cook plan (A-D4), the shopping list. A `null` recipe must
  never mean "skip silently".
- **B-D3** An ingredient entry is excluded from macros when the row is a
  `stub` — invariant 3, unchanged, and named on screen the way a stub line is.

### Front C — the surfaces

- **C-D1** The add flow: the planning picker gains ingredients the way the
  editor's line picker gained recipes — **one door**, sections inside it, not a
  second `＋`.
- **C-D2** The week grid and the shopping list render per A-D5 / A-D4.

## Acceptance criteria

- [x] The shipped rows match the signed-off `week.html` frames.
- [x] A snack shared by two people counts twice — in the week's macros and on
      the shopping list.
- [x] A protein bar can be planned, shows in the week, counts in week macros
      when it has honest numbers, and lands on the shopping list.
- [x] The XOR is enforced server-side, not only in Dart.
- [x] Tests: domain tests for each derivation branch, repo tests on a real
      `PowerSyncDatabase`, pgTAP for the check.
- [ ] A sim leg that plans one.
- [x] Docs: `docs/product-specs/product-spec.md` §4 (the week's vocabulary),
      `week.html`, `app/lib/features/planning/README.md`.

## Approach

1. Board section + rulings. Nothing else starts — this is the "design
   iteration" the owner asked for, and it is most of the risk.
2. Migration + derivations (Front B), each with its test, before any UI.
3. Surfaces (Front C).

## Decision log

- 2026-09-04 — Filed from the owner's round-five note ("I want to support
  adding ingredients to the food plan (e.g. a protein bar, which isn't a
  recipe), we need a design iteration on this"), promoting the backlog row that
  named the same trigger.
- 2026-09-04 — Owner ruled all five frame questions. A-D3 came back the
  **opposite** of the recommendation — a snack is shared, so it carries eaters
  and multiplies — which makes an ingredient entry an ordinary entry with a
  different target, and Front B correspondingly smaller.
- 2026-09-04 — **Migration 0033** carries five checks, not one. The XOR is
  B-D1's; the other four fell out of writing it down. The amount columns are
  refused on a recipe entry (its amount is its `portions`, and a second amount
  beside it would be one fact with two sources); `quantity`/`unit` are
  both-or-neither, `recipe.yield_qty`'s rule; and a `measure_id` needs a number
  to count. An amount is *optional* on the ingredient side, deliberately: an
  entry that states none is a real state the derivations name (`no amount`),
  and blocking it in the schema would have moved an honest refusal into an
  upload failure.
- 2026-09-04 — **No household-fence trigger**, unlike 0017's `sub_recipe_id`.
  That trigger exists because a component link can also close a CYCLE, which
  poisons every derivation walk; an ingredient reference cannot, and
  `recipe_line_item.ingredient_id` has carried a plain global FK with RLS
  guarding the row's own household since 0003. Same fact, one table over.
- 2026-09-04 — **The nutrition rides on the entry**, denormalised beside
  `recipeTitle`. The alternative — a second lookup from a whole-vocabulary
  watch behind the Week screen — would have added a stream to a screen that
  already loads the rows it needs, and a second place for the numbers to drift.
  So `sumPlannedMacros` gained no lookup callback: a snack is weighed from what
  its own entry carries, and nothing can be wired up wrong.
- 2026-09-04 — **A snack's exclusion borrows a LINE's wording**, not a new
  vocabulary. `MealExclusion.ingredientNotCounted` carries a `MacroLineReason`,
  so an unweighable snack says `stub ingredient` / `needs a weight` /
  `needs a density` in the exact words the recipe panel uses (B-D3). One enum
  value, not four, and no second dictionary to keep in step.
- 2026-09-04 — **The shopping rework, as built.** `buildShoppingList` grew a
  `planned` list beside `cook`, and the repository a second walk
  (`_derivePlannedIngredients`) over the week's ENTRIES — A-D4's real cost. The
  two derived sources now share one `_derivedContribution` helper carrying the
  three degradations (unrecognised unit, invalid measure, measure beside a
  non-count unit), so the cook plan's rule and the week's cannot drift; the
  manual path was left alone, because its guards are a genuinely different
  subset. Contributions interleave by day rather than sitting in a section of
  their own, so a Tuesday snack reads beside a Tuesday cook.
- 2026-09-04 — **Every reader got an explicit branch, including the ones the
  SQL already excluded.** The cook plan's inner join to `recipe` would drop a
  snack on its own; it now says `AND pe.recipe_id IS NOT NULL` anyway, because
  a null recipe must never read as an accident of a join. `watchLastPlanned`
  filters the same way — it is the RECIPE picker's recency map — and the
  picker's "already this week" strip skips `isIngredient` by name rather than
  by a null title.
- 2026-09-04 — **The row's title opens the ingredient page.** A-D5 allowed "an
  ingredient detail link at most", and E7's rule is that a row's controls are
  the facts it prints: the title names an ingredient, so it opens that
  ingredient. It also loses the dish's herb-deep semibold, which was the cue
  saying "a recipe page is behind this".

## Notes / open questions

- This is the only round-five plan with a migration and a wire change. It
  should not be lane-parallel with anything that also touches
  `plan_entry`.

## Step-done checklist

- [ ] Roadmap row updated.
- [ ] `ARCHITECTURE.md` standing table matches for `features/planning`, `cook_plan`, `shopping`.
- [ ] `app/AGENTS.md` current focus still true.
- [ ] `make test-sim` run, result recorded here.
- [ ] Backlog row retired; tech-debt rows added for anything cut.
- [ ] Migration recorded: say in the roadmap row whether it has reached cloud,
      and append the `docs/cloud-setup.md` ledger entry when it does.
- [ ] `make ci-full` green (needs Docker).
