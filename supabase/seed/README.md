# Seed data

Two things get seeded (spec §6):

1. **`usda_food`** — USDA FoodData Central (Foundation Foods + SR Legacy, CC0),
   server-side only. The reference set for *creating* ingredients and prefilling
   stubs. Never synced, never matched against at import (ADR-0005).
2. **Initial household `ingredient` vocabulary** — mined from real recipes and
   curated (currently 291 rows), so the app isn't empty on first run. Macros +
   density are prefilled from `usda_food` where a true match exists (248
   `complete`); the rest stay honest `stub`s for the flesh-out queue.

Density fallback: FDC food portions first, then FAO/INFOODS Density DB v2.0
(the FAO/INFOODS step is not wired yet — density is currently sparse).

## Building the household vocabulary (`scripts/mine_recipes.ts`)

The initial `ingredient` vocab is mined from recipes you actually cook, not typed
by hand. The pipeline is deterministic where correctness demands it, with an LLM
pass only for offline judgment (never in the runtime matcher — ADR-0004):

1. Paste recipe URLs into `scripts/recipe_urls.txt` (one per line).
2. `cd scripts && deno task mine` — fetches each, reads schema.org/Recipe
   JSON-LD, parses ingredient lines, normalizes with the shared §7 normalizer,
   and writes the raw mining outputs to `scripts/out/` (git-ignored; regenerable).
3. **Curate** `out/gold_labels.jsonl` into the true vocabulary — resolving the
   judgment cases rules can't (a choice like "avocado or sunflower oil" becomes
   *two* ingredients; "fat garlic" folds into Garlic as an alias). This produced
   `vocab.jsonl` (committed — it's judgment, not regenerable). See the flow that
   built it in the git history / `out/audit.md`.
4. `deno task gen-seed` — deterministically turns `vocab.jsonl` into
   `../seed.sql`, computing each `match_text` with the shared normalizer (so
   stored keys stay symmetric with the runtime cascade) and failing on
   collisions. Everything seeds `status='stub'` (density/macros come later).
5. `supabase db reset` applies it.

`vocab.jsonl` is the source of truth; edit it and re-run `gen-seed` to change the
seed — never hand-edit `seed.sql`.

It also emits `gold_labels.jsonl` (for `evals/`), `needs_fallback.txt` (URLs
without JSON-LD, held for the step-8 photo path), `parse_failures.jsonl`, and
`ambiguous_pairs.txt` (near-duplicates to eyeball — never auto-merged).

### The human-merge pass (why curation isn't optional)

The normalizer is deliberately conservative: it will not strip a word that is
noise in one context but identity in another. "fat" is dropped nowhere, because
`duck fat` is a real ingredient — so `fat garlic` survives as its own candidate
even though a human instantly knows it's just `garlic`. "cracked" stays because
`cracked wheat` exists, so `cracked black pepper` won't auto-fold into
`black pepper`. These are correct refusals, not bugs.

Resolving them is a **human pass** on top of the deterministic one: a person maps
the messy surface form onto the real ingredient, and that surface form is kept as
an **alias** (never discarded). `ambiguous_pairs.txt` is the worklist for it.
This is the same shape as the import-time learning loop (import-and-matching.md
§8) — a human correction becomes an alias — and the app's GUI should expose the
same move (merge a stub/ingredient into another, keeping the old name as an
alias) so the vocabulary keeps getting cleaner after seeding, not just during it.

## The USDA reference (`scripts/gen_usda.ts`)

`usda_food` (8262 foods, macros incl. fiber) is built from the USDA FoodData
Central CSV bundles (Foundation Foods + SR Legacy, CC0). The bundles are **not
committed** (~40MB); only the compact generated `../seed_usda.sql` is. To
regenerate:

1. Download + unzip the two CSV bundles from
   <https://fdc.nal.usda.gov/download-datasets> (Foundation Foods, SR Legacy).
2. `deno run --allow-read --allow-write gen_usda.ts <foundation_dir> <sr_legacy_dir>`
   — pass Foundation first so it wins on overlap. Keeps the four macros + fiber
   (per 100 g) and a density derived from a volume `food_portion`; `match_text`
   uses the shared normalizer so the reference is indexed the same way.

## Ingredient measures (`scripts/gen_measures.ts`)

`../seed_measures.sql` — the template vocab's starter **measures** ("1 potato,
medium = 213 g", step 7.6) — is GENERATED from the same FDC bundles' piece-type
`food_portion` rows, joined through `usda_links.jsonl`, with per-row provenance
in `ingredient_measure.source` (migration 0010). Never hand-edit the SQL.

```
deno task gen-measures <foundation_dir> <sr_legacy_dir>
```

Two tiers plus a survivor list (all encoded in the script):

- **Tier 1** — each ingredient's OWN linked food's piece portions, so russet
  and red potato carry their own weights. Volume rows ("1 cup") are skipped
  (bridging volume is the density's job), as are mass aliases ("1 oz"),
  serving sizes, and preparation noise; ranked container > medium > large >
  small > whole > fragment and capped at 3 per ingredient, deterministic. A
  variety linked to a broader food keeps only portions naming the variety
  ("cherry tomato" gets the 17 g `cherry` portion, never the 123 g generic
  medium). `source = usda_fdc:<fdc_id> (<portion>)`.
- **Tier 2** — an explicit borrow map for varieties whose own food has no
  usable piece portion (gold potato ← russet's size classes; canned bean
  varieties ← pinto's drained 15 oz can). `source` ends in `— borrowed`.
- **`seed:typical` survivors** — a deliberately short list where FDC has
  nothing usable and the item matters (shallot bulb, tempeh 8 oz package,
  coconut-milk 400 ml can, silken-tofu 12.3 oz block).

The generated SQL is idempotent (`on conflict do nothing` against 0010's live
`(ingredient_id, label)` unique index) and ends with a check that every seeded
match_text still resolves to a live vocab ingredient — a vocab regeneration
that drops one fails the seed loudly instead of silently dropping measures.

## Prefill: promoting stubs to `complete` (`usda_links.jsonl`)

`usda_links.jsonl` (committed) maps an ingredient's `match_text` → the `fdc_id`
of the USDA row whose food it truly is. These were resolved by trigram for the
easy cases and an LLM arbiter for the judgment ones, under a strict
**no-analogue** rule: a link is only made where the USDA food genuinely *is* the
ingredient — never a stand-in (canned ≠ dry, fruit ≠ its oil, vegan ≠ dairy).
Unmatched ingredients stay `stub`. `gen-seed` reads `usda_links.jsonl` and emits
`../seed_prefill.sql`, which copies macros/density onto matched rows and flips
them to `complete` (a guard skips USDA rows with no macros).

## Load order

`config.toml` `[db.seed].sql_paths` runs, in order: `seed.sql` (household +
vocab) → `seed_usda.sql` (reference) → `seed_prefill.sql` (macros). `supabase db
reset` applies all three.
