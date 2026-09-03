-- 0023_default_measure.sql — a curated default count measure per ingredient
-- (plan 0024, seam D1).
--
-- WHAT THIS ADDS. `ingredient.default_measure_id` says what a bare COUNT of a
-- row MEANS: "2 onions" is two `onion, medium` (110 g each). It is a STATED
-- PER-ROW FACT, curated by hand exactly like ADR-0010's `piece` removals, and
-- it is NULLABLE because null is a real answer — broccoli's `whole` / `spear`
-- / `crown` are three different things and none of them is "a broccoli", so
-- that line keeps its flag and the user picks.
--
-- ADR-0010 IS NOT REOPENED. Nothing here reads a size word out of a raw line,
-- nothing resolves a line from a rule at runtime, and no stored line is ever
-- rewritten. A cascade guesses fresh every time; this is a decision somebody
-- made, recorded with its reason in `supabase/seed/curation_overrides.jsonl`
-- (kind `default_measure`), and the import spends it once, visibly, on the
-- card (seam D2).
--
-- DATA IS DURABLE from 2026-09-03 (owner ruling, docs/cloud-setup.md §2c), so
-- this is an ADDITIVE column plus a fill-only backfill: no reset, no reseed
-- needed to reach existing households, and no row rewritten beyond the column
-- this migration adds.
--
-- SYNC. Both sync-rule files are `select * from ingredient`, so the column
-- rides across with no rule change; the client schema
-- (`app/lib/core/sync/schema.dart`) gains the column, without which PowerSync
-- drops it on the way into the local view and every read is null. RLS needs
-- nothing — the column rides `ingredient`'s existing row policies, and
-- `authenticated` already holds update on the table.

-- ---------------------------------------------------------------------------
-- 1. The column.
-- ---------------------------------------------------------------------------
alter table ingredient
  add column default_measure_id uuid
    references ingredient_measure(id) on delete set null;

comment on column ingredient.default_measure_id is
  'What a bare count of this ingredient means ("2 onions" -> 2 x onion, medium). '
  'A curated per-row FACT (plan 0024, seam D1), not a rule: null is a real answer '
  'for a fragment set (broccoli whole/spear/crown). The import review spends it '
  'once and visibly (D2); nothing downstream interprets it, and no stored line '
  'records that it came from here.';

-- Partial: the column is null on the ~149 measure-less vocab rows and on
-- every fragment set, and the only reader that looks it up BY id is the
-- clear-on-soft-delete leg in the app's measure repository.
create index ingredient_default_measure_idx
  on ingredient (default_measure_id) where default_measure_id is not null;

-- ---------------------------------------------------------------------------
-- 2. The default must be one of THIS row's own live measures.
--
-- `on delete set null` above covers a HARD delete, which is the only kind an
-- FK can see. The app soft-deletes (`deleted_at`), and a cross-ingredient or
-- cross-household id is the one way this column could tell a lie — a "1
-- onion" line silently counted as a clove. Both are refused here rather than
-- policed by every reader.
-- ---------------------------------------------------------------------------
create or replace function ingredient_default_measure_is_own()
returns trigger
language plpgsql
as $$
begin
  if new.default_measure_id is not null and not exists (
    select 1 from ingredient_measure m
    where m.id = new.default_measure_id
      and m.ingredient_id = new.id
      and m.household_id = new.household_id
      and m.deleted_at is null
  ) then
    raise exception
      'default_measure_id % is not a live measure of ingredient %',
      new.default_measure_id, new.id;
  end if;
  return new;
end;
$$;

create trigger ingredient_default_measure_own
  before insert or update of default_measure_id on ingredient
  for each row execute function ingredient_default_measure_is_own();

