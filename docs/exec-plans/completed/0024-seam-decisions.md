# Import & macros seam · v2 — decisions (D1–D6)

**Lane:** seam (DESIGN ONLY — nothing in the repo is touched by this lane).
**Occasion:** the owner's field test, 2026-09-03 (Pixel, first real import after
the polish pass). Three gaps, one direction, six decisions.

The owner's words, verbatim, because every decision below is answerable to them:

> "now piece isn't an option most things like onion, pepper, etc require users
> to select a unit on import"
> "importing the recipe — the steps weren't editable and it was mentioning it's
> still v1?!"
> "this message [incomplete · 2 unconvertible] makes it impossible to know what
> ingredients need fixing"
> "things that are to taste, or imprecise should[n't] be required or show up in
> macros"

**What this lane is NOT.** It does not reopen ADR-0010. `piece` stays an
admission fact; nothing here reads a size word out of `raw_amount`, nothing
resolves a line at runtime from a rule, and no stored line is rewritten. D1 adds
a *second stated fact* per row — the same kind of fact `allowed_units` already
is — and D2 spends it. That is the whole difference between this lane and the
cascade the owner rejected on 2026-09-02: **a curated fact is a decision
somebody made and can see; a cascade is a guess made fresh every time.**

---

## D1 — a curated default count measure per ingredient

**The gap.** ADR-0010 took `piece` off 142 seeded rows. That was right — a
stored bare `piece` on a measured row is unknowable — but it made *every*
counted-produce line a stop: "2 onions", "1 red pepper", "3 potatoes" now all
arrive flagged, and the review screen turned into a chip-tapping queue. The
owner's complaint is not that the flag is wrong; it is that the app is asking a
question whose answer is already known and is the same every time.

### Options

| | shape | what it costs |
|---|---|---|
| **A** | **`ingredient.default_measure_id` (nullable FK), curated by hand — RECOMMENDED** | one additive column, one curation pass (141 rows below), one migration + backfill |
| B | derive it at seed time ("the `, medium` row, else the sole measure") | it is the rejected cascade wearing a seed-time hat: it re-decides the list on every generator run, puts a default on broccoli (`whole`? `crown`?) and takes it off `yellow bell pepper` (no `medium` row), and the reason is nowhere a reader can see it |
| C | reuse `sort_order = 0` as the default | free, and wrong on exactly the rows that matter: it is a *display* order, so `ginger` defaults to `slice` (2.2 g) not `piece, 1 inch` (12 g), and `flour tortilla` to `package` (484 g) not `tortilla` (49 g). A 20× error with no audit trail |
| D | a `is_default` boolean on `ingredient_measure` | the same fact, stored N times with a partial-unique index to keep it honest. The FK says "the ingredient has one default"; the boolean says "each measure knows whether it is it", which is the thing you then have to police |
| E | put the default in `allowed_units` (the "first admitted count wins") | overloads a *set* with an *order*; ADR-0008 §4 is explicit that the list is a set, and every reader would have to agree on the ordering |

### Recommendation — A

`ingredient.default_measure_id uuid null references ingredient_measure(id) on
delete set null`. It is a **stated per-ingredient fact**, seeded by hand exactly
like the `piece` removals, editable by the household in the flesh-out form
("Counts as: [onion, medium ▾]"), and null wherever no honest answer exists.

Three properties that make it the same *kind* of thing as ADR-0010's fact, not a
retreat from it:

1. **It is nullable, and null is a real answer.** Broccoli has no default;
   "1 broccoli" stays flagged, exactly as ADR-0010 drew it. The model can say
   "I don't know", which a cascade never can.
2. **Nothing downstream interprets it.** A default is spent at ONE moment (D2's
   preselect) and is then an ordinary picked measure. No stored line ever
   records "this came from the default" — because by then the user has seen it
   on the card and saved over it.
3. **It is auditable per row.** `curation_overrides.jsonl` carries the reason,
   the same file that carries every `piece` removal. A future reader can ask
   "why does ginger count in 1-inch pieces?" and get an answer.

**Data is durable (owner ruling 2026-09-03), so this lands as an additive column
+ a backfill, not a reseed.** See `seam-impl.md` §1. That is the one place this
lane departs from ADR-0010's rollout, and the reason is the ruling, not
convenience.

### The seed curation shape

Same file, same grammar, one new `kind`:

```jsonl
{"kind": "default_measure", "match_text": "onion", "label": "onion, medium", "reason": "a recipe that says '2 onions' means two medium ones; small/large are said out loud when they matter"}
{"kind": "default_measure", "match_text": "broccoli", "label": null, "reason": "bunch/spear/crown are three different things and none of them is 'a broccoli'"}
```

`label: null` is an explicit **no default** — it must be written, not omitted, so
the pass is exhaustive and a newly seeded ingredient with measures fails the
generator until somebody rules on it (see `seam-impl.md` §2). Validation:
`label` must name a live measure on that row, and the row must carry ≥1 measure.

### The curation table — all 141 seeded ingredients that carry ≥1 measure

