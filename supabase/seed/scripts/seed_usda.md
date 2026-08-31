# USDA reference seed (`usda_food`)

`gen_usda.ts` turns the USDA FoodData Central CSV bundles into
`supabase/seed_usda.sql` — the server-side reference table (macros + density) the
"create a new ingredient" search and the stub prefill read. It is **never synced
and never matched at import** (ADR-0005).

The raw CSVs (~40 MB) are **not committed** — only the compact generated
`seed_usda.sql` (~1.7 MB, ~8k rows) is. Regenerate only when refreshing the data.

## Refresh

1. Download the two CC0 bundles from <https://fdc.nal.usda.gov/download-datasets>
   (filenames are dated; grab the latest Foundation and the frozen SR Legacy):

   ```
   curl -LO https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_csv_2026-04-30.zip
   curl -LO https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip
   unzip -q '*.zip'
   ```

2. Generate (Foundation first, so it's preferred on any overlap):

   ```
   cd supabase/seed/scripts
   deno run --allow-read --allow-write gen_usda.ts \
     ../../../<foundation_dir> ../../../<sr_legacy_dir>
   ```

3. `supabase db reset` loads it (wired via `config.toml` `[db.seed]`).

## What it keeps

- **Macros per 100 g** (`{kcal, protein, carb, fat, fiber}`) — FDC nutrient ids
  1008/1003/1005/1004/1079 (fiber falls back to 2033 AOAC). ~96% of foods have
  the core four; ~91% also have fiber.
- **Density** (g/ml) derived from the best-ranked volume `food_portion` (unit
  words matched in the whole portion text — SR Legacy stores most volume
  portions as free-text modifiers, which is why keying on the unit table alone
  found almost none). Where this still leaves a vocab row bare, the
  FAO/INFOODS Density DB fallback picks it up — see `fao_density.md`.
- **`match_text`** = the shared §7 normalizer over the description, so the same
  normalizer the household vocab and cascade use also indexes the reference.
