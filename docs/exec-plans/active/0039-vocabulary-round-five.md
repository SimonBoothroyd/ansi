# Exec plan: the vocabulary — the words imports actually use, and the cooked/canned basis

- **Status:** Fronts A, B and D built; Front C's statement written, rehearsed
  and **not run** — the owner's leg
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

### Front D — display names say what the thing is · RULED AND APPLIED

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
vague" into "the name contradicts the numbers"). The table was put to the
owner and **approved as proposed**; what follows is the table as ruled,
followed by what applying it did.

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
ruling rather than a patch. **Ruled (owner, 2026-09-04): agreed — `flour` goes
to `All-Purpose Flour`.**

**What happens to a line that already points at the old key.** Nothing
dangles, because a rename is **not** a new row: the operator statement updates
`canonical_name` and `match_text` **in place**, so the ingredient's `id` never
changes and every `recipe_line_item`, `shopping_list_entry`, measure and
default-measure that referenced it still does. A saved line that once read
"500 g 00 flour" keeps its link and now displays **Doppio Zero Flour** —
which is what that row always was, only badly named; the cook can see it and
re-pick if they meant plain flour. (Verified in the rehearsal: the fixture's
recipe line follows the row to its new name.) Only *future* matching moves:
`flour` — and, because the normalizer strips digits, the literal string
`00 flour` too — now resolves to `All-Purpose Flour`.

The one thing the statement will **not** do is overwrite a household's own
learning. If this household has already taught itself an alias on the key
`flour` pointing somewhere other than All-Purpose Flour, the statement leaves
it alone and says so in a notice, because an `import_correction` is a fact the
household owns.

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

**Ruled: out of scope, and none of the eight is made wrong by a rename or a
split.** Each was re-checked against the applied table: not one of the eight
rows was renamed, split, or re-linked, so every mismatch reads exactly as it
did. Two *new* observations the splits themselves created, recorded here for
the same queue rather than fixed:

- **`Edamame`** links FDC 168411, whose description is *Edamame, **frozen**,
  prepared*. FDC has no fresh-podded edamame record at all, so the plain row's
  numbers come from a frozen one. That is the honest best available and it is
  the shelled cooked bean a recipe line means — but the plain row's macros do
  carry a form its name does not. `Frozen Edamame` keeps the *unprepared*
  record (168410) and is unchanged.
- **`Canned Sweetcorn`** carries drained-solids macros (169214) and **no can
  measure**. That is a gap, not the drained/undrained bug: nothing multiplies
  the wrong basis, there is simply no can to count yet. Adding one is a
  `gen-measures` job (or an `add_measure` override) beyond the approved table.

#### D-5 · One thing the sweep found that is not about food

`supabase/seed/scripts/gen_measures.ts` contains a **literal NUL byte** — it
builds a composite key as `` `${matchText}\0${label}` `` with the zero byte
written into the source rather than escaped. `file` calls the result `data`,
so **plain `grep` and `rg` skip it silently**: a search for `coconut milk`
across the repo returns nothing from the one file that holds its measure
constant. It cost this lane a wrong answer before `grep -a` found it. Escaping
the byte (`\0`) changes nothing about the key and makes the generator
searchable again — a one-character fix for whoever next opens that file.

#### D-6 · What applying the table did

All six renames and all six splits landed through the pipeline inputs and were
regenerated with `deno task gen-seed` — no generated SQL was hand-written
except `seed_measures.sql`, whose three re-keyed tuples were applied by hand
(the documented path when the FDC bundles are absent) and re-sorted so a real
`gen-measures` run reproduces the file byte for byte.

A rename moves a row's **key**, so it moves everything keyed by it:
`usda_links.jsonl` (5 links re-keyed), `curation_overrides.jsonl` (9 overrides
re-keyed — densities, allowed-unit rulings and two `default_measure` rulings),
`seed_measures.sql` (3 measure tuples and its match_text existence list), and
`gen_measures.ts`'s own `TYPICAL` constant (the 400 ml coconut-milk can).
`Ground Cloves` needed none of that: both spellings normalise to
`clove ground`, so it is a pure display change.

