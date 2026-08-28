Shared, offline-capable recipe + meal-planning app for a two-person household. Better Paprika/Umami with a clean modern UI and light AI import.

---

## 1. Scope

**Core (v1):**
- Shared recipes, ingredients, meal plans, shopping lists across two users, offline-tolerant
- Controlled ingredient vocabulary (no free-text typos), expandable in-app, with macros
- Rich unit specification + conversion (incl. volume↔weight via density)
- Recipe books with **user-definable** sections; beautiful recipe pages with ingredient grouping ("for the sauce")
- Recipe scaling
- **Meal planning** — a single active **week** (plan → cook → reset), not a calendar; multiple meals per slot; per-meal eaters
- **Batch cook plan (derived)** — aggregates the week's meals by recipe and shows what portion size to cook; splits a dish into separate cook sessions when it's planned beyond its shelf life (or merges into one freezer batch when the recipe is freezable)
- **Recipe shelf life** — how long a dish keeps; drives batch splitting + freshness
- **Shopping list generated from the batch cook plan**, auto-aggregated, with per-ingredient provenance
- AI/deterministic import from webpage + photo, with ingredient matching

**Stretch:** web UI · barcode-add ingredient · computed recipe macros in UI · variety/monotony warnings · package-size waste flags

---

## 2. Architecture — DECIDED

| Layer | Choice | Notes |
|---|---|---|
| App framework | **Flutter** | Android now, web stretch nearly free. Impeller = smooth 60/120fps. |
| UI components | **Forui** (shadcn-style, free/OSS) | Alt: shadcn_ui port, or Material 3. FL Chart (free) for macro charts. |
| Backend | **Supabase** (Postgres + Auth + Storage) | Free tier: 2 projects, 500MB DB. Put recipe photos in Storage, not the DB. |
| Sync | **PowerSync** | Bidirectional; local SQLite + offline upload queue; native Supabase integration. Free tier: 2GB synced/mo, 50 connections. Open Edition self-hostable if needed. |
| Auth | **Google OAuth** via Supabase Auth | Anyone added needs a Google account. |

**Gotchas:**
- Idle Supabase instances can have runaway WAL growth with PowerSync — set a smaller `max_wal_size` for a hobby project.
- Supabase free tier pauses after ~1 week idle; just resume it.

---

## 3. Sync model

Single shared household dataset; both members full read/write; everything scoped to `household_id`.

- **PowerSync handles the write queue** — app reads/writes local SQLite, syncs when online.
- **Conflict resolution** (implemented in backend): list contributions and recipes are independent rows, so concurrent *adds* union and never collide. Field edits = last-write-wins (fine for two trusted users). Deletes = soft-delete tombstones.
- No CRDTs / text-merge needed.

---

## 4. Core data model

### Household & members
- `household: id · name`
- `household_member: id · household_id · display_name · auth_user_id` — the two named people. `eaters[]` on a meal references these.

