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
`id · canonical_name · aliases[] · category · density_g_per_ml (nullable) · macros {kcal, protein, carb, fat} (nullable) · macros_basis ('g' | 'ml', step 7.7) · allowed_units (jsonb unit-id array, step 7.8) · default_measure_id (nullable FK, 0023) · default_unit · status (complete | stub) · source`
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
- **`default_measure_id` says what a bare COUNT of the row MEANS** — "2
  onions" is two `onion, medium` (migration 0023, plan 0024 seam D1). It is
  the *second* stated fact per row, the same kind of fact `allowed_units`
  already is, and it exists because ADR-0010 was right and expensive: taking
  `piece` off 142 measured rows made every counted-produce line a stop, and
  the app was asking a question whose answer was already known and the same
  every time.
  - **Nullable, and null is a real answer.** Broccoli's `whole`/`spear`/
    `crown` are three different things and none of them is "a broccoli", so
    that line keeps its flag and the user picks — the model can say "I don't
    know", which a rule never can. 141 seeded rows carry a measure: 132 get a
    default, 9 fragment sets get none, each with its reason in
    `supabase/seed/curation_overrides.jsonl` (kind `default_measure`).
  - **Curated, never derived.** The three shapes are *sized family → the
    `medium`*, *sole count measure → that one*, *fragment set → none*. A rule
    would put a default on broccoli and take it off `yellow bell pepper`, and
    would re-decide the whole list on every USDA regeneration.
  - **Spent once, visibly.** The import review writes it onto a line that
    named a number and no thing (§5 · Import), and nothing downstream
    interprets it: no stored line records that it came from here.
  - Household-owned from the moment the vocabulary clones: the flesh-out
    form's **"Counts as"** row sets it, "Ask me each time" clears it, and the
    measures editor's ask-once `piece` question sets it as the second half of
    the same answer. Soft-deleting the measure clears it.

