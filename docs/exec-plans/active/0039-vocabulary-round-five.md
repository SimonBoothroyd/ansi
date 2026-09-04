# Exec plan: the vocabulary — the words imports actually use, and the cooked/canned basis

- **Status:** Fronts A + B built; Front D's table written and **awaiting the
  owner's ruling**; Front C's statement written and **not run**
- **Owner:** Simon (rulings) · agent lane (build)
- **Roadmap step:** 8.14 — field test, round five
- **Created:** 2026-09-04

## Goal

Close the vocabulary gaps that made a real import fail, and settle one honesty
question the seed cannot answer by itself: **what a lentil row means**. Done:
a page that says *green onions*, *extra virgin olive oil* or *garden peas*
matches on the first pass, and a line that says *cooked lentils* or *a can of
lentils* either lands on a row whose macros are the food in the tin, or is
honestly told there is no such row yet.

## What is true today

- **The extractor emits words the vocabulary does not have.** The extraction
  prompt normalises British → American *inside* `ingredient_text` — its own
  examples include `"spring onion" → "green onion"`
  (`supabase/functions/_shared/prompts/extraction.ts`). The vocabulary's row is
  **`Scallion`**, whose only alias is `scallions` (`seed/vocab.jsonl:40`). So
  the pipeline is wired to produce a phrase the matcher cannot resolve.
- Two rows of the same class are already recorded on the tracker: `Olive Oil`
  carries no `extra virgin olive oil` alias, and there is no plain-peas row for
  `garden peas`. Both measured, both `none`-banded.
- **Both lentil rows are the dry pantry good.** `French Green Lentils` and
  `Dried Lentils` are `default_unit: cup`, and `usda_links.jsonl` points
  `french green lentil` at **fdc 172420 — the same id as `lentil dried`**.
  There is no canned or cooked lentil row at all. So "1 × 400 g can of cooked
  lentils" has nothing honest to match, and forcing it onto a dried row would
  read the dry macros against a wet weight.
- The convention for the answer already exists: every canned bean carries a
  measure labelled **`can (15 oz), drained`** with the drained gram weight and
  a cited FDC source (`supabase/seed_measures.sql`). The canned family states
  drained-ness in the *measure label*, which is exactly the ambiguity the owner
  is asking about.
- **Data is durable.** An existing household does not get seed changes by a
  reset — new aliases and rows reach it through an operator statement, not a
  reseed.

## Fronts

Every ruling below is settled.

### Front A — the missing words · BUILT

- **A-D1** `Scallion` gains `green onion` / `green onions` (and `spring onion`,
  since the phrase survives in URLs and hand-typed lines even though the
  extractor rewrites it). This is the alias the prompt's own translation rule
  presumes.
- **A-D2** **Ruled (owner): `extra virgin olive oil` is NOT an alias of
  `Olive Oil` — they are different foods.** So the fix is a distinct
  **`Extra Virgin Olive Oil`** row (with `evoo` and `extra-virgin olive oil` as
  its aliases), not a synonym pointing at the refined oil. This supersedes the
  tracker row's framing, which proposed the alias. `Olive Oil` stays what it
  is, and a line that says plain "olive oil" still lands there.
- **A-D3** `garden peas` — **ruled with D-D5: split.** A plain `Peas` row with
  `garden peas` and `petit pois` aliases; `Frozen Peas` stays what it is,
  because "frozen" is a product form and a fresh-pea line should not have to
  claim it.
- **A-D4** Regenerate the seed; the gold/eval vectors are re-run, and any
  band change is recorded here rather than absorbed.

**What landed.** Three rows and four alias surfaces, all through the pipeline
inputs (`seed/vocab.jsonl`, `seed/usda_links.jsonl`,
`seed/curation_overrides.jsonl`) and regenerated with `deno task gen-seed` —
no generated SQL was hand-written except the one measure the generator cannot
reach (see Front B).

