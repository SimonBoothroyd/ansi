# Unit & measure matching — how amounts are interpreted end to end

_Mechanics explainer, traced to the code (ADR-0008; migrations 0009/0010/0012;
the quantity sheet). It lives here rather than in `docs/references/` — that
directory is vendored dependency snapshots, and this is first-class knowledge
about our own system._

This is a reading of the code as it stands, written to answer three owner
questions:

1. How is a line's `unit` / `unit_mappable` / `raw_amount` matched and
   interpreted through the pipeline?
2. How does "1 × 400 g tin" become **400 g** (and not just "one tin"), and where
   does the gram basis come from?
3. What is overridable today vs fixed, and how should the UI let the user
   override the unit / measure / amount interpretation?

It is a map, not a patch. Where the adapters / prompts / gold handle "400 g tin"
inconsistently, this doc **flags** it (see
[§7](#7-flagged-the-400-g-tin-is-handled-inconsistently)); it does not change
them. Step 8 closed two of those four flags; the re-trace notes say which.

---

## 1. Two systems, one basis

Amounts in Ansi are carried by **two orthogonal vocabularies**, joined by a
single per-ingredient fact — the **macro basis**.

### The unit catalog (`app/lib/core/units/units.dart`)

A closed set of catalog units in four families:

| Family | Members | Ratio | Converts |
|---|---|---|---|
| `mass` | g, kg, oz, lb | into **grams** | within family; to volume only via density |
| `volume` | ml, l, tsp, tbsp, fl_oz, cup, pt, qt | into **ml** | within family; to mass only via density |
| `count` | piece | into the **basis unit** | within family; to mass/volume only via the row's piece weight |
| `imprecise` | pinch, dash, to_taste | none | never; never scales (`scale()` returns it unchanged) |

`convert()` returns a typed `Result` — a missing density or an incompatible
pair is an `Err` (`unit/no_density`, `unit/incompatible`, `unit/imprecise`),
**never a throw and never a fabricated number** (invariant 3). A non-positive or
NaN density is treated exactly like a missing one.

### The measure system (`app/lib/core/units/measure.dart`, migrations 0009/0012)

A `Measure` names one real-world unit of **one ingredient** and pins its amount
**in that ingredient's basis unit** — "potato, large = 299 g", "can (400 ml) =
400 ml", "clove = 3 g". Measures are per-household, synced, user-editable rows
(`ingredient_measure`), referenced from a line by a nullable
`recipe_line_item.measure_id` / `shopping_list_contribution.measure_id` FK — a
**FK, not a namespaced unit string**, which keeps the unit catalog closed.

Key columns (post-0012):

- `basis_amount numeric` (was `grams` pre-0012) — the amount of **one** of this
  measure, in the ingredient's basis unit. `check (basis_amount > 0)`.
- The row stores **no basis of its own**. The basis is the ingredient's single
  fact (`ingredient.macros_basis`), joined in by every reader, so the two can
  never disagree (ADR-0008 §3).
- `source` (migration 0010) — provenance: `usda_fdc:<id> (<portion>)`,
  `… borrowed`, `seed:typical`, `manual`, or null. Displayed as words, never
  as the stored string: *USDA portion* · *borrowed* · **estimate** · *yours*.
  `seed:typical` reads **estimate** because the word sits beside a list whose
  *order* is what says which measure is the usual one, and "typical" there was
  read as a flag on the row rather than as where the number came from.
- `sort_order` — display order, and the one place "which measure is the
  typical one" is stated. The household drags it.

### The basis is the pivot (ADR-0008)

`ingredient.macros_basis` (`g` or `ml`) is the ingredient's **canonical
dimension** — the unit its macros are stored per-100 of (`macros.dart`). It
decides:

- which family a measure's `basis_amount` lives in (`MacrosBasis.baseUnit` → g
  or ml), and
- which units are **admitted** for entry (below).

**Density is the _only_ stored volume⇄mass fact.** A single
`ingredient.density_g_per_ml` unlocks the whole other family. It is enterable
as one sentence — "[1] [cup] weighs [N] [g]" (`densityForPair`: the weight in
grams over the volume in millilitres) — where **both sides take an amount and
a unit**, one a volume and the other a weight, in either order. A pack prints
*1/4 cup (30 g)* or *30 ml (1 oz)*, never grams per millilitre, and a sentence
that fixed either half made the reader convert before they could type. `ml` and
`g` are both on offer, so a known g/ml is still typeable exactly, as one pick in
the same row. A volume-named weight mapping **is** a density, so volume-named
measures never exist as measures — the add-measure form redirects "cup" into
the density field (`volumeUnitFromLabel` / `DensityEntry`).

### One control for a number with a unit

Every amount this app stores alongside a unit is entered through one widget,
`shared/amount_and_unit.dart` (`AmountAndUnitField`): an inline number slot and
a unit picker trimmed to the same height, so the sentence around it stays a
sentence at 402 pt. It is what the serving row, both sides of the density
sentence, the piece weight, a measure's amount and the recipe's yield draw.

The unit is **picked, not printed**, because a scale or a pack states one and
it is rarely the row's basis: "1 onion weighs 4 oz", "half can = 7 oz". The
amount is converted into what is stored — the basis for a measure or a piece
weight, g/ml for a density — at save, so nothing downstream learns a new fact.
What a given control offers is the honesty rule and only that:
`basisConvertibleUnits(ingredient)` for anything stored in the basis (the
row's own family, plus the other one while a density bridges it), and the
whole mass+volume roster for the two sides of a density, which is what a
density is for.

The exception is a **component line's** amount (`component_quantity_sheet.dart`,
ADR-0014): it restates a sub-recipe's stated yield, there is no density for a
recipe, and it keeps its own `kComponentKitchenUnits` over a keypad and a chip
row — a different control for a different question, deliberately not swapped.

### What a count means (ADR-0015)

A count is bridged by the **same shape of fact** as a volume, and by nothing
else. Three row facts, and what each one lets a line say:

| fact | on the row | a line may then say | stated by |
|---|---|---|---|
| **density** | `density_g_per_ml` | `tsp · tbsp · cup · ml · …` — the other mass/volume family, whole | USDA, a pack, a spoon weighed |
| **piece weight** | `piece_basis_amount` (+ `piece_source`) | `piece` — "2 dragon fruit" | the household; or the seed, borrowed from a curated size |
| **a measure** | an `ingredient_measure` row | that word — "3 clove", "1 onion, small", "2 can" | a USDA portion, borrowed, typical, or yours |
| **a serving** | an `ingredient_measure` row under the reserved `serving · ` prefix | `serving (237 ml)` — one chip, and the only place it shows | the pack, entered in the nutrition section |

`piece_basis_amount` is what **one** of the ingredient weighs, in the row's
basis unit — the same denomination `basis_amount` uses, so nothing new has to
know about bases. `piece_source` records where the number came from: `manual`,
or *borrowed from &lt;label&gt;* where the seed copied a curated size (onion
borrows `onion, medium` = 110 g).

The rules, each of them the density rule read for a count:

- **`piece` is admitted iff the default unit is `piece` and the row has a piece
  weight.** It is never offered on a row with any other default unit, and the
  form draws the piece-weight field only while the default unit is `piece`.
  Setting the weight unions `piece` in; clearing it strips `piece` back out
  (ADR-0009's D4b removal leg, on the other number).
- **Wherever `piece` is offered, the chip says what one weighs** — `piece
  (110 g)` on the quantity sheet's chip row and the import review's unit chips
  (`pieceChipLabel`), so a count never sits as a bare word beside a `clove
  (3 g)` that explains itself. The sheet's conversion line shows the
  multiplication: *2 × 110 g = 220 g*. The token a tap writes is still the
  catalog unit.
- **A `piece` default with no weight is a stranded default**, in the same class
  as a `cup` default with no density (D4c). The form flags it with its one-tap
  fix — *piece needs a weight on this row — enter one below, or switch to g* —
  and refuses Save. So a row cannot be saved as `piece`-default unweighed.
- **`convert()` bridges a `piece` through the piece weight** the way it bridges
  a `cup` through the density: `2 piece × 350 g = 700 g`. No read-through rule,
  no "counted as" annotation on the line, nothing downstream deciding what a
  `piece` meant.
- **The import review never enters a piece weight** — it is the ingredient's
  property, not the line's. A counted line on a row that does not admit `piece`
  is the ordinary `unitNotAllowed` gate; the fix is the row's own form (the
  chosen-ingredient row on the card opens it) or another unit/measure chip. A
  counted line with **no printed unit** is validated as `piece`, so it meets the
  same gate rather than one of its own.
- **A measure is for every other count word** — a size, a fragment, a container.
  Nothing is named after the row, and no measure is created on a household's
  behalf.

**The serving is stored as a measure and is not listed as one.** It is
arithmetically exactly a measure — a named amount in the row's basis — which
is what lets the nutrition section print the label's own figures back
unrounded. But it is not a word the household authored, and it is edited where
the figures it is printed per are edited. So every list of *measures* leaves it
out (`isServingMeasure`), and the one place it still appears is the chip row,
labelled `serving (237 ml)` rather than with the pack's own words
(`measureChipLabel`) — because "1 serving" is a size a week's ingredient slot
can genuinely say, and what the person picking that chip needs to know is what
it comes to.

A row can honestly carry both: onion's piece weight is 110 g *and* its
`onion, medium` measure is 110 g. Those are two statements — *an unsized onion
weighs 110 g*, and *a medium onion is 110 g* — the first sourced from the
second, and free to diverge the moment a household disagrees.

A line that says a bare count on a row with **no** piece weight can only be a
row created before this model landed. The macro engine names it as
`needs a piece weight`, and that marker opens the *ingredient's* form: one
number fixes every bare count of that ingredient in every recipe, the way one
density fixes every `cup` line.

---

## 2. The pipeline: where a line's unit is decided

```
 URL / images
     │
     ▼
┌─────────────┐   RawBlob (text / JSON-LD / transcription)
│  intake     │   supabase/functions/import-recipe/index.ts ·
│             │   supabase/functions/_shared/jsonld.ts
└─────────────┘
     │
     ▼
┌─────────────────────────┐  ① SANITIZE  (LLM, ingredient-blind, UNIT-aware)
│  adapter.sanitize()     │  prompts/extraction.ts + unit_hints.ts
│                         │  emits RawLineItem: qty/qty_low/qty_high,
│                         │  unit, unit_mappable, raw_amount, ingredient_text
└─────────────────────────┘
     │  (units biased toward the catalog; NO measure/vocab knowledge here)
     ▼
┌─────────────────────────┐  §7 NORMALIZE  (identity only)
│  matchLines → normalize │  normalize.ts — strips MEASURES/SIZES/prep words
│                         │  from ingredient_text to build match_text
└─────────────────────────┘  ← touches IDENTITY, not the amount
     │
     ▼
┌─────────────────────────┐  ⑥ MATCH cascade (deterministic, server)
│  match.ts / match_db.ts │  match_text → ingredient (exact → trigram → none)
└─────────────────────────┘
     │
     ▼   ReconciliationPayload  (raw line + band + candidates + steps)
┌─────────────────────────┐  RECONCILE + COMMIT  (app, step 8 / lane C)
│  app writes             │  raw qty/unit → recipe_line_item(quantity, unit,
│                         │  measure_id?); human resolves bands, ranges, units
└─────────────────────────┘
     │
     ├──────────────► RECIPE line (LineItem: unit, quantity, measureId, measure)
     │
     └──────────────► SHOPPING (buildShoppingList → aggregateQuantities)
```

**Two things worth internalizing:**

- **Sanitize is unit-aware and vocab-blind — and only *half* measure-blind.**
  *(Corrected 2026-08-31: the first trace of this doc said `unit_hints.ts`
  withholds `can`/`clove`/`slice`. It doesn't, and hasn't since the step-8
  integration tail.)* The hint set is four lists:

  | Hint list | Contents | Why ① gets it |
  |---|---|---|
  | `units` | the catalog's mappable ids — g, kg, oz, lb, ml, l, tsp, tbsp, fl_oz, cup, pt, qt, piece | land a printed unit on a real catalog id |
  | `imprecise` | pinch, dash, to_taste, handful | let a vague amount stay honestly vague instead of being force-fit to a number |
  | `size_words` | large, medium, small, big, tiny | size scales the amount, it isn't a unit |
  | `measures` | **clove · head · sprig · loaf · block · slice · can · bunch · stalk** | everyday **counting nouns**; without them ① force-fits "2 garlic cloves" onto `piece` (the clove→piece failure) |

  The line that matters is between a counting **noun** and a per-ingredient
  **basis**. `clove` is a word; "a clove of garlic weighs 3 g" is a fact about
  garlic. The nouns are hinted; the `ingredient_measure` table — the gram/ml
  basis riding on ONE ingredient — is **not**, and never reaches the model. So ①
  can emit `unit: "clove"`, but it still cannot mint a `can (400 g)` measure: it
  has no idea what a can of *this* ingredient weighs. `tin` is deliberately
  absent from the list because the prompt normalises `tin → can`, so measure
  labels don't fragment.

- **The import pipeline stops at a `ReconciliationPayload`.** `assemble()` in
  `import-recipe/index.ts` copies `qty/unit/unit_mappable/raw_amount` through
  untouched and attaches a match band. **The server never creates an
  `ingredient_measure` row and never assigns a `measure_id`.** Measure resolution
  is entirely app-side, at commit/edit, through the step-7.7 quantity sheet —
  which is the crux of question 2 and the reason §6 below is an app-layer story.
  What the app *does* do at commit (`_measureIdFor`) is resolve a line's unit word
  back to a measure **by exact, case-insensitive label**: a `unit: "clove"` line
  lands `measure_id = <clove>` because the seeded label is literally `clove`. A
  `unit: "can"` line usually does **not**, because the seeded labels carry their
  basis — `can (16 oz)`, `can (15 oz), drained` — so the user picks the chip.

### The three fields through the pipeline

| Field | Set by ① | Meaning | Downstream |
|---|---|---|---|
| `unit` | biased toward catalog id when the printed unit clearly maps; else the printed word | the unit string | committed to `recipe_line_item.unit`; resolved by `unitById()` — unknown → not summed |
| `unit_mappable` | `false` when the amount can't map to a catalog unit | tells the UI "this needs resolving" | drives reconciliation UX; a `false` line is a resolve target |
| `raw_amount` | **always** the full printed amount, verbatim | never lost | the audit trail + the only place a printed weight like "400 g" survives when `unit` went to `can` |

`raw_amount` is the honesty backstop: whatever the model decides about
`unit`, the printed phrase is preserved so nothing is silently dropped.

---

## 3. How "1 × 400 g tin" becomes 400 g — worked end to end

The concrete example, ingredient e.g. "chopped tomatoes" (per-g basis).

### Step A — extraction (①)

The prompt's firm rule (`extraction.ts`, mirrored in gold `_SCHEMA.md`) now
covers **both** shapes — a single tin and a multi-pack:

> CANS / TINS: a SINGLE "400 g tin" / "one 400 g can" → `qty=1, unit="can"` (NOT
> `qty=400, unit="g"`); a MULTI-PACK "2½ × 400 g cans" → `qty=2.5, unit="can"`.
> Either way **the count is the amount**; the gram basis lives in the measure
> system (keep it in `raw_amount`). Normalise "tin" → "can".

So a can line emerges as **`qty=N, unit="can"`**, with the full `"… 400 g …"`
phrase in `raw_amount`. The **400 g is not yet a number the system can compute
with** — it lives only as text in `raw_amount`. (The single-tin rule was missing
when this doc was first written; it landed with step 8 — see
[§7](#7-flagged-the-400-g-tin-is-handled-inconsistently) for what's left.)

### Step B — normalize + match

`normalize.ts` strips `tin`/`can` (both are in its `MEASURES` set) from the
identity, so `match_text` is "chopped tomato" and the match cascade lands the
ingredient. Normalization touches **identity only** — it never reads or writes
the amount. Match gives a band; reconciliation gives the user the ingredient.

### Step C — where 400 g actually comes from

The gram basis is **not** derived from the label by the pipeline. It comes from
the **measure system**, via one of three sourced routes (never invented):

1. **A pre-existing measure on the ingredient** — "can (400 g)", cloned with the
   vocab at onboarding (`ensure_onboarded`), or curated (`seed:typical`), or a
   borrowed/USDA portion (`source = usda_fdc:…`).
2. **The user types it** in the step-7.7 manage-measures form ("half can" →
   `basis_amount`), saved as `manual`.
3. It stays a bare count — no measure — and the 400 g remains only in
   `raw_amount` for the human to read.

When a measure `can (400 g)` is selected for the line, the line is stored as:

```
recipe_line_item: quantity = 1, unit = 'piece', measure_id = <can (400 g)>
```

`unit='piece'` alongside the FK is the **degrade rule** (0009 header,
`recipe.dart` LineItem): if the measure row is ever missing (deleted, unsynced),
the line reads as an honest "1 piece", never fabricated grams.

### Step D — the recipe _uses_ 400 g

At every point that needs the amount in the basis dimension:

- **`convertMeasure(1, can400, to: g)`** = `1 × 400 = 400 g`
  (`measure.dart`). The measure's `basis_amount` **is** the bridge — no density
  needed, because the measure already speaks the basis family.
- **Macros**: 400 g of a per-100-g ingredient → `macros.scaledBy(4.0)`.
- **Shopping aggregation** (`aggregateQuantities`, `shopping.dart`): a measured
  contribution folds `amount × measure.amount` straight into the **mass**
  subtotal (per-g) — `1 × 400 = 400 g` — where it sums with every other gram
  contribution of that ingredient.

The conversion line in the sheet (`_conversionNote`) shows the user exactly this:
`≈ 400 g`.

### Step E — you still _buy_ one tin (the duality)

The same single stored fact runs backwards for shopping. Once contributions roll
up to a mass total, `wholeUnitHintFor` (`shopping.dart`) calls
`amountInMeasure(total, can400)` = `total / 400`, and rounds **up** to whole
tins:

> "800 g ≈ 2 × can (400 g) → **buy 2**", or "600 g ≈ 1.5 → **buy 2**"
> (marked `approx`).

So:

- **What the recipe uses** = `qty × basis_amount` in the basis unit (400 g).
- **What you buy** = `ceil(total ÷ basis_amount)` whole measures (tins).

Both are the **same `basis_amount = 400`**, read in the two directions.
`measure.amount` is the _one_ number; grams is the forward read, "tins to buy"
is the inverse read. Nothing is stored twice, so nothing can disagree — which is
exactly why ADR-0008 forbids volume-named measures (they'd be a second copy of
the density fact).

**This is the answer to "400 g and not one tin — or both?": it is _both_, from
one stored number.** The recipe surface reads it as 400 g (via `convertMeasure`);
the shop surface reads it as tins-to-buy (via `amountInMeasure`). It is only ever
"just one tin" (a bare count, no grams) when **no measure exists** for the
ingredient — the honest degrade.

---

## 4. Honest aggregation (why the model can't cheat)

`aggregateQuantities` (`shopping.dart`) is the summation core:

- Buckets contributions by family (mass / volume / count / imprecise).
- Measured contributions (`MeasureAmount`) fold into the **basis family only** —
  per-g → mass, per-ml → volume (positive `amount` required, else skipped).
- Mass + volume unify into **one** total **only** when a density is supplied;
  otherwise the item yields **two honest subtotals** (a mass subtotal *and* a
  volume subtotal), never a guessed single number.
- `count` sums per unit; `imprecise` never sums (identical ones collapse to one
  line; distinct ones stay separate).
- A line whose stored `unit` id doesn't resolve (`unitById` → null) is surfaced
  as an unconverted note and **never summed** — falling back to "pieces" would
  invent semantics.

`wholeUnitHintFor` only offers a "buy N" hint when the item rolled up to a
**single** total, and only through a measure of the **same family** as the
basis; disagreeing measure provenance across contributions → no hint (no single
honest unit to round to).

---

## 5. What's overridable today vs fixed

### Overridable (per household, in the app)

| Thing | Where | Mechanism |
|---|---|---|
| **Unit of a line** | step-7.7 quantity sheet (`quantity_unit_sheet.dart`) — recipe editor, method editor, shopping add sheet, edit-top-up sheet, the week's own amounts (a meal, and a week variant's lines) | `UnitChipRow` → picks a `UnitOption` from `allowedUnitChoicesFor` |
| **Measure of a line** | same sheet | picks a `MeasureOption`; writes `measure_id`, `unit='piece'` |
| **Amount / quantity** | same sheet | the quantity field (nullable — "to taste" is allowed) |
| **Add / rename / re-weigh / delete a measure** | manage state of the sheet (`_MeasureManager`), **and the ingredients manager's flesh-out form**, which embeds that same editor (8.5/F2) | `addMeasure` (saved `manual`), `renameMeasure` / `setMeasureAmount` (a row is the tap target; the id is kept, so every line already pointing at it follows the correction), `softDeleteMeasure` |
| **Which measure is the typical one** | the same editor — the list drags | `reorderMeasures` stamps `sort_order` by position. **The first row is the typical measure**: it fronts the picker's measure chips (`allowedUnitChoicesFor`, whose callers pass the `sort_order`-sorted list) and it is the measure `wholeUnitHintFor` rounds to for a total whose contributions name none of their own. No flag, no pointer — the order says it. |
| **Deleting a measure** | the same editor's bin | Refused while anything still says it. `countLinesUsing` counts the live rows in `recipe_line_item` + `shopping_list_contribution` + `plan_entry` and names the recipes; the refusal reads *Can't delete “clove” yet* with a door onto them. The FKs carry no `on delete` and the delete is a tombstone, so an unguarded delete drops those lines out of the macro totals and degrades them in the shop, both silently. |
| **Density** | manage state (`DensityEntry`, `density_entry.dart`) — again shared verbatim by the flesh-out form | "[1] [cup] weighs [N] [g]" — a volume and a weight, either order; unlocks the other family live |
| **Piece weight** | the flesh-out form's `PieceWeightEntry`, beside `DensityEntry`, and the same editor in the sheet's manage state | "1 piece weighs [N] [oz]" — any unit the row can convert to its basis, stored in the basis; unlocks `piece` live, and clearing it locks `piece` again (ADR-0015) |
| **Which units are _admitted_** (`allowed_units`) | the **ingredients manager**'s flesh-out form, `/ingredients/:id` (step 8.5) — the form ADR-0008 §Consequences promised, deferred to step 8, and finally built one step later | explicit jsonb list on `ingredient`, materialized at creation, now **directly editable as chips** on that form; a density save still extends it on its own (`densityUnlockedUnits`), and deleting the density strips that half back (D4b) |

The picker itself is honest by construction: `allowedUnitChoicesFor` offers
only the ingredient's admitted units + its live measures, in chip order
(**measures first**, in their `sort_order` → the default unit and the rest of
its family → demoted other-family → imprecise last), excluding
volume-named measures. **The stored selection is always re-offered** even when
it falls outside the current filter (`offFilter`, "not in filter"), so an
existing line never renders an orphaned value.

The full answer — which units are admitted for every default unit and macro
basis, with and without a density, plus the per-category imprecise gates — is
generated from the rule itself and lives in
[`docs/generated/unit-admission.md`](../generated/unit-admission.md). Read that
rather than re-deriving the rule by hand; `make docs-check` fails when it has
drifted from `allowed_units.dart`.

### Fixed (not user-overridable)

- **The catalog** (`kAllUnits`) and its ratios — closed set, CI-enforced pure
  Dart. Its server mirror (`unit_hints.ts`) is hand-maintained in lockstep.
- **The conversion / honesty rules** — density is the only cross-family bridge;
  measures map to the basis family only; imprecise never scales/sums. These are
  invariants, not settings.
- **The macro basis** (`macros_basis`) — the ingredient's canonical dimension;
  not exposed as a per-line toggle.
- **The extraction prompt, gold conventions, and the frozen `ExtractionResult`
  contract** — server-side, out of the user's reach (READ-ONLY here).
- **The import pipeline's output** — the user resolves it at reconciliation, but
  can't reconfigure how sanitize/normalize/match behave.

### The gap this exposed — **closed by step 8**, except one piece

> When this doc was first written, reconcile-time override didn't exist: the only
> handles were the match band, and then editing the committed line in the 7.7
> sheet afterwards. Step 8 shipped the override model described in §6 below —
> the review screen routes each line into the same 7.7 sheet, seeded from the raw
> line. What did **not** ship is §6.3, the "make a measure from this label"
> affordance. So the residual gap is narrower and specific: a printed "400 g tin"
> still can't become a `can (400 g)` measure at review; it survives as
> `raw_amount` text and the user mints the measure in the manage-measures form
> after the fact.

---

## 6. The reconciliation override model — **shipped in step 8** (§6.3 excepted)

**Goal:** let the user correct the unit / measure / amount interpretation of an
imported line *at reconcile time*, reusing the 7.7 sheet, without ever inventing
grams.

**Status per subsection**, so this reads as a description and not a proposal:

| | | |
|---|---|---|
| §6.1 three handles | **shipped** | amount, unit, measure — all editable on the review card |
| §6.2 seeding the sheet | **shipped** | the card opens the 7.7 sheet seeded from the `RawLineItem`; `raw_amount` shows as the "from source" caption on every line, resolved or not |
| §6.3 measure-from-label | **NOT shipped — still the open piece** | no "can = 400 g?" proposal anywhere |
| §6.4 honesty properties | **shipped** | no grams are written that the source didn't supply; unresolvable units degrade to an honest count |
| §6.5 plug-in points | **shipped** | reconciliation is one more caller of `showQuantityUnitSheet`, beside the recipe editor's, the method editor's, the shopping add sheet's and the week's (a meal's amount, and a week variant's lines); a picked measure rides the line as its label and resolves to the FK at commit |

Step 8 also went one step further than this section proposed: rather than only
*offering* the sheet, the review screen **enforces admission** — a line whose unit
isn't in the matched ingredient's admitted set is flagged ("Pick a supported
unit"), offered inline "did you mean" unit chips, and blocks Save until it
clears.

### 6.1 What the user can change

Three independent handles, mirroring the three fields:

1. **Amount** — `qty` (or `qty_low/qty_high` for a range the user collapses).
2. **Unit** — any `UnitOption` from the ingredient's admitted set.
3. **Measure** — any `MeasureOption` on the ingredient, **or "create a measure
   from this label"** (the new affordance).

These are exactly the handles the 7.7 sheet already exposes — the override model
is "route the imported line into that sheet, seeded from the `RawLineItem`."

### 6.2 Seeding the sheet from a `RawLineItem`

At reconcile, for each committed line, open (or lazily offer) the sheet with:

- `initialQuantity = qty` (or null for a range/imprecise line);
- `initialChoice`:
  - `unit_mappable = true` and `unit` resolves → `UnitOption(unitById(unit))`;
  - a matching existing measure label (e.g. the ingredient already has
    "can (400 g)") → that `MeasureOption`;
  - otherwise → **degrade to a count**: `UnitOption(piece)` with
    `pendingMeasure`-style note, and **`raw_amount` shown verbatim** beneath the
    quantity so the printed "400 g tin" stays visible.
- `raw_amount` surfaced as a caption regardless, so the source of truth is never
  hidden behind an interpretation.

### 6.3 The "make a measure from this label" path — **still the missing piece**

When the line is a container word (`unit_mappable=false`, `unit ∈ {can, tin,
jar, sachet, block, …}`) **and** `raw_amount` contains a parseable basis amount
(e.g. "400 g"):

- Offer a one-tap **"can = 400 g?"** chip in the manage-measures form,
  pre-filling `label = "can (400 g)"` and `basis_amount = 400`, saved as
  `manual` — i.e. drive the existing `addMeasure` path with values *proposed*
  from `raw_amount` but **confirmed by the user**, never auto-committed.
- The parse is a **suggestion from the printed text**, so it stays inside
  never-invent: the number came from the source, and the human confirms it. If
  `raw_amount` has no basis amount, the offer simply doesn't appear and the line
  stays a bare count.
- Volume-named labels ("cup") still redirect to the density entry
  (`volumeUnitFromLabel`) — unchanged.

Once saved, the line becomes `quantity = qty, unit = 'piece', measure_id = <new
measure>` — and from that point the duality of §3 applies: the recipe reads
400 g, the shop reads tins-to-buy.

### 6.4 How it stays honest

- **Never invents grams.** If the user doesn't confirm a measure, the line
  degrades to a **count** with `raw_amount` visible (`pendingMeasure` note
  pattern already in the sheet). No gram number is written that the source
  didn't supply.
- **One stored fact.** The override writes a `basis_amount`, never a parallel
  gram field on the line — so recipe-use and shop-buy stay two reads of one
  number.
- **The picker filter stays the guardrail.** Overrides go through
  `allowedUnitChoicesFor` / `addMeasure`, which already refuse volume-named
  measures and offer only admitted units. The repo's `ArgumentError` validation
  surfaces inline.
- **Degrade-don't-destroy on unit change.** `QuantitySaved.unitPicked` already
  gates whether a `measure_id` is cleared — only an explicit chip tap clears it,
  so an unresolved measure isn't silently dropped by an unrelated edit.

### 6.5 Where it plugs in

- **Component:** reuse `showQuantityUnitSheet` / `QuantityUnitEditor` verbatim —
  it is already the single entry surface for every amount that has a unit
  beside it: recipe editor line items, the method editor's chips, the shopping
  add and edit-top-up sheets, and the week's own amounts. Reconciliation is one
  more caller, not a new control.
- **Seed:** a small adapter `RawLineItem → (initialQuantity, initialChoice,
  pendingMeasure, rawAmountCaption)` at the commit boundary (app-side, where step
  refs are already remapped to `line_item_id`s).
- **New affordance:** the "measure from label" proposal in `_MeasureManager`,
  fed by a `raw_amount` basis-amount parser (a pure helper: "400 g" → `(400, g)`;
  "400 ml" → `(400, ml)`; nothing parseable → no offer).
- **No contract change required:** `RawLineItem` already carries everything
  (`unit`, `unit_mappable`, `raw_amount`); the measure is created through the
  existing `manual` write path. This keeps the frozen extraction contract and
  the pipeline untouched — the override lives entirely in the app's commit/edit
  layer, which is where measure resolution already lives today.

---

## 7. Flagged: the "400 g tin" is handled inconsistently

Re-traced 2026-08-31. Two of the four are now **closed**; two stand.

1. ~~**Single-tin (`qty = 1`) has no prompt/gold rule.**~~ **CLOSED.**
   `prompts/extraction.ts` now rules on it explicitly: *a SINGLE "400 g tin" /
   "one 400 g can" / "One 14.5-ounce can" → `qty=1, unit="can"` (NOT `qty=400,
   unit="g"`); a MULTI-PACK "2½ × 400 g cans" → `qty=2.5, unit="can"`. Either way
   the count is the amount; the gram basis lives in the measure system (keep it
   in `raw_amount`).* Both shapes now land on the same committed line, which was
   the point. (The prompt also normalises `tin → can` in both the unit and the
   identity string, so British sources don't fragment the vocabulary.)

2. **"the gram basis lives in the measure system" is still partly aspirational at
   import** — narrowed. The *server* still creates no measures and assigns no
   `measure_id` (correct — it doesn't know the household's measures). The *app*
   now resolves one at commit, but only by **exact label match**: `unit: "clove"`
   → the seeded `clove` measure, automatically. `unit: "can"` usually misses,
   because the seeded labels carry their basis (`can (16 oz)`, `can (15 oz),
   drained`). So the canned case — the one this doc was written about — is still
   the one that needs a human tap, and §6.3 is still its bridge.

3. **`can` IS hinted now; `unitById("can")` still returns null.** *(Corrected —
   the original trace said `unit_hints.ts` doesn't list container words.)* `can`
   is in the hints' `measures` list, so ① emits it confidently; but it is **not**
   a catalog unit, so `unitById("can")` is null downstream and
   `aggregateQuantities` **does not sum** the line until it resolves to a measure.
   That degrade is correct — inventing grams would be worse — but the consequence
   stands and is now easier to hit: an unresolved canned ingredient contributes
   **nothing** to shopping totals, silently. The review screen's unit enforcement
   catches most of these before commit (an unadmitted unit blocks Save), which is
   the practical mitigation.

4. **`normalize.ts` MEASURES vs the measure vocabulary can drift.** Container
   words are stripped from *identity* in `normalize.ts` (`can`, `tin`, `jar`,
   `block`, `sachet`-like words) while the *measure* labels that would carry
   their weight are a separate per-ingredient table. The two lists are maintained
   independently; a container word added to one but not conceptually handled by
   the other is a quiet source of "matched the ingredient but lost the amount"
   lines. Worth a lint that the reconcile-stage "measure from label" offer covers
   the same container vocabulary `normalize` strips.

---

## Source map

- Unit catalog & conversion — `app/lib/core/units/units.dart`
- Macros & basis — `app/lib/core/units/macros.dart`
- Measures & `convertMeasure`/`amountInMeasure` — `app/lib/core/units/measure.dart`
- Admitted units (derived defaults, ordering, picker choices) —
  `app/lib/features/ingredients/domain/allowed_units.dart`, tabulated in
  [`docs/generated/unit-admission.md`](../generated/unit-admission.md)
  (generated by `app/tool/gen_unit_admission.dart`)
- Step-7.7 quantity + unit-chip sheet — `app/lib/features/ingredients/presentation/quantity_unit_sheet.dart`
- Honest aggregation & buy-hints — `app/lib/features/shopping/domain/shopping.dart`
- Recipe line (degrade rule) — `app/lib/features/recipes/domain/recipe.dart`,
  `…/data/recipe_repository_impl.dart`
- Migrations — `supabase/migrations/0009_ingredient_measures.sql`,
  `0010_measure_provenance.sql`, `0012_unit_admission.sql`
- Import spine — `supabase/functions/import-recipe/index.ts`
- Import review + commit (where `measure_id` is actually resolved) —
  `app/lib/features/import/presentation/recon_line_card.dart`,
  `…/domain/line_validation.dart`, `…/data/import_repository_impl.dart`
- Sanitize prompt & unit hints — `supabase/functions/_shared/prompts/extraction.ts`,
  `_shared/unit_hints.ts`
- Normalize & match — `supabase/functions/_shared/normalize.ts`, `match.ts`,
  `match_db.ts`
- Gold conventions — `evals/datasets/extraction/gold/_SCHEMA.md`
- Decisions — `docs/decisions/0008-unit-admission-model.md` (the model),
  `docs/decisions/0014-all-to-all-admission.md` (a family is admitted whole) and
  `docs/decisions/0015-piece-weight-is-a-row-fact.md` (a piece weight unlocks
  `piece`)
