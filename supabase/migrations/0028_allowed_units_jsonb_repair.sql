-- 0028_allowed_units_jsonb_repair.sql — re-type the admission lists the app
-- uploaded as jsonb STRINGS (2026-09-03).
--
-- The app's sync connector decodes the server's jsonb columns from PowerSync's
-- local TEXT before upload (`jsonbColumnsByTable`, core/sync/connector.dart).
-- `ingredient.allowed_units` (0012) was never added to that map, so every
-- ingredient the APP created — a manual stub, an import's create-new, a
-- barcode row — arrived with `allowed_units` stored as a jsonb string:
-- `"[\"g\",\"kg\"]"` rather than `["g","kg"]`. Seeded and template-cloned rows
-- were unaffected (they never crossed the connector).
--
-- What that broke, quietly: every server-side rule that asks
-- `allowed_units ? unit` answered false on those rows — the 0014 density
-- trigger's union (`allowed_units || additions` on a string yields an array
-- whose first element is the old string), 0021's invariant, and any future
-- admission check in SQL. The app itself kept working because its own reader
-- tolerated both shapes, which is why nothing surfaced until pgTAP ran over
-- smoke-created rows (`unit_admission.sql` #49).
--
-- The connector is fixed in the same change (and held by
-- `app/test/structure/jsonb_columns_test.dart`, which derives the jsonb column
-- set from these migrations). This migration repairs what is already stored:
--
--   1. A string that is itself a JSON array text → that array.
--   2. An array whose FIRST element is such a string (the density trigger's
--      union over a string) → the parsed inner array unioned with the rest,
--      deduplicated, order kept.
--
-- Idempotent and row-preserving (§2c): a second run finds nothing to do.

update ingredient
   set allowed_units = (allowed_units #>> '{}')::jsonb
 where jsonb_typeof(allowed_units) = 'string'
   and (allowed_units #>> '{}') ~ '^\s*\[';

update ingredient i
   set allowed_units = (
     select jsonb_agg(u order by ord)
       from (
         select u, min(ord) as ord
           from (
             select value as u, ordinality as ord
               from jsonb_array_elements((i.allowed_units -> 0 #>> '{}')::jsonb)
                    with ordinality
             union all
             select value, 1000 + ordinality
               from jsonb_array_elements(i.allowed_units - 0) with ordinality
           ) all_units
          group by u
       ) merged
   )
 where jsonb_typeof(allowed_units) = 'array'
   and jsonb_array_length(allowed_units) > 0
   and jsonb_typeof(allowed_units -> 0) = 'string'
   and (allowed_units -> 0 #>> '{}') ~ '^\s*\[';

comment on column ingredient.allowed_units is
  'Explicit per-ingredient unit admission (ADR-0008): a jsonb ARRAY of unit '
  'ids. 0028 repaired rows the app had uploaded as jsonb strings; the '
  'connector now decodes the column and a structural test holds the map.';