| Row | Key (`match_text`) | Aliases that became keys | Macros | Density |
|---|---|---|---|---|
| `Scallion` (existing) | `scallion` | `green onion`, `spring onion` | unchanged | unchanged |
| `Extra Virgin Olive Oil` (new) | `extra virgin olive oil` | `evoo` | `usda_fdc:171413 — borrowed (olive oil, salad or cooking)` | 0.907 · `fdc_density:748608` |
| `Peas` (new) | `pea` | `garden pea`, `petit pois`, `green pea` | `usda_fdc:170419` (Peas, green, raw) | 0.6129, from the same link |
| `Canned Lentils` (new) | `lentil canned` | — (`canned lentils` / `tinned lentils` normalise onto the row's own key) | `usda_fdc:172421 — borrowed (lentils, boiled — the drained basis)` | 0.8369 · `fdc_density:172421` |

Two of the three carry **no `usda_links.jsonl` entry**, and that is the point:

- `extra virgin olive oil` — FDC's own extra-virgin record (**748608**) carries
  a density but **no nutrients** in the committed reference, so a link would
  buy a density and leave the row a macro-less stub. Every olive oil is
  ~100 % fat at 884 kcal/100 g, so the macros are borrowed from the refined
  record (171413) with the borrow written into `source`, and the **density**
  is extra virgin's own record. The rows are separate because they are
  different foods to cook with, not because their macros differ.
- `lentil canned` — FDC has **no canned-lentil food at all** (raw, dry, boiled
  and sprouted only), so the no-analogue rule keeps the row link-less and the
  macros come from boiled lentils under the round-2 coherence ruling.

Two surface forms were **not** added, deliberately: `lentils in a can`
(normalises to the junk key `lentil in`), and `cooked lentils` — see B-D3.

### Front B — the cooked/canned basis · BUILT

- **B-D1** **Ruled (owner: "perfect"):** a `Canned Lentils` row joining the
  `Canned *` family, with a `can (400 g), drained` measure carrying the drained
  gram weight and its FDC citation — the shape every canned bean already has.
  The dried rows stay dried and keep their raw macros.
- **B-D2** **Ruled: say it on screen.** The drained-ness currently lives only
  in a measure *label*, which a cook reads once at pick time. So the
  ingredient detail's measures section prints the basis phrase as part of the
  measure line it already renders — no new column, no new fact, just the label
  doing its job where the decision is made.
- **B-D3** Nothing infers drained from wet: an unlinked "cooked lentils" line
  stays a stub with no macros rather than borrowing the dried row's (invariant 3).
- **B-D4** Audit the rest of the `Canned *` family for the same gap while the
  file is open — a row whose measure says `drained` but whose macros are the
  packing liquid's is the same bug wearing the right label.

**B-D1 — the row.** `Canned Lentils`, `pantry`, `oz`, with the measure
`can (400 g), drained` = **240 g**, `sort_order` 0, and that measure as the
row's `default_measure` (the whole `Canned *` family's ruling: the natural
count is the can). `tsp` and `piece` are removed from its admitted units, as
on the canned beans.

**The one number with no FDC portion behind it.** The macros and the density
are both cited FDC borrows; **240 g is not**. FDC has no canned-lentil food,
so there is no `1 can drained solids` row to cite, and the bean cans' 253–277 g
describe a 15 oz US can rather than the 400 g European one. 240 g is the
typical printed drained weight for a 400 g can of pulses and is the same
figure this repo already commits for the green-bean can, so it ships marked
`seed:typical` — the guess is visible rather than dressed as a citation.
**Owner: worth checking against a tin in the cupboard**; a label number
replaces it in one line of `curation_overrides.jsonl`.

`gen-measures` needs the ~40 MB FDC CSV bundles, which are deliberately not
committed, so the measure landed the documented way (`seed/README.md`): as an
`add_measure` override — the real source of truth — with the identical row
applied by hand to `seed_measures.sql`. A run of `gen-measures` against the
bundles reproduces it verbatim. The file's seeded-row count was one short of
the tuples it actually emits (270 stated, 271 present — an earlier hand pass
that did not bump it); it now says 272 and matches.

**B-D2 — already true, verified rather than changed.** The measure *is* the
label, and both places a cook meets it render the label whole:
`measures_editor.dart` (the MEASURES list — `Text(measure.label)` in a
`Flexible`, beside the amount) and `ingredient_detail_view.dart`'s
"One ⟨x⟩ is" select, which formats `'${label} · ${amount} ${unit}'`. So
`can (400 g), drained` prints its basis phrase at both points of decision.
No code change: the ruling asked the label to do its job, and it does.

**B-D3 — held.** `cooked lentils` normalises to `lentil cooked`, which no row
holds, so the cascade returns `none` and the line becomes a stub with no
macros. It was tempting to alias it onto `Canned Lentils`; that would be the
inference the ruling forbids (a pan of home-cooked lentils is not a drained
tin). Front D proposes the honest fix — a `Cooked Lentils` row of its own.

**B-D4 — the audit, and it is clean.** All **11** rows that carry a `drained`
measure were checked for macros on the same basis:

| Row | Measure | Macro basis | Verdict |
|---|---|---|---|
| `chickpea canned` | can (15 oz), drained · 253 g | `usda_fdc:173800` — *canned, drained solids* | coherent |
| `dark red kidney bean canned` | can (15 oz), drained · 266 g | `usda_fdc:174285` — *drained solids* | coherent |
| `light red kidney bean canned` | can (15 oz), drained · 266 g | `usda_fdc:174285` — *drained solids* | coherent |
| `pinto bean canned` | can (15 oz), drained · 277 g | `usda_fdc:174286` — *drained solids* | coherent |
| `green bean canned` | can (14.5 oz), drained · 240 g | `usda_fdc:321611` — *drained solids* | coherent |
| `black bean canned` | can (15 oz), drained · 277 g | borrowed pinto drained solids | coherent (round-2 ruling) |
| `black eyed pea canned` | can (15 oz), drained · 277 g | borrowed pinto drained solids | coherent (round-2 ruling) |
| `cannellini bean canned` | can (15 oz), drained · 277 g | borrowed pinto drained solids | coherent (round-2 ruling) |
| `great northern bean canned` | can (15 oz), drained · 277 g | borrowed pinto drained solids | coherent (round-2 ruling) |
| `navy bean canned` | can (15 oz), drained · 277 g | borrowed pinto drained solids | coherent (round-2 ruling) |
| `lentil canned` | can (400 g), drained · 240 g | borrowed boiled lentils | coherent (this plan) |

Round 2 already paid this debt for the beans; nothing was left owing. The one
undrained-basis row the sweep did find is **`Sauerkraut`** (FDC 169279,
*canned, solids and liquids*, on a row people use drained) — 19 kcal/100 g
either way, so it is recorded in Front D's findings rather than patched.

**What the shared lentil fdc id means** (the owner asked). Verified:
`french green lentil` and `lentil dried` both point at **172420 —
*Lentils, raw***. Consequence: the two rows carry byte-identical numbers
(352 kcal, 24.63 P / 63.35 C / 1.06 F / 10.7 fibre, density 0.8115) and differ
only in display name and aliases. FDC has no French-green or Puy record, so
the link is an honest variety borrow — but **nothing in the data distinguishes
the rows**, and nothing marks the borrow, because `gen_measures`' automatic
"several rows share one food" marker fires on MEASURES and neither row has
one. So the shared id is not a bug to fix: it says the French-green row is a
naming and alias convenience over the generic dried-lentil food. That is why
Front D proposes **renaming** it (`Dried French Green Lentils`) rather than
splitting it — there is no second set of numbers to split into.

### Front D — display names say what the thing is · TABLE WRITTEN, NOT APPLIED

**Ruled (owner): a review pass over the whole vocabulary.** The lentil row is
not a one-off — several display names prefer brevity to clarity, and a name a
cook has to *guess at* is the same defect as a wrong number.

- **D-D1** The rule: a display name must distinguish the row from every other
  row a cook could reasonably confuse it with. Where a **product form**
  changes what the food is — dried / cooked / canned / raw / smoked / refined
  versus extra-virgin — it belongs in the name, not only in a measure label or
  a note. A-D2 is this rule applied once; Front D applies it everywhere.
- **D-D2** Sweep all rows for the classes this has already produced:
  a dry good named as if it were cooked (`French Green Lentils`,
  `Dried Lentils`), an oil named as if there were only one (`Olive Oil`), a
  frozen product named as the plain food (`Frozen Peas` standing in for peas),
  a canned row whose drained-ness lives only in a measure label (Front B).
- **D-D3** A rename is **not** free: `match_text`, the aliases and the learning
  loop key off the name. Every rename keeps the old surface form as an alias,
  the way the `Canned *` audit already did — so nothing that matched before
  stops matching.
- **D-D4** The output is a table in this plan — row, new name, why, aliases
  added — reviewed by the owner **before** any statement runs. This is a
  vocabulary edit, not a refactor.
- **D-D5** **Ruled (owner): split.** Where two rows should exist and only one
  does — peas, and cooked versus dried pulses generally — the row is split
  rather than overloaded, each split naming its own FDC target and carrying
  the old surface form as an alias so nothing that matched before stops
  matching. The table in D-D4 lists every split for review before the
  statement runs; the ruling is that splitting is the right answer, not that
  it happens unseen.

All **311** rows were read against D-D1, with each row's FDC link and its
record's own description beside it (that pairing is what turns "the name is
vague" into "the name contradicts the numbers"). **Nothing below is applied.**

#### D-1 · Renames — 6 rows

Each keeps its old surface form as an alias (D-D3) unless the row says
otherwise.