-- ---------------------------------------------------------------------------
-- 3. The backfill, as a re-runnable function.
--
-- Every household holds its OWN `ingredient_measure` rows — `ensure_onboarded`
-- re-inserts them with fresh ids — so there is no shared measure id to copy.
-- The key is (ingredient `match_text`, measure `label`): the same key the
-- clone, `rollout_measure_refresh.sql` and the generated `seed_curation.sql`
-- all use, because a measure has no identity beyond its label on its
-- ingredient.
--
-- TWO RULES, both ADR-0009 rule 3's posture:
--   1. It only ever FILLS A NULL. A household that has set its own default
--      keeps it, forever, including on a re-run — the fill is a union, never
--      an overwrite.
--   2. It never REMOVES. The 9 rulings of `label: null` live in
--      curation_overrides.jsonl and emit nothing here: the column is already
--      null, and writing it is the one way this could take a household's
--      default away.
--
-- It is a FUNCTION rather than a bare statement because the template can gain
-- a measure after this migration runs — `yellow bell pepper` gains a borrowed
-- `pepper, medium` with this very slice, and reaches existing households
-- through `rollout_measure_refresh.sql`. Re-running
-- `select ingredient_default_measure_backfill();` after that rollout fills the
-- rows whose measure was missing the first time, and is a no-op everywhere
-- else.
--
-- The list below is a SNAPSHOT of the 2026-09-03 curation, frozen the way a
-- migration freezes everything. The source of truth stays
-- curation_overrides.jsonl, and a fresh stack gets its values from
-- `seed_curation.sql`.
-- ---------------------------------------------------------------------------
-- The pairs ride as `match_text|label` strings so they stay readable side by
-- side (a temp table or a repeated `values` CTE would say the same thing
-- twice, once per statement below). No label contains a `|`; the generator
-- that wrote this list asserts it.
create or replace function ingredient_default_measure_backfill()
returns integer
language plpgsql
as $$
declare
  filled integer;
  orphans text;
  curation constant text[] := array[
    'active yeast dry|sachet',
    'almond|almond',
    'apple|apple, medium',
    'apricot|apricot',
    'asparagus|spear, medium',
    'avocado|avocado',
    'baked bean|can (16 oz)',
    'banana|banana, medium',
    'basil|leaf',
    'bay leaf|leaf',
    'beet|beet',
    'black bean canned|can (15 oz), drained',
    'black eyed pea canned|can (15 oz), drained',
    'blueberry|berry',
    'brazil nut|kernel',
    'brussel sprout|sprout',
    'burger bun|bun',
    'butternut squash|squash, whole',
    'cannellini bean canned|can (15 oz), drained',
    'cantaloupe|melon, medium',
    'carrot|carrot, medium',
    'cauliflower|head, medium',
    'celery|stalk, medium',
    'cherry|cherry',
    'chickpea canned|can (15 oz), drained',
    'cilantro|sprig',
    'cinnamon stick|stick',
    'coconut milk|can (400 ml)',
    'corn|ear, medium',
    'corn tortilla|tortilla',
    'cremini mushroom|mushroom, whole',
    'cucumber|cucumber',
    'dark red kidney bean canned|can (15 oz), drained',
    'date|date, pitted',
    'dill|sprig',
    'dill pickle|spear',
    'edamame frozen|package',
    'eggplant|eggplant, unpeeled',
    'english muffin|muffin',
    'enoki mushroom|mushroom, medium',
    'extra firm tofu|block (14 oz)',
    'fennel|bulb',
    'fig dried|fig, whole',
    'fire tomato canned roasted|can (14.5 oz)',
    'flour tortilla|tortilla',
    'gala apple|apple, medium',
    'garlic|clove',
    'ginger|piece, 1 inch',
    'gold potato|potato, medium',
    'granny smith apple|apple, medium',
    'grapefruit|grapefruit, whole',
    'great northern bean canned|can (15 oz), drained',
    'green bean|bean',
    'green bean canned|can (14.5 oz), drained',
    'green bell pepper|pepper, medium',
    'green grape|grape',
    'green olive|olive',
    'hazelnut|nut',
    'hot chili|chili',
    'instant yeast|sachet',
    'jalapeno|jalapeno',
    'king oyster mushroom|mushroom, medium',
    'kiwi|kiwi, whole',
    'kombu|strip',
    'leek|leek',
    'lemon|lemon, whole',
    'lemon juice|lemon',
    'light red kidney bean canned|can (15 oz), drained',
    'lime|lime, whole',
    'lime juice|lime',
    'mango|mango, whole',
    'multigrain bread|slice regular',
    'napa cabbage|head',
    'navy bean canned|can (15 oz), drained',
    'nectarine|nectarine, whole',
    'nori|sheet',
    'okra|pod',
    'onion|onion, medium',
    'orange|orange, whole',
    'orange bell pepper|pepper, medium',
    'orange juice|orange, juiced',
    'oyster mushroom|mushroom',
    'parsley|sprig',
    'parsnip|parsnip, medium',
    'pea frozen|package',
    'peach|peach, medium',
    'pineapple|pineapple, whole',
    'pinto bean canned|can (15 oz), drained',
    'pistachio|kernel',
    'plantain|plantain',
    'poblano pepper|pepper',
    'portobello mushroom|mushroom, whole',
    'radish|radish, medium',
    'raspberry|raspberry',
    'red bell pepper|pepper, medium',
    'red delicious apple|apple, medium',
    'red grape|grape',
    'red onion|onion, medium',
    'red potato|potato, medium',
    'rhubarb|stalk',
    'russet potato|potato, medium',
    'scallion|scallion, medium',
    'serrano pepper|pepper',
    'shallot|shallot, medium',
    'shiitake bacon|slice',
    'shiitake mushroom|mushroom, whole',
    'silken tofu|block (12.3 oz)',
    'soft sandwich bread|slice',
    'sprouted multigrain bread|slice',
    'star anise|pod',
    'strawberry|strawberry, medium',
    'sweet potato|sweet potato',
    'tatsoi|head',
    'tempeh|package (8 oz)',
    'thai basil|leaf',
    'tofu bacon|slice',
    'tomato|tomato, medium',
    'tomato canned|can (14.5 oz)',
    'tomato canned whole|can (14.5 oz)',
    'tomato paste|can (6 oz)',
    'tomato puree canned|can (29 oz)',
    'tomato sauce canned|can (15 oz)',
    'tostada shell|shell',
    'turnip|turnip, medium',
    'vegan sausage|link',
    'watermelon|melon',
    'wheat bread whole|slice',
    'white bread|slice',
    'white mushroom|mushroom, medium',
    'yellow bell pepper|pepper, medium',
    'yellow squash|squash, medium',
    'zucchini|zucchini, medium'
  ];
