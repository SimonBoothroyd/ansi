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

The authoritative column list for every table is generated from the migrations
into [`../generated/db-schema.md`](../generated/db-schema.md) (`make docs`,
diffed by `make docs-check`). This section says what the tables *mean* and
which facts are load-bearing; where the two disagree, the generated file is
right.

### Household & members
- `household: id · name · week_starts_on`
  - `week_starts_on` is the ISO weekday the household's week begins on
    (1 = Monday … 7 = Sunday, Monday by default). It decides which seven days a
    week **is**, so it is a household fact rather than a device one: two phones
    disagreeing about it would not disagree about a view, they would file meals
    into two different weeks. Set from the Household section of `/account`,
    and the phone only ever reads it — see *Meal plan* below.
- `household_member: id · household_id · display_name · auth_user_id ·
  portion_factor` — the two named people. `eaters[]` on a meal references
  these. `portion_factor` is that person's usual portion (¼–3, ×1 by
  default), set from the household roster on `/account`; it is what makes
  demand fractional.

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
  `ingredient.allowed_units` lists exactly what a line may *say*. Since
  [ADR-0014](../decisions/0014-all-to-all-admission.md) the derived rule is
  **all to all**: the whole basis family, always (yeast finally admits `g`,
  and `kg`, `oz`, `lb` with it), the whole other mass/volume family once a
  density exists (demoted below the measures in chip order), `piece` on a
  count row, and imprecise words only for the categories that earn them.
  There is no kitchen trim and no magnitude gate — the household prunes what
  it will never say, per row, in the flesh-out form — and `mg` is not a unit
  at all any more. Materialized at
  creation from `default_allowed_units()` (Dart mirror
  `defaultAllowedUnitSet` — shared test vectors), **editable per ingredient in
  the flesh-out form** (`/ingredients/:id`), and carried verbatim into the
  seed — which lists every row whose list overrules the derived one
  (`supabase/seed/README.md`, R4). Since
  [ADR-0009](../decisions/0009-density-unlocks-both-families.md) the density leg
  is ungated — a stored density unlocks the other family whatever the default
  unit's family, so "1 cup diced mango" is sayable on a piece-default row — and
  a density arriving after creation extends the list by trigger, wherever it
  came from. What we may *compute* is unchanged — totals still degrade honestly.
  A row's **default unit** is a different kind of fact — what the household
  counts the thing in — but it must still be one the row can *say*, so the
  chip row **offers only the sayable units** (`defaultUnitOfferFor`): the basis
  family always, the other mass/volume family once a density bridges it. The
  rest are named in one line under the row in the allowed-units note's voice —
  *tsp · tbsp · fl oz · cup · ml · l · pt · qt unlock when this row has a
  density* — rather than offered and then refused. `piece` is the exception
  that stays offered unweighed, because picking it is what opens the weight
  field.
  The **stored** default is always drawn, sayable or not: a default stranded
  after the fact — a basis flipped to per 100 ml under a `g` default, a density
  deleted under a `cup` one, a `piece` still unweighed — is the chip the person
  must move off. It renders as the selection *and* as stranded, is flagged on
  the line under the chips, and is **refused at Save**. The flag names the
  unit, the basis and both fixes — add a density, or switch to the basis
  family's unit — and the stored row is never rewritten silently.
- **An amount prints and parses as a kitchen fraction** (`formatAmount` /
  `parseAmount`, `core/units/number_format.dart`). Halves, thirds, quarters
  and eighths print as the **vulgar glyph**, tight against the whole — `½`,
  `⅔`, `1⅛`, never `1 1/8` and never `1 ½`. All nine glyphs are carried by
  every bundled face, and a structural test reads each font's `cmap` so the
  ruling cannot rot. A stored value within 0.0075 of a fraction IS it, so a
  figure already rounded on its way in reads back as what it was — `0.67` is
  `⅔`, `0.13` is `⅛` — while `0.26` stays `0.26`. Anything else falls
  through to the trimmed two-decimal rule. Reading back takes decimals with a
  dot or a comma, `2/3`, `1 1/2`, `1½` and the vulgar glyphs, and **stores the
  exact value** (⅔, not 0.67). A field that takes an amount therefore uses
  the TEXT keyboard: iOS's numeric pads carry no `/`, and a person typing
  `2/3` into one must be read. The portion count keeps its own rule (`¼ ½ ¾`
  glyphs, `formatFraction`), and a macro figure keeps its own (energy whole, a
  gram figure whole from a gram up and one decimal below it) — macros are
  label readings, not fractions.
- **The fraction is a kitchen unit's rule, not every unit's.** `g`, `kg`, `ml`
  and `l` are what a scale and a jug read out, and they read decimals:
  `213.5 g`, never `213½ g`; `1.5 l`, never `1½ l`. Cups, spoons, fl oz,
  oz, lb, pieces, named measures, servings and batches are said by hand and
  keep their fractions, as does a figure with no unit at all — a bare count,
  the cook plan's `×¾`. Which rule a figure gets is decided by
  `formatAmountIn(amount, unit)` (and `formatQuantityIn` for one that may be
  absent), off `Unit.isMetric`; every surface with a unit in scope prints
  through it, so the same number reads the same way wherever it appears.
  **Only printing splits** — a grams field still accepts `2/3` typed into it.
- **Density is the single volume⇄mass fact**, entered as one sentence
  (7.8): "1 `[tbsp]` weighs `[N]` g" (`densityFromVolumeWeight`), with `ml`
  among the spoons so a known g/ml is typeable exactly. A volume-named measure label is therefore
  REDIRECTED into density entry — volume-named measures never exist, so the
  two facts can never disagree. Saving a density also extends the explicit
  `allowed_units` with the family it unlocks, in the same write.

### Ingredient
The column list is generated from the migrations —
[`../generated/db-schema.md`](../generated/db-schema.md), kept honest by
`make docs-check`. What the columns *mean*:

- **Aliases are rows, not a column.** `ingredient_alias` holds the other
  names a household calls a row (`ingredient_alias`: `alias_text` as it was
  seen, `match_text` normalized, `source`; per household, soft-deleted like
  everything else). The matcher searches them beside the canonical name.
- **A row coined here states its category.** `/ingredients/new` keeps Save
  down until one is picked, in the form's own refusal voice, because a
  category decides two things a guess gets wrong: where the row sits in the
  shop walk (`core/aisles.dart` — uncategorised sorts ahead of every aisle,
  under *Other*) and which imprecise words it may ever say
  (`kImpreciseCategoryGates` — no category, no `pinch`, no `handful`). Nothing
  is defaulted to `pantry`, and a scan or a USDA pick does not fill it: the
  sources have no opinion the household's aisles would recognise. Rows that
  already exist without one stay saveable — the rule is about coining a row,
  not about editing one.
