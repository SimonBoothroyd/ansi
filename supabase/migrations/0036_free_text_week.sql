-- 0036_free_text_week.sql — a free-text item belongs to the week it was added
-- on.
--
-- 0019 gave the shopping overlay a week and made one exception: an INGREDIENT
-- entry carried the Monday it was ticked against, while a FREE-TEXT entry
-- ("paper towels") carried no week and read on every week's list, on the
-- reasoning that a staple you are out of is a fact about the cupboard rather
-- than about a week. In use that is wrong, and the owner has reversed it. You
-- write "paper towels" while shopping for one week; it is the same act as a
-- top-up, it is bought on that trip, and a row that reappears on every future
-- list is an item nobody can finish — the only way to be rid of it is to
-- delete it, which is not what a check-off is for.
--
-- So a free-text entry is week-scoped like everything else in the overlay, and
-- the client stamps `week_start_date` on it (the viewed week, the same key
-- `week_plan` is addressed by). The read is the simpler half of the reversal:
-- it now takes `week_start_date = $1` and nothing else, so a row with a NULL
-- week is read by no week at all.
--
-- That is what makes the backfill load-bearing rather than cosmetic. Unlike
-- 0019 — which could leave old rows alone, because a null-week free-text row
-- still read everywhere under the old rule — a row left null here would simply
-- vanish off every list on the next app launch. It is real data somebody
-- typed. So:
--
--   * every `shopping_list_entry` with `free_text is not null and
--     week_start_date is null` lands on the ISO Monday of its own `created_at`
--     — the week the person was looking at when they typed it. Postgres weeks
--     start Monday, so `date_trunc('week', …)::date` IS the week key, read in
--     the server's timezone (UTC);
--   * across EVERY household, the template included, and including
--     soft-deleted rows — an undelete must not resurrect a global row into a
--     world that has no such thing;
--   * `updated_at` is bumped, because PowerSync syncs the change down on that.
--
-- The column stays NULLABLE, deliberately. Pre-0019 ingredient rows are null
-- too (0019 wrote no backfill and this migration does not invent weeks for
-- them — an ingredient entry with no week is a stale tick, not lost content),
-- and an older client still in somebody's hand may write a null free-text row
-- tomorrow. Which is why the backfill is a FUNCTION rather than a bare
-- statement: it can be re-run after a rollout, and the pgTAP suite can prove
-- the rule on a row it inserts itself (migrations run before the tests, so a
-- one-shot `do` block would have nothing left to observe).
--
-- Row-preserving (docs/cloud-setup.md §2c): one UPDATE that only ever fills a
-- null. Idempotent — a filled row no longer matches — and reset-safe, so
-- `supabase db reset` re-runs it cleanly.

create or replace function shopping_free_text_week_backfill()
returns integer
language plpgsql
as $$
declare
  stamped integer;
begin
  with landed as (
    update shopping_list_entry
       set week_start_date = date_trunc('week', created_at)::date,
           updated_at      = now()
     where free_text is not null
       and week_start_date is null
    returning id
  )
  select count(*) into stamped from landed;
  return stamped;
end;
$$;

comment on function shopping_free_text_week_backfill() is
  'Stamps every free-text shopping entry that carries no week onto the Monday '
  'of its own created_at, across all households and including soft-deleted '
  'rows. Idempotent: only ever fills a null.';

-- Client roles have no business running it; the boundary they get is RLS on
-- the table, and this statement reaches every household.
revoke execute on function shopping_free_text_week_backfill()
  from public, anon, authenticated;

do $$
declare
  stamped integer;
begin
  stamped := shopping_free_text_week_backfill();
  raise notice
    '0036_free_text_week: % week-less free-text row(s) landed on their week',
    stamped;
end;
$$;

comment on column shopping_list_entry.week_start_date is
  'The Monday of the week this entry belongs to (matches '
  'week_plan.week_start_date). Every entry the app writes carries one, a '
  'free-text non-food item included. Nullable only for rows an older client '
  'wrote: a free-text row with no week is backfilled onto the Monday of its '
  'created_at, and an ingredient row with no week is a pre-0019 tick that '
  'belongs to no week and is read by none.';