| Row today | Proposed name | Why | Aliases added |
|---|---|---|---|
| `French Green Lentils` | **`Dried French Green Lentils`** | a `cup`-default dry good named as if it were the cooked pulse. It links FDC 172420 *Lentils, raw*, so its macros are dry — 352 kcal against a name that reads like something you spoon out of a pan | `french green lentils`, `puy lentils`, `lentilles vertes` |
| `00 Flour` | **`Doppio Zero Flour`** | the sharpest find in the sweep. The normalizer strips digits, so this row's key is the bare word **`flour`** — every unqualified "flour" line in the household lands on an Italian pizza flour instead of `All-Purpose Flour` | see the note below — this is the one rename that **cannot** keep its old surface form |
| `Coconut Milk` | **`Canned Coconut Milk`** | the row *is* the tin: `piece`-default, one `can (400 ml)` measure, FDC 170173 *coconut milk, canned*. A carton of drinking coconut milk is ~20 kcal/100 ml against this row's ~197 | `coconut milk`, `tinned coconut milk`, `full-fat coconut milk` |
| `Hot Chili` | **`Fresh Red Chili`** | "hot chili" names heat, not form, and sits beside `Red Pepper Flakes`, `Chili Powder`, `Chili Crisp` and three named fresh chillies. The row is FDC 170106 *Peppers, hot chili, red, raw* | `hot chili`, `red chilli`, `fresh chilli`, `birds eye chilli` |
| `Baked Beans` | **`Canned Baked Beans`** | FDC 175182 *Beans, baked, canned*, and its only measure is `can (16 oz)`. The one member of the canned family whose name omits it | `baked beans` |
| `Ground Clove` | **`Ground Cloves`** | the spice is plural everywhere it is printed. Display-only: both forms normalise to `clove ground`, so **nothing about matching changes** | none needed |

**The `00 Flour` exception, and the decision it forces.** D-D3 says a rename
keeps its old surface form as an alias. Here that is self-defeating: the old
surface form `00 flour` normalises to `flour`, which is precisely the key the
rename exists to give up. So the owner has a second question, not just a
rename:

> Who should hold the bare key `flour`? The recommendation is
> **`All-Purpose Flour`**, as an alias — that is what an unqualified "flour"
> means in a recipe line — and `Doppio Zero Flour` keeps only keys that name
> it (`doppio zero flour`, `tipo 00 flour`, `pizza flour`).

This one **does** change what an existing line matches, which is why it is a
ruling rather than a patch.

#### D-2 · Splits — 6, one of them already built

Each split names its own FDC target; the original keeps its own key, so
nothing that matched before stops matching.

| Today | Add | Why | FDC target |
|---|---|---|---|
| `Frozen Peas` | **`Peas`** — *built in Front A* | a "garden peas" line should not have to claim "frozen" | 170419 *Peas, green, raw* |
| `Frozen Edamame` | **`Edamame`** | the peas defect again, and the only other frozen-standing-in-for-plain row in the vocabulary | 168411 *Edamame, frozen, prepared* (the shelled cooked bean a recipe means) |
| `Corn` | **`Canned Sweetcorn`** (and, if the owner wants it, `Frozen Corn`) | `Corn` is FDC 169998 *Corn, sweet, yellow, raw* with ear measures — fresh cobs. A tin of sweetcorn has nothing to land on | 169214 *canned, whole kernel, drained solids*; 168398 *frozen, kernels cut off cob* |
| `Dried Lentils` / `Canned Lentils` | **`Cooked Lentils`** | B-D3 deliberately leaves a "cooked lentils" line a stub; D-D5 says the answer is the row, not the inference. `Canned Lentils` already borrows exactly these macros, so the row would carry them by a direct link | 172421 *Lentils, mature seeds, cooked, boiled, without salt* |
| `Pasta`, `Spaghetti`, `Cavatappi`, `Ditalini` | **`Cooked Pasta`** | all four link FDC 169736 *Pasta, dry, enriched*. "2 cups cooked pasta" would take the dry basis — a ~2.3× kcal overcount | 169737 *Pasta, cooked, enriched, without added salt* |
| `White Rice`, `Brown Rice`, `Quinoa` | **`Cooked White Rice`**, **`Cooked Brown Rice`**, **`Cooked Quinoa`** | the same defect with the worst arithmetic: raw white rice is 360 kcal/100 g, cooked is 130 | 168930, 169704, 168917 |

**Why splits and not 17 renames.** Every staple carb in the vocabulary links a
raw or dry FDC record while its name says nothing — `Pasta` (*dry*), the five
rices (*raw*), `Quinoa` (*uncooked*), `Bulgur` (*dry*), `Buckwheat`,
`Cornmeal`, `Farro`, both oat rows. Renaming them all (`Dried Pasta`,
`Uncooked White Rice`, …) was considered and **rejected**: a recipe line that
says "pasta" or "rice" *does* mean the dry good, so the plain name is already
correct, and renaming would move keys that thousands of lines already match.
The defect is only ever the *cooked* line — so the fix is the missing row, not
a new word on the row that works. The last two table entries are the short
list where "cooked X" is a phrase people actually write; the rest can wait
until one shows up.

#### D-3 · Considered under D-D1 and deliberately left alone

- **`Olive Oil`** — the owner's own ruling: the plain name stays the catch-all
  so a line that says "olive oil" still lands somewhere.
- **`Sea Salt`** — the identical shape beside `Fine Sea Salt`, `Flaky Salt`,
  `Table Salt`, `Kosher Salt` and `Kala Namak` (all six share FDC 173468).
  Plain name, catch-all, same ruling.