**Every rename kept its old surface form**, which the generated `seed.sql`
proves — `french green lentils` → `french green lentil`, `hot chilies` →
`hot chili`, `coconut milk` → `coconut milk`, `baked beans` → `baked bean` are
all now alias rows on the renamed ingredient. The single exception is the
ruled one: `00 flour` normalises to `flour`, which `All-Purpose Flour` now
holds.

The eight new rows all link an FDC record of their **own** form, so each takes
that record's macros and density from the ordinary prefill — no borrows, no
label numbers, nothing hand-typed:

| Row | Key | FDC | kcal/100 g | density |
|---|---|---|---|---|
| `Edamame` | `edamame` | 168411 | 121 | 0.6551 |
| `Canned Sweetcorn` | `sweetcorn canned` | 169214 | 67 | 0.6932 |
| `Frozen Corn` | `corn frozen` | 168398 | 88 | 0.5748 |
| `Cooked Lentils` | `lentil cooked` | 172421 | 116 | 0.8369 |
| `Cooked Pasta` | `pasta cooked` | 169737 | 158 | 0.5241 |
| `Cooked White Rice` | `white rice cooked` | 168930 | 130 | 0.7862 |
| `Cooked Brown Rice` | `brown rice cooked` | 169704 | 123 | 0.8538 |
| `Cooked Quinoa` | `quinoa cooked` | 168917 | 120 | 0.7820 |

Each carries the unit ruling its nearest sibling already carries (no `tsp` on
a pulse or a grain; no `tsp`/`tbsp` on cooked pasta or frozen corn, mirroring
frozen peas). R1 and R2 both hold: every one is cup- or oz-default with a
density inside the kitchen band.

**B-D3 is superseded, on purpose.** It ruled that an unlinked "cooked lentils"
line stays a stub rather than borrowing the dried row's macros — and that
still holds, because nothing infers. What changed is that the line is no
longer unlinked: `Cooked Lentils` links 172421 directly, so the line now bands
`auto` onto a row whose numbers are its own. It is not an alias of
`Canned Lentils` — a pan of home-cooked lentils is not a drained tin — the two
rows simply rest on the same FDC record, one by link and one by borrow.

### Front C — the household gets it · WRITTEN, NOT RUN

- **C-D1** Every change above lands as an **operator statement** applied to the
  live household (aliases inserted, rows added), never a reseed and never a
  migration that rewrites household data.
- **C-D2** The statement is written into the plan, run by the owner, and the
  readback recorded — the same shape as the `0026–0031` cloud readback.

It covers **all three built fronts** in two parts: Part 1 adds Fronts A and
B's rows and words, Part 2 applies Front D's renames and splits. Both are
re-runnable (every write is guarded), both touch exactly one household, and
neither deletes anything. Paste the live household's id into the first line of
each part and run them in order in the Supabase SQL editor.

**It has been rehearsed, not run.** Both parts were executed verbatim against
a throwaway household on the local stack inside a transaction that **rolled
back** — so each is known to parse, to do what its readback claims, and to be
re-runnable (a second pass renamed 0 of 6 and inserted nothing). Nothing has
been written to the live household; that is the owner's leg.

#### Part 1 — Fronts A and B

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

#### Part 2 — Front D

Run after Part 1, with the same household id. The renames are **in place** —
the row's `id` never changes, so nothing that already points at it dangles
(see the `00 Flour` note above).