begin
  update ingredient i
     set default_measure_id = m.id,
         updated_at = now()
    from (select split_part(x, '|', 1) as match_text,
                 split_part(x, '|', 2) as label
          from unnest(curation) x) c,
         ingredient_measure m
   where i.match_text = c.match_text
     and i.deleted_at is null
     and i.default_measure_id is null
     and m.ingredient_id = i.id
     and m.household_id = i.household_id
     and m.deleted_at is null
     and lower(btrim(m.label)) = lower(btrim(c.label));
  get diagnostics filled = row_count;

  -- A curated (match_text, label) pair naming a row that EXISTS but carries
  -- no such measure is a relabelled measure, and it would quietly leave that
  -- row asking for a unit on every counted line — the exact friction D1
  -- removes. Named out loud, the way seed_measures.sql's tail names a
  -- match_text the vocab no longer carries. A warning rather than an
  -- exception: on a fresh `db reset` this function runs before the seed, with
  -- no vocabulary at all, and a household that simply lacks the row is not an
  -- error either.
  select string_agg(c.match_text || ' / ' || c.label, ', ')
    into orphans
  from (select split_part(x, '|', 1) as match_text,
               split_part(x, '|', 2) as label
        from unnest(curation) x) c
  where exists (
    select 1 from ingredient i
    where i.match_text = c.match_text and i.deleted_at is null
  ) and not exists (
    select 1 from ingredient i
    join ingredient_measure m
      on m.ingredient_id = i.id and m.household_id = i.household_id
     and m.deleted_at is null
    where i.match_text = c.match_text and i.deleted_at is null
      and lower(btrim(m.label)) = lower(btrim(c.label))
  );
  if orphans is not null then
    raise warning
      'default measure curation names labels no measure carries: %', orphans;
  end if;

  return filled;