### Unit system (build FIRST — everything depends on it)
- Families: `mass`, `volume`, `count`, `imprecise` (pinch, dash, to taste)
- Canonical base: **grams** (mass), **ml** (volume)
- Within-family = fixed ratio table; volume↔mass = via ingredient `density_g_per_ml`
- Imprecise units: non-scaling, non-converting flag
- **Named measures** (step 7.6): a per-ingredient `Measure` ("1 potato, large
  = 299 g", "1 can (400 ml) = 400 g") bridges count↔**mass** via its stored
  gram weight — the honest bridge for count foods, which a liquid density
  can't describe. Measures never reach volume without the ingredient's
  density, and a missing/invalid measure never invents grams (a
  measure-quantified line stores `unit = 'piece'` as its honest count
  fallback).

### Ingredient
`id · canonical_name · aliases[] · category · density_g_per_ml (nullable) · macros_per_100g {kcal, protein, carb, fat} (nullable) · default_unit · status (complete | stub) · source (usda_fdc_id | manual | barcode)`
- `status = stub` → drives the "needs fleshing out" queue + honest macro math.
- Seed from USDA FoodData Central **Foundation Foods + SR Legacy** (CC0). Density from FDC food portions, fallback FAO/INFOODS Density DB v2.0.

### Ingredient measure (step 7.6)
`ingredient_measure: id · household_id · ingredient_id · label · grams (> 0) · sort_order`
- Per-household, synced, user-editable rows — households disagree about what
  "1 portion" is, and import (step 8) will create them from labels. The
  curated starter set is hand-seeded (`supabase/seed_measures.sql`, sources
  noted) and clones with the vocab at onboarding.
- `recipe_line_item.measure_id` / `shopping_list_contribution.measure_id`
  (nullable FKs) quantify a line in a measure ("2 × potato, large"); unit
  pickers offer an ingredient's live measures beside its honest unit set
  (`allowedUnitChoicesFor`).

### Recipe
`id · title · book_id · section (user-defined label) · servings_base · ingredient_groups[] · steps[]`
- **ingredient_group:** `name · line_items[]`
- **line_item:** `ingredient_id · quantity · unit`
- Scaling = quantity × factor (imprecise units left as-is).

### Recipe book & sections
`book: id · name` · `section: user-defined label` (NOT a fixed preset enum).
- v1 assumption: a recipe lives in one book. (Multi-book many-to-many = open question, low priority.)

### Meal plan (week-based) — the INPUT
- `week_plan: id · household_id · week_start_date · label`
  - One active week; past weeks archived (cheap) → "copy last week" / reuse. Single-week grid UI, no calendar.
- `plan_entry: id · week_plan_id · day_of_week · meal_slot (user-definable) · recipe_id · eaters[] (→ household_member ids)`
  - You just say *what you want to eat* per meal — no batch/leftover thinking here.
  - **Multiple entries per (day, slot) allowed** → different breakfasts, office-lunch-for-one, etc.
  - Demand for an entry = `|eaters|` portions. (Optional refinement: per-entry `portions_override` for big/small appetites.)

### Batch cook plan (DERIVED) — the second view
Groups the week's `plan_entry` rows **by recipe**, then splits each group into **cook sessions** bounded by shelf life:
- `cook_session (derived): recipe_id · covers[] (plan_entry ids) · cook_day (default = earliest covered day, user-adjustable) · total_portions (Σ eaters over covered) · scale_factor (total_portions / recipe.servings_base)`
- **Clustering rule (greedy, not a solver):** sort the days a dish appears; start a session at the first; include each later day within `keeps_for_days`; open a new session when one falls outside. O(n log n).
- **"Same dish too far apart" → two things to cook**, each labelled why ("keeps 4 days"). Replaces manual leftover linking — batching is derived from demand, not hand-assigned.
- **Scaling helpers apply to the session batch (step 7.6):** a fractional `scale_factor` gets a **whole-batch nudge** on the session card ("cook ×1 instead — covers 4 portions · 1 left over") — display-level advice the cook can toggle per session; the honest raw factor stays what everything (the shopping list included) scales by. Ingredient quantities scale linearly; cook times / pan sizes may need human judgment.
- **Freezer (core, built in step 5):** if `recipe.freezable`, distant instances merge into one session (cook once, freeze the far share) instead of splitting.

### Recipe additions for the above
- `keeps_for_days` (fridge shelf life) — **core**; drives clustering + freshness.
- `freezable` (bool) · `freezer_days` (nullable) — core (step 5); merges a freezable dish's distant instances into one session.

### Shopping list (provenance-aware)

Persisted state is a **thin overlay**; the cook side of the list is derived, not
stored ([ADR-0007](../decisions/0007-shopping-list-thin-overlay.md)):

- `shopping_list_entry: id · household_id · ingredient_id (nullable) · free_text (non-ingredients, e.g. "paper towels") · checked · unit`  ← one per ingredient the user has *touched* (checked off or topped up), plus free-text items; holds the check-off state
- `shopping_list_contribution: id · entry_id · quantity · unit · note`  ← **manual top-ups only.** Cook contributions are never persisted — each device re-derives them live from the synced week + recipes (there is no `cook_session` table, so nothing stable to reference). The migration carries `source_type`/`source_cook_session_id` columns for forward-compat, but `source_type` is always `manual` and the session id stays null in v1.

**Behavior:**
- Generate from the **batch cook plan** → one *derived* contribution per (cook_session, ingredient), quantity = ingredient × session `scale_factor`, computed at read time.
- Display groups by ingredient, sums derived + manual contributions in canonical base (density-converted; measure-quantified lines fold into the mass subtotal via their gram weights), shows breakdown: *"Flour — 500g · Curry batch (cook Mon) 300g · Cookies 150g · +50g manual."*
- **Whole-unit hint (step 7.6):** a count-family ingredient *with a measure* whose single total is fractional gets an honest round-up hint beside the total ("2.25 → buy 3", or "≈ 2.25 potato, large → buy 3" derived from a mass total via the primary measure) — a hint, never a replaced total.
- **Top up** = persist a `manual` contribution against the entry (find-or-create).
- **Check-off** = on the entry (rolled-up ingredient), not per contribution.
- **Storage rule:** only what cannot be re-derived is stored (check-off, manual top-ups, free-text items) → nothing to reconcile between devices when the week or a recipe changes. An ingredient entry is displayed only while it has at least one live contribution (derived or manual); when its last one vanishes it drops off the list, its checked row staying inert. (`supabase/migrations/0006_shopping.sql`.)
- Batching is resolved in the cook plan, so each dish is bought once at its batch size (no double-buying, no manual leftover bookkeeping).

---

## 5. Feature specs

**Import (webpage):** parse schema.org/Recipe JSON-LD first (no AI). LLM fallback for messy pages.
**Import (photo):** vision model → structured lines. Both feed one reconciliation screen.
**Reconciliation screen (matching, not free text):**
- Confident auto-match → shown with an "undo / wrong match" affordance to correct it
- Medium confidence → "did you mean?" suggestions
- No match → "add new" → creates a **stub** → lands in fleshing-out queue

**Fleshing-out queue:** list of stub ingredients needing density/macros before they count toward conversions or macro totals.

---

## 6. Data sources

| Need | Source | License |
|---|---|---|
| Macros / canonical ingredients | USDA FoodData Central (Foundation Foods + SR Legacy) | CC0 |
| Volume↔weight density | FDC food portions (primary) + FAO/INFOODS Density DB v2.0 (fallback) | CC0 / open |
| Barcode → product (stretch) | Open Food Facts | ODbL |

---

## 7. Build sequence (reordered for meal-planning core)

1. **Unit + ingredient data model** (seed USDA, wire conversions incl. density)
2. **Single-user recipes** (create → group ingredients → scale → beautiful recipe page)
3. **Recipe books + user-defined sections**
4. **Week planning** (single-week grid; multiple entries/slot; eaters; copy-last-week)
5. **Batch cook plan** (aggregate by recipe; shelf-life clustering into cook sessions; adjustable cook day; whole-ingredient scaling)
6. **Shopping list from cook plan** (contributions per cook_session → aggregation → provenance → check-off + manual top-up)
7. **Sync layer** (PowerSync + household + offline queue) — can begin in parallel once the schema in 1–6 stabilizes
8. **AI/deterministic import** (JSON-LD → photo → reconciliation → stub queue)
9. **Computed macros in UI** (stretch; "incomplete" when stubs present)
10. **Web UI** (stretch; nearly free given Flutter)
11. **Anti-waste extras** (stretch; freezer-aware batching, variety/monotony warnings, package-size flags)

---

## 8. Remaining open questions (low priority)

- [x] Per-entry `portions_override` for big/small appetites, or `|eaters|` only?
      → **both:** `plan_entry.portions` defaults to `|eaters|`, overridable (step 4).
- [ ] Can a recipe belong to multiple books? (v1 assumes one)
- [x] Meal slots: fixed set or fully user-definable? → **user-definable** free
      text, with Breakfast/Lunch/Dinner offered as defaults (step 4).
- [x] Freezer-aware batching in v1 or stretch? → **v1** (step 5): a freezable
      recipe's distant instance merges into one cook session (cook once, freeze
      the far share) rather than splitting.