```sql
-- Round-five display-name sweep → the same live household. Re-runnable.
begin;

-- Part 2 — Front D: the display-name sweep. Re-runnable; renames in place.
do $$
declare
  hh    uuid := '00000000-0000-0000-0000-000000000000';  -- ← the live household
  clash text;
  n     int;
begin
  -- 1. THE SIX RENAMES, IN PLACE --------------------------------------------
  -- A rename is NOT a new row: the id stays, so every recipe line, shopping
  -- entry and measure that already points at the row follows it to its new
  -- name. `clove ground` is the display-only one — both spellings normalise
  -- to the same key, so only its canonical_name moves.
  update ingredient i
     set canonical_name = r.new_name, match_text = r.new_mt, updated_at = now()
    from (values
      ('french green lentil', 'french green lentil dried',
         'Dried French Green Lentils'),
      ('flour',              'doppio zero flour',  'Doppio Zero Flour'),
      ('coconut milk',       'coconut milk canned', 'Canned Coconut Milk'),
      ('hot chili',          'red chili fresh',     'Fresh Red Chili'),
      ('baked bean',         'baked bean canned',   'Canned Baked Beans'),
      ('clove ground',       'clove ground',        'Ground Cloves')
    ) as r(old_mt, new_mt, new_name)
   where i.household_id = hh and i.deleted_at is null
     and i.match_text = r.old_mt
     and (i.canonical_name, i.match_text) is distinct from (r.new_name, r.new_mt)
     and not exists (select 1 from ingredient x
                      where x.household_id = hh and x.deleted_at is null
                        and x.match_text = r.new_mt and x.id <> i.id);
  get diagnostics n = row_count;
  raise notice 'renamed % of 6 rows (a row already renamed, absent, or blocked '
               'by an existing row on the new key is skipped)', n;

  -- 2. THE OLD SURFACE FORMS, KEPT AS ALIASES (D-D3) ------------------------
  insert into ingredient_alias (household_id, ingredient_id, alias_text,
                                match_text, source)
  select hh, i.id, a.alias_text, a.match_text, 'seed'
    from ingredient i
    join (values
      ('french green lentil dried', 'French green lentils', 'french green lentil'),
      ('french green lentil dried', 'puy lentils',          'puy lentil'),
      ('french green lentil dried', 'lentilles vertes',     'lentille verte'),
      ('doppio zero flour',         'tipo 00 flour',        'tipo flour'),
      ('doppio zero flour',         'pizza flour',          'pizza flour'),
      ('coconut milk canned',       'coconut milk',         'coconut milk'),
      ('red chili fresh',           'hot chilies',          'hot chili'),
      ('red chili fresh',           'red chilli',           'red chilli'),
      ('red chili fresh',           'fresh chilli',         'chilli fresh'),
      ('red chili fresh',           'birds eye chilli',     'bird eye chilli'),
      ('baked bean canned',         'baked beans',          'baked bean')
    ) as a(ing_match, alias_text, match_text) on i.match_text = a.ing_match
   where i.household_id = hh and i.deleted_at is null
     and not exists (select 1 from ingredient_alias x
                      where x.household_id = hh and x.match_text = a.match_text
                        and x.deleted_at is null);

  -- 3. THE `flour` HANDOVER --------------------------------------------------
  -- The one rename that cannot keep its own old surface form: "00 flour"
  -- normalises to the bare key `flour`, which is exactly the key it gives up.
  -- The key goes to All-Purpose Flour — unless this household has taught
  -- itself something about `flour`, in which case that correction is a fact
  -- the household owns and this statement refuses to overwrite it.
  select string_agg(i.canonical_name, ', ') into clash
    from ingredient_alias a
    join ingredient i on i.id = a.ingredient_id
   where a.household_id = hh and a.match_text = 'flour'
     and a.deleted_at is null and i.match_text <> 'all purpose flour';
  if clash is not null then
    raise notice 'this household already points the key `flour` at % — LEFT '
                 'ALONE, so All-Purpose Flour does not take it. That alias is '
                 'something the household taught itself; decide which row '
                 'should own the key, then re-run.', clash;
  else
    insert into ingredient_alias (household_id, ingredient_id, alias_text,
                                  match_text, source)
    select hh, i.id, 'flour', 'flour', 'seed'
      from ingredient i
     where i.household_id = hh and i.deleted_at is null
       and i.match_text = 'all purpose flour'
       and not exists (select 1 from ingredient_alias x
                        where x.household_id = hh and x.match_text = 'flour'
                          and x.deleted_at is null);
  end if;

  -- 4. THE EIGHT NEW ROWS ----------------------------------------------------
  -- Every one links an FDC record of its OWN form, so macros and density are
  -- that record's, not a borrow.
  insert into ingredient (household_id, canonical_name, category, default_unit,
                          density_g_per_ml, macros, macros_basis, status,
                          source, match_text)
  select hh, r.name, r.category, r.unit, r.density, r.macros::jsonb, 'g',
         'complete', 'usda_fdc:' || r.fdc, r.mt
    from (values
      ('Edamame', 'produce', 'cup', 0.6551, 168411,
       '{"kcal":121,"protein":11.91,"fat":5.2,"carb":8.91,"fiber":5.2}', 'edamame'),
      ('Canned Sweetcorn', 'pantry', 'oz', 0.6932, 169214,
       '{"kcal":67,"protein":2.29,"fat":1.22,"carb":14.34,"fiber":2}',
       'sweetcorn canned'),
      ('Frozen Corn', 'produce', 'cup', 0.5748, 168398,
       '{"kcal":88,"protein":3.02,"fat":0.78,"carb":20.71,"fiber":2.1}',
       'corn frozen'),
      ('Cooked Lentils', 'pantry', 'cup', 0.8369, 172421,
       '{"kcal":116,"protein":9.02,"fat":0.38,"carb":20.13,"fiber":7.9}',
       'lentil cooked'),
      ('Cooked Pasta', 'grains', 'cup', 0.5241, 169737,
       '{"kcal":158,"protein":5.8,"fat":0.93,"carb":30.86,"fiber":1.8}',
       'pasta cooked'),
      ('Cooked White Rice', 'grains', 'cup', 0.7862, 168930,
       '{"kcal":130,"protein":2.38,"fat":0.21,"carb":28.59}',
       'white rice cooked'),
      ('Cooked Brown Rice', 'grains', 'cup', 0.8538, 169704,
       '{"kcal":123,"protein":2.74,"fat":0.97,"carb":25.58,"fiber":1.6}',
       'brown rice cooked'),
      ('Cooked Quinoa', 'grains', 'cup', 0.782, 168917,
       '{"kcal":120,"protein":4.4,"fat":1.92,"carb":21.3,"fiber":2.8}',
       'quinoa cooked')
    ) as r(name, category, unit, density, fdc, macros, mt)
   where not exists (select 1 from ingredient x
                      where x.household_id = hh and x.match_text = r.mt
                        and x.deleted_at is null);

  -- 5. THEIR ALIASES ---------------------------------------------------------
  insert into ingredient_alias (household_id, ingredient_id, alias_text,
                                match_text, source)
  select hh, i.id, a.alias_text, a.match_text, 'seed'
    from ingredient i
    join (values
      ('edamame',           'shelled edamame',     'edamame shelled'),
      ('edamame',           'soy beans',           'soy bean'),
      ('sweetcorn canned',  'canned corn',         'corn canned'),
      ('sweetcorn canned',  'sweetcorn',           'sweetcorn'),
      ('corn frozen',       'frozen sweetcorn',    'sweetcorn frozen'),
      ('corn frozen',       'frozen corn kernels', 'corn kernel frozen'),
      ('lentil cooked',     'boiled lentils',      'boiled lentil'),
      ('pasta cooked',      'cooked spaghetti',    'spaghetti cooked'),
      ('white rice cooked', 'cooked rice',         'rice cooked'),
      ('white rice cooked', 'steamed rice',        'steamed rice')
    ) as a(ing_match, alias_text, match_text) on i.match_text = a.ing_match
   where i.household_id = hh and i.deleted_at is null
     and not exists (select 1 from ingredient_alias x
                      where x.household_id = hh and x.match_text = a.match_text
                        and x.deleted_at is null);

  -- 6. THE UNIT RULINGS ON THE NEW ROWS -------------------------------------
  update ingredient set
    allowed_units = (select coalesce(jsonb_agg(e), '[]'::jsonb)
                       from jsonb_array_elements_text(allowed_units) e
                      where e <> all (r.units)),
    updated_at = now()
    from (values ('lentil cooked',     array['tsp']),
                 ('pasta cooked',      array['tsp', 'tbsp']),
                 ('white rice cooked', array['tsp']),
                 ('brown rice cooked', array['tsp']),
                 ('quinoa cooked',     array['tsp']),
                 ('edamame',           array['tsp']),
                 ('corn frozen',       array['tsp', 'tbsp']),
                 ('sweetcorn canned',  array['tsp']))
         as r(mt, units)
   where ingredient.household_id = hh and ingredient.match_text = r.mt
     and ingredient.deleted_at is null
     and ingredient.allowed_units ?| r.units;
end $$;

commit;
```

