# Seed data

Two things get seeded (spec §6):

1. **`usda_food`** — USDA FoodData Central (Foundation Foods + SR Legacy, CC0),
   server-side only. The reference set for *creating* ingredients and prefilling
   stubs. Never synced, never matched against at import (ADR-0005).
2. **Initial household `ingredient` vocabulary** — a small curated starter set
   (~a few dozen rows) so the app isn't empty on first run.

Density fallback: FDC food portions first, then FAO/INFOODS Density DB v2.0.

`scripts/seed_usda.md` documents the intended loader (not implemented in the
scaffold — it's a feature). `supabase db reset` will run `seed.sql` once it exists.
