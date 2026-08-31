-- rollout_ingredient_refresh.sql — hand-written, operator-run, idempotent.
--
-- WHY THIS EXISTS. `ensure_onboarded()` clones the template household's
-- vocabulary into a household exactly once, at creation. A template reseed
-- (docs/cloud-setup.md §2) therefore reaches NEW households only — an
-- already-onboarded household keeps the copy it was born with. That is fine
-- for a throwaway dev household (wipe and re-onboard), and NOT fine for the
-- owner's live household, which holds real recipes. This script rolls a
-- reseeded template's *ingredient* improvements forward onto every existing
-- household, in place, without touching anything the household itself owns.
--
-- It is deliberately generic: it is not "the FAO rollout", it is "carry the
-- template's density + allowed_units forward". Re-run it after any future
-- template reseed that fills densities or widens unit admission.
--
-- SCOPE — exactly two columns, both monotone (they only ever ADD):
--   (a) density_g_per_ml — filled ONLY where the household's is NULL and the
--       template's is not. A household's own density is never overwritten.
--   (b) allowed_units    — replaced by the UNION of the household's list and
--       the template's. A unit the household admitted is never removed.
-- Plus `updated_at = now()`, so PowerSync replicates the row down to devices.
-- Nothing else moves: not `source`, not `status`, not `macros`, not measures,
-- not aliases (see "DELIBERATELY LEFT ALONE" at the bottom).
--
-- JOIN KEY — `match_text`, scoped to the household. That is the identity that
-- survives cloning: `ensure_onboarded()` copies `match_text` verbatim while
-- minting fresh `id`s, and its own alias/measure legs re-associate the clone
-- with its source by `di.match_text = si.match_text` (migration
-- 0012_unit_admission.sql). `gen_seed.ts` fails the build on a match_text
-- collision, so the key is unique within the template.
--
-- The template household is resolved the same way `ensure_onboarded()`
-- resolves it: the oldest live `is_template` household.
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
--   select distinct on (i.match_text)
--          i.match_text, i.density_g_per_ml, i.allowed_units
--   from ingredient i
--   join tpl_household th on th.id = i.household_id
--   where i.deleted_at is null
--   order by i.match_text, i.created_at, i.id
-- )
-- select
--   h.id   as household_id,
--   h.name as household,
--   count(*) filter (where i.deleted_at is null) as live_rows,
--   count(*) filter (where i.deleted_at is null and t.match_text is not null)
--     as matched_to_template,
--   count(*) filter (where i.deleted_at is null and t.match_text is null)
--     as household_only_rows_untouched,
--   count(*) filter (where i.deleted_at is not null)
--     as deleted_rows_untouched,
--   count(*) filter (
--     where i.deleted_at is null
--       and i.density_g_per_ml is null and t.density_g_per_ml is not null)
--     as leg_a_density_fills,
--   count(*) filter (
--     where i.deleted_at is null
--       and t.allowed_units is not null
--       and not (t.allowed_units <@ coalesce(i.allowed_units, '[]'::jsonb)))
--     as leg_b_unit_extensions,
--   count(*) filter (
--     where i.deleted_at is null
--       and i.density_g_per_ml is not null and t.density_g_per_ml is not null
--       and i.density_g_per_ml is distinct from t.density_g_per_ml)
--     as own_density_kept_as_is
-- from ingredient i
-- join household h on h.id = i.household_id
-- left join tpl t on t.match_text = i.match_text
-- where not h.is_template
--   and h.deleted_at is null
-- group by h.id, h.name
-- order by h.name, h.id;
--
-- `leg_a_density_fills` + `leg_b_unit_extensions` overlap (one row can need
-- both); the UPDATE below reports the count of rows touched by EITHER leg, so
-- expect it to land between max(a, b) and a + b.
--
-- ---------------------------------------------------------------------------
-- STEP 2 — the rollout. Idempotent: the WHERE clause admits only rows that
-- actually change, so a second run reports UPDATE 0.
-- ---------------------------------------------------------------------------

begin;

with tpl_household as (
  -- Same resolution as ensure_onboarded(): oldest live template.
  select id from household
  where is_template and deleted_at is null
  order by created_at
  limit 1
),
tpl as (
  -- One template row per match_text. `distinct on` is belt-and-braces: the
  -- generator already forbids collisions, and the oldest row wins if one ever
  -- slips through, so the rollout stays deterministic.
  select distinct on (i.match_text)
         i.match_text, i.density_g_per_ml, i.allowed_units
  from ingredient i
  join tpl_household th on th.id = i.household_id
  where i.deleted_at is null
  order by i.match_text, i.created_at, i.id
)
update ingredient i
set
  -- (a) fill only; coalesce keeps a household's own density verbatim.
  density_g_per_ml = coalesce(i.density_g_per_ml, t.density_g_per_ml),
  -- (b) union only; the household's admissions come first (a stored SET —
  -- the client owns display order), the template's additions append.
  allowed_units = case
    when i.allowed_units is null and t.allowed_units is null then null
    else (
      select coalesce(jsonb_agg(u.unit order by u.ord, u.unit), '[]'::jsonb)
      from (
        select e.unit, min(e.ord) as ord
        from (
          select unit, ord
          from jsonb_array_elements_text(coalesce(i.allowed_units, '[]'::jsonb))
               with ordinality as own(unit, ord)
          union all
          select unit, 1000 + ord
          from jsonb_array_elements_text(coalesce(t.allowed_units, '[]'::jsonb))
               with ordinality as tmpl(unit, ord)
        ) e
        group by e.unit
      ) u
    )
  end,
  -- Bump so PowerSync replicates the change down to every device.
  updated_at = now()
from tpl t, household h
where h.id = i.household_id
  and not h.is_template          -- never write to the template itself
  and h.deleted_at is null
  and i.deleted_at is null       -- a row the household deleted stays deleted
  and i.match_text = t.match_text
  and (
    -- leg (a): a density to gain
    (i.density_g_per_ml is null and t.density_g_per_ml is not null)
    or
    -- leg (b): a unit to gain (jsonb containment = "template ⊆ household")
    (t.allowed_units is not null
     and not (t.allowed_units <@ coalesce(i.allowed_units, '[]'::jsonb)))
  );

commit;

-- ---------------------------------------------------------------------------
-- DELIBERATELY LEFT ALONE
--
--   * Template households (`is_template`) — the source, not a target.
--   * Soft-deleted households and soft-deleted ingredient rows. A row the
--     household tombstoned stays tombstoned; the template getting a new
--     density is not a reason to resurrect it.
--   * Rows with no template counterpart by match_text — the household's own
--     `manual` / `import_stub` ingredients. They never had a template row and
--     never gain one here.
--   * A household row whose density is already set, even where it disagrees
--     with the template's. The household's number wins; only NULLs are filled.
--   * Every other column. `source` and `status` in particular are NOT
--     rewritten: a household row that gains a density from a template whose
--     `source` now reads `fao_infoods_v2:…` keeps its own provenance string,
--     and a `stub` stays a `stub` (status turns on macros, which this rollout
--     does not touch). Provenance for the rolled-out number is this script
--     plus the template's row — recorded here rather than smeared across
--     307 rows of somebody else's `source` column.
--   * `ingredient_alias`, `ingredient_measure`. Measures have their own,
--     separate retrofit — the run-once `backfilled_at` clone inside
--     `ensure_onboarded()` (migration 0011). The two mechanisms are
--     independent and safe to run in either order: this one never touches
--     `ingredient_measure` or `household.backfilled_at`.
-- ---------------------------------------------------------------------------
