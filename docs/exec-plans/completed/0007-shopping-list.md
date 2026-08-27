# Exec plan: Shopping list from the cook plan

- **Status:** done
- **Owner:** Simon (+ agent)
- **Roadmap step:** Step 6 — shopping list from cook plan
- **Created:** 2026-08-27

## Goal

The fourth core screen: **Shop**. The provenance-aware shopping list (spec §4).
It sums each ingredient's contributions from the batch cook plan — one per
(cook session, ingredient), quantity = the recipe line × the session's scale
factor — groups them by aisle, shows the breakdown ("Flour — 500 g · Curry ·
cook Mon 300 g · Cookies 150 g · +50 g manual"), and holds check-off on the
rolled-up item. A "+ add item or top up an ingredient" affordance adds non-food
staples and manual top-ups. The Shop tab in `MiseBottomNav` goes live.

Like the cook plan, the list is **derived**; only a thin overlay is persisted.

## Acceptance criteria

- [x] Migration `0006_shopping.sql`: `shopping_list_entry` (check-off +
      free-text anchor) + `shopping_list_contribution` (manual breakdown), RLS /
      grants / publication in the 0003–0005 shape; mirrored in `schema.dart`.
- [x] Shopping domain is pure Dart (invariant 2): entities +
      `aggregateQuantities` (honest summation, invariant 3) + `buildShoppingList`
      + `cookLabel`. Fully unit-tested.
- [x] Shopping data: `SqliteShoppingRepository` derives cook contributions live
      (reusing `buildCookPlan`) and overlays the persisted check-off / manual
      rows; watch fires on all seven source tables (column-per-table so none is
      dropped). Writes go through the views (no UPSERT): check-off is a
      find-or-create; top-up + free-text insert.
- [x] Shop screen matching the design board: aisle groups → item rows (check
      box · name · total) with a provenance breakdown; the add/top-up sheet;
      empty state.
- [x] `/shop` route; the Shop tab in `MiseBottomNav` goes live.
- [x] Tests: domain aggregation + build + lifecycle; repo assembly / check-off /
      top-up / free-text / recipe-deletion on a real PowerSync db; a screen
      smoke. `make ci` green.
- [x] Docs updated: roadmap, shopping README, QUALITY, this log.

## Approach

Dependency order, mirroring the step-4/5 slice structure:

1. **Migration + schema** — the two overlay tables.
2. **Domain** (`shopping/domain/shopping.dart`) — input record types +
   `ShoppingContribution`/`ShoppingItem`/`ShoppingGroup`/`ShoppingList`;
   `aggregateQuantities`, `buildShoppingList`, `cookLabel`.
3. **Data** — `SqliteShoppingRepository` (derive via `buildCookPlan` + overlay
   reads → `buildShoppingList`; check-off / top-up / free-text writes) +
   providers.
4. **Presentation** — `ShoppingView` + the add/top-up sheet + `shopping_format`
   + view models.
5. **Wiring** — `/shop` route; enable the Shop tab.
6. **Tests + docs + sim run.**

## Decision log

- 2026-08-27 — **Persistence model (confirmed with Simon): derived list + thin
  overlay.** The cook plan is purely derived (no `cook_session` ids), so the
  shopping list's cook contributions are re-derived live too; only check-off +
  manual/free-text rows are stored. Chosen over materializing every contribution
  (spec's literal wording) to avoid the regeneration/reconciliation the derived
  steps 4/5 deliberately avoided. Matches "data is ephemeral".
- 2026-08-27 — **Entry lifecycle (Simon's sync question: recipe deleted but the
  ingredient was checked).** Rule: an item shows only while it has a live
  contribution (derived cook or persisted manual) or is free-text. A deleted
  recipe's ingredient drops off unless it has a manual top-up; its checked row
  stays inert. Recipe deletion never touches the vocab `ingredient` row, so
  `ingredient_id` never dangles. Prior check-off returns if the ingredient is
  re-planned. A "clear list / new trip" action is deferred (a step-7 sync
  concern). Pinned by a repo test (`a deleted recipe drops its ingredient even
  if it was checked`).
- 2026-08-27 — **Honest aggregation.** `aggregateQuantities` sums within a unit
  family, bridges mass↔volume only with a density, and yields two subtotals
  rather than invent one when families can't merge (invariant 3). Count sums per
  unit; imprecise never sums.
- 2026-08-27 — **Watch triggers via column-per-table.** The read depends on
  seven tables (week/plan/recipe/group/line-item + the two shopping tables). The
  watch query selects a column from each — the shopping tables joined `ON 1=1`
  purely to be seen — so PowerSync's `EXPLAIN`-based detection registers them
  all, avoiding the dropped-LEFT-JOIN trap ([[mise-powersync-watch-left-join]]).
- 2026-08-27 — **Provenance label.** `cookLabel` shows the recipe title, plus
  "· cook <day>" only when the recipe is batched into >1 session (so the
  breakdown disambiguates which cook) — matching the mockup ("Curry · cook Mon"
  vs "Oat Cookies").

- 2026-08-27 — **Sim verification + a sheet-padding fix.** Drove Shop on the
  iOS sim: tab live, empty state, add sheet (both modes, live vocab search, unit
  defaulting, quantity), added a "Paper towels" non-food item (→ NON-FOOD group,
  em-dash total), and checked it off (green tick + strikethrough, persisted).
  The add sheet is a fixed-height sheet with its action button pinned to the
  bottom, so its `viewInsets.bottom + 12` padding tucked the button under the
  home-indicator zone; switched to
  `max(viewInsets.bottom, safeArea.bottom) + 12`. The other sheets
  (`recipe_picker`/`confirm_meal`) size to content (`mainAxisSize.min`), so their
  action buttons don't pin to the bottom edge and don't hit this.

- 2026-08-27 — **Edit/remove a manual top-up (Simon follow-up).** Surfaced each
  manual contribution's id through the domain
  (`ShoppingContribution.contributionId`) and added
  `editContribution`/`removeContribution` to the repo. A manual provenance line
  is now tappable (pencil affordance) → an edit sheet (prefilled qty+unit, Save,
  and a red Remove) — removing one top-up leaves the item's cook contributions
  and check-off intact, and drops the item only when nothing live remains.
  Covered by a repo test; verified remove end-to-end on the sim.

- 2026-08-27 — **Discoverable delete + honest empty state (Simon follow-ups).**
  (1) The non-food "—" is the total column (per the board), not a delete button,
  and remove was long-press-only — added **swipe-to-delete** (red trash panel +
  the confirm dialog), gated to *user-added* lines (`ShoppingItem.isUserAdded` —
  no cook contribution): a free-text item or an ingredient that's only a manual
  top-up. A cook-derived line isn't wholesale-deletable (edit the week; drop its
  top-up via the edit sheet). (2) An empty list with a **live plan** now reads
  "Nothing to sum yet — your planned recipes don't list ingredients yet…" (→
  Open the library) instead of the misleading "Plan the week", by watching the
  derived cook plan. Both covered by tests; verified on the sim.
- 2026-08-27 — **Flagged (not built): unit-list filtering.** The unit pickers
  offer all `kAllUnits`; they should be filtered per ingredient (same family as
  its `default_unit`, cross-family only with a density). Aggregation already
  stays honest without it. Logged in the tech-debt tracker.

## Notes / open questions

- Package-size / whole-unit rounding on the shopping total is stretch anti-waste
  work (roadmap step 11).
- Still local-only (no `.connect()` — sync is step 7).

## Step-done checklist

- [x] Roadmap row updated: status flipped, one line on shipped + deferred.
- [x] `docs/QUALITY.md` grade for shopping updated.
- [x] `app/AGENTS.md` still true (no "current focus" block to update).
- [x] `make test` green (domain + repo + screen); sim run recorded below.
- [x] Tech-debt: a Week→Shop scenario for `app_test.dart` (as with cook) is a
      tech-debt row; the flow was driven manually on the sim.
- [x] `make ci` green.