- **A typed name is tidied when the field is left, and the form says what it
  changed.** Every name a person writes in an editor — an ingredient's
  canonical name, a recipe title, a book or section name, an alias — is
  trimmed, has its runs of whitespace collapsed and loses a lone trailing `.`
  or `,` the moment the field loses focus, with Save as the backstop for a
  field that was typed in and never left. It is then Title Cased, small words
  excepted (`cream of tartar` → `Cream of Tartar`, `smoky bean stew` →
  `Smoky Bean Stew`, `desserts` → `Desserts`) — **one rule for every kind of
  name**, because a recipe title and a book name sit on the same shelves as an
  ingredient and reading as a label is what a shelf wants. What follows a
  comma is a qualifier and is left exactly as typed (`Chicken Thigh,
  boneless`). Only an alias is exempt, left as typed because the vocabulary
  stores aliases lowercase. Case is only ever *added* — `BBQ sauce` becomes
  `BBQ Sauce`, never `Bbq`. An
  ingredient's canonical name additionally gets **one suggestion**: a name that
  reads as a recipe line becomes the entry it was about (`chopped onions` →
  `Onions`, `2 cups flour` → `Flour`; a plural is a name, since the vocabulary
  keeps `Bay Leaves` and `Chives` as they are), using the same word classes the
  normalizer keys on. Case and spacing change silently; a changed *word* never
  does — the field prints `was “chopped onions” · keep the old word` beneath
  it, and one tap restores the typed name and stops the suggestion for it until
  it is edited again. It fires in editors only: **not** in the ingredient
  picker, not on method prose or line notes, not on shopping item names or meal
  labels, and never on a name a save left untouched.
- **A household's ingredient names and its aliases are ONE namespace**, keyed
  by `match_text` (`domain/name_namespace.dart`). A name that lands on one
  already there — a canonical name or somebody's alias, `Sauerkraut`,
  `sauerkraut ` and `Sauer-Kraut` being one name here — **refuses the save**,
  in the row's own words (*Already an ingredient: Sauerkraut*) with that row as
  a door. A row is always saveable under the name it already has. A name that
  is merely *near* one is not refused: up to three rows surface under the
  pickers' `DID YOU MEAN` band, and on `/ingredients/new` a tap **asks** ("Use
  Sauerkraut instead?") before it pops the form with the existing row — the
  person resolved it, not the rule. Nothing renames onto an occupied name and
  nothing merges two rows. Detail:
  [`search-and-matching.md`](../design-docs/search-and-matching.md) §4.
- **An ingredient is retired only when nothing live names it**, and **a line
  whose ingredient is gone is shown and repairable.** The two halves are one
  rule. `ingredient_id` carries no `on delete` and a delete is a tombstone, so
  a retired row a line still names leaves the line pointing at nothing — and
  the readers that filter on liveness then drop it, which is a recipe silently
  one line short. So the retire is refused while a live line names the row, in
  the app's ⋯ menu (*Still used by 3 recipes (4 lines)*) **and in the database**
  (migration `0041`, so a hand statement at a SQL prompt meets the same rule
  with the same count). A line counts wherever a line lives: a recipe line, a
  bare-ingredient meal, a this-week swap. And where a line was already left
  broken, it reads with the row's **last known name** plus
  `ingredient removed · pick again` — muted, on the recipe page and in the
  editor, where the row opens into its card and `change ›` is the picker, so
  the line keeps its id.
  Nothing derives from a retired row: the macro total leaves the line out and
  names it, in the same voice a stub line is named. The same migration
  re-points what was already broken onto the single live row of the same
  `match_text` where there is exactly one, and leaves a line with no single
  twin for a person to pick — guessing between two live rows is not a repair.
- **`source_label` says which food the numbers came from, by name.**
  `source` holds a key — an FDC id, a barcode — and no screen ever prints one;
  `source_label` is what a person reads. A USDA pick stores that food's
  description alongside `source = usda_fdc:<id>`; a barcode scan stores the
  pack's brand and product name alongside `source = off:<barcode>`, and stores
  nothing where Open Food Facts named neither, because no label means the row
  says nothing rather than inventing a name. `source_score` is the USDA half of
  it — the query's coverage of the matched description, so the form can say how
  well the food fits the name typed. A scan is an exact-key fetch and carries
  no score. Both are written offline-first, so the form and the lists print
  them with no network.
- `source` is **provenance, and it is load-bearing**: `seed` (the template
  vocab), `manual` (made through `/ingredients/new`, from the manager or a
  picker), `import_stub` (created at an import commit), `usda_fdc:<id>` (a food picked from the USDA search),
  `off:<barcode>` (a barcode scan). Until 0029 a server trigger read it to
  decide whether a row was its business; **nothing matches to USDA on its own
  any more** (plan 0029), so a `usda_fdc:<id>` stamp always means a person
  picked that food. `seed` (whose density-less tail is audited, not
  accidental) and barcode rows (whose Open Food Facts provenance must not be
  overwritten by a USDA id) are safe by construction now rather than by a
  trigger's WHEN clause.
- `status = stub` → surfaces in the manager's stub band + honest macro math.
- **A macro panel is four required figures and an optional fifth.** `kcal`,
  `protein`, `carb` and `fat` are all-or-none — a part of a panel is not a
  panel — and `fiber` is stated or not, per row. A row without fibre is
  **complete**, the form's fifth field may be left blank, and the stored jsonb
  simply omits the key. Fibre alone is refused: it qualifies a panel rather
  than being one.
  - **A total states fibre only when EVERY figure behind it did**, at every
    scope — a line, a recipe, a day, a week. A fibre total short by an unknown
    amount is exactly the fabricated number invariant 3 forbids, so it is not
    shown; instead the lines that could not supply it are **named**, in the
    `not counted` grammar the imprecise and optional lines already use:
    `fibre not counted · 2 lines without it: Onion, Stock`. An unstated fibre
    is never an exclusion — the line is in the total, the denominator does not
    move, and nothing is flagged as needing a fix.
  - Where it shows: the macro line appends ` · 3 fibre` (spelled out — `F` is
    fat), the recipe panel gains a fifth cell, and the week's strip gains a
    `fib` cell. Each appears only where the figure does; a blank cell would
    read as a zero.
