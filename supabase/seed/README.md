# Seed data

Two things get seeded, and they have different owners:

1. **The household vocabulary** — `snapshot.jsonl` in, `../seed_vocab.sql`
   out. The owner's **live household rows are the curated truth**, and the
   seed is a copy of them. The direction is **cloud → seed**.
2. **`usda_food`** — the USDA FoodData Central reference (Foundation Foods +
   SR Legacy, CC0), server-side only, never synced and never matched against
   at import (ADR-0005). Generated separately by `scripts/gen_usda.ts` into
   `../seed_usda.sql` — see `scripts/seed_usda.md`. Nothing on this page
   touches it.

## The vocabulary: one input, one output

```
supabase/seed/snapshot.jsonl   →   deno task gen-seed   →   supabase/seed_vocab.sql
```

`snapshot.jsonl` is one JSON object per ingredient, exactly the shape
`export_all.sql` produces: the curated columns (`canonical_name`, `category`,
`default_unit`, `macros_basis`, `density_g_per_ml`, `macros`, `status`,
`source`, `source_label`, `source_score`, `source_edited`,
`piece_basis_amount`, `piece_source`, `allowed_units`, `match_text`), plus
`derived_allowed_units` (what `default_allowed_units()` would have said), plus
the row's `aliases` and `measures` with their own `source` stamps. Ids and
timestamps are stripped when the file is written, and the generator ignores
them if they are there — the seed mints its own row identity wherever it
lands.

`seed_vocab.sql` is ONE file and replaces the five-stage pipeline that came
before it (mined vocab → USDA prefill → generated measures → curation
overrides → FAO density fallback). There is nothing left to re-derive: a
density somebody filled in the app, a unit they admitted, a measure they kept,
a piece weight they borrowed — those decisions already happened, in the app,
on the row. Re-deriving them from raw sources was the old pipeline's whole
job, and it is over.

**Current counts** (computed by the generator into `counts.json`, never typed
by hand — `scripts/cloud_verify.sh` and the deploy job read that file):

- **319** ingredients — **283** `complete`, **36** honest `stub`s
- **138** aliases · **272** measures
- **60** rows whose `allowed_units` differs from what the rule derives

## Re-exporting from the cloud (the owner runs this)

The cloud is the owner's; agents are permission-gated from `--linked` on
purpose. So this leg is human-run:

```sh
supabase db query --linked -f supabase/seed/export_all.sql \
  | sed -n '/^{/,$p' \
  | jq -c '.rows[0].snapshot[]
           | del(.id, .created_at, .updated_at)
           | .aliases  = [ (.aliases  // [])[] | del(.updated_at) ]
           | .measures = [ (.measures // [])[] | del(.id, .updated_at) ]' \
  > supabase/seed/snapshot.jsonl
cd supabase/seed/scripts && deno task gen-seed
```

