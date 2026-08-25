# Seed data

Two things get seeded (spec §6):

1. **`usda_food`** — USDA FoodData Central (Foundation Foods + SR Legacy, CC0),
   server-side only. The reference set for *creating* ingredients and prefilling
   stubs. Never synced, never matched against at import (ADR-0005).
2. **Initial household `ingredient` vocabulary** — a small curated starter set
   (~a few dozen rows) so the app isn't empty on first run.

Density fallback: FDC food portions first, then FAO/INFOODS Density DB v2.0.

## Building the household vocabulary (`scripts/mine_recipes.ts`)

The initial `ingredient` vocab is mined from recipes you actually cook, not typed
by hand. Deterministically (no AI — JSON-LD is structured):

1. Paste recipe URLs into `scripts/recipe_urls.txt` (one per line).
2. `cd scripts && deno task mine` — fetches each, reads schema.org/Recipe
   JSON-LD, parses ingredient lines, and normalizes them with the shared §7
   normalizer (so seed and live cascade agree).
3. Review `scripts/out/vocab_candidates.csv` (deduped, sorted by frequency) and
   curate the rows you want into `seed.sql`. `out/` is git-ignored — the curated
   `seed.sql` is what's committed, not the raw run.

It also emits `gold_labels.jsonl` (for `evals/`), `needs_fallback.txt` (URLs
without JSON-LD, held for the step-8 photo path), `parse_failures.jsonl`, and
`ambiguous_pairs.txt` (near-duplicates to eyeball — never auto-merged).

`scripts/seed_usda.md` documents the intended USDA loader (not implemented in the
scaffold — it's a feature). `supabase db reset` will run `seed.sql` once it exists.