- **`Vegan Cheese`, `Plant Milk`, `Pasta`, `White Rice`** — catch-alls by
  design, each with named siblings beside them.
- **`Green Beans`, `Tomato`, `Corn`** — the plain name means fresh, and the
  canned counterpart already says canned. (Corn still needs its *tin*, D-2.)
- **`Basil`, `Cilantro`, `Parsley`, `Mint`, `Chives`, `Rosemary`** — no dried
  counterpart row exists to confuse them with. `Fresh Oregano` and
  `Fresh Thyme` carry "fresh" only because `Dried Oregano` and `Dried Thyme`
  do exist, which is the rule working, not an inconsistency.
- **Singular vs plural** (`Beets`, `Cherries` vs `Apple`, `Carrot`) — style,
  not clarity; the normalizer folds both to the same key.
- **`High-Heat Oil`** — not a rename but a **merge** candidate: it and
  `Sunflower Oil` share FDC 172338 and are the same food under two names.
  Left for the owner because a purpose-named row may be wanted on purpose.

#### D-4 · Basis mismatches the sweep found — data, not names

These are not naming defects, so they are not in the rename table; they are
rows whose numbers and whose measure disagree about what is being weighed —
the same defect as the lentil, in a different costume. Recorded here for the
owner rather than fixed under a naming plan.

| Row | The mismatch |
|---|---|
| `Lemon` | macros are FDC 167746 *Lemons, raw, **without peel*** against a `lemon, whole` 100 g measure — one whole lemon computes as 100 g of peeled flesh |
| `Gold Potato` | FDC 2346403 *without skin*, while `Russet Potato` and `Red Potato` are *flesh and skin* |
| `Cinnamon Stick` | a `piece`-default row carrying FDC 171320 *cinnamon, **ground*** |
| `Vanilla Paste` | carries `Vanilla Extract`'s record (173471); paste is a sugar syrup |
| `Orange Bell Pepper` | carries `Red Bell Pepper`'s record (170108) — FDC has no orange bell |
| `Sauerkraut` | FDC 169279 *canned, solids **and liquids***, on a row people use drained (19 kcal either way) |
| `Applesauce` | FDC 167772 *unsweetened*; the name does not say so, and sweetened is ~2× the carbs |
| `King Oyster Mushroom` | already known and recorded in `curation_overrides.jsonl` — the link resolves to plain oyster mushrooms, 5–10× lighter |

### Front C — the household gets it · WRITTEN, NOT RUN

- **C-D1** Every change above lands as an **operator statement** applied to the
  live household (aliases inserted, rows added), never a reseed and never a
  migration that rewrites household data.
- **C-D2** The statement is written into the plan, run by the owner, and the
  readback recorded — the same shape as the `0026–0031` cloud readback.

It covers **Fronts A and B only** — Front D adds nothing until its table is
ruled on. It is re-runnable (every write is guarded), it touches exactly one
household, and it never deletes. Paste the live household's id into the first
line and run it in the Supabase SQL editor.

**It has been rehearsed, not run.** The statement below was executed verbatim
against a throwaway household on the local stack inside a transaction that
**rolled back** — so it is known to parse, to do what the readback claims, and
to be re-runnable (a second pass inserted nothing). Nothing has been written
to the live household; that is the owner's leg.