end;
$$;

-- Operator surface only: no client role calls either of these.
revoke execute on function ingredient_default_measure_backfill()
  from public, anon, authenticated;
revoke execute on function ingredient_default_measure_is_own()
  from public, anon, authenticated;

select ingredient_default_measure_backfill();

-- ---------------------------------------------------------------------------
-- 4. ensure_onboarded() — 0012's body plus the default-measure carry.
--
-- The ingredient clone lists its columns explicitly, so a fresh household's
-- rows arrive with `default_measure_id` null — and it could not be otherwise:
-- the template's value points at a TEMPLATE measure, which the own-measure
-- trigger above rightly refuses. So the default is carried across the same
-- way everything else about a measure is, BY LABEL, in a pass that runs after
-- the measures exist.
--
-- Two legs, because there are two clone paths: the run-once measure backfill
-- for a household that predates 0009, and the create path. Both fill only a
-- null, so a household that has already chosen keeps its choice.
-- ---------------------------------------------------------------------------
create or replace function ensure_onboarded()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid       uuid := auth.uid();
  hh        uuid;
  member_no int;
  src       uuid;
begin
  if uid is null then
    raise exception 'ensure_onboarded() requires an authenticated caller';
  end if;

  -- Serialise concurrent onboards (two users racing for the last seat, or one
  -- user's two devices onboarding at once). Transaction-scoped: released
  -- automatically at commit/rollback, re-entrant within this transaction.
  -- The measure backfill below runs under the same lock, so two devices
  -- signing in at once can't double-clone.
  perform pg_advisory_xact_lock(hashtext('ensure_onboarded'));

  -- Already onboarded? Ordered like current_household_id(), so every path
  -- resolves the same membership.
  select household_id into hh
  from household_member
  where auth_user_id = uid and deleted_at is null
  order by created_at
  limit 1;
  if hh is not null then
    -- Run-once measure backfill (0011): heal a household that predates 0009
    -- (or whose operator cleared the marker for a template reseed). Gated on
    -- the marker, NOT the live count — a household that deliberately deleted
    -- its measures stays deleted. A household that already has measures is
    -- stamped without cloning (it was backfilled by other means).
    if exists (
      select 1 from household
      where id = hh and backfilled_at is null
    ) then
      if not exists (
        select 1 from ingredient_measure im
        where im.household_id = hh and im.deleted_at is null
      ) then
        select id into src
        from household
        where is_template and deleted_at is null
        order by created_at
        limit 1;

        if src is not null then
          insert into ingredient_measure (household_id, ingredient_id, label,
            basis_amount, sort_order, source)
          select hh, di.id, im.label, im.basis_amount, im.sort_order, im.source
          from ingredient_measure im
          join ingredient si on si.id = im.ingredient_id
            and si.household_id = src and si.deleted_at is null
            and si.source is distinct from 'manual'
          join ingredient di on di.household_id = hh
            and di.match_text = si.match_text and di.deleted_at is null
          where im.household_id = src and im.deleted_at is null;

          -- The curated default follows its measure, by label (0023).
          update ingredient di
             set default_measure_id = dm.id,
                 updated_at = now()
            from ingredient si
            join ingredient_measure sm on sm.id = si.default_measure_id
            join ingredient_measure dm on dm.household_id = hh
             and dm.deleted_at is null
             and lower(btrim(dm.label)) = lower(btrim(sm.label))
           where si.household_id = src and si.deleted_at is null
             and si.source is distinct from 'manual'
             and di.household_id = hh and di.deleted_at is null
             and di.match_text = si.match_text
             and dm.ingredient_id = di.id
             and di.default_measure_id is null;
        end if;
      end if;
      update household set backfilled_at = now() where id = hh;
    end if;
    return hh;
  end if;

  -- Join an existing household that still has room (v1 = two people).
  -- Template households are never joinable: they exist only to be cloned
  -- from, and must stay pristine and member-less (see 0008 — memberless is
  -- also what keeps their rows out of RLS reads and sync buckets).
  select h.id into hh
  from household h
  where h.deleted_at is null
    and not h.is_template
    and (
      select count(*) from household_member m
      where m.household_id = h.id and m.deleted_at is null
    ) < 2
  order by h.created_at
  limit 1;

  -- …otherwise create a fresh one and clone the starter vocab from the
  -- template household (the seeded "Home" locally; cloud seeds its own).
  -- Only curated template content is copied: `source = 'manual'` ingredients
  -- and `'import_correction'` aliases are a household's private typed-in
  -- data and never leave it. No template → clean no-op (empty vocab).
  -- `backfilled_at` is stamped at creation: the clone below IS the measure
  -- backfill, so the run-once gate must never fire again for this household.
  if hh is null then
    insert into household (name, backfilled_at) values ('Home', now())
    returning id into hh;

    select id into src
    from household
    where is_template and deleted_at is null
    order by created_at
    limit 1;

    if src is not null then
      with cloned as (
        insert into ingredient (household_id, canonical_name, category,
          default_unit, density_g_per_ml, macros, macros_basis, status,
          source, match_text, allowed_units)
        select hh, canonical_name, category, default_unit, density_g_per_ml,
          macros, macros_basis, status, source, match_text, allowed_units
        from ingredient
        where household_id = src and deleted_at is null
          and source is distinct from 'manual'
        returning id, match_text
      ),
      -- Aliases follow their ingredient by matching canonical match_text
      -- within the clone (source→clone id map keyed on the unique
      -- match_text). Aliases of excluded (manual) ingredients drop out of the
      -- join naturally; import corrections are excluded explicitly.
      alias_clone as (
        insert into ingredient_alias (household_id, ingredient_id, alias_text,
          match_text, source)
        select hh, c.id, a.alias_text, a.match_text, a.source
        from ingredient_alias a
        join ingredient si on si.id = a.ingredient_id and si.household_id = src
        join cloned c on c.match_text = si.match_text
        where a.deleted_at is null
          and a.source <> 'import_correction'
      )
      -- Measures follow their ingredient by the same match_text map, so the
      -- starter "potato, medium = 213 g" vocabulary arrives with the vocab —
      -- provenance (`source`) included, amounts in the basis unit (0012).
      insert into ingredient_measure (household_id, ingredient_id, label,
        basis_amount, sort_order, source)
      select hh, c.id, im.label, im.basis_amount, im.sort_order, im.source
      from ingredient_measure im
      join ingredient si on si.id = im.ingredient_id and si.household_id = src
      join cloned c on c.match_text = si.match_text
      where im.household_id = src and im.deleted_at is null;

      -- …and the curated default count measure follows its measure, BY LABEL
      -- (0023, seam D1). It cannot ride the ingredient clone above: the
      -- template's id names a TEMPLATE measure, which the own-measure trigger
      -- rightly refuses, and the new household's measures do not exist until
      -- the statement above has run. A household starts on the curated
      -- answer and owns it from that moment (the "Counts as" row).
      update ingredient di
         set default_measure_id = dm.id,
             updated_at = now()
        from ingredient si
        join ingredient_measure sm on sm.id = si.default_measure_id
        join ingredient_measure dm on dm.household_id = hh
         and dm.deleted_at is null
         and lower(btrim(dm.label)) = lower(btrim(sm.label))
       where si.household_id = src and si.deleted_at is null
         and si.source is distinct from 'manual'
         and di.household_id = hh and di.deleted_at is null
         and di.match_text = si.match_text
         and dm.ingredient_id = di.id
         and di.default_measure_id is null;
    end if;
  end if;

  select count(*) into member_no
  from household_member
  where household_id = hh and deleted_at is null;

  insert into household_member (household_id, display_name, auth_user_id, sort_order)
  values (
    hh,
    coalesce(
      auth.jwt() -> 'user_metadata' ->> 'full_name',
      split_part(auth.jwt() ->> 'email', '@', 1),
      'Member'
    ),
    uid,
    member_no
  );

  return hh;
end;
$$;

-- CREATE OR REPLACE preserves the existing grant (0007/0008):
-- ensure_onboarded → authenticated only.