- **A panel that argues with itself says so, and blocks nothing.** One muted
  line under the macro fields, in the derivation's own slot, about what Save
  would *store*: protein, fat and carb all zero on a food that states calories
  ("the label's macros are all zero for a food with calories"), or a
  fibre-adjusted Atwater gap — `4P + 9F + 4C` with a stated fibre moved off
  the 4 and onto a 2 — that misses the stated energy by more than **both**
  150 kcal and half of it ("these numbers don't add up: about N kcal from the
  macros"). Both thresholds are deliberately loose: acetic acid and alcohol
  are not Atwater macros, so a vinegar and a glass of red wine break the
  arithmetic honestly, and so do a mineral raising agent and a high-fibre
  cocoa. It is advice — the dock owns the refusals, and a panel read off a
  label is the household's whatever the arithmetic makes of it.
- **Where the line is dense, the two fixed units are glyphs.** On a picker
  row, a recipe line's own macros, the week's strip and the ingredient page's
  read line, energy is drawn as a flame after its figure and fibre as a sheaf
  of wheat after its own; each carries the word it replaced to a screen
  reader, so nothing is lost to anyone who cannot see it. The words stay where
  there is room for them — the recipe panel's cells, and the form's field
  labels, where a person is typing into the slot the word names.
- **One rounding rule, and it is display only.** Everywhere a macro figure is
  printed — a form field's seed text, the derivation under it, a picker row,
  the recipe panel's cells, the week's strip — energy prints whole, and so
  does a gram figure of a gram or more; below a gram it keeps one decimal
  (`286`, `21`, `0.4`, `0`). Whole because nobody weighs the tenth of a gram
  of protein in a portion; the sub-gram decimal stays because an oat milk's
  0.42 g must not print as `0`.
  What is stored is untouched by it: a field nobody typed in saves the figure
  it was seeded with, so a row derived from a serving reverses to the label's
  own numbers exactly.
- **Macros are stored WITH the basis the label read them in** (per-100 g or
  per-100 ml — liquid labels read per 100 ml, and densities are sparse, so
  converting at entry can't be the design). A **barcode** scan has to work that
  basis out: Open Food Facts files both readings under the same `*_100g` keys
  and defaults `nutrition_data_per` to `100g`, so a gram reading there is the
  form's default rather than a claim. The mapper reads, strongest first, a
  `nutrition_data_per` that *names* ml, the net quantity printed on the pack,
  the conversion the label prints beside its serving (`0.25 cup (28 g)`),
  `serving_quantity_unit`, then OFF's own `en:beverages` category — and never
  implies a density from any of it. Consumers apply the aggregation
  doctrine: a line whose unit family matches the basis computes directly;
  cross-basis bridges only via density; otherwise the total is honestly
  `incomplete`. USDA prefill rows are per-100 g.
- **A US label is entered per serving, in the unit it prints in.** The macros
  section's third mode takes an amount and any kitchen unit (`g kg oz lb · ml l
  tsp tbsp fl oz cup pt qt`), and **the unit's family is the basis**: a mass
  serving stores per 100 g, a volume one per 100 ml, converted through the unit
  catalog alone — `2 tbsp` is 29.57 ml exactly, and no density is involved.
  The four fields hold the label's figures as printed and one muted line under
  them says what will be stored. Changing mode **clears** them: they meant per
  100, and reading them as per serving is how a right number becomes a wrong
  one. Nothing typed in the mode yet and what it cleared comes straight back,
  so a mis-tap costs nothing — but with **figures in and no serving under
  them the mode does not leave**: there is no derivation to put in their
  place, blanking them invites the label's serving column to be retyped as
  per 100, and carrying them across relabels it. The chips say the same
  sentence Save says about the same missing number, and the figures stand.
  A **scan lands in this mode whenever the label printed figures for one
  serving** — whether that was the pack's only column or the one it printed
  beside its per-100 one: the label's numbers are the fact and per 100 is the
  derivation. A serving with no figures of its own, or figures with no serving
  to divide by, lands per 100; a per-100 scan that named no serving at all is
  the one state the form says, unprompted, that the mode is there.
- **The serving is kept as the row's one `serving · 2 tbsp` measure**, so the
  reading posture prints the label's own line back — `190 kcal · 7P 7C 16F per
  2 tbsp` — by reversing the stored per-100 exactly, with the per-100 figures
  muted under it. A save that states a serving replaces whatever serving the
  row had; one that says nothing about it leaves it alone.
  - **It is stored as a measure and listed as none.** The reserved
    `serving · ` prefix (`domain/serving_measure.dart`) is what every list of
    measures filters on, in the read posture and in the editor alike: the
    serving is not a word the household coined, and it is stated in
    *Nutrition*, beside the figures it is printed per. Its one remaining
    appearance is the quantity sheet's chip row, labelled by its **size** —
    `serving (237 ml)`, the way `piece (110 g)` reads — because "1 serving"
    is an amount a week's ingredient slot can genuinely say.
- **A density is stated in the density sentence and nowhere else.** That
  sentence takes an amount now — "2 tbsp weighs 32 g", as a pack prints it —
  and reads back the same way, with the stored `g/ml` as the aside. When the
  row's serving is a volume, the sentence is offered that amount and unit as
  its left-hand side.
  - **A US serving line is a density statement, and both halves are kept.**
    "2 tbsp (7 g)" weighs one spoonful in one breath, but only the reading the
    row's basis is in can be its `serving` measure — so on a per-100 g row the
    spoon would be thrown away and on a per-100 ml row the weight would. The
    pack's line is kept verbatim beside the serving and read back for the
    density sentence, which is then offered **both** slots filled in. It stays
    an offer: nothing is written until the button is pressed
    ([ADR-0008](../decisions/0008-unit-admission-model.md) §2,
    [ADR-0011](../decisions/0011-one-save-one-write.md)), and typing over
    either half is the ordinary case. A serving with no volume anywhere —
    typed or printed — offers nothing, because what a millilitre of a gram
    weighs is not a fact.
- **The seed is the owner's household, exported.** `supabase/seed/snapshot.jsonl`
  holds one JSON object per curated ingredient — its columns, its aliases and
  its measures, each with the `source` stamp the row already carries — and
  `supabase/seed/scripts/gen_seed.ts` generates `supabase/seed_vocab.sql` from
  it. Nothing is re-derived: a density, an admitted unit, a kept measure, a
  borrowed piece weight are decisions somebody made in the app, on the row, and
  the seed copies them rather than mining them back out of USDA FoodData
  Central, Open Food Facts or FAO/INFOODS — which is what every row's `source`
  names instead. The counts are computed by the generator into
  `supabase/seed/counts.json` and never typed by hand. Most rows state a
  density; the handful that do not are honest gaps for a person to fill, not a
  pipeline that missed. The pipeline and the invariants it fails a reset on:
  `supabase/seed/README.md`.

### Ingredient measure (steps 7.6–7.8)
An `ingredient_measure` row names one countable thing and says what it weighs:
`basis_amount` is `> 0` and denominated in the ingredient's `macros_basis`
(g or ml, 0012), which is what lets a count bridge to the numbers.
- Per-household, synced, user-editable rows — households disagree about what
  "1 portion" is. An imported line lands on a measure the row **already** has,
  by exact label (`clove` → the `clove` measure); minting one from a printed
  "400 g tin" is a tap in the measures editor, never something the import does
  on a household's behalf. The starter set is the curated household's own
  measures, exported into the
  seed (`supabase/seed_vocab.sql`, per-row `source` provenance) and clones
  with
  the vocab at onboarding (backfill gated run-once by
  `household.backfilled_at`, 0011 — deleting your measures never resurrects
  them).
- **In-app measure editor (7.7; density entry 7.8):** authors
  `source = 'manual'` rows ("half can = 200 g"), **renames and re-weighs one
  in place** (the row is the tap target and the id is kept, so every line
  already pointing at it follows the correction), **reorders the list by
  drag** — the first row is the ingredient's *typical* measure, which is what
  fronts the chip row — soft-deletes unwanted ones,
  and sits beside the DENSITY entry ("1 tbsp weighs N g", which folds to
  `0.13 g/ml · change` once the row states a number).
  - **A measure a recipe still uses cannot be deleted.** The FKs carry no
    `on delete` and a delete is a tombstone, so the lines naming it would
    simply stop counting — dropped from the macro totals, degraded to a bare
    count on the shop. So the delete counts the lines first and refuses with
    something to act on: *2 lines still say it, in 1 recipe*, and a **Show me
    where** door listing every recipe that does. Both delete paths — the
    sheet's manage state and the flesh-out form — go through the one gate.
  Labels that merely name a volume unit are redirected into that density
  entry — density owns volume conversion. Provenance is shown humanized
  (USDA portion / borrowed / estimate / yours), never as raw machine strings.
  A curated `seed:typical` row reads **estimate**: the list's *order* is what
  says which measure is the typical one, so the word would have read as a flag
  on the row rather than as where the number came from.
  - **The editor reports intent; the host decides when it becomes a write**
    ([ADR-0011](../decisions/0011-one-save-one-write.md)). The same two
    widgets serve two screens with two persistence models, and neither is a
    flag on the widget: in the **quantity sheet** the host writes on tap and
    the verb is *Save*; on the **flesh-out form** the host adds to a draft,
    the verb is *Add*, and nothing reaches the database until one Save
    applies the row, its measures, its density, its piece weight and its
    aliases in a single transaction.
- **No unique label index** (0011, the shopping-entry doctrine): two offline
  devices adding the same label must never fail upload — duplicate live
  `(ingredient_id, label)` rows merge deterministically on read (oldest row
  canonical), and hidden duplicates still resolve by id from lines.
- `recipe_line_item.measure_id` / `shopping_list_contribution.measure_id`
  (nullable FKs) quantify a line in a measure ("2 × potato, large"); the
  quantity surface offers an ingredient's live measures as chips beside its
  honest unit set (`allowedUnitChoicesFor`).
- **A PIECE WEIGHT is a row fact, exactly as a density is**
  ([ADR-0015](../decisions/0015-piece-weight-is-a-row-fact.md)).
  `ingredient.piece_basis_amount` says what **one** of the ingredient weighs, in
  the row's basis unit; `piece_source` says where the number came from
  (`manual`, or *borrowed from &lt;label&gt;* where the seed copied a curated
  size — onion borrows `onion, medium` = 110 g). Density says what a volume of
  this weighs and unlocks the volume family; a piece weight says what one of
  this weighs and unlocks `piece`.
  - **`piece` is admitted iff the default unit is `piece` AND the row has a
    piece weight.** It is never offered on a row with any other default unit,
    and the form draws the weight field only while the default unit is `piece`.
    Setting the number unions `piece` in; clearing it strips `piece` out, the
    way clearing a density strips the units it granted.
  - **A `piece` default with no weight is a stranded default**, in the same
    class as a `cup` default with no density: the form draws the flag with its
    one-tap fix — *piece needs a weight on this row — enter one below, or switch
    to g* — and **refuses Save**. Nothing is saveable as `piece`-default
    unweighed, and nothing at runtime has to decide what a `piece` meant.
  - **Measures are for every other count word** — a size, a fragment, a
    container (`onion, small` · `clove` · `can (400 ml)`). Nothing is named
    after the row, no measure is created on a household's behalf, and no row
    points at one. A row may honestly carry both: *an unsized onion weighs
    110 g* and *a medium onion is 110 g* are two statements, the first sourced
    from the second and free to diverge.
  - **A count converts like any unit.** The macro engine reads a `piece` line
    through the piece weight the way it reads a `cup` line through the density
    — no read-through rule, no "counted as" note on the line. (The shopping
    list still totals a count per unit — "2 piece" — as it always has; the
    weight is a macro fact, not a buying one.) A bare count on a row with no weight can only be a row created
    before this model landed; it reads `needs a piece weight`, and that marker
    opens the *ingredient's* form. One number fixes every bare count of that
    ingredient in every recipe.

### Recipe
A recipe is a title filed under a book and a user-defined section, with a
`servings_base` it scales from, a `favorite` flag, its ingredient groups and
its steps.
- **ingredient_group:** `name · line_items[]`
- **line_item:** `ingredient_id · quantity · unit · optional (0025)`
- Scaling = quantity × factor (imprecise units left as-is).
- **Optional lines (plan 0025, D6a/D6b).** `optional` is a stored fact about
  a line — "lime, to serve (optional)" — not about its amount: the page
  still prints `1 lime`, with a muted `optional` tag after the note in the
  stub badge's voice. It is seeded from the extractor's flag at import and
  set from **the line card's flag row** — which leads that row on every
  expanded card, in the editor and at review alike, matched or not, and reads
  the line rather than the raw extraction. The quantity/unit sheet keeps its
  Optional switch only where the host has no card to carry it (the week's
  variant editor); on a recipe line the toggle is the one door. It rides a sub-recipe component line as it rides an ingredient
  one, and the seam names the sub-recipe's title where it left. Its only
  effect is on what a
  TOTAL covers, through one seam — `effectiveLines(lines, overrides:)` —
  that every derivation runs over: the macro summary and the shopping list
  leave the line out **and name it where it left** (an `OPTIONAL · Lime,
  Coriander` row under the panel, beside the imprecise one; `2 optional lines
  not listed — lime, coriander` as the recipe's muted echo row on Shop, where
  each name is a **door** — a tap writes this week's include row for that
  line), never a silent drop. **The cook plan honours the flag through the
  same seam**: an optional ingredient line changes nothing there — a batch is
  a batch whether the lime comes — but an optional sub-recipe component is
  only cooked when the week includes it, because a sauce nobody is making is
  a pot nobody is washing. A recipe whose
  every line is optional summed nothing and refuses, like an all-imprecise
  one. **A planned week may overrule the recipe** through the same seam:
  `effectiveLines(lines, overrides:)` applies that week's variant *first* — a
  line ticked back in, left out, swapped, re-amounted or added — and hands
  back what is left with `optional` cleared on anything the week already ruled
  on, so a second pass changes nothing. A caller holding no week passes no
  overrides and reads the recipe as it stands.
  - **Optional has two owners, and each decides where the question comes
    up.** The recipe says *may be skipped* — the author's claim, from import
    or the editor, and the only place the flag itself changes. The week says
    *this time, yes* — the cook's claim, the `include` row. On the recipe
    page **opened from a week that plans it**, the tag is that switch: an
    empty ring before `optional`, one tap → a filled `included` chip, the
    week's row written, the panel recounted over the week's lines with an
    `INCLUDED · names · for this week` row. The shop's echo names are the
    same door. From the Library the tag is a tag: with no week there is no
    decision, and nothing is written. A household that always wants the lime
    unticks optional in the editor — for them it is not optional; there is no
    third "usually yes" state.
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
  - **The walk keeps both halves.** Every line that joined is recorded with
    what it contributed (`RecipeMacroSummary.lineMacros`, keyed by line id)
    beside the notes naming every line that did not, so a surface printing a
    figure per line reads the sum rather than converting anything a second
    time. The recipe page's `⋯` menu toggles that on — **`Show line macros`**,
    off by default, held for the session and never persisted — and prints
    each line's own `197 kcal · 2P 3C 20F` under its name — protein, carb,
    fat, the panel's own order, one size down. These are the line
    *as displayed*, so unlike the per-serving strip they **do** move with the
    servings scaler. A line the total left out prints its reason instead of
    figures, in `incompleteLineNote`'s exact words — never a zero, and a
    folded multi-use row prints figures only when every use joined, so a
    partial is never shown either. A line whose amber marker is already
    printing that reason does not print it twice.
  - **The refusal NAMES its causes** (plan 0024 seam D5). The count line the
    picker rows print is kept verbatim, and under it the panel lists the
    lines the total is waiting on — `Dragon fruit · needs a piece weight`,
    `Tofu · stub ingredient` — capped at four with `+N more`, each one a door
    to the fix its reason implies; `needs a piece weight` opens the
    **ingredient's** form, because the missing number is the row's, not the
    line's. The same reason is drawn **in place** on the
    ingredient row, in the import review's amber, because it is the same
    claim: *this line is why a number is missing.* One helper
    (`incompleteLineNote`) gives every reason one wording, so the panel, the
    marker and the picker row are one vocabulary. Nothing new joins any
    total; the refusal just stops being anonymous.
  - **Imprecise lines never gate the total** (seam **D6**). `to taste`,
    `pinch`, `dash` and `handful` are unweighable BY NATURE — no measure and
    no density turns a handful into grams — so they are excluded **by rule**,
    the total is shown, and the exclusion is printed under it by name, every
    time, in a labelled row of its own: `NOT COUNTED · Parsley · handful,
    Sesame seeds · to taste`, with the optional lines in a second row under
    it and one caption under both.
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
  *Reality check:* this rule is only bearable because the seeded vocabulary
  states a density on all but a handful of its rows, so most real recipes read
  as numbers. The rows that still cannot bridge are an honest tail for a person
  to fill in — the `incomplete` they produce is the rule working, not the rule
  misfiring.

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
are, and only visibly.

**A new word arrives in the old word's case** (`chipWord`). A name is stored
Title Case and a sentence usually is not, so the word being replaced decides:
lower-case in, lower-case out (`Olive Oil` → `add the olive oil` — **every**
word of the name goes down, not just the first), a capital keeps a capital and
touches nothing after it (the stored name already is capitalised), and an
ALL-CAPS word of more than one letter shouts the whole name. A word carrying a
capital *after* its first letter is a shape somebody meant and stands whole —
`BBQ sauce`, `pH buffer`, `McIntosh apple`. A plain leading capital is not that
evidence, because the vocabulary stores every name Title Case: `Aged Parmesan`
reads `aged parmesan` mid-sentence. A chip being *made* has no old word, so its
position decides instead: the stored name as it stands when it opens the step,
lower-case anywhere else. Case is all that is fixed —
pluralising a swapped-in name is not attempted. Removing a referenced line asks first and leaves each
chip's word as plain text, and `save()` prunes dangling refs regardless: **a
saved method never refs a line the recipe does not have.**

**A chip's label is the printed word, and it wins over the line's name.** A
labelled chip never looks its line up to render: the step says `salt` over a
`Kosher salt` line and `aioli` over `Romesco Aioli`, because the prose is what
someone wrote. What a chip takes from its line automatically is the
**amount**; the word changes only through the visible, one-tap-undoable
relabel above, and never on a quantity, unit, measure or note edit.

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
  - `unique (household_id, week_start_date)` — **many weeks per household are legal**, one row per week, created lazily on a week's first meal. Nothing is written by *looking* at a week.
  - **A week is addressed by the date of its own first day**, and `day_of_week` is the **offset from that key**, 0..6 — never a calendar weekday. Which day that is belongs to the household (`household.week_starts_on`), so `week_start_date + day_of_week days` is a meal's real date under any start day, and one pure value (`core/week_shape.dart`) resolves a date into a week, a week into seven labelled days, and an offset into the day it names.
  - **Changing the first day moves every week the household has planned.** The owner shops and plans on Sunday, so the week shopped for on a Sunday has to contain that Sunday's dinner; under a Monday key it belonged to the week that was ending. The flip is one server transaction (`set_household_week_start`) that re-keys `week_plan`, re-points every `plan_entry` by its own calendar date, carries the shopping ticks with their week and moves a variant only where its recipe left. Nothing is deleted and no meal changes date — only its address. It is **online-only** for exactly that reason (the same shape as the online-only match engine, ADR-0004), and residue-driven per week, so running it again is a no-op and running it after a meal queued offline repairs that week.
  - **A week is a position, not a singleton** (week redesign, D2). The app holds a *viewed week*, defaulting to the one containing today; the header names it (`This week · 31 Aug` / `Next week · 7 Sep` / `Last week · 24 Aug` / `Week of 14 Sep`) and steps through it. Unbounded in both directions; a past week is **editable, not locked** — nothing downstream corrupts, and every rule about *when* a week would lock is wrong for someone catching up on a Tuesday. There is no calendar and no month view, and "archived" is prose, not a column.
  - **Cook and Shop derive from the VIEWED week** (D3), not from the week containing today: you plan next week on a Sunday, so you must be able to cook and shop for it on a Sunday. There is **one** viewed week (plan 0025 D7a): changing it on any tab changes it on all three, and the week switcher is the **only title** of all three tabs (D7c — no "Batch cook plan" / "Shopping list"; the lit tab in the bar says where you are, which is why its selected state steps to herb-deep, D7d). The switcher's herb dot and its "This week" item are how a derived tab says which week it shows and offers the tap home; "Copy last week into this one" is a Week write and appears only on the Week screen's menu (D7b). Each tab's menu speaks in its own derivation — meals · cooks · items — for the week it has on screen.
- `plan_entry: id · week_plan_id · day_of_week · meal_slot (user-definable) · recipe_id · ingredient_id · quantity · unit · measure_id · eaters[] (→ household_member ids) · portions (nullable override)`
  - You just say *what you want to eat* per meal — no batch/leftover thinking here.
  - **Multiple entries per (day, slot) allowed** → different breakfasts, office-lunch-for-one, etc.
  - **A meal is a recipe OR a bare ingredient** (migration 0033), never both
    and never neither — the same XOR `recipe_line_item` has worn since 0017.
    Something you simply *eat* — a protein bar, a yoghurt, an apple — is
    planned as itself rather than dressed up as a one-line recipe. The `snacks`
    slot it usually sits in cost no migration: `meal_slot` was already free
    text.
    - An **ingredient** entry states the amount of ONE portion
      (`quantity` + `unit`, or a `measure_id` — "1 bar" — with `unit` holding
      the honest count fallback), set with the same quantity sheet every other
      amount in the app uses, opened on the row's own default unit. The
      amount columns are refused on a recipe entry, whose amount is its
      `portions`; `quantity`/`unit` are both-or-neither, and an entry that
      states no amount is a real state the surfaces name (`no amount`) rather
      than a number anything guesses.
    - It **carries eaters and multiplies** like any other entry — multiple
      people can have the same snack — so `eaters[]`, `portions` and the demand
      rules below are unchanged.
    - **Every derivation branches on it explicitly**; a null `recipe_id` never
      means "skip". Week macros weigh it from the vocab row's per-100 numbers
      through the same basis/density matrix a recipe LINE uses, and a stub says
      so in a stub line's exact words. **The cook plan ignores it** — nothing
      about it is cooked, so it opens no session and joins no batch. **The
      shopping list includes it**, which is why that derivation walks the
      week's *entries* and not only its cook sessions.
    - On screen it is **visibly not a recipe**: no shelf-life chip, no batch
      hint, no recipe door (its title opens the *ingredient* page), and its
      amount where a cook marker would be. The add door is **one** door — the
      planning picker gained an Ingredients section, the way the editor's line
      picker gained "Your recipes" — because a cook should not have to know,
      before searching, whether the thing they want is a recipe.
  - **Demand for an entry, in three rules** (`demandPortions`): the
    whole-number `portions` override wins when one is set; otherwise demand
    is **Σ of the eaters' `portion_factor`** — so a 1 and a ¾ eater want
    `1¾`, not `2`; and an eater the roster no longer holds counts as one
    portion, exactly as the head-count did. Demand is a `double` and is
    printed as a fraction everywhere, never rounded.
- `week_recipe_line_override: id · household_id · week_plan_id · recipe_id ·
  recipe_line_item_id (null only when the row ADDS a line) · action (include ·
  exclude · replace · add) · ingredient_id · sub_recipe_id · quantity · unit ·
  measure_id · note · sort_order` (migration 0040)
  - **A recipe cooked differently for ONE week.** The row is a **delta**
    against a recipe line, never a copy of the recipe: a swap, an amount, an
    addition, an exclusion, or an optional line ticked back in. The recipe is
    untouched, so the Library, the recipe page and every other week read
    exactly what they read before.
  - **One variant per (week, recipe)**, all days of that week. A cook session
    is one pot, one scale, one line set, so two meals of the same dish in one
    week that disagreed about what goes in could not share it.
  - **Amounts are absolute, never a factor.** The recipe moving 400 g to 500 g
    later leaves that week at the 400 g somebody asked for.
  - The **shopping list is where lines meet the week**, so it is where the
    variant joins: the derivation runs the week's overrides through
    `effectiveLines` before it expands a session, and names what the week left
    out the same way it names an optional line. That echo row is also a door:
    tapping an optional name writes the week's include row
    (`setLineIncluded`), and the item arrives with its `· this week, ticked
    in` provenance.
  - The **cook plan reads the week too**: the component graph is filtered
    through `effectiveLines` per (week, recipe) before any demand is derived,
    so an optional sub-recipe cooks only where the week ticked it in and one
    the week left out cooks not at all.
  - `sub_recipe_id` is a column and not yet a door — a **swap** of one
    sub-recipe for another stays suppressed (the filter rules on which lines
    the week cooks; it does not re-target them). The line picker suppresses
    its "Your recipes" section in week mode.
  - **Three doors, one screen.** The first is a row at the foot of the meal
    editor sheet — *edit for this week* — which states its own scope ("a change
    covers every day this week — Tue and Sat") because the sheet is per meal and
    the variant is per week. The other two are where a planned recipe is
    *looked at*: the Week's dish row and the Cook card's title open the recipe
    page **with the week they belong to** (`/recipes/:id?week=…`), and that page
    then prints one band under its title — "Planned Tue · Sat this week", plus
    "edited for this week" once there is a variant — and gains a second ⋯ item
    beside its own, renamed, "Edit recipe": **"Edit for this week · Tue & Sat
    only"**. The band is the condition of that item, not decoration: it says
    which days a tap would change. The week is re-checked against the plan
    rather than trusted, so a stale link offers neither. That page also
    **holds the week**: its Ingredients tab draws the week's effective lines
    read-only, in week mode's own grammar — a replaced amount as the week
    states it, an excluded line struck, an added line after the last group,
    an included optional line with its tag lit — and the `optional` tag is
    the one control on it, ticking a line in or out for that week without
    opening the editor. From the Library the page is untouched (Favorite ·
    Show line macros · Edit · Delete), and Cook stays read-only — its title
    carries the week, it does not write it.
    Still not a fourth target on the dish row: a control drawn on every row is
    a target every row pays for.

### Batch cook plan (DERIVED) — the second view
Groups the week's `plan_entry` rows **by recipe** — the ingredient entries are
not cooked and are left out by name, not by accident — then splits each group
into **cook sessions** bounded by shelf life:
- `cook_session (derived): recipe_id · covers[] (plan_entry ids) · cook_day (default = earliest covered day, user-adjustable) · total_portions (Σ demandPortions over covered — a double) · scale_factor (total_portions / recipe.servings_base)`
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

- `shopping_list_entry: id · household_id · ingredient_id (nullable) · free_text (non-ingredients, e.g. "paper towels") · checked · unit · week_start_date (nullable)`  ← one per ingredient the user has *touched* (checked off or topped up), plus one per free-text item — both **per week**; holds the check-off state
- `shopping_list_contribution: id · entry_id · quantity · unit · note`  ← **manual top-ups only.** Cook contributions are never persisted — each device re-derives them live from the synced week + recipes (there is no `cook_session` table, so nothing stable to reference). The migration carries `source_type`/`source_cook_session_id` columns for forward-compat, but `source_type` is always `manual` and the session id stays null in v1.

**Behavior:**
- Generate from the **batch cook plan** → one *derived* contribution per (cook_session, ingredient), quantity = ingredient × session `scale_factor`, computed at read time.
- …**and from the week's own entries**, for the meals that are a bare
  ingredient (migration 0033): quantity = its stated per-portion amount × its
  demand, computed at read time too. A snack belongs to no cook session, so a
  derivation that walked only sessions would leave a hole in a list somebody
  shops from. Its provenance segment says *when* — "Snack · Tue" — because the
  item's own name is already the *what*; it degrades on an unrecognised unit or
  an unusable measure exactly as a cook line does, and sums into the same line
  as any recipe that also uses the ingredient, so it is bought once.
- Display groups by ingredient, sums derived + manual contributions in canonical base (density-converted; measure-quantified lines fold into the mass subtotal via their gram weights), shows breakdown: *"Flour — 500g · Curry batch (cook Mon) 300g · Cookies 150g · +50g manual."* **Every unchecked row shows its breakdown**, a single-source one included — a shopper reading a line should never have to remember which recipe asked for it; ticking a row collapses it.
- **Shopped in the measure it was asked for:** when *every* contribution to a line was quantified in the same measure, the line's total is a count of that measure — "1 can (400 g), drained" — with the mass it weighs beside it as the secondary. You buy cans, not 8.47 oz. The moment a plain mass/volume line or a second measure joins the sum there is no single countable answer, so the canonical family sum prints as it always did; each provenance line keeps its own words either way. The ingredient's default unit biases only a sum that real mass/volume lines stated — never a measure-only one, which stays in the basis the measure folded into.
- **Whole-unit hint (step 7.6):** a fractional single total that is *not* already counted in a measure gets an honest round-up hint beside it ("2.25 → buy 3" for a plain count, or "≈ 2.25 potato, large → buy 3" derived from a mass total via the ingredient's primary measure) — a hint, never a replaced total.
- **A line at a retired ingredient buys nothing, and is named rather than
  dropped.** A row the household retired is not a fact about food any more —
  its name, aisle and density are all stale — so neither derivation shops from
  it: the recipe line and the bare-ingredient meal both leave the aisles. They
  are not silent about it either. The list's **third echo channel** names each
  one under the row's last known name, in the unresolved echo's amber voice:
  *"Sauerkraut · ingredient removed · pick again in the recipe"*, or *"… in the
  plan"* for a planned meal, because that is where its pick is. The planned
  meal's row is kept deliberately — it used to vanish with its check-off,
  which is how a missing snack went unnoticed. The words are the recipe page's
  and the editor's, one vocabulary for one kind of broken line (see
  *Ingredient*: a retire is refused while a live line names the row).
- **Top up** = persist a `manual` contribution against the entry (find-or-create).
- **Check-off** = on the entry (rolled-up ingredient), not per contribution.
- **Scoped to a week** (migrations 0019 and 0036): every entry carries the first day of the week it was made against, so a tick made while looking at next week belongs to next week's list. That includes a *free-text non-food item* — you wrote "paper towels" while shopping for one week, and it is bought on that trip, so it does not follow you onto every future list. A contribution rides its entry and stores no week of its own. `week_start_date` stays nullable for the rows older clients wrote; a week-less free-text row is backfilled onto the start of the week its `created_at` falls in. There is still **no unique index** on an entry (0006's reasoning is unchanged: two offline devices must each be able to create one and converge later); convergence simply happens within a week.
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
one provider read by three quiet surfaces — the shell's banner, a line on the
`/account` screen under the household roster, and, because Shop is the one
screen two phones drive simultaneously, in a supermarket, walking apart, a
line under the shopping list's header in that screen's own noun (*2 ticks
waiting*). Being **offline is never reported**: the app
distinguishes *waiting* (the offline-first design working, always muted) from
*stalled past five minutes* and from a write the server **refused and
discarded**, which is the only place data is lost and now the only red one. The
words, the thresholds and the seven things the app deliberately stays quiet
about: [`../design-docs/errors-and-sync-health.md`](../design-docs/errors-and-sync-health.md).

**Import (webpage or photo):** paste a URL or a set of photos and get one
reviewable recipe. How the page or the photos become lines, how a line is
matched to the vocabulary, and what the review commits:
[`import-and-matching.md`](./import-and-matching.md).

**The review screen** is one always-editable list — the match decides only how
a line starts, never whether it can be changed:
- **A line that named a number and no thing is validated as `piece`**
  ([ADR-0015](../decisions/0015-piece-weight-is-a-row-fact.md)). "2 red peppers"
  is a `piece` line, and it is clean exactly when the matched row admits
  `piece` — a `piece` default with a stated piece weight. On a row that does
  not, it is the **ordinary `unitNotAllowed` gate**: amber, "Pick a supported
  unit", the row's measures and units as did-you-mean chips, Save held. There
  is no `inferred` mark, no counts-as line and no revert, because nothing was
  guessed.
  - **The review never enters a piece weight.** It is the ingredient's
    property, not the line's, so the fix is the row's own form — the
    chosen-ingredient row on the card opens it — or picking another unit or
    measure chip. A weight typed there admits `piece` for that row and every
    other bare count of it, everywhere.
  - **A line that NAMES a thing is never overruled.** "1 **bunch** cilantro"
    keeps its flag: a bunch is about twenty-five of cilantro's 2.22 g sprigs,
    and no row fact answers a word the vocabulary does not carry. A refused
    `cup` is a *density* gap and a refused count is a *piece weight* gap; each
    names the number it wants.
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

**The recipe editor's ingredient line is that same card.** At rest it is the
row the recipe page prints — `[amount] [name] [note]`, bare on its hairline,
with the grip beside it — and **anywhere on it opens the card in place**: the
identity behind `change ›` in the head, the `optional` toggle on the flag row,
the amount as a chip that opens the quantity sheet, and the **notes field**,
which is the door a note never had (the column has always been there; only the
import review could write it). The bin moves into the head beside the chevron
that closes the card, *used in N steps* moves onto the card under the head —
where it stands over the two controls that can break a method chip — and
starting a drag closes every open card. Several lines can stand open at once,
each surviving a keystroke in another. What the editor pays for it: changing an
amount is two taps, row then chip. What it buys: one gesture instead of two
invisible doors on one row, and a note a cook can set where the line lives.

**The vocabulary is grouped by section (shipped):** `/ingredients` lists the
whole vocabulary under **aisle headers**, in the same shop-walk order the Shop
tab groups by (`core/aisles.dart` — one order, shared, because somebody who
learned it on one screen should not meet a different one two taps away), A–Z
within a section. **Other** follows the eight named aisles — it is where you
look once they have run out — and the categories a household coined come
after it, alphabetically. A header
says the section, so the row's fact line no longer repeats it. **Search still
replaces the whole list** with one flat run of results — and those rows keep
their category, because nothing else there says where they live.

**Fleshing out a stub (step 8.5, shipped):** a stub needs density/macros before
it counts toward conversions or macro totals. It surfaces as a **band pinned on
top of the whole vocabulary** in the ingredients manager (`/ingredients`), above
the aisle sections and not as a separate queue screen — a vocabulary you can
only see when it is broken is not a vocabulary you can edit. **Nothing prefills a stub.** A row is matched to the
USDA reference set only when a person opens the form's `Fill it in from ▸ Look
up in USDA`, searches it and picks a food; the pick fills the *draft* — the
description, the density and the macros — and one Save writes the row with
everything else on the form ([ADR-0011](../decisions/0011-one-save-one-write.md)).
A barcode scan fills the draft the same way from Open Food Facts. The phone
never reads the reference set directly (ADR-0005): the search is a read-only
server function. Filling in is never promotion: **macros gate `complete`, density does not, and
confirming is an explicit human act** in the flesh-out form (reversible —
a `complete` row can be un-confirmed).

**The ingredient page reads before it edits (design board "Ingredient detail",
shipped):** `/ingredients/:id` is **one route in two postures**. A row that
exists opens as a **fact sheet** — the same three groups (Identity, Nutrition,
Units & measures) with each field's value *stated* rather than offered, the
status strip, and nothing to commit — and `⋯ ▸ Edit` turns the same page into
the flesh-out form, which Save, Mark complete and back all put back down onto
the fact sheet. Every stated line is a stored fact restated in the words the
field itself uses (the picker row's macro line, the density and piece-weight
entries' own sentences, the admission chips' labels): the two postures share
one set of sentences so they cannot tell two stories about one row, and the
reading posture adds no fact the form does not already hold. Honest numbers
hold here too — a row with no panel reads **needs macros**, never four zeros.

An incomplete row keeps **one** call to action on the fact sheet, `Fill it in`,
which opens the form. `/ingredients/new` is always the form (there is nothing
yet to read) and it is the one exit that still leaves the page, popping with
the row it made for the picker that pushed it. **It also has one button.** A
row that does not exist yet is saved `complete` or not at all: `Save` and
`Mark complete` are the same act there, so the dock draws only `Save`, live
only once the row would pass the very gate `Mark complete` applies to a stored
stub, with the standing refusal printed above it in the words the form already
uses. Stubs are what the *seed* leaves for a person to finish and are meant to
run out; this form does not mint new ones. The consequence is deliberate: the
import review's create-new door and the picker's create footer both push this
form, so neither can resolve a line onto a bare stub any more — the person
fills the row in, and the line resolves onto something that counts. `?edit=1` opens the form
directly, and the doors that exist to *change* a field hand it over: a recipe
page's macro-panel fix marker, the import review's piece-weight door, and the
manager's "needs fleshing out" band. The plain doors — a manager row, an
ingredient's name on a recipe line — read.

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
  (`315 ingredients · 18 stubs` on a household fresh off the seed), one
  control — and a `›` rather than a fold,
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
- **A recipe row is title · ★ (only when favourited) · serves N · › · `⋯`.**
  The star still only **reports** — it is drawn on the row and toggled from the
  row's menu, never by touching the row, so the row's own tap still means
  exactly one thing: open the recipe. The menu is *Move to…* and the favourite
  toggle. **Move to…** re-files one recipe where the shelves are visible rather
  than through the editor: every shelf in every book, the one it is on marked
  `here now` and unpickable, and the sentence said before it acts — the delete
  refusal's "Move them to…" grammar in the singular. It writes through a narrow
  `setFiling`, never a whole-recipe save: moving a recipe is not an edit of
  every field it holds. No shelf-life chip and no macro
  badge: shelf life is a planning fact, and on honest numbers a macro badge is
  a number nobody asked for or an `incomplete` nag on most rows.
- **Empty states are honest.** A count of zero reads "no recipes yet", never
  `0 recipes`. An empty shelf offers the two doors in place — it has no section
  labels to hang a `＋` from, so the dashed pair stays exactly where it has
  always been. A search with no
  hits echoes the query as typed, over `＋ new recipe called "…"`, which carries the query into the
  editor as the title (`/recipes/new?title=`), and `⤓ import a recipe instead`.

**The recipe header's FILE UNDER** is one line, not a question: `BOOK · SECTION`
in the recipe page's own eyebrow words, with `change ›` opening the shipped book
+ section picker. A recipe made from a section's `＋` opens already filed there,
so the form states a fact. The control stays because the same form renders for
every existing recipe, and because two creation doors have no shelf to inherit —
the Week picker's `＋ new recipe` and the no-hits state — where a wrong default
is now visible and one tap from right.

**Pickers (step 7.7 — design board "Pickers v2", shipped):** one selection
anatomy, two contents. Both pickers share a sheet shell (top-anchored search,
source-tab slot, footer slot):

- **Ingredient picker** (recipe editor + shopping top-up): a Recent section
  (recently used in lines/top-ups) before any query; dense information-honest
  rows — category, capability hints ("has density", "3 measures"), a per-100
  macro line for complete rows, a `stub` badge (never zeros); an add-new
  affordance that carries the typed query into `/ingredients/new`, where the
  row is filled in and saved `complete` before the picker resolves onto it. Search is the
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
  the chip row (**the row's own measures first**, with their provenance
  dots and in the order the household dragged them · the default unit and
  the rest of its family · the demoted other family · imprecise after a
  divider · a `+` chip) riding the keyboard at the
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
  recipes" section, pinned by a cross-picker test. It searches **recipes and
  ingredients together**: under a typed query an INGREDIENTS section follows
  the recipe rows, carrying its own `DID YOU MEAN` band, so a meal that is a
  bare ingredient is planned through the same door and a cook never has to know
  before searching which of the two the thing they want is. With an empty query
  there is no such section — nobody opened *add a meal* to browse the
  vocabulary.
- **Confirm & place:** picked card with the honest macro line, a **slot**
  picker (the three defaults plus a `+` that names a custom one), and the full
  batch prose ("Chicken Curry already cooks Monday and keeps 4 days — Wednesday
  is inside that window, so this joins Monday's batch instead of a second
  cook"). The **day is not asked**: every add starts from a day card, so the
  day arrived with the flow and the sheet states it — as the subtitle ("to ·
  Wednesday") and on the button ("Add to Wednesday"). A wrong day is one
  back-tap while the sheet is open, and remove-and-re-add once it is placed.

**The Week screen (week v3, design board "Week · v3"):** one screen, one
state. v2 split it into a presentation mode and an edit mode because "the mode
changes what a tap means"; v3 deletes the mode, because a row's three targets
say what each tap means without one.

- **A dish row is two lines:** the title with its eaters and — only when the
  override differs from the eaters' factor-weighted demand — a portions chip;
  beneath it the
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
Chrome (header, switcher, tabs, lens, primary doors) always renders.
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
| Volume↔weight density | FDC food portions, and the household's own curated values (the seed is an export of a live household, and derives nothing) | CC0 / the household's |
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