### Recipe
`id · title · book_id · section (user-defined label) · servings_base · favorite (step 7.7) · ingredient_groups[] · steps[]`
- **ingredient_group:** `name · line_items[]`
- **line_item:** `ingredient_id · quantity · unit · optional (0025)`
- Scaling = quantity × factor (imprecise units left as-is).
- **Optional lines (plan 0025, D6a/D6b).** `optional` is a stored fact about
  a line — "lime, to serve (optional)" — not about its amount: the page
  still prints `1 lime`, with a muted `optional` tag after the note in the
  stub badge's voice. It is seeded from the extractor's flag at import,
  toggled in the quantity/unit sheet (the editor and the review share it;
  never offered on a component line), and its only effect is on what a
  TOTAL covers, through one seam — `effectiveLines(lines, planEntryId)` —
  that every derivation runs over: the macro summary and the shopping list
  leave the line out **and name it where it left** (`not counted · 2
  optional lines: Lime, Coriander` under the panel, composed with the
  imprecise exclusion; `2 optional lines not listed — lime, coriander` as
  the recipe's muted echo row on Shop), never a silent drop; the cook plan
  is unaffected — a batch is a batch whether the lime comes. A recipe whose
  every line is optional summed nothing and refuses, like an all-imprecise
  one. Deliberately not built: the per-week override (tick an optional line
  back in for one planned week, substitute an ingredient) — the seam's
  unread `planEntryId` is where it joins (tracker).
- `favorite` is the household-shared curated shortlist behind the recipe
  picker's Favorites tab; marked from the recipe page's header menu.
- **Per-serving macro summation (step 7.7, pulled from step 9):** pure-Dart
  `summarizeRecipeMacros` sums line items × vocab macros honouring
  `macros_basis` (measure lines via grams); ANY stub / unbridgeable line —
  and a recipe with no lines at all — renders the whole summary honestly
  `incomplete` — no partial total ever shows as the recipe's macros, and an
  empty sum never shows as ~0 kcal. Feeds the
  picker rows **and the recipe page's per-serving macro panel** — step 9
  shipped that panel off this same summation, so the two surfaces cannot
  disagree.
  - **The refusal NAMES its causes** (plan 0024 seam D5). The count line the
    picker rows print is kept verbatim, and under it the panel lists the
    lines the total is waiting on — `Cucumber · needs a weight`, `Tofu ·
    stub ingredient` — capped at four with `+N more`, each one a door to the
    fix its reason implies. The same reason is drawn **in place** on the
    ingredient row, in the import review's amber, because it is the same
    claim: *this line is why a number is missing.* One helper
    (`incompleteLineNote`) gives every reason one wording, so the panel, the
    marker and the picker row are one vocabulary. Nothing new joins any
    total; the refusal just stops being anonymous.
  - **Imprecise lines never gate the total** (seam **D6**). `to taste`,
    `pinch`, `dash` and `handful` are unweighable BY NATURE — no measure and
    no density turns a handful into grams — so they are excluded **by rule**,
    the total is shown, and the exclusion is printed under it by name, every
    time: `not counted: Parsley · handful, Sesame seeds · to taste`.
    Invariant 3 holds in both halves and is read the *stronger* way: nothing
    is invented (a handful contributes zero because zero grams of it were
    claimed, not because a number was guessed) and nothing is silent (a
    reader can see exactly what the figure covers). The imprecise family is
    already excluded everywhere else on purpose — `convert` refuses it,
    `scale` leaves it alone — so the macro engine treating the same word as a
    fixable defect was the outlier. **One guard:** a recipe whose lines are
    *all* imprecise summed nothing and still refuses (`nothing weighable
    yet`), the same shape as `no ingredients yet`. If a household ever wants
    a handful weighed, the answer is a **measure** on that row
    (`handful ≈ 25 g`, with provenance), not an engine special case.
  *Reality check, resolved:* this read `incomplete` on most real
  recipes when density coverage was 7/291; 7.8's FDC-spoons→density work, the
  FAO fallback and 8.5's D4d pass took it to **297/308**, so most recipes now
  read as numbers and the residual `incomplete` is the honest 11-row tail.

#### The method (step 8 tokens · the 0022 editor)

**One shape.** A step is an ordered list of tokens — plain text, `ref` chips
pointing at line items by id, and `timer`s ([import spec §4.6](./import-and-matching.md)
is the frozen contract). Since 0022 the editor **writes that shape for every
recipe**, a chip-less step being one text token; the plain `steps: List<String>`
is write-never, read-legacy. The recipe page, the import review screen, the
editor's preview and cook mode therefore all read one method model through one
renderer (`method_step_text.dart`) and one fold (`foldMethod`).

**The editor's document is text plus ranges.** A ref's `label` already *is* the
word standing at that position, so a token stream flattens to exactly the
sentence a human would type with one range marked: `toDraft`/`toTokens`
(`recipes/domain/method_draft.dart`) are inverses, byte-identical over the
sausage-sliders gold. A chip is a styled range, never a widget in the field, so
caret, selection, IME and backspace behave normally — and **typing inside a chip
demotes it**: the word stays, the link goes.

**A chip is made by selecting text and saying what it is.** Highlight a run,
and the selection toolbar offers *To ingredient* (the line picker, over this
recipe's own lines) and *To timer* (a stepper, seeded by parsing only the
selected substring). The selected words become the chip's word verbatim.
**Nothing scans prose on its own** — auto-chipping typed text would be
ADR-0004's render-time matching in a different hat.

**When a chip shows its amount:** *the first time a step calls for something,
its chip shows the amount; after that it's the same stuff, so the chip just
names it* — with a switch on any chip to override. The rule is computed for a
hand-made chip and taken from the extractor for an imported one (§4.6 records
the positional heuristic as brittle for imports); a step-named portion always
shows regardless, because that number is transcribed from the page. The switch
changes **display only**: no quantity is invented, moved or summed by flipping
it.

**The substitution invariant:** *a chip never names something the recipe does
not contain.* Tapping a line's identity re-points it while **keeping the line's
id**, so the chips survive; every chip referencing it then takes the new name,
the affected steps are flagged for that sitting, and `was "sausage" · keep the
old word` is one tap. Prose is authored and is never rewritten — only labels
are, and only visibly. Removing a referenced line asks first and leaves each
chip's word as plain text, and `save()` prunes dangling refs regardless: **a
saved method never refs a line the recipe does not have.**

**Convert to plain text** (the METHOD header's `⋯`) is the one lossy act and
the one-way exit: each step keeps its own prose byte-identically, only the links
go. There is no re-chip — tokenization happens only inside the import call.

### Recipe book & sections
`book: id · name · sort_order · deleted_at` · `section: user-defined label`
(NOT a fixed preset enum).
- v1 assumption: a recipe lives in one book. (Multi-book many-to-many = open question, low priority.)
- Books are renameable, reorderable and soft-deletable off those columns —
  Library v2 needed no migration. **A book is a shelf, not a container:**
  deleting one never cascades to its recipes.
- Which books are **folded shut is deliberately not a column.** It is a viewing
  preference, kept per device in `SharedPreferences`
  (`ansi.book_collapsed.<id>`, swept on sign-out with the other device-local
  keys). Syncing it would mean one member's tap folding the other's screen
  mid-scroll under last-write-wins.

### Meal plan (week-based) — the INPUT
- `week_plan: id · household_id · week_start_date · label`
  - `unique (household_id, week_start_date)` — **many weeks per household are legal**, one row per Monday, created lazily on a week's first meal. Nothing is written by *looking* at a week.
  - **A week is a position, not a singleton** (week redesign, D2). The app holds a *viewed week*, defaulting to the one containing today; the header names it (`This week · 31 Aug` / `Next week · 7 Sep` / `Last week · 24 Aug` / `Week of 14 Sep`) and steps through it. Unbounded in both directions; a past week is **editable, not locked** — nothing downstream corrupts, and every rule about *when* a week would lock is wrong for someone catching up on a Tuesday. There is no calendar and no month view, and "archived" is prose, not a column.
  - **Cook and Shop derive from the VIEWED week** (D3), not from the week containing today: you plan next week on a Sunday, so you must be able to cook and shop for it on a Sunday. There is **one** viewed week (plan 0025 D7a): changing it on any tab changes it on all three, and the week switcher is the **only title** of all three tabs (D7c — no "Batch cook plan" / "Shopping list"; the lit tab in the bar says where you are, which is why its selected state steps to herb-deep, D7d). The switcher's herb dot and its "This week" item are how a derived tab says which week it shows and offers the tap home; "Copy last week into this one" is a Week write and appears only on the Week screen's menu (D7b). Each tab's menu speaks in its own derivation — meals · cooks · items — for the week it has on screen.
- `plan_entry: id · week_plan_id · day_of_week · meal_slot (user-definable) · recipe_id · eaters[] (→ household_member ids) · portions (nullable override)`
  - You just say *what you want to eat* per meal — no batch/leftover thinking here.
  - **Multiple entries per (day, slot) allowed** → different breakfasts, office-lunch-for-one, etc.
  - Demand for an entry = the `portions` override, else `|eaters|` (spec §8's big/small appetites, resolved).

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

- `shopping_list_entry: id · household_id · ingredient_id (nullable) · free_text (non-ingredients, e.g. "paper towels") · checked · unit · week_start_date (nullable)`  ← one per ingredient the user has *touched* (checked off or topped up) **per week**, plus free-text items; holds the check-off state
- `shopping_list_contribution: id · entry_id · quantity · unit · note`  ← **manual top-ups only.** Cook contributions are never persisted — each device re-derives them live from the synced week + recipes (there is no `cook_session` table, so nothing stable to reference). The migration carries `source_type`/`source_cook_session_id` columns for forward-compat, but `source_type` is always `manual` and the session id stays null in v1.

**Behavior:**
- Generate from the **batch cook plan** → one *derived* contribution per (cook_session, ingredient), quantity = ingredient × session `scale_factor`, computed at read time.
- Display groups by ingredient, sums derived + manual contributions in canonical base (density-converted; measure-quantified lines fold into the mass subtotal via their gram weights), shows breakdown: *"Flour — 500g · Curry batch (cook Mon) 300g · Cookies 150g · +50g manual."*
- **Whole-unit hint (step 7.6):** a count-family ingredient *with a measure* whose single total is fractional gets an honest round-up hint beside the total ("2.25 → buy 3", or "≈ 2.25 potato, large → buy 3" derived from a mass total via the primary measure) — a hint, never a replaced total.
- **Top up** = persist a `manual` contribution against the entry (find-or-create).
- **Check-off** = on the entry (rolled-up ingredient), not per contribution.
- **Scoped to a week** (migration 0019, week redesign D3): an *ingredient* entry carries the Monday it was ticked or topped up against, so a tick made while looking at next week belongs to next week's list. A *free-text staple* carries no week and reads on every one — you are out of paper towels whichever week is on screen. A contribution rides its entry and stores no week of its own. There is still **no unique index** on an entry (0006's reasoning is unchanged: two offline devices must each be able to create one and converge later); convergence simply happens within a week.
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

**Errors & sync health (shipped):** one rule — *a toast reports an act, a banner
reports a state*. Every write reached from a widget goes through one guarded
door, so an action that didn't happen says so in the user's own noun and offers
Retry; a screen that couldn't load says what, why and Try again. Sync health is
one provider read by three quiet surfaces — the shell's banner, a line in the
Library `⋯` menu, and, because Shop is the one screen two phones drive at once
in a supermarket, a line under the shopping list's header in that screen's own
noun (*2 ticks waiting*). Being **offline is never reported**: the app
distinguishes *waiting* (the offline-first design working, always muted) from
*stalled past five minutes* and from a write the server **refused and
discarded**, which is the only place data is lost and now the only red one. The
words, the thresholds and the seven things the app deliberately stays quiet
about: [`../design-docs/errors-and-sync-health.md`](../design-docs/errors-and-sync-health.md).

**Import (webpage):** parse schema.org/Recipe JSON-LD first (no AI). LLM fallback for messy pages.
**Import (photo):** vision model → structured lines. Both feed one reconciliation screen.
**Reconciliation screen (matching, not free text):**
- Confident auto-match → shown with an "undo / wrong match" affordance to correct it
- Medium confidence → "did you mean?" suggestions
- No match → "add new" → creates a **stub**, surfaced for fleshing out
- **A line that named a number and no thing arrives on the row's curated
  default measure, unflagged** (plan 0024 seam D2). "2 red peppers" comes in
  as `2 × pepper, medium`, the card is clean, Save is not gated, the raw
  source line stays above it, and the chips stay visible with the default
  selected — the choice made for you, beside the ones you could make instead.
  The card says the fact out loud where it is applied: `counts as pepper,
  medium · 119 g · tap a chip to change`. There is no `inferred` mark, no
  revert and no provenance on the stored line, because those are a *guess's*
  apparatus and this is displayed at the point of use. Mechanically the
  resolution's unit is set to the measure's LABEL — the exact token a tapped
  chip writes — so the card is clean for the ordinary reason and the commit
  is byte-for-byte what a tap produces.
  - **The scope rule, in one sentence: the default answers a line that named
    a number and no thing; it never overrules a line that named a thing.** It
    fires on no printed unit, or a count-family unit the row refuses
    (`piece`). "1 **bunch** cilantro" keeps today's flag — cilantro's default
    IS `sprig` at 2.22 g and a bunch is about twenty-five of them. A refused
    `cup` is a *density* gap, not a count gap, and a measure cannot answer it.
  - A row with **no default** keeps today's flag and its did-you-mean chips.
- **The header is the editor's** (plan 0025 #4, board frames a/b): TITLE ·
  SERVES · MAKES (both denominations) · TIMES · SHELF LIFE · FILE UNDER are
  the recipe editor's own `RecipeHeaderForm`, rendered over a header draft
  the review holds from the moment the page arrives. Prefilled only where the
  page plainly said it — servings, a plain-amount yield, the printed cook and
  total times — and unset otherwise (shelf life, a section); filed into the
  default book from the start so FILE UNDER shows where it will land. What
  only the review knows is drawn *around* the form, never inside a copy of
  it: the never-invent strip above, *not printed — set it* beside SERVES,
  *from source: …* under MAKES. Nothing in the header gates Save; every
  column of it rides the commit.
- **The METHOD is editable here**, with the same step cards as the recipe
  editor (seam D4) — the screen most likely to need a method fix used to be
  the only one that could not make it. Chips key on the preview's line ids
  and convert back to line indexes at commit; a chip whose lines were all
  dropped demotes to plain prose. The one thing the review cannot do is mint
  a brand-new line, and the picker's add-a-line door says so.

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

**The Library (design board "Library · v3", shipped):** the app's home screen —
books, their user-named sections, and the recipes filed under each.

- **The header is a search field and one link.** No screen name: the lit tab
  says where you are, the rule Week, Cook and Shop already follow. The pinned
  field takes the title slot, and the only control beside it is the household
  glyph, which **navigates** to `/account`. That it is a link and not a menu is
  the point — a popover accumulates because adding a row to one is free (v2's
  `⋯` took Household and sync health within a day of shipping), while a control
  that navigates has nowhere to put a sixth item.
- **Creation lives on the shelf it fills.** Every section label carries a `＋`
  opening the two doors that make a recipe (New recipe · Import a recipe) —
  v2's promise word for word, on a row that knows its book *and* its section,
  so `/recipes/new?book=…&section=…` files the recipe where you tapped instead
  of in whichever book `ensureDefaultBook()` returns. The synthetic
  `Unsectioned` label carries one too: that is the door for "this book, no
  section". An expanded card carries **no dashed rows at all** — New section is
  the book `⋯`'s item, which it always was.
- **The vocabulary is a shelf, not a menu item.** An Ingredients card closes
  the library with the book anatomy exactly — a name, a count line
  (`308 ingredients · 3 stubs`), one control — and a `›` rather than a fold,
  because 300 rows do not belong inside a card. It is not reference data filed
  under a menu: `shopping_list_entry` has carried `ingredient_id` beside
  `free_text` since `0006`, under a check that exactly one is set, so a top-up
  is already an ingredient put on a list with no recipe near it. The stub
  badge's old dot retires — a count line says outright what the dot hinted at.
- **`/account` holds the household, this device and the session** — the
  members and their usual portions, the quiet sync line, and Sign out with its
  confirm. A pushed page, not a fifth tab: the four tabs are a loop (find ·
  plan · cook · buy), and this is visited monthly. The *loud* half of sync
  health does not live here — a stall or a refused write still raises the
  shell's banner over whatever you are doing.
- **Search is a field pinned under the header**, not a sheet or a route. A live
  query REPLACES the tree with flat rows carrying a `Book · Section` filing
  line (without it, two recipes called "Ragù" in two books are the same row
  twice); clearing it restores the tree exactly, folds included. Titles only in
  v1 — an ingredient-level search ("recipes with almonds") is a different query
  shape and needs a row that explains its own hit. Matching is the shared
  deterministic predicate (ADR-0004), never a second matcher.
- **Books fold** from a chevron on the header, default open, remembered per
  device. A folded book keeps its honest count line (`42 recipes · 3
  sections`), because a fold that hides how much it hides is a fold you stop
  trusting. Sections do not fold.
- **A book's `⋯`** offers Rename · New section · Move up / Move down · Delete
  book. **Delete is refused when the book holds recipes**, naming the count read
  at the moment of the tap, and the refusal is a door: "Move them to…" re-files
  every recipe into another book **unsectioned** (a section belongs to the book
  it was named in) and says so before it acts. Deleting the household's only
  book is refused separately — `ensureDefaultBook()` would re-mint one, and a
  book that reappears is worse than a refusal.
- **A recipe row is title · ★ (only when favourited) · serves N · ›.** The star
  reports; toggling stays on the recipe page. No shelf-life chip and no macro
  badge: shelf life is a planning fact, and on honest numbers a macro badge is
  a number nobody asked for or an `incomplete` nag on most rows.
- **Empty states are honest.** A count of zero reads "no recipes yet", never
  `0 recipes`. An empty shelf offers the two doors in place — it has no section
  labels to hang a `＋` from, so the dashed pair stays exactly where it has
  always been. A search with no
  hits echoes the query as typed — never "did you mean", which no matcher backs
  yet — over `＋ new recipe called "…"`, which carries the query into the
  editor as the title (`/recipes/new?title=`), and `⤓ import a recipe instead`.

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

**The Week screen (week v3, design board "Week · v3"):** one screen, one
state. v2 split it into a presentation mode and an edit mode because "the mode
changes what a tap means"; v3 deletes the mode, because a row's three targets
say what each tap means without one.

- **A dish row is two lines:** the title with its eaters and — only when the
  override differs from the eater count — a portions chip; beneath it the
  **cook marker**, read back off `buildCookPlan` for the same week (`cooks
  today · batch of 4` with the mini fresh→gone bar · `from Monday's batch` ·
  `Tuesday's freezer share ❄`). A single-meal cook gets **no marker** — "cooks
  today" on every row is noise, and an absent second line collapses the row
  back to one. The marker and the day's macro line are **never hidden**: v2's
  edit mode suppressed both, which blanked the numbers you were editing
  against.
- **A row's controls are the facts the row prints (E7).** The **title** opens
  the recipe it names. The **portions chip + eater avatars are one target**,
  opening a compact editor holding exactly those two fields — one target and
  not two, because the chip is drawn only when an override differs, so a
  chip-only tap would be missing from most rows and could never *set* a first
  override. The **`−`** removes the meal. Day · slot is not a printed value —
  a row's *position* is its day — so a meal is **moved by removing it and
  adding it again** through the picker's "already this week" quick picks.
- **Remove is undone, not confirmed (E3).** The `−` is muted, not red, and
  there is no confirm dialog: it would tax every removal to prevent a rare
  mis-tap. What makes it safe is an **undo toast** naming what would come back
  ("dinner · Ada & Jun · 1¾ portions"), because an undo you cannot audit is a
  promise rather than a control. This is the one deliberate exception to "no
  success toasts" — the toast is not reporting success, it is carrying the
  undo.
- **One add door, in every state (E5).** `＋ add a meal` is the last row of
  every day card, sitting with the meals and **above** the day's total,
  because it adds a *meal*, not a number. On an empty day it is the same line
  saying `nothing planned`. It replaced v2's dashed edit-only box and its
  separate emptiness line, which were one door wearing two hats.
- **The test a target must pass** is not "is the row's tap unambiguous" but
  **"is the target drawn"**. That is why there is no long-press anywhere on
  this screen, and why the `›` went: it was drawn, but it announced *the row
  navigates* and so competed with the row itself.
- **The lens** (`Everyone · Ada · Jun`) sits with the numbers and **dims** the
  meals a person is not eating rather than removing them: a day somebody else
  cooks for themselves is not an empty day.

**Macros on a set of meals — the rule (invariant 3 at a new scope):**

> A meal-set total shows the sum of the meals that **resolved**, is labelled
> with its **own denominator** (`1 of 2 meals`), and **names every excluded
> meal** in `incompleteNote`'s exact words. When **nothing** resolves, no
> number is drawn at all — the `incomplete` badge and the reasons, exactly as
> the recipe macro panel refuses. An **empty** set is a third state — `no
> meals` — never `0 kcal`.

This is not invariant 3 bending: on the recipe page the scope is fixed ("this
recipe's macros") and a partial sum lies about it, whereas here the scope is a
set of meals whose label states it and each meal is an independently honest
unit — the shopping list's doctrine. The teeth: the denominator is mandatory,
and an exclusion is *named*, not counted. Under **Everyone** an entry counts
`portions ?? |eaters|` servings; under a **person's** lens it counts only if
they are an eater, at an even split (the only figure `eaters` + `portions` can
honestly state). An entry nobody is eating is excluded with a reason, never
divided by zero. The week band is labelled **PLANNED** and says outright that
it is the sum of what is planned, not a daily target — a week that only plans
dinners averages a dinner.

**House rule — a screen never swaps itself out for a data condition (D5b).**
Chrome (header, switcher, tabs, mode, lens, primary doors) always renders.
Emptiness is expressed *inside* the screen's own structure — a quiet line where
the content would be, on the row, card or section that is empty — and every
empty region carries the affordance that would fill it. A full-bleed
illustrated state is reserved for a screen with genuinely **no** valid action;
there are none in this app. Corollaries: an absence is written as an absence,
not a zero; and the first tap after "empty" lands where the user pointed, not
on a default. Applied to Week (the blank-week page is deleted; an empty week is
seven empty day cards, one `＋ Add the first meal`, and `copy last week` while
it has zero entries), to Cook and to Shop.

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
