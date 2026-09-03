-- rollout_measure_refresh.sql — hand-written, operator-run, idempotent.
--
-- WHY THIS EXISTS. `ensure_onboarded()` clones the template household's
-- measures into a household exactly once — at creation, or once more through
-- the run-once `household.backfilled_at` gate (migration 0011), which only
-- fires for a household holding ZERO live measures. So a measure that joins
-- the template later (a regenerated `seed_measures.sql` — the "Canned Diced
-- Tomatoes has no `can` measure" tracker rows) reaches NEW households only.
-- The old answer for existing households — soft-delete their measures, clear
-- the marker, let the clone re-run — wipes their user-authored measures too,
-- and since 2026-09-03 household data is durable (docs/cloud-setup.md §2c).
-- This script carries a reseeded template's *measures* forward onto every
-- existing household, in place, ADDING ONLY.
--
-- It is the sibling of `rollout_ingredient_refresh.sql`, deliberately a
-- separate file: that script is an UPDATE of two columns on `ingredient`
-- whose whole contract is "fill-only / union-only"; this one is an INSERT of
-- whole rows into `ingredient_measure` whose contract is "insert-missing".
-- Folding an insert leg into a fill/union script would blur both contracts.
-- Run them in either order; neither reads what the other writes.
--
-- SCOPE — one thing, monotone: for every live non-template household, every
-- live ingredient that matches a template ingredient by `match_text`, and
-- every live template measure on that ingredient, INSERT the measure if the
-- household's ingredient has no row with that label — live OR tombstoned.
-- Copied columns are exactly the ones `ensure_onboarded()` clones: `label`,
-- `basis_amount`, `sort_order`, `source`. A fresh row carries
-- `created_at`/`updated_at = now()` by default, so PowerSync replicates it.
-- Nothing else moves (see "DELIBERATELY LEFT ALONE" at the bottom).
--
-- JOIN KEY — (ingredient `match_text`, measure `label`), scoped to the
-- household. `match_text` is the ingredient identity that survives cloning
-- (`ensure_onboarded()` mints fresh ids and re-associates measures by
-- `di.match_text = si.match_text`, migration 0012). A measure has no
-- identity of its own beyond its `label` on its ingredient: that is the key
-- the generated `seed_measures.sql` guards on, the key 0010's (since
-- dropped) unique index enforced, and the key the client merges duplicates
-- on at read time (0011, oldest row canonical). Label comparison is exact —
-- the seed writes the label verbatim and the clone copies it verbatim.
--
-- The template household is resolved the same way `ensure_onboarded()`
-- resolves it: the oldest live `is_template` household. Measures of the
-- template's `manual` ingredients are excluded exactly as the clone excludes
-- them (a manual row is a household's private typed-in data).
--
-- ---------------------------------------------------------------------------
-- STEP 1 — PREVIEW (read-only). Run this FIRST and read the blast radius.
-- Uncomment the block, run it, then run the script proper.
-- ---------------------------------------------------------------------------
--
-- with tpl_household as (
--   select id from household
--   where is_template and deleted_at is null
--   order by created_at
--   limit 1
-- ),
-- tpl as (
--   select distinct on (si.match_text, im.label)
--          si.match_text, si.macros_basis,
--          im.label, im.basis_amount, im.sort_order, im.source
--   from ingredient_measure im
--   join tpl_household th on th.id = im.household_id
--   join ingredient si on si.id = im.ingredient_id
--    and si.household_id = th.id
--    and si.deleted_at is null
--    and si.source is distinct from 'manual'
--   where im.deleted_at is null
--   order by si.match_text, im.label, im.created_at, im.id
-- ),
-- slots as (
--   -- one row per (household ingredient, template measure) pair
--   select h.id as household_id,
--          di.macros_basis as own_basis, t.macros_basis as tpl_basis,
--          (select count(*) from ingredient_measure x
--            where x.ingredient_id = di.id and x.label = t.label) as any_rows,
--          (select count(*) from ingredient_measure x
--            where x.ingredient_id = di.id and x.label = t.label
--              and x.deleted_at is null) as live_rows
--   from tpl t
--   join ingredient di on di.match_text = t.match_text
--    and di.deleted_at is null
--   join household h on h.id = di.household_id
--    and not h.is_template
--    and h.deleted_at is null
-- ),
-- own as (
--   -- a household's live measures with no template counterpart
--   select im.household_id, count(*) as n
--   from ingredient_measure im
--   join ingredient di on di.id = im.ingredient_id
--   join household h on h.id = im.household_id
--    and not h.is_template
--    and h.deleted_at is null
--   where im.deleted_at is null
--     and not exists (
--       select 1 from tpl t
--       where t.match_text = di.match_text and t.label = im.label)
--   group by im.household_id
-- )
-- select
--   h.id   as household_id,
--   h.name as household,
--   count(s.household_id) as template_measure_slots,
--   count(*) filter (where s.any_rows = 0 and s.own_basis = s.tpl_basis)
--     as to_insert,
--   count(*) filter (where s.live_rows > 0)
--     as already_present_untouched,
--   count(*) filter (where s.any_rows > 0 and s.live_rows = 0)
--     as tombstoned_kept_dead,
--   count(*) filter (where s.any_rows = 0 and s.own_basis <> s.tpl_basis)
--     as basis_mismatch_skipped,
--   coalesce(o.n, 0) as own_measures_untouched
-- from household h
-- left join slots s on s.household_id = h.id
-- left join own   o on o.household_id = h.id
-- where not h.is_template
--   and h.deleted_at is null
-- group by h.id, h.name, o.n
-- order by h.name, h.id;
--
-- `to_insert` is exactly the number of rows the INSERT below will add for
-- that household; after a run, re-run the preview and it reads 0 everywhere.
--
-- ---------------------------------------------------------------------------
-- STEP 2 — the rollout. Idempotent: the `not exists` guard admits only
-- labels the household's ingredient has never had, so a second run reports
-- INSERT 0 0.
--
-- The statement between the `>>>` / `<<<` markers is mirrored VERBATIM in
-- supabase/tests/measure_rollout.sql (pgTAP cannot include a file outside
-- tests/); `make db-lint` diffs the two blocks, so edit them together.
-- ---------------------------------------------------------------------------

begin;

-- >>> rollout_measure_refresh.sql — mirrored in tests/measure_rollout.sql
with tpl_household as (
  -- Same resolution as ensure_onboarded(): oldest live template.
  select id from household
  where is_template and deleted_at is null
  order by created_at
  limit 1
),
tpl as (
  -- One template measure per (match_text, label). `distinct on` is
  -- belt-and-braces: the seed guards on the label, and the oldest row wins
  -- if a duplicate ever slips through, so the rollout stays deterministic.
  -- `manual` template ingredients are excluded exactly as the clone
  -- excludes them.
  select distinct on (si.match_text, im.label)
         si.match_text, si.macros_basis,
         im.label, im.basis_amount, im.sort_order, im.source
  from ingredient_measure im
  join tpl_household th on th.id = im.household_id
  join ingredient si on si.id = im.ingredient_id
   and si.household_id = th.id
   and si.deleted_at is null
   and si.source is distinct from 'manual'
  where im.deleted_at is null
  order by si.match_text, im.label, im.created_at, im.id
)
insert into ingredient_measure
  (household_id, ingredient_id, label, basis_amount, sort_order, source)
select di.household_id, di.id, t.label, t.basis_amount, t.sort_order, t.source
from tpl t
join ingredient di on di.match_text = t.match_text
 and di.deleted_at is null          -- a row the household deleted stays deleted
join household h on h.id = di.household_id
 and not h.is_template              -- never write to the template itself
 and h.deleted_at is null
where
  -- `basis_amount` is an amount in the INGREDIENT's basis unit (0012). A
  -- household that flipped its row's basis would read the template's number
  -- in the wrong unit — leave that ingredient alone rather than invent one.
  di.macros_basis = t.macros_basis
  -- Insert-missing: no row with this label on this ingredient, live OR
  -- tombstoned. A label the household soft-deleted stays deleted (0011's
  -- doctrine: deliberate deletion is never resurrected); a live one keeps
  -- its own weight, whatever the template now says.
  and not exists (
    select 1 from ingredient_measure x
    where x.ingredient_id = di.id
      and x.label = t.label
  );
-- <<< rollout_measure_refresh.sql

commit;

-- ---------------------------------------------------------------------------
-- DELIBERATELY LEFT ALONE
--
--   * Template households (`is_template`) — the source, not a target.
--   * Soft-deleted households and soft-deleted ingredient rows: a tombstoned
--     ingredient gains no measure.
--   * Every EXISTING measure row, in every household. This script never
--     UPDATEs or DELETEs: a live measure keeps its `basis_amount`, `label`,
--     `sort_order` and `source` even where the template's row now differs
--     (a corrected template weight does NOT propagate — that would be an
--     overwrite, and the household may have edited the number on purpose).
--     A tombstoned measure stays tombstoned.
--   * A household's own measures (`source = 'manual'`, or any label with no
--     template counterpart). They never had a template row and never gain
--     one here.
--   * Measures of the template's `manual` ingredients — private, exactly as
--     in `ensure_onboarded()`.
--   * A household ingredient whose `macros_basis` disagrees with the
--     template's (the preview's `basis_mismatch_skipped`). Honest numbers
--     over coverage: a per-g amount on a per-ml row is a wrong number.
--   * `household.backfilled_at`. The run-once gate is neither read nor
--     reset; a household this script has visited is in the same state a
--     fresh onboarding clone would have produced, and needs no marker.
--   * Ingredients with no template counterpart by `match_text` (a
--     household's own `manual` / `import_stub` rows), and `ingredient`
--     itself — `rollout_ingredient_refresh.sql` owns that table.
--
-- ONE SHAPE TO KNOW ABOUT. Two live household rows can share a `match_text`
-- (two offline devices each minting the same stub — 0020 keeps the unique
-- index template-only for this reason). Each such row is its own ingredient
-- to the app, so each gains the template's measures, exactly as 0011's clone
-- leg treats them. That is not a duplicate: it is one measure per
-- ingredient row.
-- ---------------------------------------------------------------------------
