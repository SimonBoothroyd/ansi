-- 0020 — the template vocab can be reseeded: one live row per match_text
-- (ingredient) and per (ingredient, match_text) (alias) in the TEMPLATE
-- household, enforced by partial unique indexes, after tombstoning the exact
-- duplicates a non-idempotent hand-run of seed.sql left behind (2026-09-03:
-- 616 template ingredients for 308 distinct match_texts, aliases ×3).
--
-- Why the template only. A household-wide unique index would be the wrong
-- kind of safety: two offline devices can each mint a manual stub with the
-- same match_text and both must upload and converge later — the same reason
-- 0006 has no unique index on a shopping entry. The client coalesces those;
-- the matcher's dedupe key expects them. The template is different: it is
-- member-less (0008), no device ever writes to it, and the only writer is the
-- generated seed — so here uniqueness is exactly the invariant the reseed
-- button (deploy-supabase, `reseed_template`) relies on.
--
-- Dedupe rule: keep the EARLIEST live row per key (the one existing households
-- were cloned from, by match_text — ids never mattered to the clone), tombstone
-- the rest, and tombstone every alias whose ingredient is now tombstoned. The
-- onboarding clone (0009) reads `deleted_at is null` throughout, so nothing
-- tombstoned here reaches a household.

do $$
declare
  template constant uuid := '00000000-0000-0000-0000-0000000000aa';
begin
  -- Ingredient duplicates within the template: keep the earliest.
  update ingredient i
     set deleted_at = now(), updated_at = now()
    from (
      select id,
             row_number() over (partition by match_text
                                order by created_at, id) as rn
        from ingredient
       where household_id = template and deleted_at is null
    ) d
   where i.id = d.id and d.rn > 1;

  -- Aliases pointing at a tombstoned template ingredient go with it.
  update ingredient_alias a
     set deleted_at = now(), updated_at = now()
    from ingredient i
   where a.ingredient_id = i.id
     and a.household_id = template
     and a.deleted_at is null
     and i.deleted_at is not null;

  -- Alias duplicates within one template ingredient: keep the earliest.
  update ingredient_alias a
     set deleted_at = now(), updated_at = now()
    from (
      select id,
             row_number() over (partition by ingredient_id, match_text
                                order by created_at, id) as rn
        from ingredient_alias
       where household_id = template and deleted_at is null
    ) d
   where a.id = d.id and d.rn > 1;
end $$;

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