```sql
-- Round-five vocabulary → one live household. Re-runnable; adds only.
-- Replace the uuid below with the LIVE household's id (NOT the template's
-- 00000000-0000-0000-0000-0000000000aa).
begin;

do $$
declare
  hh  uuid := '00000000-0000-0000-0000-000000000000';  -- ← the live household
  scal uuid;
  lent uuid;
  meas uuid;
begin
  if not exists (select 1 from household where id = hh and deleted_at is null)
  then
    raise exception 'no such household: %', hh;
  end if;
  if exists (select 1 from household where id = hh and is_template) then
    raise exception 'that is the TEMPLATE household — this statement is for a '
                    'live one; the template gets its rows from the seed';
  end if;

  -- 1. THE THREE NEW ROWS ---------------------------------------------------
  -- allowed_units is left null on purpose: the before-insert trigger
  -- (migration 0012) materialises it from default_allowed_units(), exactly as
  -- the seed does, and step 3 then applies the same removals the curation
  -- pass applies to the template.

  insert into ingredient (household_id, canonical_name, category, default_unit,
                          density_g_per_ml, macros, macros_basis, status,
                          source, match_text)
  select hh, 'Extra Virgin Olive Oil', 'fats & oils', 'tbsp', 0.907,
         '{"kcal":884,"protein":0,"fat":100,"carb":0,"fiber":0}'::jsonb,
         'g', 'complete',
         'usda_fdc:171413 — borrowed (olive oil, salad or cooking)'
           || ' + fdc_density:748608',
         'extra virgin olive oil'
   where not exists (select 1 from ingredient
                      where household_id = hh
                        and match_text = 'extra virgin olive oil'
                        and deleted_at is null);

  insert into ingredient (household_id, canonical_name, category, default_unit,
                          density_g_per_ml, macros, macros_basis, status,
                          source, match_text)
  select hh, 'Peas', 'produce', 'cup', 0.6129,
         '{"kcal":81,"protein":5.42,"fat":0.4,"carb":14.45,"fiber":5.7}'::jsonb,
         'g', 'complete', 'usda_fdc:170419', 'pea'
   where not exists (select 1 from ingredient
                      where household_id = hh and match_text = 'pea'
                        and deleted_at is null);

  insert into ingredient (household_id, canonical_name, category, default_unit,
                          density_g_per_ml, macros, macros_basis, status,
                          source, match_text)
  select hh, 'Canned Lentils', 'pantry', 'oz', 0.8369,
         '{"kcal":116,"protein":9.02,"fat":0.38,"carb":20.13,"fiber":7.9}'::jsonb,
         'g', 'complete',
         'usda_fdc:172421 — borrowed (lentils, boiled — the drained basis)'
           || ' + fdc_density:172421',
         'lentil canned'
   where not exists (select 1 from ingredient
                      where household_id = hh and match_text = 'lentil canned'
                        and deleted_at is null);

  -- 2. THE ALIASES ----------------------------------------------------------
  -- Only the surfaces that become their OWN key are listed: `canned lentils`,
  -- `tinned lentils` and `extra-virgin olive oil` normalise onto their row's
  -- own match_text, so an alias row for them would be a duplicate key (the
  -- seed generator drops them for the same reason).

  select id into scal from ingredient
   where household_id = hh and match_text = 'scallion' and deleted_at is null;
  if scal is null then
    raise notice 'no Scallion row in this household — skipping its aliases';
  else
    insert into ingredient_alias (household_id, ingredient_id, alias_text,
                                  match_text, source)
    select hh, scal, a.alias_text, a.match_text, 'seed'
      from (values ('green onion', 'green onion'),
                   ('spring onion', 'spring onion')) as a(alias_text, match_text)
     where not exists (select 1 from ingredient_alias x
                        where x.household_id = hh and x.match_text = a.match_text
                          and x.deleted_at is null);
  end if;

  insert into ingredient_alias (household_id, ingredient_id, alias_text,
                                match_text, source)
  select hh, i.id, a.alias_text, a.match_text, 'seed'
    from ingredient i
    join (values ('extra virgin olive oil', 'evoo', 'evoo'),
                 ('pea', 'garden peas', 'garden pea'),
                 ('pea', 'petit pois', 'petit pois'),
                 ('pea', 'green peas', 'green pea'))
         as a(ing_match, alias_text, match_text) on i.match_text = a.ing_match
   where i.household_id = hh and i.deleted_at is null
     and not exists (select 1 from ingredient_alias x
                      where x.household_id = hh and x.match_text = a.match_text
                        and x.deleted_at is null);

  -- 3. THE CANNED-LENTIL MEASURE, AND THE UNIT REMOVALS ---------------------

  select id into lent from ingredient
   where household_id = hh and match_text = 'lentil canned'
     and deleted_at is null;

  insert into ingredient_measure (household_id, ingredient_id, label,
                                  basis_amount, sort_order, source)
  select hh, lent, 'can (400 g), drained', 240, 0, 'seed:typical'
   where not exists (select 1 from ingredient_measure
                      where ingredient_id = lent
                        and label = 'can (400 g), drained'
                        and deleted_at is null);

  select id into meas from ingredient_measure
   where ingredient_id = lent and label = 'can (400 g), drained'
     and deleted_at is null;
  update ingredient set default_measure_id = meas, updated_at = now()
   where id = lent and default_measure_id is distinct from meas;

  -- The same removals the curation pass makes on the template.
  -- `units` and not `drop`: `drop` is a reserved word and will not parse as a
  -- column alias here.
  update ingredient set
    allowed_units = (select coalesce(jsonb_agg(e), '[]'::jsonb)
                       from jsonb_array_elements_text(allowed_units) e
                      where e <> all (r.units)),
    updated_at = now()
    from (values ('extra virgin olive oil',
                    array['pinch', 'dash', 'handful']),
                 ('lentil canned', array['tsp', 'piece']),
                 ('pea',           array['tsp', 'tbsp']))
         as r(mt, units)
   where ingredient.household_id = hh and ingredient.match_text = r.mt
     and ingredient.deleted_at is null
     and ingredient.allowed_units ?| r.units;
end $$;

commit;
```

**Readback** — run after, with the same household id, and paste the result
into the decision log:

