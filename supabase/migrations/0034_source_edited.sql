-- 0034_source_edited.sql — a row that was edited stops claiming its numbers
-- are the lookup's (exec plan 0040, front B).
--
-- THE PROBLEM. `source` is patch-shaped and preserved across a form save
-- (`ingredient_repository_impl.dart`: `source = COALESCE(?, source)`), which is
-- right — a save that is not about the match must not erase which food filled
-- the row. But it means a row keeps saying `usda_fdc:168930` after a human has
-- typed their own macros or their own density over the prefill, and the
-- provenance card goes on naming a food whose numbers are no longer on the row.
--
-- THE COLUMN (B-D1). One synced boolean. The alternatives were both worse:
-- encoding the fact in `source` breaks every `usda_fdc:` parser in the app and
-- the edge functions; diffing against the source's own figures means storing a
-- second copy of them on every row for the sake of a comparison.
--
-- WHAT MAY SET IT — the fence that keeps it honest. The flag means *the numbers
-- on this row are no longer the source's*, so only a write that touches
-- **macros, macros basis or density** may set it, and only on a row whose
-- `source` is a lookup stamp (`usda_fdc:<id>` or `off:<barcode>`). A rename, a
-- unit toggle, a measure or an alias does not contradict the source and leaves
-- it alone. A fresh pick CLEARS it (B-D3): the numbers are the new food's.
--
-- WHO WRITES IT. The app, and only the app — the three client paths that can
-- change a number on a stored row: `saveForm`, `setDensity` and `clearDensity`.
-- There is deliberately NO trigger here. The one server-side writer that used
-- to fill rows on its own (`ingredient_usda_prefill`) was dropped in 0029, and
-- re-introducing server logic that flips a provenance flag is exactly what that
-- migration removed. This file adds a column, a comment and nothing else, so
-- the fence lives in one place (`ingredient_repository_impl.dart`) rather than
-- in two implementations that can drift.
--
-- RLS/grants: unchanged. `ingredient` is granted table-wide to `authenticated`
-- (0002) under the household policies, so the new column rides the existing
-- grant; there is nothing column-narrow to widen.
--
-- Sync: `docker/powersync.yaml` and `docker/powersync-cloud.streams.yaml` both
-- select `*` from `ingredient`, so the column syncs with no rule change; the
-- client schema gains it in `app/lib/core/sync/schema.dart` (integer 0/1, which
-- is how PowerSync carries a boolean).

alter table ingredient
  add column if not exists source_edited boolean not null default false;

comment on column ingredient.source_edited is
  'True when a human has overridden the numbers a lookup filled in — macros, '
  'macros basis or density — on a row whose source is a lookup stamp '
  '(usda_fdc:<id> or off:<barcode>). Plan 0040 B-D1. Written ONLY by the '
  'app''s write paths (saveForm, setDensity, clearDensity); no trigger sets '
  'it. A rename, a unit toggle, a measure or an alias never sets it: those do '
  'not contradict the source. A fresh pick clears it, because the numbers are '
  'the new food''s again. Read by the provenance card''s third state (Filled '
  'from USDA · edited here) and by the ingredients list''s source line.';
