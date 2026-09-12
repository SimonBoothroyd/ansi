-- 0041_ingredient_retire_guard.sql — an ingredient is retired only when
-- nothing live names it, and what is already broken is re-pointed.
--
-- The incident this closes: a hand data pass on cloud found two live
-- `ingredient` rows keyed to the same `match_text` in one household, retired
-- the newer one (an import had created it), and did NOT re-point the one live
-- `recipe_line_item` that referenced it. The recipe then held a live line
-- whose `ingredient_id` pointed at a row with `deleted_at` set. Nothing
-- refused the statement and nothing repaired it afterwards — the app's own
-- delete door has always counted recipe lines and refused, but a hand
-- statement runs past the door, and the database had no opinion.
--
-- So the opinion moves into the database, where every writer meets it: the
-- app, the edge functions, the PowerSync upload queue, and a person with a
-- SQL prompt.
--
-- Three tables carry an `ingredient_id` a *line* can be about —
-- `recipe_line_item`, `plan_entry` (a bare-ingredient meal, 0033) and
-- `week_recipe_line_override` (this week's swap, 0040). All three are guarded
-- and all three are repaired. `shopping_list_entry` is deliberately not:
-- an entry is this week's shopping, re-derived every week and check-off
-- state besides, so a retired ingredient there costs a stale row, not a
-- broken recipe. `ingredient_alias` and `ingredient_measure` are parts OF
-- the row and go down with it (the app tombstones them in the same
-- transaction).
--
-- **Reachability matches the app's count exactly.** The app refuses a delete
-- while a live line in a live group of a live recipe names the row
-- (`ingredient_repository_impl.softDelete`), so this counts the same set. A
-- database that refused MORE than the client checks would turn a legal local
-- delete into an upload the sync queue can never drain — a failure the user
-- cannot act on, which is strictly worse than the one being fixed.
--
-- **A data repair lives here on purpose.** 0020's header says the opposite —
-- "a database that has drifted is RESET from migrations + seeds" — and that
-- was true when it was written. It is not true now: cloud data has been
-- production since v0.7.0, so drift is repaired forward, in a migration,
-- never reset away. The repair is idempotent (it only touches rows whose
-- ingredient is retired) and it is honest: a row with no single live twin is
-- left exactly as it is and counted out loud, because guessing which of two
-- live rows a line meant is not a repair.

-- ---------------------------------------------------------------------------
-- 1. What "live lines still use this ingredient" means, in one place.
-- ---------------------------------------------------------------------------
--
-- One stored definition, read by the guard below and asserted by
-- `supabase/tests/ingredient_retire_guard.sql`, so the count in the refusal
-- and the count a test reads can never be two different questions.
create or replace function ingredient_live_line_uses(p_ingredient_id uuid)
returns bigint
language sql
stable
as $$
  select
    (select count(*)
       from recipe_line_item li
       join ingredient_group gr on gr.id = li.group_id
       join recipe r            on r.id  = gr.recipe_id
      where li.ingredient_id = p_ingredient_id
        and li.deleted_at is null
        and gr.deleted_at is null
        and r.deleted_at is null)
  + (select count(*)
       from plan_entry pe
       join week_plan wp on wp.id = pe.week_plan_id
      where pe.ingredient_id = p_ingredient_id
        and pe.deleted_at is null
        and wp.deleted_at is null)
  + (select count(*)
       from week_recipe_line_override wro
       join week_plan wp on wp.id = wro.week_plan_id
      where wro.ingredient_id = p_ingredient_id
        and wro.deleted_at is null
        and wp.deleted_at is null);
$$;

comment on function ingredient_live_line_uses(uuid) is
  'How many live lines name this ingredient — recipe lines (in live groups '
  'of live recipes), bare-ingredient meals, and this-week overrides. The '
  'same set the app''s delete door counts (ingredient_repository_impl.'
  'softDelete), so client and server refuse the same deletes.';

-- ---------------------------------------------------------------------------
-- 2. The guard: retiring a row nothing can name is fine; retiring one a line
--    still names is refused, by the count.
-- ---------------------------------------------------------------------------
--
-- The refusal NAMES THE NUMBER and says what to do, because whoever hit it —
-- an operator at a prompt, an edge function, the app — can act on "three
-- lines still use this" and cannot act on "constraint violated".
--
-- Not scoped away from the template household. The template carries no
-- recipes, no weeks and no plan entries, so the seed's retire step (the
-- generated `seed_vocab.sql` tail that drops rows the snapshot no longer
-- carries) counts zero and passes untouched. If a template recipe ever
-- existed, refusing would be the RIGHT answer there too: every new household
-- clones the template, and a clone that starts with a line pointing at
-- nothing is the same bug shipped to everyone.
create or replace function ingredient_retire_refuses_live_lines()
returns trigger
language plpgsql
as $$
declare
  uses bigint;
begin
  uses := ingredient_live_line_uses(old.id);
  if uses > 0 then
    -- Agreement is substituted rather than approximated: "1 live lines" is
    -- the kind of sentence that makes a reader distrust the number beside it.
    raise exception
      'retire refused: % live % still % this ingredient; re-point % first',
      uses,
      case when uses = 1 then 'line' else 'lines' end,
      case when uses = 1 then 'uses' else 'use' end,
      case when uses = 1 then 'it' else 'them' end
      using errcode = '23503',
            hint = 'Re-point or remove the lines naming '
                   || old.id::text
                   || ', then retire the row.';
  end if;
  return new;