```sql
select i.canonical_name, i.match_text, i.status, i.default_unit,
       i.density_g_per_ml, i.macros->>'kcal' as kcal, i.allowed_units,
       (select count(*) from ingredient_alias a
         where a.ingredient_id = i.id and a.deleted_at is null) as aliases,
       (select m.label from ingredient_measure m
         where m.id = i.default_measure_id) as default_measure
  from ingredient i
 where i.household_id = '00000000-0000-0000-0000-000000000000'  -- ← same id
   and i.deleted_at is null
   and i.match_text in ('scallion', 'extra virgin olive oil', 'pea',
                        'lentil canned', 'olive oil', 'pea frozen')
 order by i.canonical_name;
```

Expected: six rows; `Extra Virgin Olive Oil` / `Peas` / `Canned Lentils` all
`complete` with a density and a kcal; `Scallion` carrying two more aliases than
before; `Canned Lentils` showing `can (400 g), drained` as its default measure;
`Olive Oil` and `Frozen Peas` **unchanged** — that pair is in the query
precisely to prove the new rows did not touch them.

The rehearsal's readback, for comparison (a bare household, so `Olive Oil` and
`Frozen Peas` are absent and `Scallion` starts alias-less):

| name | status | unit | density | kcal | allowed_units | aliases | default measure |
|---|---|---|---|---|---|---|---|
| Canned Lentils | complete | oz | 0.8369 | 116 | oz, lb, g, tbsp, cup, pt, ml | 0 | `can (400 g), drained` |
| Extra Virgin Olive Oil | complete | tbsp | 0.907 | 884 | tbsp, tsp, cup, ml, pt, g, to_taste | 1 | — |
| Peas | complete | cup | 0.6129 | 81 | cup, ml, l, pt, qt, g, kg, handful | 3 | — |
| Scallion | stub | piece | — | — | piece, g, handful | 2 | — |

Read the admitted units as the proof the removals landed: no `tsp` or `piece`
on the canned lentils, no `pinch`/`dash`/`handful` on the extra virgin oil
(`to_taste` survives — it is the finishing oil), no `tsp`/`tbsp` on the peas.

## Acceptance criteria

- [x] `green onion` resolves, and `extra virgin olive oil` resolves to its
      **own row** rather than to `Olive Oil` — shown by re-running the eval,
      with the before/after bands recorded here.
- [x] A canned/cooked lentil line has an honest target (per B-D1) or is honestly
      refused; no dried row silently absorbs a wet weight.
- [x] Where drained-ness matters, the screen says so (B-D2) — verified in the
      two widgets that render a measure, no change needed.
- [ ] Front D's rename table is written, ruled and applied; every renamed row
      keeps its old surface form as an alias and nothing that matched before
      stops matching (asserted over the gold). — **table written, awaiting the
      ruling; nothing applied.**
