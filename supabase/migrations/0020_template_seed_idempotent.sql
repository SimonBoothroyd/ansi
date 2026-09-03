-- 0020 — the template vocab is reseedable: ONE live row per match_text
-- (ingredient) and per (ingredient, match_text) (alias) in the TEMPLATE
-- household, enforced by partial unique indexes. The generated seed.sql
-- upserts on them, so the deploy-supabase `reseed_template` button can run
-- against an already-seeded project.
--
-- Why the template only. A household-wide unique index would be the wrong
-- kind of safety: two offline devices can each mint a manual stub with the
-- same match_text and both must upload and converge later — the same reason
-- 0006 has no unique index on a shopping entry. The client coalesces those;
-- the matcher's dedupe key expects them. The template is different: it is
-- member-less (0008), no device ever writes to it, and the only writer is the
-- generated seed — so here uniqueness is exactly the invariant the reseed
-- relies on.
--
-- No data repair lives here on purpose (owner posture, 2026-09-03: dev data is
-- throwaway, so a database that has drifted is RESET from migrations + seeds
-- rather than patched by a fix-up migration — docs/cloud-setup.md §2).

create unique index if not exists ingredient_template_match_text_uq
  on ingredient (match_text)
  where household_id = '00000000-0000-0000-0000-0000000000aa'
    and deleted_at is null;

create unique index if not exists ingredient_alias_template_uq
  on ingredient_alias (ingredient_id, match_text)
  where household_id = '00000000-0000-0000-0000-0000000000aa'
    and deleted_at is null;

comment on index ingredient_template_match_text_uq is
  'One live template ingredient per match_text — the reseed (seed.sql) upserts on it. Template-only on purpose: household rows may legitimately duplicate offline (see 0020).';
comment on index ingredient_alias_template_uq is
  'One live template alias per (ingredient, match_text) — the reseed skips existing ones. Template-only on purpose (see 0020).';