The `sed` is not optional: the CLI chats before its JSON ("Initialising login
role…", the update nag), so only the document from the first `{` is fed to
`jq`. `export_all.sql` returns **one row per household** — the template first,
then every household with a member — so `.rows[0]` is the template. To promote
a PERSON's household instead, pick its row by id and read that `.snapshot`;
that is the move the "cloud rows are the curated truth" ruling describes.

`rows` order and the snapshot's own order are stable (`order by
h.is_template desc, h.created_at`, and `order by r->>'match_text'` inside), so
re-exporting an unchanged household produces a byte-identical file and a
no-op diff.

## What the generator decides

A snapshot is data; these four things are judgments the generator makes, and
each one can fail the build rather than emit a broken seed.

1. **`match_text` is recomputed, then asserted.** Every key is re-derived with
   the shared §7 normalizer (`functions/_shared/normalize.ts`) and compared
   with the exported value — for ingredients and for aliases. A disagreement
   means the stored vocabulary and the runtime cascade have drifted apart, so
   the build fails naming both values. (This is also the gate on any
   normalizer change: edit the normalizer, and the seed tells you which rows
   need renaming before it will regenerate.)
2. **One namespace for every key.** Ingredient keys and alias keys live in a
   single space, because the cascade's exact tier searches both tables as one
   surface. An alias that normalizes onto another ingredient's key — or
   another ingredient's alias — fails the build naming both sides. Only an
   alias its own ingredient already covers is dropped quietly. (`planSeed`,
   tested in `scripts/gen_seed.test.ts`.)
3. **A seed row must clone.** `ensure_onboarded()` (migration 0039)
   deliberately leaves a household's private typed-in data behind: it skips
   `source = 'manual'` ingredients and `source = 'import_correction'` aliases.
   A seed row carrying either would seed and then reach no household at all,
   so the generator re-stamps exactly those two to `'seed'` and says how many
   in a comment in the generated file. Every other stamp is the row's real
   provenance and is carried verbatim.
4. **`allowed_units` is written explicitly, and gets the last word.** 0012's
   insert trigger fills the list from `default_allowed_units()` only when the
   writer leaves it NULL, so passing the curated list is what preserves a
   curator's admissions *and* their refusals. On a refresh, two AFTER UPDATE
   triggers (0014's density leg, 0039's piece leg) would union units back in
   when a density or piece weight arrives, so the generated file re-asserts
   the snapshot's list in one closing statement.

## The invariants the generated file carries

`supabase db reset` FAILS loudly on any of these. They are checks on the
exported data now — the rows are curated rather than derived, so the only
thing left to be wrong is that the curation itself is dishonest.

- **R1** — a volume `default_unit` REQUIRES a density. A volume line on a
  density-less per-g ingredient can never compute macros. Fix it by filling an
  honest density on the row in the app, or flipping its default to a weight,
  then re-exporting.
- **R2** — every stored density lands in the kitchen band **0.03–2.0 g/ml**.
  This catches the wrong physical quantity (2.165 is crystal salt, not what a
  spoonful weighs) without second-guessing the genuinely light end (dill at
  0.038).
- **R3** (ADR-0015) — the two halves of the piece rule: **(a)** every
  `piece`-default row says what one of it weighs, and **(b)** no row with any
  other default admits `piece`.
- **R4** — every row whose `allowed_units` differs from
  `derived_allowed_units` is listed in the generated file as an auditable
  comment block with its diff (`+unit` admitted, `-unit` withheld). This is
  what the old overrides file's `allowed_units` entries were for: a curated
  refusal must survive the reseed, but it must not survive invisibly.
- …and every measure resolves to a live vocab row, by the same `where not
  exists` guard per live label the measures insert uses (0011 dropped the
  unique index an `on conflict` would have needed, because offline duplicates
  must never fail an upload).

## Loading it

`config.toml` `[db.seed].sql_paths` runs three files, in order:
`seed_vocab.sql` (the template household + its whole vocabulary) →
`seed_usda.sql` (the reference) → `seed_usda_index.sql` (the BM25 index over
it — `usda_probe` raises without it). `supabase db reset` applies all three.

The file is **re-runnable** (migration 0020): the template holds one live row
per `match_text`, so an existing row is refreshed in place and a new one is
inserted, and a reseed of an unchanged snapshot is a complete no-op. On cloud
that is the deploy workflow's **`reseed_template`** button — the
promote-to-template leg. It touches the member-less template household only.

> **Existing households do not move with it.** `ensure_onboarded()` clones the
> template once, at creation. Carrying a reseeded template forward onto
> households that already exist is a separate, operator-run leg:
> `../rollout_ingredient_refresh.sql` and `../rollout_measure_refresh.sql`
> (docs/cloud-setup.md §2b). Both are deliberately **fill-only / union-only**
> for other households: they add a missing fibre figure or a newly admitted
> unit, they add measures nobody has, and they never overwrite a number
> somebody edited. A row a person has made their own stays theirs.

## Mining recipes (`scripts/mine_recipes.ts`)

Still here, and no longer a seed input. It fetches the recipe URLs in
`scripts/recipe_urls.txt`, reads schema.org/Recipe JSON-LD, parses ingredient
lines and normalizes them with the shared §7 normalizer, writing to
`scripts/out/` (git-ignored, regenerable). What it produces now is
`gold_labels.jsonl` for `evals/` — the raw → match_text ground truth the
matching calibration set is built from — plus `needs_fallback.txt`,
`parse_failures.jsonl` and `ambiguous_pairs.txt`.

The vocabulary it once bootstrapped has since been curated in the app, row by
row, which is precisely why the snapshot replaced it.