- [ ] The live household has the new words — statement run, readback recorded.
      **(Front C is the owner's leg.)**
- [x] Docs: the seed README's row/coverage counts, `ARCHITECTURE.md`, the
      product spec, `import-and-matching.md`, the two board frames that print a
      vocabulary count, and `scripts/cloud_verify.sh`'s expectation.

## Measurements

The vocabulary went from **308 → 311** rows; macro coverage **272 → 275**
`complete`; density coverage **297 → 300** (the 11-row audited bare tail is
unchanged). `seed.sql` emits 311 ingredients and 116 aliases.

**The four phrases, through the real cascade** (`match.ts` + `match_trgm.ts`
over `vocab.jsonl` — the same engine `score_matching.ts` uses):

| Phrase | Before | After |
|---|---|---|
| `green onion` / `green onions` | `none` | `auto` → **Scallion** (1.000) |
| `spring onion` | `none` | `auto` → **Scallion** (1.000) |
| `extra virgin olive oil` | `none` | `auto` → **Extra Virgin Olive Oil** (1.000) |
| `evoo` | `none` | `auto` → **Extra Virgin Olive Oil** (1.000) |
| `garden peas` / `petit pois` / `peas` | `none` | `auto` → **Peas** (1.000) |
| `canned lentils` / `tinned lentils` | `none` | `auto` → **Canned Lentils** (1.000) |
| `olive oil` | `auto` → Olive Oil | `auto` → **Olive Oil** (unchanged) |
| `frozen peas` | `auto` → Frozen Peas | `auto` → **Frozen Peas** (unchanged) |
| `dried lentils` | `auto` → Dried Lentils | `auto` → **Dried Lentils** (unchanged) |
| `cooked lentils` | `none` | `none` (B-D3 — deliberate) |

**The eval bands did not move**, which is the result to want here:

| | Before | After |
|---|---|---|
| normalization | 17/17 exact | 17/17 exact |
| matching · identity lane band agreement | 96.9 % (413/426) | 96.9 % (413/426) |
| · auto | P 100.0 % · R 98.5 % | P 100.0 % · R 98.5 % |
| · suggest | P 86.2 % · R 80.6 % | P 86.2 % · R 80.6 % |
| · none | P 40.0 % · R 85.7 % | P 40.0 % · R 85.7 % |
| · dangerous auto-accepts | 0 | 0 |
| matching · raw-line lane | 62.2 % (265/426) | 62.2 % (265/426) |
| extraction D2 (mock-oracle) | F1 100.0 %, ledger clean | F1 100.0 %, ledger clean |
| extraction D2 (mock-degraded) | F1 92.8 % | F1 92.8 % |
| vocab size the run reports | 308 rows | 311 rows |

Three new rows and six new alias keys, and not one of the 426 calibration
cases changed band. That is the honest reading: the mined corpus is American
recipe pages, so it contains none of the phrases this plan adds — the change
is **provably non-regressive** and its benefit is invisible to this eval by
construction. `gen_matching_cases.ts` was re-run so the labels are recomputed
against the new vocabulary; it produced a byte-identical `cases.jsonl`.

## Approach

1. Front A — mechanical, measurable, and it unblocks the next real import.
2. Front B — the ruling first, then the row + measure, then the screen line.
3. Front D — the sweep and its table, reviewed before anything runs. It is the
   biggest piece and the one most likely to grow a split (D-D5).
4. Front C — one statement covering every front, run once.

## Decision log

- 2026-09-04 — Filed from the owner's round-five notes ("Green onion missing as
  an ingredient?", "We need to revisit the lentil ingredient — not clear if we
  adding drained weight or canned weight"), folding in the two tracker rows
  from the wild-garlic hunt, which are the same class of gap.
- 2026-09-04 — Owner on Front B: *"perfect — and we should do another review
  pass for similar unclarity… some of our display names seem to prefer brevity
  over clarity. note things like olive oil and extra virgin olive oil ARE not
  the same."* → A-D2 becomes a **distinct row**, and Front D is added as a
  vocabulary-wide naming pass.
- 2026-09-04 — Build lane, Front A/B. Three rows, six alias keys, one measure.
  `Extra Virgin Olive Oil` and `Canned Lentils` are deliberately **not** in
  `usda_links.jsonl` — FDC's extra-virgin record has a density but no
  nutrients, and FDC has no canned lentil at all — so both take cited
  `— borrowed` macros the way the canned beans do, and the link-less state is
  the no-analogue rule working rather than a gap.
- 2026-09-04 — Build lane, B-D4. The `Canned *` audit came back clean: all 11
  drained-measure rows already carry drained-basis macros, because round 2
  paid that debt for the beans. The one undrained-basis row found anywhere
  was `Sauerkraut`, recorded in D-4 rather than patched.
- 2026-09-04 — Build lane, B-D2. Verified rather than changed: both surfaces
  that render a measure print the whole label, so `can (400 g), drained`
  already says its basis where the pick happens.
- 2026-09-04 — Build lane, Front D. 311 rows read against D-D1 with each
  row's FDC record beside it: 6 renames, 6 splits (one built), 8 basis
  mismatches, and an explicit list of rows the rule says to leave alone.
  Two items need an owner ruling before anything runs: who holds the bare key
  **`flour`** (today: an Italian 00 flour, by accident of the normalizer
  stripping digits), and whether the cooked/dry axis is answered by new
  `Cooked *` rows or left alone.
- 2026-09-04 — Build lane, Front C. The statement was rehearsed against a
  throwaway household on the local stack inside a rolled-back transaction: it
  parses, the readback matches, the unit removals land, and a second pass
  inserts nothing. It has **not** been run against the live household — the
  owner's leg, by C-D2.

## Notes / open questions

- The tracker's other wild-garlic row — *does a `none` line keep its top-N as
  offers?* — is deliberately **not** here. It is a band/threshold question
  about the cascade, and it wants its own decision (and eval re-calibration),
  not a vocabulary errand.
- **`lentils` on its own still bands `none`.** With three lentil rows it is
  genuinely ambiguous, so `none` is defensible — but the *better* answer is
  `suggest` with all three as candidates, which is the same top-N question the
  tracker row above asks. Left there on purpose.
- `docs/design-docs/search-and-matching.md` and two Dart doc comments still say
  "the 308-row seed vocabulary". They are describing **a measurement that was
  taken** on 308 rows, so the number was left alone rather than edited into a
  claim the measurement does not support.

## Step-done checklist

- [ ] Roadmap row updated.
- [x] `ARCHITECTURE.md` standing table matches for the seed/matching areas.
- [x] Eval re-run and its numbers recorded here.
- [ ] Tech-debt rows retired (`seed/vocab`) and any new gap added.
- [ ] Seed changes: say in the roadmap row whether the household statement has
      run, and append the `docs/cloud-setup.md` ledger entry when it does.
- [ ] `make ci` green.
