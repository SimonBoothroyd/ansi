# `piece` — the seeded curation pass (owner ticks this)

**The ruling this implements** (owner, 2026-09-02): *"if a suitable alternative
exists e.g. clove, medium, etc that is MUCH clearer than piece and piece should
not be available in those cases, otherwise we have to arbitrarily guess what
piece means. Piece is the fallback when no appropriate measure is available.
This isn't rule-based. we need to manually decide for seeded, and then the user
needs to decide for new ingredients."*

So this file is **not** a rule and not generated output. It is a decision list:
for each seeded ingredient that carries at least one piece-type measure, does
`piece` stay in its `allowed_units`, or come out? The groupings below are a
*draft* for reading speed — every row is yours to flip, and the tick box is
the point.

**Scope.** All **142** seeded ingredients in `supabase/seed_measures.sql` that
carry ≥1 measure (270 measure rows). The generator already excludes pure volume
portions (ADR-0008 §2: a volume-named weight is a density), so every measure
listed here is piece-type and none is filtered out by `isVolumeUnitLabel`.
The other ~149 vocab rows have no measures at all and are untouched: they keep
`piece` if they had it, because there is nothing clearer to say.

**How to read a row.** The measures are printed with the seed's own labels and
gram weights, in `sort_order`. Tick to accept the draft; strike it to flip.

**Draft totals:** drop `piece` on **119**, keep it on **4**, **19** flagged for
your call.

---

## Owner rulings — 2026-09-02

Sections **A** and **B** (119 rows): **accepted as drafted** — `piece` comes out.

**C — the four "keep" rows, all ruled:**

