# USDA seed — intended loader (not implemented; it's a feature)

Goal: populate the server-side `usda_food` reference and a small starter
`ingredient` vocabulary (spec §6).

1. Download USDA FoodData Central: **Foundation Foods + SR Legacy** (CC0).
2. For each food: description, category, macros per 100 g, and a density derived
   from FDC food portions where present.
3. Density fallback: **FAO/INFOODS Density DB v2.0** where FDC lacks a portion.
4. Compute `match_text` for each row with the same normalization as import (§7),
   so the create-ingredient search is symmetric with matching.
5. Load into `usda_food` (server-side only — never synced, never matched at
   import; ADR-0005). Seed a few dozen curated `ingredient` rows for first-run.

Implement as a one-off script (Deno or Python) invoked from `supabase/seed/`.
