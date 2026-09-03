-- 0025_optional_line.sql — `optional` becomes a first-class line fact (exec
-- plan 0025 item 6, owner rulings D6a + D6b).
--
-- "I don't think there's a way in the UI to flag / unflag an ingredient as
-- optional, but import can flag ingredients as being?" The extractor has
-- always emitted `optional` per raw line and the review card has always shown
-- it as a raw tag — and there it stopped: nothing below the card had a column
-- for it, so commit dropped the flag on the floor. This migration is the
-- column. Additive and row-preserving (docs/cloud-setup.md §2c): every
-- existing line reads `false`, which is exactly what it always meant.
--
-- What the flag DOES is ruled by D6b and lives in the app, not here: an
-- optional line is left out of the macro total and the shopping list and is
-- NAMED where it left ("not counted · 2 optional lines: Lime, Coriander";
-- "2 optional lines not listed — lime, coriander"); the cook plan is
-- unaffected. Never a silent drop — invariant 3 read the stronger way.
--
-- Deliberately NOT here: the per-week override the owner wants later (tick an
-- optional line in for one planned week, substitute an ingredient). Its shape
-- is designed for — a `plan_entry_line_override` keyed by plan entry and line
-- — and the app routes every derivation through one `effectiveLines` seam so
-- that join lands in one place. That is a later migration, not this one.
--
-- Sync: the cloud stream selects `*` from `recipe_line_item`, so the column
-- rides down without a stream change; `schema.dart` gains the matching
-- integer column (0/1, like `favorite`).

alter table recipe_line_item
  add column optional boolean not null default false;

comment on column recipe_line_item.optional is
  'The recipe says this line may be left out. Excluded from macros and the '
  'shopping list and named there (plan 0025 D6b); the cook plan ignores it.';