end;
$$;

comment on function ingredient_retire_refuses_live_lines() is
  'BEFORE UPDATE guard: a row cannot gain a deleted_at while live lines name '
  'it. The message carries the count because a refusal a human can act on '
  'beats an error they cannot.';

drop trigger if exists ingredient_retire_guard on ingredient;
create trigger ingredient_retire_guard
  before update on ingredient
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function ingredient_retire_refuses_live_lines();

-- ---------------------------------------------------------------------------
-- 3. The repair, as a function — so the same code the migration runs once is
--    the code a test exercises and an operator can re-run.
-- ---------------------------------------------------------------------------
--
-- A line pointing at a retired row is re-pointed to the live row of the same
-- `(household_id, match_text)` when there is EXACTLY ONE — which is what a
-- de-duplication leaves behind, and the only case where the line's intent is
-- not in doubt. Zero live twins, or two, and the row is left alone and
-- counted: the app now shows such a line with its last known name and
-- `ingredient removed · pick again`, so a person picks, and nothing is
-- guessed on their behalf.
--
-- The three statements are written out rather than looped over `format(%I)`:
-- dynamic SQL is opaque to `supabase db lint`, and a repair nothing can
-- statically check is the wrong shape for a repair. What keeps them from
-- drifting is that the decision they share — *which* row to re-point to —
-- is a function of its own, and that all three are exercised by
-- `supabase/tests/ingredient_retire_guard.sql`.

-- The live row a retired one's lines belong to, or NULL when that cannot be
-- said: no live twin, or more than one. Returning NULL for "ambiguous" is
-- what makes the repair statements below both filter and decide with the one
-- call — and it is invariant 3's shape, one table over: no answer beats a
-- guessed one.
create or replace function single_live_twin_of(p_retired uuid)
returns uuid
language sql
stable
as $$
  select case when count(*) = 1 then (array_agg(live.id))[1] end
    from ingredient dead
    join ingredient live
      on live.household_id = dead.household_id
     and live.match_text = dead.match_text
     and live.deleted_at is null
   where dead.id = p_retired
     and dead.deleted_at is not null
     and dead.match_text is not null;
$$;

comment on function single_live_twin_of(uuid) is
  'The one live ingredient of the same (household_id, match_text) as this '
  'retired row — what a de-duplication left behind. NULL when there is no '
  'live twin or more than one, because a line''s intent is then not '
  'inferable and must be re-pointed by a person.';

create or replace function repair_lines_at_retired_ingredients()
returns table (repointed bigint, stranded bigint)
language plpgsql
as $$
declare
  n bigint;
begin
  repointed := 0;

  update recipe_line_item r
     set ingredient_id = single_live_twin_of(r.ingredient_id),
         updated_at = now()
   where r.deleted_at is null
     and single_live_twin_of(r.ingredient_id) is not null;
  get diagnostics n = row_count;
  repointed := repointed + n;

  update plan_entry pe
     set ingredient_id = single_live_twin_of(pe.ingredient_id),
         updated_at = now()
   where pe.deleted_at is null
     and single_live_twin_of(pe.ingredient_id) is not null;
  get diagnostics n = row_count;
  repointed := repointed + n;

  update week_recipe_line_override wro
     set ingredient_id = single_live_twin_of(wro.ingredient_id),
         updated_at = now()
   where wro.deleted_at is null
     and single_live_twin_of(wro.ingredient_id) is not null;
  get diagnostics n = row_count;
  repointed := repointed + n;

  -- Counted AFTER the updates, so this is what is genuinely left: a live
  -- line whose ingredient is retired and whose intent nobody can infer.
  select count(*) into stranded
    from (
      select r.ingredient_id
        from recipe_line_item r where r.deleted_at is null
      union all
      select pe.ingredient_id
        from plan_entry pe where pe.deleted_at is null
      union all
      select wro.ingredient_id
        from week_recipe_line_override wro where wro.deleted_at is null
    ) ref
    join ingredient dead on dead.id = ref.ingredient_id
   where dead.deleted_at is not null;

  return next;
end;
$$;

comment on function repair_lines_at_retired_ingredients() is
  'Re-points every live recipe line / bare-ingredient meal / week override '
  'whose ingredient is retired onto the single live row of the same '
  '(household_id, match_text), and returns (repointed, stranded). Idempotent; '
  'a line with no single live twin is left for a person to re-point.';

-- ---------------------------------------------------------------------------
-- 4. Run it once, out loud.
-- ---------------------------------------------------------------------------
--
-- Both numbers are announced whether or not they are zero: a reset log that
-- says "0 re-pointed, 0 left" is the evidence the repair ran, and a silent
-- repair is the same class of bug as the silent retire that caused this.
do $$
declare
  result record;
begin
  select * into result from repair_lines_at_retired_ingredients();
  raise notice
    '0041: re-pointed % live line(s) from a retired ingredient to its single '
    'live twin', result.repointed;
  raise notice
    '0041: % live line(s) still name a retired ingredient with no single '
    'live twin — left as they are; the app names them and asks for a pick',
    result.stranded;
end;
$$;
