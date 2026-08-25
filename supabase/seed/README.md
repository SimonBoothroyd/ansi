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

`scripts/seed_usda.md` documents the intended USDA loader (not implemented in the
scaffold — it's a feature). `supabase db reset` will run `seed.sql` once it exists.