**Readback** — run after, with the same household id:

```sql
select i.canonical_name, i.match_text, i.status, i.default_unit,
       i.density_g_per_ml, i.macros->>'kcal' as kcal, i.allowed_units,
       (select count(*) from ingredient_alias a
         where a.ingredient_id = i.id and a.deleted_at is null) as aliases
  from ingredient i
 where i.household_id = '00000000-0000-0000-0000-000000000000'  -- ← same id
   and i.deleted_at is null
   and i.match_text in ('french green lentil dried', 'doppio zero flour',
                        'all purpose flour', 'coconut milk canned',
                        'red chili fresh', 'baked bean canned', 'clove ground',
                        'edamame', 'sweetcorn canned', 'corn frozen',
                        'lentil cooked', 'pasta cooked', 'white rice cooked',
                        'brown rice cooked', 'quinoa cooked')
 order by i.canonical_name;

-- who owns the bare key `flour` now (expect: All-Purpose Flour)
select i.canonical_name as flour_key_owner
  from ingredient_alias a join ingredient i on i.id = a.ingredient_id
 where a.household_id = '00000000-0000-0000-0000-000000000000'  -- ← same id
   and a.match_text = 'flour' and a.deleted_at is null;
```

The rehearsal's readback (a bare fixture household, so the renamed rows show as
stubs — the fixture never had their macros; in the live household they keep
whatever they already carried, because a rename touches only the name and the
key):