| ingredient | ruling | what lands |
|---|---|---|
| `broccoli` | "bunch → piece" (confirmed: the bunch is the whole) | `piece` comes out; the 608 g **bunch** is relabelled `whole` so "1 broccoli" reads as one |
| `dill pickle` | spear | `piece` comes out; `spear` is the count |
| `ginger` | "can we do 2 cm piece? or make more clear that slice 2.2 g is the 2 cm piece" → asked what recipes say; they count "a 1-inch / thumb-sized piece" or "1 tbsp grated" | `piece` comes out; keep `slice`; **add `piece, 1 inch` at 12 g** (`seed:typical`, 10–15 g is the usual range; the tbsp form rides ginger's density). Label open to "2 cm" if the owner prefers |
| `kombu` | strip | `piece` comes out; `strip` is the count |

**D — the owner's calls:**

| ingredient | ruling | what lands |
|---|---|---|
| `asparagus` | drop; spears are fine | out |
| `basil` | "do we have some tsp-like measure? normally x tsp chopped or y g chopped" | out; the tsp/tbsp/cup ↔ g bridge is a **density**, not a measure — see the density note below |
| `cauliflower` | drop | out |
| `celery` | drop | out |
| `cherry tomato` | "cherry is wrong… we measure these by cup or g so piece isn't needed; we need clean macros / density" → "drop piece / cherry / tomato altogether" | out; the `cherry 17 g` measure (USDA, borrowed from the generic tomato row) is **dropped entirely**; the row's default is cup so it never carries `piece`; density 0.63 g/ml + macros verified present |
| `iceberg lettuce` | drop | out |
| `mint` | drop | out |
| `multigrain bread` | drop | out |
| `cabbage` | drop | out |
| `rhubarb` | drop | out |

**Applied by analogy** (confirmed by the owner, "sgtm"): `red cabbage`, `red leaf lettuce`, `romaine lettuce` → out (as cabbage / iceberg); `soft sandwich bread`, `sprouted multigrain bread`, `wheat bread whole`, `white bread` → out (as multigrain bread); `thai basil` → out (as basil); `spinach` → out (as mint: bunch/package are the counts).

**Net:** `piece` stays on **no** seeded ingredient that carries a measure; the ~149 measure-less rows keep it.

**Density note (basil, thai basil, cherry tomato).** The volume ↔ mass chips
(tsp · tbsp · cup ↔ g) come from a density, which the USDA seed row carries
when its portion text yielded one; the build lane verifies these three rows
have a density and macros, and adds a curated one (with a source) where
missing — never a guessed number.

---

## A · Drop `piece` — the measure names the thing itself (72)

An `apple, medium` is an apple. There is no question `piece` answers here that
the measure does not answer better, and the sized rows are exactly the
"is it medium or large?" guess the ruling refuses to make.

| ✓ | ingredient (`match_text`) | its measures | reason |
|---|---|---|---|
| ☐ | `almond` | almond 1.2 g | the measure names the thing itself |
| ☐ | `apple` | apple, medium 182 g · apple, large 223 g · apple, small 149 g · apple, extra small 101 g | the measure names the thing itself |
| ☐ | `apricot` | apricot 35 g | the measure names the thing itself |
| ☐ | `avocado` | avocado 201 g | the measure names the thing itself |
| ☐ | `banana` | banana, medium 118 g · banana, large 136 g · banana, small 101 g · banana, extra small 81 g · banana, extra large 152 g | the measure names the thing itself |
| ☐ | `bay leaf` | leaf 0.2 g | the measure names the thing itself |
| ☐ | `beet` | beet 82 g | the measure names the thing itself |
| ☐ | `blueberry` | berry 1.36 g | the measure names the thing itself |
| ☐ | `brussel sprout` | sprout 19 g | the measure names the thing itself |
| ☐ | `burger bun` | bun 44 g | the measure names the thing itself |
| ☐ | `butternut squash` | squash, whole 1130 g | the measure names the thing itself |
| ☐ | `carrot` | carrot, medium 61 g · carrot, large 72 g · carrot, small 50 g · slice 3 g · strip, large 7 g · strip, medium 4 g | the measure names the thing itself |
| ☐ | `cherry` | cherry 8.2 g | the measure names the thing itself |
| ☐ | `cinnamon stick` | stick 2.6 g | the measure names the thing itself |
| ☐ | `corn tortilla` | tortilla 24 g | the measure names the thing itself |
| ☐ | `cremini mushroom` | mushroom, whole 20 g | the measure names the thing itself |
| ☐ | `cucumber` | cucumber 301 g | the measure names the thing itself |
| ☐ | `date` | date, pitted 24 g | the measure names the thing itself |
| ☐ | `eggplant` | eggplant, peeled 458 g · eggplant, unpeeled 548 g | the measure names the thing itself |
| ☐ | `english muffin` | muffin 57 g | the measure names the thing itself |
| ☐ | `enoki mushroom` | mushroom, medium 3 g · mushroom, large 5 g | the measure names the thing itself |
| ☐ | `flour tortilla` | package 484 g · tortilla 49 g | the measure names the thing itself |
| ☐ | `gala apple` | apple, medium 172 g · apple, large 200 g · apple, small 157 g | the measure names the thing itself |
| ☐ | `gold potato` | potato, medium 213 g · potato, large 369 g · potato, small 170 g | the measure names the thing itself |
| ☐ | `granny smith apple` | apple, medium 167 g · apple, large 206 g · apple, small 144 g | the measure names the thing itself |
| ☐ | `grapefruit` | grapefruit, whole 246 g | the measure names the thing itself |
| ☐ | `green bean` | bean 5.5 g | the measure names the thing itself |
| ☐ | `green bell pepper` | pepper, medium 119 g · pepper, large 164 g · pepper, small 74 g · ring 10 g · strip 2.7 g | the measure names the thing itself |
| ☐ | `green grape` | grape 4.9 g | the measure names the thing itself |
| ☐ | `green olive` | olive 2.7 g | the measure names the thing itself |
| ☐ | `hazelnut` | nut 1.4 g | the measure names the thing itself |
| ☐ | `hot chili` | chili 45 g | the measure names the thing itself |
| ☐ | `jalapeño` | jalapeño 14 g | the measure names the thing itself |
| ☐ | `king oyster mushroom` | mushroom, medium 90 g | the measure names the thing itself |
| ☐ | `kiwi` | kiwi, whole 69 g | the measure names the thing itself |
| ☐ | `leek` | leek 89 g · slice 6 g | the measure names the thing itself |
| ☐ | `lemon` | lemon, whole 100 g | the measure names the thing itself |
| ☐ | `lime` | lime, whole 67 g | the measure names the thing itself |
| ☐ | `mango` | mango, whole 336 g | the measure names the thing itself |
| ☐ | `nectarine` | nectarine, whole 129 g | the measure names the thing itself |
| ☐ | `onion` | onion, medium 110 g · onion, large 150 g · onion, small 70 g · slice, large 38 g · slice, medium 14 g · slice, thin 9 g · ring 6 g | the measure names the thing itself |
| ☐ | `orange` | orange, whole 140 g | the measure names the thing itself |
| ☐ | `orange bell pepper` | pepper, medium 119 g · pepper, large 164 g · pepper, small 74 g · ring 10 g | the measure names the thing itself |
| ☐ | `oyster mushroom` | mushroom 15 g | the measure names the thing itself |
| ☐ | `parsnip` | parsnip, medium 120 g | the measure names the thing itself |
| ☐ | `peach` | peach, medium 150 g · peach, large 175 g · peach, small 130 g · peach, extra large 224 g | the measure names the thing itself |
| ☐ | `pineapple` | pineapple, whole 905 g · slice 166 g · slice, thin 56 g | the measure names the thing itself |
| ☐ | `plantain` | plantain 267 g | the measure names the thing itself |
| ☐ | `poblano pepper` | pepper 100 g | the measure names the thing itself |
| ☐ | `portobello mushroom` | mushroom, whole 84 g | the measure names the thing itself |
| ☐ | `radish` | radish, medium 4.5 g · radish, large 9 g · radish, small 2 g · slice 1 g | the measure names the thing itself |
| ☐ | `raspberry` | raspberry 1.9 g | the measure names the thing itself |
| ☐ | `red bell pepper` | pepper, medium 119 g · pepper, large 164 g · pepper, small 74 g · ring 10 g | the measure names the thing itself |
| ☐ | `red delicious apple` | apple, medium 212 g · apple, large 260 g · apple, small 158 g | the measure names the thing itself |
| ☐ | `red grape` | grape 4.9 g | the measure names the thing itself |
| ☐ | `red onion` | onion, medium 110 g · onion, large 150 g · onion, small 70 g | the measure names the thing itself |
| ☐ | `red potato` | potato, medium 213 g · potato, large 369 g · potato, small 170 g | the measure names the thing itself |
| ☐ | `russet potato` | potato, medium 213 g · potato, large 369 g · potato, small 170 g | the measure names the thing itself |
| ☐ | `scallion` | scallion, medium 15 g · scallion, large 25 g · scallion, small 5 g | the measure names the thing itself |
| ☐ | `serrano pepper` | pepper 6.1 g | the measure names the thing itself |
| ☐ | `shallot` | shallot, medium 30 g | the measure names the thing itself |
| ☐ | `shiitake mushroom` | mushroom, whole 19 g | the measure names the thing itself |
| ☐ | `strawberry` | strawberry, medium 12 g · strawberry, large 18 g · strawberry, small 7 g · strawberry, extra large 27 g | the measure names the thing itself |
| ☐ | `sweet potato` | sweet potato 130 g | the measure names the thing itself |
| ☐ | `tomato` | tomato, medium 123 g · tomato, large 182 g · tomato, small 91 g · cherry 17 g · plum tomato 62 g · slice, medium 20 g · slice, large 27 g · wedge 31 g · slice, thin, small 15 g | the measure names the thing itself |
| ☐ | `tostada shell` | shell 12.3 g | the measure names the thing itself |
| ☐ | `turnip` | turnip, medium 122 g · turnip, large 183 g · turnip, small 61 g · slice 15 g | the measure names the thing itself |
| ☐ | `watermelon` | melon 4518 g · wedge 286 g · watermelon ball 12.2 g | the measure names the thing itself |
| ☐ | `white mushroom` | mushroom, medium 18 g · mushroom, large 23 g · mushroom, small 10 g · slice 6 g | the measure names the thing itself |
| ☐ | `yellow bell pepper` | pepper, large 186 g · strip 5.2 g | the measure names the thing itself |
| ☐ | `yellow squash` | squash, medium 196 g | the measure names the thing itself |
| ☐ | `zucchini` | zucchini, medium 196 g · zucchini, large 323 g · zucchini, small 118 g · slice 9.9 g | the measure names the thing itself |

---

## B · Drop `piece` — the natural count is a named part or container (47)

Nobody writes "1 piece of garlic"; they write a clove. Nobody writes "1 piece
of chickpeas"; they write a can. The named noun *is* how the food is counted,
so `piece` is only a worse way of saying it.

| ✓ | ingredient (`match_text`) | its measures | reason |
|---|---|---|---|
| ☐ | `active yeast dry` | sachet 7 g | the natural count is **sachet** |
| ☐ | `baked bean` | can (16 oz) 454 g | the natural count is **can** |
| ☐ | `black bean canned` | can (15 oz), drained 277 g | the natural count is **can** |
| ☐ | `black eyed pea canned` | can (15 oz), drained 277 g | the natural count is **can** |
| ☐ | `brazil nut` | kernel 5 g | the natural count is **kernel** |
| ☐ | `cannellini bean canned` | can (15 oz), drained 277 g | the natural count is **can** |
| ☐ | `cantaloupe` | melon, medium 552 g · melon, large 814 g · melon, small 441 g · wedge, large 102 g · wedge, medium 69 g · wedge, small 55 g · cantaloupe ball 13.8 g | the natural count is **melon** |
| ☐ | `chickpea canned` | can (15 oz), drained 253 g | the natural count is **can** |
| ☐ | `cilantro` | sprig 2.22 g | the natural count is **sprig** |
| ☐ | `coconut milk` | can (400 ml) 400 g | the natural count is **can** |
| ☐ | `corn` | ear, medium 102 g · ear, large 143 g · ear, small 73 g | the natural count is **ear** |
| ☐ | `dark red kidney bean canned` | can (15 oz), drained 266 g | the natural count is **can** |
| ☐ | `dill` | sprig 0.2 g | the natural count is **sprig** |
| ☐ | `edamame frozen` | package 432 g | the natural count is **package** |
| ☐ | `extra firm tofu` | block (14 oz) 397 g | the natural count is **block** |
| ☐ | `fennel` | bulb 234 g | the natural count is **bulb** |
| ☐ | `fig dried` | fig, whole 8.4 g | the natural count is **fig, whole** |
| ☐ | `fire tomato canned roasted` | can (14.5 oz) 411 g · can (28 oz) 794 g | the natural count is **can** |
| ☐ | `garlic` | clove 3 g | the natural count is **clove** |
| ☐ | `great northern bean canned` | can (15 oz), drained 277 g | the natural count is **can** |
| ☐ | `green bean canned` | can (14.5 oz), drained 240 g | the natural count is **can** |
| ☐ | `instant yeast` | sachet 7 g | the natural count is **sachet** |
| ☐ | `lemon juice` | lemon 48 g | the natural count is **lemon** |
| ☐ | `light red kidney bean canned` | can (15 oz), drained 266 g | the natural count is **can** |
| ☐ | `lime juice` | lime 44 g | the natural count is **lime** |
| ☐ | `napa cabbage` | head 950 g | the natural count is **head** |
| ☐ | `navy bean canned` | can (15 oz), drained 277 g | the natural count is **can** |
| ☐ | `nori` | sheet 2.5 g | the natural count is **sheet** |
| ☐ | `okra` | pod 11.88 g | the natural count is **pod** |
| ☐ | `orange juice` | orange, juiced 86 g | the natural count is **orange, juiced** |
| ☐ | `parsley` | sprig 1 g | the natural count is **sprig** |
| ☐ | `pea frozen` | package 284 g | the natural count is **package** |
| ☐ | `pinto bean canned` | can (15 oz), drained 277 g | the natural count is **can** |
| ☐ | `pistachio` | kernel 0.7 g | the natural count is **kernel** |
| ☐ | `shiitake bacon` | slice 5 g | the natural count is **slice** |
| ☐ | `silken tofu` | block (12.3 oz) 349 g | the natural count is **block** |
| ☐ | `star anise` | pod 2 g | the natural count is **pod** |
| ☐ | `tatsoi` | head 150 g | the natural count is **head** |
| ☐ | `tempeh` | package (8 oz) 227 g | the natural count is **package** |
| ☐ | `tofu bacon` | slice 15 g | the natural count is **slice** |
| ☐ | `tomato canned` | can (14.5 oz) 411 g · can (28 oz) 794 g | the natural count is **can** |
| ☐ | `tomato canned whole` | can (14.5 oz) 411 g · can (28 oz) 794 g · tomato, medium 111 g · tomato, large 164 g · tomato, small 82 g | the natural count is **can** |
| ☐ | `tomato paste` | can (6 oz) 170 g | the natural count is **can** |
| ☐ | `tomato puree canned` | can (29 oz) 822 g · can (15 oz) 425 g | the natural count is **can** |
| ☐ | `tomato sauce canned` | can (15 oz) 425 g · can (8 oz) 227 g | the natural count is **can** |
| ☐ | `vegan sausage` | link 100 g | the natural count is **link** |
| ☐ | `vegetable broth` | can (14.5 oz) 390 g · carton (32 oz) 926 g | the natural count is **can / carton** |

---

## C · Keep `piece` — the measures are cuts of a whole that has no measure (4)

The owner's own example is the shape: broccoli's `bunch · spear · crown` are
three different things and none of them is "a broccoli". A recipe that says
"1 broccoli" means a whole one, and the vocab cannot say that — so the honest
count has to stay available.

| ✓ | ingredient (`match_text`) | its measures | reason |
|---|---|---|---|
| ☐ | `broccoli` | bunch 608 g · spear 31 g · crown 150 g | bunch 608 · spear 31 · crown 150 — three different things, none of them "a broccoli" |
| ☐ | `dill pickle` | spear 40.4 g | only "spear 40.4 g" — a cut, not a whole pickle |
| ☐ | `ginger` | slice 2.2 g | only "slice 2.2 g"; recipes say "a 2 cm piece of ginger" (ADR-0008 names this case) |
| ☐ | `kombu` | strip 10 g | only "strip 10 g" — a cut; "a piece of kombu" is the idiom |

---

## D · Your call (19)

Each of these has a real countable measure **and** a plausible whole that the
vocab cannot name — the exact tension the ruling puts in your hands rather than
in a rule. My leaning is noted per row; none of it is load-bearing.

| ✓ | ingredient (`match_text`) | its measures | reason |
|---|---|---|---|
| ☐ | `asparagus` | spear, medium 16 g · spear, large 20 g · spear, small 12 g · spear, extra large 24 g · spear tip 3.5 g | spear sizes + spear tip — a spear is the count; no whole bunch measure |
| ☐ | `basil` | leaf 0.5 g | leaf 0.5 g — a leaf is the count; no whole plant/bunch measure |
| ☐ | `cabbage` | head, medium 908 g · leaf, medium 23 g · head, large 1248 g · leaf, large 33 g · head, small 714 g · leaf 15 g | head sizes + leaf sizes — head is the whole; leaf is a fragment |
| ☐ | `cauliflower` | head, medium 588 g · head, large 840 g · head, small 265 g · floweret 13 g | head sizes + floweret — head is the whole |
| ☐ | `celery` | stalk, medium 40 g · stalk, large 64 g · stalk, small 17 g · strip 4 g | stalk sizes — a stalk is the count, but a whole head of celery has none |
| ☐ | `cherry tomato` | cherry 17 g | "cherry 17 g" is the count, but the label reads as a fruit name |
| ☐ | `iceberg lettuce` | head, medium 539 g · leaf, medium 8 g · head, large 755 g · leaf, large 15 g · head, small 324 g · leaf, small 5 g | head sizes + leaf sizes — same shape as cabbage |
| ☐ | `mint` | sprig 2 g · bunch 25 g | sprig + bunch — two countables, neither is "a mint" |
| ☐ | `multigrain bread` | slice regular 26 g · slice, large 41 g | slice is the count; a whole loaf has no measure |
| ☐ | `red cabbage` | head, medium 839 g · head, large 1134 g · head, small 567 g · leaf 23 g | head sizes + leaf — same shape as cabbage |
| ☐ | `red leaf lettuce` | leaf inner 2.6 g · leaf outer 17 g · head 309 g | leaf inner/outer + head — same shape |
| ☐ | `rhubarb` | stalk 51 g | stalk 51 g — a stalk is the count; no whole |
| ☐ | `romaine lettuce` | leaf inner 6 g · leaf outer 28 g · head 626 g | leaf inner/outer + head — same shape |
| ☐ | `soft sandwich bread` | slice 27.3 g | slice is the count; a whole loaf has no measure |
| ☐ | `spinach` | bunch 340 g · package 284 g | bunch + package — neither is "a spinach" |
| ☐ | `sprouted multigrain bread` | slice 38 g | slice is the count; a whole loaf has no measure |
| ☐ | `thai basil` | leaf 0.5 g | leaf 0.5 g — same as basil |
| ☐ | `wheat bread whole` | slice 32.1 g | slice is the count; a whole loaf has no measure |
| ☐ | `white bread` | slice 27.3 g | slice is the count; a whole loaf has no measure |

Leanings for D, in one line each: **drop** on `cabbage · red cabbage ·
cauliflower · iceberg lettuce · romaine lettuce · red leaf lettuce` (a head is
the whole, and it is seeded) and on `cherry tomato` (the cherry is the count);
**keep** on `basil · thai basil · mint · spinach · celery · rhubarb ·
asparagus` (a leaf/sprig/stalk/spear is a part, and "a bunch of parsley"-shaped
lines are real) and on the five **breads** (a slice is seeded, a loaf is not,
and "1 loaf" is a line a recipe really prints).

---

## How this lands in the pipeline

`allowed_units` is an **explicit per-ingredient column** (ADR-0008 §4,
migration 0012) materialized at ingredient creation from
`default_allowed_units()`. So this pass needs no new column and no new concept
— it is a change to what that list holds for 119 rows.

1. **The derived default keeps a count row's `piece`.** `default_allowed_units()`
   (`supabase/migrations/0012_unit_admission.sql`) and its Dart mirror
   `_derivedSet` (`app/lib/features/ingredients/domain/allowed_units.dart:145-152`,
   `case UnitFamily.count: units.add(pieces)`) are **not** changed. A row with no
   measures must still get `piece`, and the default function does not — and
   should not — know about the measure table. Change one, change both stays
   intact because neither moves.
2. **The seed subtracts.** `supabase/seed_curation.sql` already carries
   per-row `allowed_units` overrides that are "genuinely non-derivable"
   (ADR-0009 rule 2 keeps exactly this kind: liquid smoke `tsp`, hot sauce
   `to_taste`). This pass is the same kind of fact and belongs there, expressed
   through `supabase/seed/curation_overrides.jsonl` as
   `{"kind":"allowed_units","match_text":"avocado","remove":["piece"],
   "reason":"the avocado measure is the count — piece would be a guess"}`, one
   line per dropped row, regenerated into `seed_curation.sql`. That keeps the
   decision **in the committed curation file where a human can read and revise
   it**, which is exactly what "we need to manually decide for seeded" asks
   for, and it survives a reseed.
3. **Reseed, not a migration.** All dev data is throwaway through the roadmap,
   so re-running the seed is the whole rollout. A migration would have to
   guess whether a household had edited its own list — and ADR-0009 rule 3
   (union-never-remove on a backfill) says it must not remove anything from a
   list the household owns. **The one removal leg in the model stays the
   density-deletion one; this pass does not add a second.**
4. **A pgTAP assertion, not a rule.** `supabase/tests/unit_admission.sql`
   gains a check in the spirit of the ADR-0009 one: for the ticked rows,
   `'piece' <> ALL(allowed_units)` after seeding — so a future reseed or an
   unrelated generator change cannot quietly put it back.
5. **Nothing else in the app changes for this file.** The chip row, the
   validation and the import flag all read `allowed_units` already.
