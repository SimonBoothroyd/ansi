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
- **Named measures** (step 7.6; basis-aware since 7.8/ADR-0008): a
  per-ingredient `Measure` ("1 potato, large = 299 g", "1 can (400 ml) =
  400 ml") bridges count↔**the ingredient's basis** via its stored
  `basis_amount` (denominated in `macros_basis`: g or ml). Crossing
  mass↔volume still needs the density, and a missing/invalid measure never
  invents an amount (a measure-quantified line stores `unit = 'piece'` as
  its honest count fallback).
- **Unit admission is per-ingredient and explicit** (ADR-0008, step 7.8):
  `ingredient.allowed_units` lists exactly what a line may *say* — the
  default unit's family trimmed to kitchen magnitudes ("no litres of
  yeast"), the basis family (yeast finally admits `g`), the other family
  once a density exists (demoted below the measures in chip order), and
  imprecise units only for seasoning/oil categories. Materialized at
  creation from `default_allowed_units()` (Dart mirror
  `defaultAllowedUnitSet` — shared test vectors), curated for the seed
  vocab (`curation_overrides.jsonl`), and **editable per ingredient in the
  step-8.5 flesh-out form** (`/ingredients/:id`). Since
  [ADR-0009](../decisions/0009-density-unlocks-both-families.md) the density leg
  is ungated — a stored density unlocks the other family whatever the default
  unit's family, so "1 cup diced mango" is sayable on a piece-default row — and
  a density arriving after creation extends the list by trigger, wherever it
  came from. What we may *compute* is unchanged — totals still degrade honestly.
- **Density is the single volume⇄mass fact**, enterable two equivalent ways
  (7.8): as g/ml, or as "1 tbsp of this weighs N g"
  (`densityFromVolumeWeight`). A volume-named measure label is therefore
  REDIRECTED into density entry — volume-named measures never exist, so the
  two facts can never disagree. Saving a density also extends the explicit
  `allowed_units` with the family it unlocks, in the same write.

### Ingredient
`id · canonical_name · aliases[] · category · density_g_per_ml (nullable) · macros {kcal, protein, carb, fat} (nullable) · macros_basis ('g' | 'ml', step 7.7) · allowed_units (jsonb unit-id array, step 7.8) · default_unit · status (complete | stub) · source`
- `source` is **provenance, and it is load-bearing**: `seed` (the template
  vocab), `manual` (typed in the picker or the manager), `import_stub` (created
  at an import commit), `usda_fdc:<id>` (what the server-side prefill stamps),
  `off:<barcode>` (a barcode scan). The stub-prefill trigger reads it to decide
  whether a row is its business — it never touches `seed` (whose density-less
  tail is audited, not accidental) or a barcode row (whose Open Food Facts
  provenance must not be overwritten by a USDA id).
- `status = stub` → surfaces in the manager's stub band + honest macro math.
- **Macros are stored WITH the basis the label read them in** (per-100 g or
  per-100 ml — liquid labels read per 100 ml, and densities are sparse, so
  converting at entry can't be the design). Consumers apply the aggregation
  doctrine: a line whose unit family matches the basis computes directly;
  cross-basis bridges only via density; otherwise the total is honestly
  `incomplete`. USDA prefill rows are per-100 g.
- Seed from USDA FoodData Central **Foundation Foods + SR Legacy** (CC0).
  Density from FDC volume food portions parsed out of the full portion text
  (7.8 took coverage to 211/291), fallback FAO/INFOODS Density DB v2.0, then
  step 8.5's D4d hand pass — **297/308 today**; the 11-row tail is audited and
  tracked, not accidental (tracker).

### Ingredient measure (steps 7.6–7.8)
`ingredient_measure: id · household_id · ingredient_id · label · basis_amount (> 0, in the ingredient's macros_basis unit — 0012) · sort_order · source`
- Per-household, synced, user-editable rows — households disagree about what
  "1 portion" is, and import (step 8) will create them from labels. The
  starter set is GENERATED from FDC food portions
  (`supabase/seed_measures.sql`, per-row `source` provenance) and clones with
  the vocab at onboarding (backfill gated run-once by
  `household.backfilled_at`, 0011 — deleting your measures never resurrects
  them).
- **In-app measure editor (7.7; density entry 7.8):** the quantity sheet's
  manage state authors `source = 'manual'` rows ("half can = 200 g"),
  soft-deletes unwanted ones, and holds the DENSITY entry (g/ml ⇄ "a spoon
  weighs…"). Labels that merely name a volume unit are redirected into that
  density entry — density owns volume conversion. Provenance is shown
  humanized (USDA portion / borrowed / typical / yours), never as raw
  machine strings.
- **No unique label index** (0011, the shopping-entry doctrine): two offline
  devices adding the same label must never fail upload — duplicate live
  `(ingredient_id, label)` rows merge deterministically on read (oldest row
  canonical), and hidden duplicates still resolve by id from lines.
- `recipe_line_item.measure_id` / `shopping_list_contribution.measure_id`
  (nullable FKs) quantify a line in a measure ("2 × potato, large"); the
  quantity surface offers an ingredient's live measures as chips beside its
  honest unit set (`allowedUnitChoicesFor`).
- **`piece` is the fallback, and it is an admission fact**
  ([ADR-0010](../decisions/0010-piece-is-an-admission-fact.md)): it means "a
  whole one of these, and we have nothing better to call it", so where an
  ingredient carries an appropriate piece-type measure `piece` is simply not in
  its `allowed_units` and is never offered — nothing at runtime ever has to
  guess whether a `piece` meant a clove or a medium one. Which rows those are
  is **decided by hand, never derived**: by us for the seeded vocabulary
  (`supabase/seed/curation_overrides.jsonl`, one reasoned line per row), and by
  the household for their own rows, asked once in the measures editor the
  moment they add a row's first measure.

### Recipe
`id · title · book_id · section (user-defined label) · servings_base · favorite (step 7.7) · ingredient_groups[] · steps[]`
- **ingredient_group:** `name · line_items[]`
- **line_item:** `ingredient_id · quantity · unit`
- Scaling = quantity × factor (imprecise units left as-is).
- `favorite` is the household-shared curated shortlist behind the recipe
  picker's Favorites tab; marked from the recipe page's header menu.
- **Per-serving macro summation (step 7.7, pulled from step 9):** pure-Dart
  `summarizeRecipeMacros` sums line items × vocab macros honouring
  `macros_basis` (measure lines via grams); ANY stub / unbridgeable /
  imprecise-only line — and a recipe with no lines at all — renders the
  whole summary honestly `incomplete` — no partial total ever shows as the
  recipe's macros, and an empty sum never shows as ~0 kcal. Feeds the
  picker rows **and the recipe page's per-serving macro panel** — step 9
  shipped that panel off this same summation, so the two surfaces cannot
  disagree. *Reality check, resolved:* this read `incomplete` on most real
  recipes when density coverage was 7/291; 7.8's FDC-spoons→density work, the
  FAO fallback and 8.5's D4d pass took it to **297/308**, so most recipes now
  read as numbers and the residual `incomplete` is the honest 11-row tail.

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

**Navigation (design board "Navigation · v2", shipped):** four tabs — **Library ·
Week · Cook · Shop** — are the loop, under **one** bottom bar that never moves.
The tabs are branches of a single shell, so a switch is a 120 ms opacity-only
cross-fade of the content with the bar held still, and each tab keeps its own
scroll and its own view state (the Week's per-person lens survives a trip
through Cook). Everything else — a recipe, the editor, import, the ingredients
manager — is **pushed over** the shell and covers the bar, keeping each
platform's native push and back gesture. Back on a non-Library tab returns to
the Library and a second back leaves the app. Sheets and dialogs open above the
whole shell. The mechanics, the full back table and the rules that are
structurally enforced: [`../design-docs/navigation.md`](../design-docs/navigation.md).

**Import (webpage):** parse schema.org/Recipe JSON-LD first (no AI). LLM fallback for messy pages.
**Import (photo):** vision model → structured lines. Both feed one reconciliation screen.
**Reconciliation screen (matching, not free text):**
- Confident auto-match → shown with an "undo / wrong match" affordance to correct it
- Medium confidence → "did you mean?" suggestions
- No match → "add new" → creates a **stub**, surfaced for fleshing out

**Fleshing out a stub (step 8.5, shipped):** a stub needs density/macros before
it counts toward conversions or macro totals. It surfaces as a **band on top of
the whole vocabulary** in the ingredients manager (`/ingredients`), not as a
separate queue screen — a vocabulary you can only see when it is broken is not a
vocabulary you can edit. Arriving stubs are **prefilled server-side** from
`usda_food` by a database trigger (never a client lookup — ADR-0005), and a
rename re-runs it; a barcode scan prefills the same way from Open Food Facts.
Prefilling is never promotion: **macros gate `complete`, density does not, and
confirming is an explicit human act** in the flesh-out form (reversible —
a `complete` row can be un-confirmed).

**Pickers (step 7.7 — design board "Pickers v2", shipped):** one selection
anatomy, two contents. Both pickers share a sheet shell (top-anchored search,
source-tab slot, footer slot):

- **Ingredient picker** (recipe editor + shopping top-up): a Recent section
  (recently used in lines/top-ups) before any query; dense information-honest
  rows — category, capability hints ("has density", "3 measures"), a per-100
  macro line for complete rows, a `stub` badge (never zeros); an add-new
  affordance creating a `manual` stub from the typed query. Search is the
  shared three-tier rule (exact · every-token word prefix · a guarded
  typo tier that runs only when the first two find nothing, rendered under a
  `DID YOU MEAN` header) — see
  [`search-and-matching.md`](../design-docs/search-and-matching.md). Still
  deterministic and still ADR-0004: no index, no model, and nothing resolved
  without a human picking it.
- **Quantity + unit chips** (replaces every unit dropdown): tapping a
  quantity opens a sheet — ingredient card (name + macro line), quantity
  input, a live honest conversion line ("≈ 610 g · via density
  1.02 g/ml" — shown only when the unit system can actually bridge), then
  the chip row (precise units · measure chips with provenance dots ·
  imprecise after a divider · a `+` chip) riding the keyboard at the
  sheet's bottom — the stack above the keyboard reads chips → Done →
  keyboard (Done sits between the chips and the keyboard; no native
  accessory view). The `+` chip opens the manage-measures state (list +
  add form, see above). The stored selection is always offered: an
  off-filter value (a merge-hidden duplicate measure, a no-longer-allowed
  unit) stays reachable, subtly marked "not in filter"; deleting the
  selected measure in the manage state resets the choice to the default
  unit with a visible note (never a silently tombstoned reference).
- **Recipe picker** (planning): Recent · Books · Favorites tabs; day-tagged
  "already this week" quick picks; rows carry filing, last-planned recency,
  shelf-life chips, and per-serving macros or the `incomplete` badge with
  its reason; an "Eating: Ada & Jun · shared" footer. Title search is the same
  three-tier rule the ingredient picker uses — as is the editor's "Your
  recipes" section, pinned by a cross-picker test. Planning search is
  recipes-only in v1 (foods-as-ad-hoc-meals revisited with step 8).
- **Confirm & place:** picked card with the honest macro line, one combined
  "Day · Slot" dropdown (day changeable at confirm), and the full batch
  prose ("Chicken Curry already cooks Monday and keeps 4 days — Wednesday is
  inside that window, so this joins Monday's batch instead of a second
  cook").

---

## 6. Data sources

| Need | Source | License |
|---|---|---|
| Macros / canonical ingredients | USDA FoodData Central (Foundation Foods + SR Legacy) | CC0 |
| Volume↔weight density | FDC food portions (primary) + FAO/INFOODS Density DB v2.0 (fallback) | CC0 / open |
| Barcode → product (shipped, step 8.5 — on-device lookup, prefills a draft and never completes a row) | Open Food Facts | ODbL (credit shown in the app) |

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
8.5. **Ingredients manager** (the vocabulary gets a screen: browse/search, the
   flesh-out form owning `allowed_units`/density/macros/name, confirm a stub,
   add from barcode)
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