| name | key | status | unit | density | kcal | aliases |
|---|---|---|---|---|---|---|
| All-Purpose Flour | `all purpose flour` | stub | cup | — | — | 1 |
| Canned Baked Beans | `baked bean canned` | stub | oz | — | — | 1 |
| Canned Coconut Milk | `coconut milk canned` | stub | piece | — | — | 1 |
| Canned Sweetcorn | `sweetcorn canned` | complete | oz | 0.6932 | 67 | 2 |
| Cooked Brown Rice | `brown rice cooked` | complete | cup | 0.8538 | 123 | 0 |
| Cooked Lentils | `lentil cooked` | complete | cup | 0.8369 | 116 | 1 |
| Cooked Pasta | `pasta cooked` | complete | cup | 0.5241 | 158 | 1 |
| Cooked Quinoa | `quinoa cooked` | complete | cup | 0.7820 | 120 | 0 |
| Cooked White Rice | `white rice cooked` | complete | cup | 0.7862 | 130 | 2 |
| Doppio Zero Flour | `doppio zero flour` | stub | cup | — | — | 2 |
| Dried French Green Lentils | `french green lentil dried` | stub | cup | — | — | 3 |
| Edamame | `edamame` | complete | cup | 0.6551 | 121 | 2 |
| Fresh Red Chili | `red chili fresh` | stub | piece | — | — | 4 |
| Frozen Corn | `corn frozen` | complete | cup | 0.5748 | 88 | 2 |
| Ground Cloves | `clove ground` | stub | pinch | — | — | 0 |