Scope and provenance are ADR-0010's: every measure below is a row in
`supabase/seed_measures.sql` (270 rows over 141 ingredients, USDA `food_portion`
weights plus `seed:typical`), and the generator already excludes volume-named
portions (ADR-0008 §2), so nothing here is filtered out by `isVolumeUnitLabel`.
The other ~149 vocab rows carry no measures and are untouched: their
`default_measure_id` is null by construction, and they still admit `piece`.

**Totals: 132 defaults · 9 explicit nones · 21 flagged for the owner's ruling.**

The three shapes, said once:

- **sized family → the `medium`** — onion, pepper, potato, apple, tomato…
  "2 onions" means two medium ones; a recipe says *large* out loud when it
  matters, and the printed word then wins (D2's scope rule).
- **sole count measure → that one** — cucumber, avocado, garlic → `clove`,
  the retail can/block/package rows. There is nothing else the line could mean;
  this is ADR-0010 consequence 4's own sentence, finally acted on.
- **fragment set → none** — broccoli (`whole`/`spear`/`crown`), cabbage and the
  lettuces (`head` vs `leaf`), mint (`sprig` vs `bunch`), spinach
  (`bunch` vs `package`), vegetable broth (`can` vs `carton`). Two or more
  *kinds* of countable thing, no dominant one: the flag stands and the user
  picks, which is the ADR's own answer.

| ingredient (`match_text`) | seeded measures (label · g, in `sort_order`) | proposed `default_measure_id` | why |
|---|---|---|---|
| `active yeast dry` | sachet 7 | `sachet` | sole count |
| `almond` | almond 1.2 | `almond` | sole count |
| `apple` | apple, medium 182 · apple, large 223 · apple, small 149 · apple, extra small 101 | `apple, medium` | sized family → medium |
| `apricot` | apricot 35 | `apricot` | sole count |
| `asparagus` | spear, medium 16 · spear, large 20 · spear, small 12 · spear, extra large 24 · spear tip 3.5 | `spear, medium` | sized family of the counted thing (a spear IS what a recipe counts) |
| `avocado` | avocado 201 | `avocado` | sole count — the ADR-0010 field-test row |
| `baked bean` | can (16 oz) 454 | `can (16 oz)` | sole count (the retail can) |
| `banana` | banana, medium 118 · banana, large 136 · banana, small 101 · banana, extra small 81 · banana, extra large 152 | `banana, medium` | sized family → medium |
| `basil` | leaf 0.5 | `leaf` | sole count |
| `bay leaf` | leaf 0.2 | `leaf` | sole count |
| `beet` | beet 82 | `beet` | sole count |
| `black bean canned` | can (15 oz), drained 277 | `can (15 oz), drained` | sole count (the retail can) |
| `black eyed pea canned` | can (15 oz), drained 277 | `can (15 oz), drained` | sole count (the retail can) |
| `blueberry` | berry 1.36 | `berry` | sole count |
| `brazil nut` | kernel 5 | `kernel` | sole count |
| `broccoli` | whole 608 · spear 31 · crown 150 | **none** | fragment set — bunch/spear/crown; ADR-0010 already keeps this row honest **← your call** |
| `brussel sprout` | sprout 19 | `sprout` | sole count |
| `burger bun` | bun 44 | `bun` | sole count |
| `butternut squash` | squash, whole 1130 | `squash, whole` | sole count |
| `cabbage` | head, medium 908 · leaf, medium 23 · head, large 1248 · leaf, large 33 · head, small 714 · leaf 15 | **none** | fragment set — head vs leaf **← your call** |
| `cannellini bean canned` | can (15 oz), drained 277 | `can (15 oz), drained` | sole count (the retail can) |
| `cantaloupe` | melon, medium 552 · melon, large 814 · melon, small 441 · wedge, large 102 · wedge, medium 69 · wedge, small 55 · cantaloupe ball 13.8 | `melon, medium` | sized family of the WHOLE; wedges/balls are fragments |
| `carrot` | carrot, medium 61 · carrot, large 72 · carrot, small 50 · slice 3 · strip, large 7 · strip, medium 4 | `carrot, medium` | sized family → medium |
| `cauliflower` | head, medium 588 · head, large 840 · head, small 265 · floweret 13 | `head, medium` | the head IS the cauliflower; floweret is the fragment **← your call** |
| `celery` | stalk, medium 40 · stalk, large 64 · stalk, small 17 · strip 4 | `stalk, medium` | a recipe counts stalks; the seed has no whole-head measure **← your call** |
| `cherry` | cherry 8.2 | `cherry` | sole count |
| `chickpea canned` | can (15 oz), drained 253 | `can (15 oz), drained` | sole count (the retail can) |
| `cilantro` | sprig 2.22 | `sprig` | sole count |
| `cinnamon stick` | stick 2.6 | `stick` | sole count |
| `coconut milk` | can (400 ml) 400 | `can (400 ml)` | sole count (the retail can) |
| `corn` | ear, medium 102 · ear, large 143 · ear, small 73 | `ear, medium` | sized family → medium |
| `corn tortilla` | tortilla 24 | `tortilla` | sole count |
| `cremini mushroom` | mushroom, whole 20 | `mushroom, whole` | sole count |
| `cucumber` | cucumber 301 | `cucumber` | sole count — the field-test row that stayed flagged (D3) |
| `dark red kidney bean canned` | can (15 oz), drained 266 | `can (15 oz), drained` | sole count (the retail can) |
| `date` | date, pitted 24 | `date, pitted` | sole count |
| `dill` | sprig 0.2 | `sprig` | sole count |
| `dill pickle` | spear 40.4 | `spear` | sole count (owner ruled spear IS the count) |
| `edamame frozen` | package 432 | `package` | sole count |
| `eggplant` | eggplant, peeled 458 · eggplant, unpeeled 548 | `eggplant, unpeeled` | you buy and count the unpeeled one **← your call** |
| `english muffin` | muffin 57 | `muffin` | sole count |
| `enoki mushroom` | mushroom, medium 3 · mushroom, large 5 | `mushroom, medium` | sized family → medium |
| `extra firm tofu` | block (14 oz) 397 | `block (14 oz)` | sole count (the retail block) |
| `fennel` | bulb 234 | `bulb` | sole count |
| `fig dried` | fig, whole 8.4 | `fig, whole` | sole count |
| `fire tomato canned roasted` | can (14.5 oz) 411 · can (28 oz) 794 | `can (14.5 oz)` | two can sizes; 14.5 oz is the standard retail can (sort 0) **← your call** |
| `flour tortilla` | package 484 · tortilla 49 | `tortilla` | a recipe counts tortillas; the package is the shopping unit **← your call** |
| `gala apple` | apple, medium 172 · apple, large 200 · apple, small 157 | `apple, medium` | sized family → medium |
| `garlic` | clove 3 | `clove` | sole count — owner example |
| `ginger` | slice 2.2 · piece, 1 inch 12 | `piece, 1 inch` | what a recipe counts ("a 1-inch piece"); slice is the fragment **← your call** |
| `gold potato` | potato, medium 213 · potato, large 369 · potato, small 170 | `potato, medium` | sized family → medium |
| `granny smith apple` | apple, medium 167 · apple, large 206 · apple, small 144 | `apple, medium` | sized family → medium |
| `grapefruit` | grapefruit, whole 246 | `grapefruit, whole` | sole count |
| `great northern bean canned` | can (15 oz), drained 277 | `can (15 oz), drained` | sole count (the retail can) |
| `green bean` | bean 5.5 | `bean` | sole count |
| `green bean canned` | can (14.5 oz), drained 240 | `can (14.5 oz), drained` | sole count (the retail can) |
| `green bell pepper` | pepper, medium 119 · pepper, large 164 · pepper, small 74 · ring 10 · strip 2.7 | `pepper, medium` | sized family → medium |
| `green grape` | grape 4.9 | `grape` | sole count |
| `green olive` | olive 2.7 | `olive` | sole count |
| `hazelnut` | nut 1.4 | `nut` | sole count |
| `hot chili` | chili 45 | `chili` | sole count |
| `iceberg lettuce` | head, medium 539 · leaf, medium 8 · head, large 755 · leaf, large 15 · head, small 324 · leaf, small 5 | **none** | fragment set — head vs leaf **← your call** |
| `instant yeast` | sachet 7 | `sachet` | sole count |
| `jalapeno` | jalapeno 14 | `jalapeno` | sole count |
| `king oyster mushroom` | mushroom, medium 90 | `mushroom, medium` | sole count |
| `kiwi` | kiwi, whole 69 | `kiwi, whole` | sole count |
| `kombu` | strip 10 | `strip` | sole count (owner ruled strip IS the count) |
| `leek` | leek 89 · slice 6 | `leek` | the whole; slice is the fragment |
| `lemon` | lemon, whole 100 | `lemon, whole` | sole count |
| `lemon juice` | lemon 48 | `lemon` | sole count ("juice of 1 lemon") |
| `light red kidney bean canned` | can (15 oz), drained 266 | `can (15 oz), drained` | sole count (the retail can) |
| `lime` | lime, whole 67 | `lime, whole` | sole count |
| `lime juice` | lime 44 | `lime` | sole count |
| `mango` | mango, whole 336 | `mango, whole` | sole count |
| `mint` | sprig 2 · bunch 25 | **none** | fragment set — sprig vs bunch, 12× apart **← your call** |
| `multigrain bread` | slice regular 26 · slice, large 41 | `slice regular` | sized family of the counted thing (a slice) |
| `napa cabbage` | head 950 | `head` | sole count — the contrast with `cabbage`: one measure, no ambiguity |
| `navy bean canned` | can (15 oz), drained 277 | `can (15 oz), drained` | sole count (the retail can) |
| `nectarine` | nectarine, whole 129 | `nectarine, whole` | sole count |
| `nori` | sheet 2.5 | `sheet` | sole count |
| `okra` | pod 11.88 | `pod` | sole count |
| `onion` | onion, medium 110 · onion, large 150 · onion, small 70 · slice, large 38 · slice, medium 14 · slice, thin 9 · ring 6 | `onion, medium` | sized family → medium; owner example |
| `orange` | orange, whole 140 | `orange, whole` | sole count |
| `orange bell pepper` | pepper, medium 119 · pepper, large 164 · pepper, small 74 · ring 10 | `pepper, medium` | sized family → medium |
| `orange juice` | orange, juiced 86 | `orange, juiced` | sole count |
| `oyster mushroom` | mushroom 15 | `mushroom` | sole count |
| `parsley` | sprig 1 | `sprig` | sole count |
| `parsnip` | parsnip, medium 120 | `parsnip, medium` | sole count |
| `pea frozen` | package 284 | `package` | sole count |
| `peach` | peach, medium 150 · peach, large 175 · peach, small 130 · peach, extra large 224 | `peach, medium` | sized family → medium |
| `pineapple` | pineapple, whole 905 · slice 166 · slice, thin 56 | `pineapple, whole` | the whole; slices are fragments |
| `pinto bean canned` | can (15 oz), drained 277 | `can (15 oz), drained` | sole count (the retail can) |
| `pistachio` | kernel 0.7 | `kernel` | sole count |
| `plantain` | plantain 267 | `plantain` | sole count |
| `poblano pepper` | pepper 100 | `pepper` | sole count |
| `portobello mushroom` | mushroom, whole 84 | `mushroom, whole` | sole count |
| `radish` | radish, medium 4.5 · radish, large 9 · radish, small 2 · slice 1 | `radish, medium` | sized family → medium |
| `raspberry` | raspberry 1.9 | `raspberry` | sole count |
| `red bell pepper` | pepper, medium 119 · pepper, large 164 · pepper, small 74 · ring 10 | `pepper, medium` | sized family → medium; the field-test row |
| `red cabbage` | head, medium 839 · head, large 1134 · head, small 567 · leaf 23 | **none** | fragment set — head vs leaf **← your call** |
| `red delicious apple` | apple, medium 212 · apple, large 260 · apple, small 158 | `apple, medium` | sized family → medium |
| `red grape` | grape 4.9 | `grape` | sole count |
| `red leaf lettuce` | leaf inner 2.6 · leaf outer 17 · head 309 | **none** | fragment set — inner/outer leaf vs head **← your call** |
| `red onion` | onion, medium 110 · onion, large 150 · onion, small 70 | `onion, medium` | sized family → medium |
| `red potato` | potato, medium 213 · potato, large 369 · potato, small 170 | `potato, medium` | sized family → medium |
| `rhubarb` | stalk 51 | `stalk` | sole count |
| `romaine lettuce` | leaf inner 6 · leaf outer 28 · head 626 | **none** | fragment set — inner/outer leaf vs head **← your call** |
| `russet potato` | potato, medium 213 · potato, large 369 · potato, small 170 | `potato, medium` | sized family → medium |
| `scallion` | scallion, medium 15 · scallion, large 25 · scallion, small 5 | `scallion, medium` | sized family → medium |
| `serrano pepper` | pepper 6.1 | `pepper` | sole count |
| `shallot` | shallot, medium 30 | `shallot, medium` | sole count |
| `shiitake bacon` | slice 5 | `slice` | sole count |
| `shiitake mushroom` | mushroom, whole 19 | `mushroom, whole` | sole count |
| `silken tofu` | block (12.3 oz) 349 | `block (12.3 oz)` | sole count (the retail block) |
| `soft sandwich bread` | slice 27.3 | `slice` | sole count |
| `spinach` | bunch 340 · package 284 | **none** | fragment set — bunch vs package **← your call** |
| `sprouted multigrain bread` | slice 38 | `slice` | sole count |
| `star anise` | pod 2 | `pod` | sole count |
| `strawberry` | strawberry, medium 12 · strawberry, large 18 · strawberry, small 7 · strawberry, extra large 27 | `strawberry, medium` | sized family → medium |
| `sweet potato` | sweet potato 130 | `sweet potato` | sole count |
| `tatsoi` | head 150 | `head` | sole count |
| `tempeh` | package (8 oz) 227 | `package (8 oz)` | sole count (the retail package) |
| `thai basil` | leaf 0.5 | `leaf` | sole count |
| `tofu bacon` | slice 15 | `slice` | sole count |
| `tomato` | tomato, medium 123 · tomato, large 182 · tomato, small 91 · cherry 17 · plum tomato 62 · slice, medium 20 · slice, large 27 · wedge 31 · slice, thin, small 15 | `tomato, medium` | sized family → medium; cherry/plum/slice/wedge are other things |
| `tomato canned` | can (14.5 oz) 411 · can (28 oz) 794 | `can (14.5 oz)` | two can sizes; 14.5 oz is the standard retail can (sort 0) **← your call** |
| `tomato canned whole` | can (14.5 oz) 411 · can (28 oz) 794 · tomato, medium 111 · tomato, large 164 · tomato, small 82 | `can (14.5 oz)` | a canned-tomato line counts cans, not the tomatoes inside **← your call** |
| `tomato paste` | can (6 oz) 170 | `can (6 oz)` | sole count (the retail can) |
| `tomato puree canned` | can (29 oz) 822 · can (15 oz) 425 | `can (29 oz)` | two can sizes; 29 oz is the standard puree can (sort 0) **← your call** |
| `tomato sauce canned` | can (15 oz) 425 · can (8 oz) 227 | `can (15 oz)` | two can sizes; 15 oz is the standard sauce can (sort 0) **← your call** |
| `tostada shell` | shell 12.3 | `shell` | sole count |
| `turnip` | turnip, medium 122 · turnip, large 183 · turnip, small 61 · slice 15 | `turnip, medium` | sized family → medium |
| `vegan sausage` | link 100 | `link` | sole count |
| `vegetable broth` | can (14.5 oz) 390 · carton (32 oz) 926 | **none** | fragment set — can vs carton, 2.4× apart **← your call** |
| `watermelon` | melon 4518 · wedge 286 · watermelon ball 12.2 | `melon` | the whole; wedge/ball are fragments — 4518 g, so verify **← your call** |
| `wheat bread whole` | slice 32.1 | `slice` | sole count |
| `white bread` | slice 27.3 | `slice` | sole count |
| `white mushroom` | mushroom, medium 18 · mushroom, large 23 · mushroom, small 10 · slice 6 | `mushroom, medium` | sized family → medium |
| `yellow bell pepper` | pepper, large 186 · strip 5.2 | `pepper, large` | SEED GAP: no `pepper, medium` on this row (the other three bells have one) **← your call** |
| `yellow squash` | squash, medium 196 | `squash, medium` | sole count |
| `zucchini` | zucchini, medium 196 · zucchini, large 323 · zucchini, small 118 · slice 9.9 | `zucchini, medium` | sized family → medium |

### The 21 rows flagged **← your call**

Grouped, so they read in one sitting:

- **Which can is "a can"** (5): `fire tomato canned roasted`, `tomato canned`,
  `tomato canned whole`, `tomato puree canned`, `tomato sauce canned`. Each
  carries two sizes; the proposal is the standard retail one (`sort_order 0`).
  If you would rather a canned line always ask, these five become **none** and
  cost one tap per canned-tomato import.
- **Whole vs part where the seed only has the part** (4): `cauliflower`
  (`head, medium`), `celery` (`stalk, medium` — there is no whole-head measure),
  `eggplant` (`unpeeled`, 548 g vs peeled 458 g), `flour tortilla` (`tortilla`
  49 g, not the 484 g package).
- **Ginger** (1): `piece, 1 inch` (12 g), the measure you asked for on
  2026-09-02 — not `slice` (2.2 g), which is `sort_order 0`.
- **Fragment sets I am proposing as none** (3, beyond the owner's own
  examples): `mint`, `spinach`, `vegetable broth`.
- **Big-number rows** (1): `watermelon` → `melon` (4518 g). Right by meaning,
  and the single most expensive default in the table if it is ever wrong.
- **Cabbage and the lettuces** (4 confirmations): `cabbage`, `iceberg lettuce`,
  `red cabbage`, `red leaf lettuce`, `romaine lettuce` are drawn as **none** per
  your example. Worth noting the counter-case one row down: `napa cabbage` has
  a single `head` measure and therefore *does* get a default. Same food, two
  answers, because the vocabulary differs — which is the argument for a curated
  fact rather than a rule.
- **A seed gap** (1): `yellow bell pepper` carries only `pepper, large` (186 g)
  and `strip`, where the other three bells carry medium/large/small. Proposal:
  default it to `pepper, large` **and** file an `add_measure` for
  `pepper, medium` at 119 g (borrowed from the other bells, `— borrowed` in the
  source string, as the generator already does), then move the default to it.

---

## D2 — import preselects the default, and does not flag the line

**The ruling.** On a line whose printed unit the row cannot carry, if the row
has a `default_measure_id`, the review **selects that measure**: the chip is
selected, the card is NOT flagged, Save is not gated, the raw source line stays
visible above it, and changing it is one tap on a chip that is already on
screen. Rows with no default keep today's behaviour exactly.

### The scope question — which lines does the default answer?

This is the only substantive sub-decision, and it is where the cascade would
sneak back in if we are careless.

| | scope | consequence |
|---|---|---|
| **A** | **the line printed NO unit, or a `count`-family unit the row refuses (i.e. `piece`) — RECOMMENDED** | answers "2 onions", "1 red pepper", "3 potatoes", "1 avocado" — every line the owner complained about — and never overrides a word the source actually said |
| B | any unit the row refuses (the brief's literal reading) | also fires on "1 **bunch** cilantro" → preselects `sprig` (1 g against 25 g), on "1 **head** cabbage" where a row has no head, on "1 **can**" where the row's can is a different size. The source said something specific and we would be replacing it with our default: that is the guess ADR-0010 forbids |
| C | A, plus mass/volume units the row refuses | a "1 cup kale" line on a density-less row is a *density* gap, not a count gap; a measure cannot answer it (ADR-0008 §2) |

**Recommendation — A.** The rule in one sentence: *the default answers a line
that named a number and no thing; it never overrules a line that named a thing.*
Concretely, preselect when `resolution.unit` is null/empty or resolves to a unit
in `UnitFamily.count`; otherwise leave today's flag up. This keeps B's failure
mode — silently turning a printed `bunch` into a `sprig` — impossible, and it
costs nothing the owner asked for: no line they named printed a word.

### What "preselected" means in the data

The resolution's `unit` is **set to the measure's label** at preselect time (the
same token a tapped chip writes, via `sheetChoiceUnit`), so:

- `lineIssues` sees an acceptable token and returns no issue — the card is clean
  and Save is open **for the ordinary reason**, not by a special case. No new
  `LineIssue`, no "flagged but allowed" state, nothing that has to be remembered
  in two places.
- The commit path is unchanged: `unit = 'onion, medium'` rides through
  `buildCommit` → the repository's measure-label resolution exactly as a tapped
  chip does today.
- The chip row is **shown, not hidden**, on a preselected line — with the
  default chip `on`. The user sees the choice that was made for them and the
  alternatives beside it. (Hiding it would make the tap-to-change invisible and
  turn a stated fact into a silent one.)
- The card carries a quiet mono line: `counts as onion, medium · 110 g · tap to
  change`. That sentence is the whole honesty argument for D2: the default is
  **shown at the moment it is applied**, on the card, next to the raw source
  line. Nothing is inferred behind the user's back, because nothing is behind
  their back.

**No `inferred` mark, no revert affordance, no provenance on the stored line.**
Those were the rejected cascade's apparatus, needed because a *guess* has to be
undoable. A default that is displayed at the point of use and changeable in one
tap needs none of it, and the saved row is an ordinary measure line.

**The editor and the top-up sheets open on the default too** (same one-liner:
`initialChoice ??= defaultMeasure`), so "add an onion to this recipe" and "top
up onions on the shopping list" start on `onion, medium` rather than on nothing.
There the sheet is the user's own act, so there is no flag question at all.

---

## D3 — why the single-measure preselect never fired (cucumber)

**Named, in code.** `preselectedMeasure` (`line_validation.dart:233`) is
consulted in **exactly one place**: `editLineAmount`
(`recon_line_card.dart:840`), where it seeds `showQuantityUnitSheet`'s
`initialChoice`. It is a *sheet-opening* affordance.

Nothing in the validation path calls it. `importValidation`
(`import_view_models.dart:296`) builds each line's `LineValidation` from
`lineIssues(r, ingredient:, measures:)`, and `lineIssues` checks
`acceptableUnitTokens(...).contains(resolution.unit)`. The cucumber resolution's
unit is still `'piece'` — the preselect never wrote anything — so the check
fails, `unitNotAllowed` is returned, the card shows "Pick a supported unit", and
Save stays gated. The doc comment says so out loud: *"the flag stays up until
the user actually confirms"*.

So the field-test report is accurate and the behaviour is as-shipped: **one
measure pre-selects the SHEET, not the LINE.** ADR-0010's consequence 4 reads
"one measure pre-selects (there is nothing else the line could have meant)",
which the owner reasonably read as "is not flagged". The code and the ADR say
different things; the ADR is what everyone believed.

**It is not the measures race.** That was a real bug, and a different one: plan
0020 **J2** fixed two sites where measures were read through an autoDispose
*stream* provider with nothing listening, so the future completed with a
`StateError` and the catch turned it into "no measures" — which made even the
sheet preselect inert, and flagged `3 clove` garlic lines. Both sites now read
straight off the keepAlive repository (`recon_line_card.dart:809`,
`import_view_models.dart:311-313`), and `importValidation` reads
`AsyncValue.value` so a recompute keeps the last map rather than blinking. If a
measures read genuinely fails now it surfaces as the provider's error, not as a
screen of wrong flags.

**D2 subsumes it** — under D2 a cucumber line arrives with `unit = 'cucumber'`
and no flag at all — but the bug is named here because the two are separable:
even a row with NO curated default (broccoli) should not be told "one measure
pre-selects" when nothing on screen changes. If D2 were deferred, the minimum
fix is to make `preselectedMeasure`'s single-measure leg write the resolution at
arrival (and then it *is* D2 for the sole-measure case, which is the honest way
to describe it).

---

## D4 — the review screen edits the method with the editor v2 step cards

**The gap.** `reconciliation_view.dart:121-125` still prints:

> "Method is read-only in v1 — chips render with live amounts; editing lands
> later via the recipe's Edit route."

That note is stale: the editor v2 step cards shipped 2026-09-02 (plan 0022 D1,
`method_editor.dart`). The review screen kept the read-only fold
(`_MethodPreview`) and the notice underneath it, so an import — the one moment
the method is most likely to need a fix — is the one screen that cannot edit it.

### Options for reuse

| | shape | trade-off |
|---|---|---|
| **A** | **extract the ~20-method surface `MethodStepCard` uses off `RecipeEditor` into an abstract `MethodEditing` interface; `RecipeEditor` implements it; a new `ImportMethodEditing` adapter implements it over the import controller — RECOMMENDED** | one interface, no widget changes beyond the type of one field; both hosts keep their own state model |
| B | hoist the drafts + line map into a shared `MethodDraftController` (a `ChangeNotifier`) that both editors own | cleaner in the abstract, but it re-plumbs the shipped editor's state — a rewrite of the surface that just shipped and is under sim coverage |
| C | route to the recipe editor immediately after Save ("edit the method there") | zero new code; refuses the owner's actual request, and moves the fix past the commit that the method's chips are keyed to |
| D | duplicate the step card for the review screen | two step cards drift; the whole point of `MethodStepText` being shared is that they cannot |

**Recommendation — A.** The card's needs are already a narrow, nameable surface:
`methodDraft`, `lineById`, `substitution`, `relabels`, `editStep`,
`addMethodStep`, `removeMethodStep`, `moveMethodStep`, `chipRange`,
`timerRange`, `insertChip`, `insertTimer`, `removeChip`, `setTimerSpan`,
`repointChip`, `renameChip`, `setChipAmountRule`, `keepOldWord`,
`convertMethodToPlainText`, `methodLinkCounts`, and (for the picker's add door)
`addLineItem` / `addComponentLineItem` / `ensureGroupId`. `RecipeEditor` already
has every one; the adapter implements them against `ImportReconciling`.

**Scope cut for v1 of this:** on the review screen the line picker offers **this
import's lines only** — the `＋ Add an ingredient to this recipe` door is
disabled there, with a one-line reason. The review screen has never had an
add-a-line affordance, and adding one would mean minting a flat line index that
`buildCommit` does not walk. `substitution` / `relabels` are likewise empty at
review: identity changes on the review screen already re-point by line index,
so no chip can be orphaned by one.

### How the ref keys map at commit

This is the load-bearing detail, and it needs no new machinery — it needs one
conversion at one seam.

- **In the payload** (`reconciliation_payload.dart:192`), a `StepToken.ref`
  carries `refs: List<int>` — flattened **line indexes**.
- **On the review screen**, the preview recipe already mints synthetic ids:
  `previewLineId(i) == 'line-$i'` (`preview_recipe.dart:21`), and
  `_methodStep` remaps index refs onto them. So the editor's document model
  (`MethodDraftStep` + `RefSpan.refs: List<String>`) is keyed on `'line-<i>'` —
  the ids the fold already renders with, so `MethodStepText`'s "Reads as"
  preview shows live amounts with zero extra plumbing.
- **At commit**, `toTokens(draft)` gives a `MethodToken` stream with `String`
  refs; the seam parses `'line-<i>'` back to `i` and emits the payload's
  `StepToken.ref(refs: [i…])`. A ref whose index is **dropped** is left out —
  and a chip with no surviving refs demotes to plain text, which is the rule
  `buildCommit` and `_remapSteps` already implement (the never-dangling-line
  invariant). An unparseable id is a programming error and throws, rather than
  silently vanishing.
- **The repository is untouched**: `import_repository_impl.dart` mints a uuid
  per surviving flat index and `_remapSteps` rewrites index → `line_item_id`
  exactly as today.

Two invariants to pin with tests: **line indexes never renumber during review**
(a dropped line's index stays unused — `buildCommit` already depends on this),
and **round-trip stability**: payload steps → drafts → tokens → payload steps is
byte-identical when the user edits nothing.

**The stale notice and `_MethodPreview` are deleted**, not amended.

---

## D5 — the macro panel names the lines

**The gap, in the owner's words:** "this message makes it impossible to know
what ingredients need fixing". Today `incompleteNote` counts
(`2 stub lines · 1 unconvertible`); it never says *which*.

### Options

| | shape | trade-off |
|---|---|---|
| **A** | **the summary carries a per-line reason list; the panel lists them; the ingredient rows carry an in-place marker; tapping a marked row opens its fix — RECOMMENDED** | one new field on `RecipeMacroSummary`, one shared per-line wording helper |
| B | panel lists the lines; rows unchanged | the panel is below the fold on a long recipe, so you read a name and then hunt for it |
| C | rows marked only, panel keeps the counts | you can see *that* rows are marked but not what the total is waiting on; and a stub row's marker is the only place the word "stub" would appear |
| D | a separate "what's missing" screen | a fourth surface rendering the same summary, and the drift risk `incomplete_macros.dart` exists to prevent |

**Recommendation — A**, both halves, one vocabulary.

**One helper, same words.** `shared/incomplete_macros.dart` grows
`incompleteLineNote(MacroLineReason)` beside the existing `incompleteNote`, and
every surface reads it — the panel's list, the row marker's tooltip line, and
(later) the picker row. Wordings, mapped from the existing reason buckets so
nothing new is invented:

| reason | line wording | tapping the row |
|---|---|---|
| bare count, no measure | `Cucumber · needs a weight` | the line's amount sheet, opened on its default measure if it has one |
| stub ingredient | `Tofu · stub ingredient` | the ingredient's flesh-out form (`/ingredients/:id`) |
| unknown ingredient row (not synced) | `Tofu · not in your ingredients yet` | the flesh-out form |
| cross-basis without density | `Kale · needs a density` | the flesh-out form, density section |
| no quantity at all | `Salt · no amount` | the amount sheet |
| sub-recipe unresolved | `Romesco Aioli · sub-recipe has no yield` | the sub-recipe |
| sub-recipe incomplete | `Romesco Aioli · sub-recipe incomplete` | the sub-recipe |

The panel prints them under the badge, one per line, capped at **4** with
`+N more` (the count that is already there is the honest fallback for a very
broken recipe). The row marker is a small amber dot plus the mono reason at the
end of the `l3` amount column — deliberately the same amber as the review card's
`attn` state, because it is the same claim: *this line is why a number is
missing.*

**Invariant 3 is unchanged.** Nothing new is included in any total; the panel
still refuses, in the same words. What changes is that the refusal now names its
causes, which is strictly more honest, not less.

---

## D6 — imprecise lines never gate the total

**The ruling.** `to taste`, `pinch`, `dash`, `handful` — `UnitFamily.imprecise`
— are unweighable **by nature**. They are excluded from the sum **by rule**, the
total is shown, and the exclusion is named beneath it:

> `not counted: Parsley · handful, Sesame seeds · to taste`

Only **stubs** and **count-without-weight** lines (and the sub-recipe reasons)
still make a recipe `incomplete`.

### The invariant-3 argument

Invariant 3 says *never invent a value to make math work* and *an unknown must
not be silently dropped*. Both halves survive, and the second is the one people
worry about:

1. **Nothing is invented.** A handful of parsley contributes exactly zero to the
   total because zero grams of it were claimed — not because a number was
   guessed at and rounded down.
2. **Nothing is silent.** The exclusion is printed under the number, by name,
   every time. A reader can see precisely what the figure does and does not
   cover. That is a stronger form of honesty than the current behaviour, which
   hides the whole total and names nothing.
3. **The imprecise family is already excluded everywhere else, on purpose.**
   `convert` refuses it (`unit/imprecise`), `scale` leaves it untouched — "a
   pinch doubled is still a pinch". The macro engine treating the same word as a
   *fixable defect* is the outlier, not the exclusion.
4. **The current behaviour fails the invariant in the other direction.** "A
   recipe with a pinch of salt is unknowable" is not honest — it is a refusal to
   report a number that is knowable to within a pinch of salt. The household
   loses per-serving macros on nearly every real recipe, which is how a true
   statement becomes a useless one.

**The one guard:** a recipe whose lines are *all* imprecise summed nothing, and
`0 kcal` would be a fabrication. That case stays incomplete, with its own reason
(`nothing weighable yet`) — the same shape as the existing `noLines` guard.

### `handful` — excluded, or fixable?

The owner lumped it with `to taste`. **Recommendation: excluded, with the rest
of the family.** Reasons, in order of weight:

1. **One word, one meaning.** `handful` is `UnitFamily.imprecise` in the
   catalog. Splitting it — imprecise for scaling and conversion, fixable for
   macros — means the codebase holds two opinions about one unit, and every
   future reader has to learn which surface believes which.
2. **The fix does not exist.** "Fixable" means a household can resolve it in a
   tap; there is no measure or density that turns a handful into grams, because
   a handful is not a thing that has a weight. Marking it fixable would mark
   lines that can never be cleared, which is the "queue that never empties"
   failure D2 is trying to end.
3. **Extraction rarely emits it.** `handful` arrives when the source PRINTED
   "a handful", i.e. when the author deliberately declined to weigh it. Honouring
   that is respecting the source, which is 0014's whole posture.
4. **It is a *herb-scale* word.** A handful is parsley, spinach, basil, nuts —
   tens of grams against a recipe's thousands. If it were butter or flour the
   argument would be different, and the category gate (`impreciseUnitsFor`)
   already stops the editor offering "a dash of kale".

**The alternative, honestly stated:** if the owner later wants a handful to be
weighable, the right move is not a macro-engine special case — it is a
**measure** on the row (`handful ≈ 25 g`, `seed:typical`, with provenance),
which makes it a measure line like any other and takes it out of the imprecise
family for that ingredient entirely. That door stays open and needs no decision
now.

**A catalog note:** the brief mentions `drizzle`. The catalog holds exactly four
imprecise units — `pinch`, `dash`, `handful`, `to_taste` (`units.dart:108-111`).
`drizzle`, `glug`, `splash` do not exist; adding one is a catalog change plus
the DB's `unit_family()` mirror (migration 0017) plus an `allowed_units`
category gate, and is out of this lane's scope. Nothing in D6 depends on it —
the rule is *the family*, so a future word joins by being declared imprecise.
