# ADR-0005: Two-tier ingredient vocabulary

- **Status:** Accepted (from import-and-matching design doc §5)
- **Date:** 2026-08-24

## Context

USDA FoodData Central has ~8,000 relevant rows where a single ingredient appears
many ways ("chicken thigh" fifteen times). Matching against it directly produces
constant wrong matches.

## Decision

Separate the thing we **match against** from the thing we **search when creating**:

- `ingredient` — the household's curated vocabulary (~150–300 rows). Match target;
  syncs to devices. Grows through imports, corrections, and stubs.
- `usda_food` — full USDA reference, read-only, server-side only. Used for the
  "create a new ingredient" search and background stub prefill. Never matched
  against during import.
- `ingredient_alias` — its own trigram-indexed table (not an array column) so
  corrections write back cleanly and improve matching over time (the learning
  loop, design doc §8).

## Consequences

- High-precision matching against a small, real vocabulary.
- A cheap, high-value learning loop: a user's correction becomes an alias with
  `source = 'import_correction'`, so the household's own phrasing is absorbed
  with zero ML.