…and the three things the rehearsal existed to prove:

- `renamed 6 of 6 rows` on the first pass, **`renamed 0 of 6`** on the second,
  with the ingredient and alias counts unchanged — it is re-runnable.
- the fixture's recipe line, saved as *"500 g 00 flour"*, still resolves
  through the same `ingredient_id` and now reads **Doppio Zero Flour**. No
  dangling line, no orphan.
- `flour_key_owner` comes back **All-Purpose Flour**, and re-running does not
  double-insert it or fire the household-learning guard.


## Acceptance criteria

- [x] `green onion` resolves, and `extra virgin olive oil` resolves to its
      **own row** rather than to `Olive Oil` — shown by re-running the eval,
      with the before/after bands recorded here.
- [x] A canned/cooked lentil line has an honest target (per B-D1) or is honestly
      refused; no dried row silently absorbs a wet weight.
- [x] Where drained-ness matters, the screen says so (B-D2) — verified in the
      two widgets that render a measure, no change needed.
- [x] Front D's rename table is written, ruled and applied; every renamed row
      keeps its old surface form as an alias and nothing that matched before
      stops matching (asserted over the gold) — the one ruled exception is
      `00 flour`, whose old surface form IS the key it gives up.
- [ ] The live household has the new words — statement run, readback recorded.
      **(Front C is the owner's leg.)**
- [x] Docs: the seed README's row/coverage counts, `ARCHITECTURE.md`, the
      product spec, `import-and-matching.md`, the two board frames that print a
      vocabulary count, `scripts/cloud_verify.sh`'s expectation, and the
      real-vocab import test's stated auto count.

## Measurements

The vocabulary went from **308 → 311** rows after Fronts A+B, then
**311 → 319** after Front D; macro coverage **272 → 275 → 283** `complete`;
density coverage **297 → 300 → 308** (the 11-row audited bare tail is unchanged
throughout — every new row links an FDC record that has both). `seed.sql` now
emits 319 ingredients and 138 aliases.

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
recipe pages, so it contains none of the phrases Fronts A+B add — the change
is **provably non-regressive** and its benefit is invisible to this eval by
construction. `gen_matching_cases.ts` was re-run so the labels are recomputed
against the new vocabulary; it produced a byte-identical `cases.jsonl`.

### Front D

Front D was the one that could genuinely move the numbers — a rename moves a
row's key, and `flour` is a word the corpus actually uses. It did move the
calibration set, and here is exactly how.

**Nine of the 426 cases were relabelled.** Eight are the same row under its new
name (the oracle following the rename, which is what a rename means):

| Line | Was | Now |
|---|---|---|
| "1 small hot pepper…" | Hot Chili | Fresh Red Chili |
| "1 hot chili pepper…" | Hot Chili | Fresh Red Chili |
| "2 small (or 1 large) hot chili…" | Hot Chili | Fresh Red Chili |
| "1-2 hot chilies or big pinch red pepper flakes" | Hot Chili + Red Pepper Flakes | Fresh Red Chili + Red Pepper Flakes |
| "1 (13.5 ounces) can full-fat coconut milk…" | Coconut Milk | Canned Coconut Milk |
| "1 can full-fat coconut milk…" | Coconut Milk | Canned Coconut Milk |
| "1 pound French green lentils…" | French Green Lentils | Dried French Green Lentils |
| "Pinch ground clove (optional)" | Ground Clove | Ground Cloves |

The ninth is substantive and is the split showing up in the oracle:
*"12 ounces (340 g) shelled frozen edamame, defrosted"* now covers
**`["Frozen Edamame", "Edamame"]`** where it covered only `Frozen Edamame`.
Its band stays `suggest`, which is right — that line genuinely names both rows
now, and a human picks.

**No band moved, and no calibration number moved:**

| | After A+B | After D |
|---|---|---|
| normalization | 17/17 exact | 17/17 exact |
| identity lane band agreement | 96.9 % (413/426) | 96.9 % (413/426) |
| · auto | P 100.0 % · R 98.5 % | P 100.0 % · R 98.5 % |
| · suggest | P 86.2 % · R 80.6 % | P 86.2 % · R 80.6 % |
| · none | P 40.0 % · R 85.7 % | P 40.0 % · R 85.7 % |
| · auto top-1 ingredient | 100.0 % (382/382) | 100.0 % (382/382) |
| · dangerous auto-accepts | 0 | 0 |
| raw-line lane | 62.2 % (265/426) | 62.2 % (265/426) |
| extraction D2 oracle / degraded | F1 100.0 % / 92.8 % | F1 100.0 % / 92.8 % |
| vocab size the run reports | 311 rows | 319 rows |

One number is worth reporting **before** the relabel, because it is the honest
size of a rename's blast radius: run against the *stale* labels, `auto top-1
ingredient` fell from 100.0 % to **98.2 % (375/382)** — seven lines "wrong"
purely because the oracle still said `Hot Chili` and `Coconut Milk`. Bands and
dangerous-accepts were untouched even then. Regenerating the labels restored
100.0 %.

**And one real gain, outside the calibration set.** The edge-function test that
imports the `gumbo` gold over the real vocabulary moved from
`auto=20 suggest=4 none=7+1` to **`auto=21 suggest=4 none=7`**: that recipe's
*"cooked rice"* line, which had nothing to land on, now bands `auto` onto
`Cooked White Rice`. The cooked/dry split earned its keep on a real page the
day it landed. (The test's floor assertion is unchanged; its stated "currently
19/32" comment was refreshed to 21/32.)

**Every phrase the sweep was supposed to fix, through the real cascade:**

| Phrase | Before Front D | After |
|---|---|---|
| `flour` | `auto` → **00 Flour** (an Italian pizza flour) | `auto` → **All-Purpose Flour** |
| `00 flour` | `auto` → 00 Flour | `auto` → **All-Purpose Flour** (the ruled consequence) |
| `doppio zero flour` / `tipo 00 flour` / `pizza flour` | `none` | `auto` → **Doppio Zero Flour** |
| `french green lentils` / `puy lentils` | `auto` → French Green Lentils / `none` | `auto` → **Dried French Green Lentils** |
| `coconut milk` / `tinned coconut milk` | `auto` → Coconut Milk / `suggest` (0.684) | `auto` → **Canned Coconut Milk** |
| `hot chili` / `red chilli` | `auto` → Hot Chili / `none` | `auto` → **Fresh Red Chili** |
| `baked beans` | `auto` → Baked Beans | `auto` → **Canned Baked Beans** |
| `ground clove` / `ground cloves` | `auto` → Ground Clove | `auto` → **Ground Cloves** |
| `edamame` | `none` | `auto` → **Edamame** |
| `sweetcorn` / `canned corn` | `none` | `auto` → **Canned Sweetcorn** |
| `frozen corn` | `none` | `auto` → **Frozen Corn** |
| `cooked lentils` | `none` (B-D3) | `auto` → **Cooked Lentils** |
| `cooked pasta` | `none` | `auto` → **Cooked Pasta** |
| `cooked rice` / `cooked white rice` | `none` / `suggest` → White Rice (0.611 — the dry row) | `auto` → **Cooked White Rice** |
| `cooked brown rice` / `cooked quinoa` | `suggest` → Brown Rice (0.611 — the dry row) / `none` | `auto` → **Cooked Brown Rice** / **Cooked Quinoa** |
| `lentils` (bare) | `none` | `suggest` → Dried French Green Lentils (0.636) |
| `pasta`, `quinoa`, `corn`, `frozen edamame`, `frozen peas`, `olive oil`, `dried lentils` | `auto` | `auto`, **unchanged** |

Two of those deserve a second look rather than a tick:

- **`lentils` on its own moved from `none` to `suggest`.** Four lentil rows now
  raise its trigram score to 0.636, over the suggest floor. That is an
  improvement — a bare "lentils" line is genuinely ambiguous and now offers a
  human something to pick — but it is a band change caused by vocabulary size,
  not by a threshold, and it is exactly the case the tracker's open `none`
  top-N question is about.
- **`sweetcorn` bare now lands on `Canned Sweetcorn`.** For a British kitchen
  that is usually right (the tin is the default sense), but a cob-of-sweetcorn
  line would need `corn`. Recorded, not adjusted.

Worth noticing what the split *replaced*, not just what it filled: before
Front D, "cooked white rice" and "cooked brown rice" banded **`suggest` at
0.611 onto the DRY rows** — the cascade was already offering a cook the raw
grain for a cooked line, which is the lentil defect with a softer landing. It
is not that those lines had nothing; it is that what they had was wrong by a
factor of nearly three. They are `auto` onto their own rows now.

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

- 2026-09-04 — Owner ruled all three open items. (1) The bare key **`flour`**
  goes to `All-Purpose Flour`, as recommended; `00 Flour` becomes
  `Doppio Zero Flour` and gives the key up. (2) Front D's table is **approved
  as proposed** — all six renames and all six splits with the FDC targets
  listed, every rename keeping its old surface form as an alias except the
  `00 Flour` case; the eight basis mismatches stay out of scope and the
  "considered and left alone" list stands. (3) The **240 g** drained-lentil
  weight **stays as it is**, marked `seed:typical`, for the owner to check
  against a real tin.
- 2026-09-04 — Build lane, Front D applied. Six renames (five moving a key, one
  display-only), eight new rows, 5 links and 9 curation overrides re-keyed, 3
  measure tuples and `gen_measures.ts`'s own TYPICAL constant re-keyed. Nine
  calibration cases relabelled and no band moved; the gumbo real-vocab import
  gained one `auto` line ("cooked rice"). None of the eight recorded basis
  mismatches is made wrong by a rename or a split — two NEW observations the
  splits created are recorded beside them instead (`Edamame`'s FDC record is
  still a frozen one; `Canned Sweetcorn` has drained macros but no can
  measure yet).
- 2026-09-04 — Build lane, Front C Part 2. Rehearsed the same way: 6 of 6
  renames on the first pass, 0 of 6 on the second, the fixture's saved
  "500 g 00 flour" line following its row to Doppio Zero Flour with no
  dangling reference, and `flour` ending up owned by All-Purpose Flour. The
  statement refuses to take the `flour` key if the household has already
  taught itself an alias on it — an `import_correction` is the household's own
  fact, not this statement's to overwrite.

## Notes / open questions

- The tracker's other wild-garlic row — *does a `none` line keep its top-N as
  offers?* — is deliberately **not** here. It is a band/threshold question
  about the cascade, and it wants its own decision (and eval re-calibration),
  not a vocabulary errand.
- **`lentils` on its own now bands `suggest`** (it was `none` before this
  plan). Four lentil rows push its trigram score to 0.636. It is the better
  answer, but it arrived as a side effect of vocabulary size rather than a
  ruling, and the tracker's open top-N question still governs what a `none`
  line should offer.
- **`gen_measures.ts` is invisible to `grep`.** It carries a literal NUL byte
  as a composite-key separator, so the file reads as binary and plain
  `grep`/`rg` skip it without a word. See D-5 — escaping it (`\0`) is a
  one-character fix.
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
