-- 0048_recipe_measure.sql — a recipe's own word for one of what it makes.
--
-- `ingredient_measure` gave the household a word for one of a THING — `clove`,
-- `can`, `potato, medium` — and pinned it to the ingredient's basis unit. A
-- recipe has the same problem and no way to say it: a sauce you made can only
-- be asked for in `batch`, or in a unit family the target's
-- `yield_qty`/`yield_unit` happens to state. So a cook who ladles a blob of
-- romesco onto a plate has to either weigh the batch or say `0.15 batch`,
-- which is not a sentence anybody says in a kitchen.
--
-- A `recipe_measure` is that missing word: free text the household coins per
-- recipe — `blob`, `ladle`, `patty`, `loaf` — and NOTHING about the word is
-- known here. The label is whatever they typed.
--
-- ---------------------------------------------------------------------------
-- One number, and it is `per_batch`
-- ---------------------------------------------------------------------------
--
-- A measure states how many of itself a batch makes: *a batch makes 20 blob*.
-- That is the whole definition, and everything falls out of it — `3 blob` of
-- the sauce is 3/20 = 0.15 batches, which is the denomination every derivation
-- already walks in (the cook plan scales batches, the shop sums a batch's
-- lines, macros divide a batch's totals).
--
-- What it deliberately does NOT need:
--
--   * **no yield.** `recipe.yield_qty`/`yield_unit` is what turns `¼ cup` into
--     a batch share, and a recipe nobody measured has none. A measure counts
--     what the batch makes directly, so it resolves where the yield cannot —
--     that is the whole point of the feature, not a convenience.
--   * **no unit**, and so no unit family, no density, no bridge. `blob` is not
--     a volume that happens to lack a number; it is a count of a thing this
--     recipe makes, and the only conversion it can ever be asked for is into
--     batches, which the one number already gives.
--   * **no `source` column.** An `ingredient_measure` carries provenance
--     because its amount can arrive from USDA, a borrow or an estimate. A
--     recipe's measures only ever come from the household that wrote the
--     recipe, so a column recording that would have exactly one value.
--
-- **Scaling multiplies the LINE, never the measure.** Cooking a parent at ×2
-- asks for `6 blob`, not for a blob twice the size: the measure is a property
-- of the sub-recipe's own batch and is read the same at every scale.
--
-- ---------------------------------------------------------------------------
-- No unique index on (recipe_id, label) — 0011's doctrine, restated
-- ---------------------------------------------------------------------------
--
-- 0011 dropped `measure_live_label_uq` for a reason that applies here
-- unchanged: two offline devices coining `blob` on the same recipe would make
-- one of them 23505 on upload, and the PowerSync connector drops the WHOLE
-- crud transaction on a failed upload — so an offline duplicate would not just
-- lose the duplicate, it would lose everything queued beside it. Duplicates
-- therefore merge on READ, oldest row canonical, exactly as they do for
-- ingredient measures. The editor refuses a label already live on this recipe
-- before it is typed twice on one device; that is an ergonomic, not a fence,
-- and it is a client rule.
--
-- ---------------------------------------------------------------------------
-- A measure that has gone: nothing degrades to a count
-- ---------------------------------------------------------------------------
--
-- A line saying `3 blob` whose measure has been tombstoned is UNRESOLVED, and
-- stays unresolved. It must never be re-read as `3 piece` of the yield: three
-- of a thing nobody can measure any more is not three of whatever the batch is
-- counted in, and a confidently wrong batch share poisons the cook plan, the
-- shop and the macros in a way a missing one never does (invariant 3 — never
-- invent a value to make the math work). So the app refuses to derive it, the
-- number is kept, and every surface names the refusal.
--
-- Three consequences, and they belong together:
--
--   1. **The app blocks deleting a measure lines still say.** A client rule,
--      exactly as 8.5 ruled it for ingredients: one count query, two uses —
--      the refusal ("3 lines still say it, in 2 recipes") and the door that
--      lists them. No server gate, no RPC.
--   2. **A hand SQL soft-delete re-points its referrers in the SAME
--      transaction.** There are exactly two, and both are added below:
--      `recipe_line_item.recipe_measure_id` and
--      `week_recipe_line_override.recipe_measure_id`. Stamping `deleted_at`
--      without re-pointing them is the Sauerkraut miss one more time.
--   3. **`plan_entry` deliberately never points here.** A planned meal's
--      amount is its `portions` (`plan_entry_amount_is_for_ingredients`), so a
--      week slot has no amount for a measure to denominate. A recipe's word
--      for one of what it makes is a RECIPE-to-recipe fact.
--
-- ---------------------------------------------------------------------------
-- What this migration does not touch, and the one rule that has to widen
-- ---------------------------------------------------------------------------
--
-- Additive: production data, no column dropped and no row rewritten.
-- `line_item_component_has_no_measure` (0017) STAYS exactly as written — it
-- now reads "a component line carries no *ingredient* measure", which is still
-- true and still the rule: `measure_id` counts an ingredient's things and a
-- sub-recipe has none. The new `recipe_measure_id` is the opposite fence, and
-- the two never overlap.
--
-- The exceptions are the two rules that say a line's amount must name a
-- UNIT, because a line said in a recipe's own word names none. "5 blob" is a
-- whole fact with nothing missing: the word is its own denomination. There is
-- no honest unit to keep beside it — `batch` is the right dimension carrying
-- the wrong number (5, not 5/20) and `piece` is exactly the count this design
-- refuses to degrade to — so either would be a stored lie waiting for a reader
-- to believe it. Both rules therefore WIDEN by one arm and lose nothing:
--
--   * `recipe_line_item.unit` drops its NOT NULL (0003) and a new XOR makes it
--     total again — 0017's own move on this table, one column over;
--   * `week_recipe_line_override_amount_pair` (0040) is restated with 0040's
--     form kept verbatim as its `else`.
--
-- No existing row can fail either new form: `recipe_measure_id` is null on
-- every row there is, and `unit` is still refused as null everywhere it was.

-- ---------------------------------------------------------------------------
-- 1. The table.
-- ---------------------------------------------------------------------------

create table recipe_measure (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references household(id),
  -- Cascades like `ingredient_group` does (0003) and like an
  -- `ingredient_measure` does to its ingredient: a measure is a word for one
  -- of what THIS recipe makes, so with the recipe gone there is nothing left
  -- for it to name. A soft delete needs no cascade — every read joins
  -- `deleted_at is null`.
  recipe_id    uuid not null references recipe(id) on delete cascade,
  -- The household's own word, as typed: "blob", "ladle", "patty", "loaf".
  -- Nothing is hard-coded and nothing parses it.
  label        text not null
    constraint recipe_measure_label_not_blank check (btrim(label) <> ''),
  -- How many of this measure ONE batch makes. The only number there is.
  per_batch    numeric not null
    constraint recipe_measure_per_batch_positive check (per_batch > 0),
  sort_order   int not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz           -- soft-delete tombstone (spec §3)
);

comment on table recipe_measure is
  'A household word for one of what a recipe makes — "blob", "ladle", '
  '"patty" — so a component line in another recipe can say "3 blob" of it. '
  'One number defines it (per_batch), it needs no yield, no unit and no '
  'density, and there is deliberately NO unique index on (recipe_id, label): '
  'two offline devices coining the same word must not 23505 on upload, which '
  'would drop the whole crud transaction (0011''s doctrine). Duplicates merge '
  'on read, oldest row canonical.';

comment on column recipe_measure.label is
  'The word itself, as the household typed it. Free text — nothing here knows '
  'or guesses what a "blob" is, and no reader parses it.';

comment on column recipe_measure.per_batch is
  'How many of this measure ONE batch of the recipe makes ("a batch makes 20 '
  'blob"). A line saying N of it resolves to N / per_batch batches, which is '
  'the denomination every derivation already walks in. Scaling a parent '
  'multiplies the LINE''s quantity, never this number.';

comment on column recipe_measure.sort_order is
  'The order the household dragged the list into. The first measure fronts '
  'the chip row on a component''s quantity dock.';

-- Foreign-key lookup indexes.
create index recipe_measure_recipe_idx    on recipe_measure (recipe_id);
create index recipe_measure_household_idx on recipe_measure (household_id);

-- No household fence trigger on `recipe_id`, deliberately, and for 0033's
-- reason rather than 0017's: a measure pointing at another household's recipe
-- can never be USED, because the only thing that reads one is a component line
-- whose `sub_recipe_id` 0017's trigger has already fenced into this household,
-- and the line guard below insists the measure names that same recipe. A row
-- like that is inert, not dangerous, and it cannot close a cycle.

-- RLS: household-scoped read/write; deletes are soft, so no delete policy
-- (the 0005 trio, verbatim).
alter table recipe_measure enable row level security;

create policy recipe_measure_read on recipe_measure
  for select using (household_id = current_household_id());
create policy recipe_measure_write on recipe_measure
  for insert with check (household_id = current_household_id());
create policy recipe_measure_update on recipe_measure
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

-- Privileges mirror the policies (no DELETE — soft delete). RLS filters,
-- GRANTs gate: without this the table is invisible to the app.
grant select, insert, update on recipe_measure to authenticated;
grant all on recipe_measure to service_role;

-- Syncs with the household's recipes (docker/powersync.yaml and
-- docker/powersync-cloud.streams.yaml gain the matching rule in this change).
alter publication powersync add table recipe_measure;

-- No `updated_at` trigger: no table in this schema has one, and adding one
-- here would make this the odd table out. Writers stamp it, as they do
-- everywhere else.

-- ---------------------------------------------------------------------------
-- 2. The two lines that can say one.
-- ---------------------------------------------------------------------------
--
-- A recipe measure is only ever sayable on a COMPONENT line — it counts what
-- another recipe's batch makes, and an ingredient has no batch. It only ever
-- means something beside a number: "blob" alone says nothing, the way 0033's
-- `measure_needs_amount` says of an ingredient measure. And it carries no
-- unit, for the reason the header gives: the word IS the denomination, and
-- every candidate unit would be a lie a reader could act on.

alter table recipe_line_item
  -- Relaxed exactly as `ingredient_id` was in 0017, and for the same reason:
  -- the column stays load-bearing, and the XOR below is what makes it total.
  -- 0003 made `unit` not null because every line said its amount in one; a
  -- line said in a recipe's own word says it in no unit at all, and the two
  -- together still cover every line there is.
  alter column unit drop not null,
  add column recipe_measure_id uuid references recipe_measure(id),
  add constraint line_item_recipe_measure_is_a_component
    check (recipe_measure_id is null or sub_recipe_id is not null),
  add constraint line_item_recipe_measure_needs_amount
    check (recipe_measure_id is null or quantity is not null),
  -- A line is denominated in a unit OR in the sub-recipe's own word, never
  -- both and never neither. `batch` beside "3 blob" would be the right
  -- dimension carrying the wrong number, and `piece` is exactly the count
  -- this design refuses to degrade to, so there is nothing honest to store.
  add constraint line_item_unit_xor_recipe_measure
    check (num_nonnulls(unit, recipe_measure_id) = 1);

comment on column recipe_line_item.recipe_measure_id is
  'The sub-recipe''s own word this component line is counted in ("3 blob"). '
  'Only a component line may carry one, and only beside a quantity; the '
  'measure must belong to the recipe sub_recipe_id points at, which the '
  'recipe_line_item_recipe_measure_guard trigger enforces (the FK is global). '
  'A line whose measure has been tombstoned is UNRESOLVED and is never re-read '
  'as a count of the yield.';

create index line_item_recipe_measure_idx
  on recipe_line_item (recipe_measure_id);

-- The week-variant editor re-amounts a component line, so the delta table
-- carries the same pointer. It DOES hold `sub_recipe_id` of its own (0040
-- ships it as a column), so the component rule is expressible here as a check
-- rather than left to the trigger — and 0040's `action_shape` already keeps
-- `include`/`exclude` free of a target, so those two actions can never carry a
-- measure either.
alter table week_recipe_line_override
  add column recipe_measure_id uuid references recipe_measure(id),
  add constraint week_recipe_line_override_recipe_measure_is_a_component
    check (recipe_measure_id is null or sub_recipe_id is not null),
  add constraint week_recipe_line_override_recipe_measure_needs_amount
    check (recipe_measure_id is null or quantity is not null);

-- …and the pair rule widens by exactly one arm (see the header). 0040's form
-- is kept verbatim as the `else`, so every refusal it made it still makes.
alter table week_recipe_line_override
  drop constraint week_recipe_line_override_amount_pair;
alter table week_recipe_line_override
  add constraint week_recipe_line_override_amount_pair check (
    case when recipe_measure_id is not null
      then unit is null
      else num_nonnulls(quantity, unit) <> 1
    end
  );

comment on column week_recipe_line_override.recipe_measure_id is
  'The sub-recipe''s own word THIS WEEK''s amount is counted in. Same rules as '
  'recipe_line_item''s column, and the same trigger: a component target, a '
  'number beside it, and a measure belonging to the recipe sub_recipe_id '
  'names. Absolute like every other value here — the recipe re-stating "blob" '
  'later leaves this week at the count somebody asked for.';

create index week_recipe_line_override_recipe_measure_idx
  on week_recipe_line_override (recipe_measure_id);

-- ---------------------------------------------------------------------------
-- 3. The measure belongs to the recipe the line points at (the 0023
--    precedent, two tables over).
-- ---------------------------------------------------------------------------
--
-- The FK reaches `recipe_measure` globally and RLS only guards the ROW's own
-- household, so nothing in the schema stops a client from pointing a line at
-- another recipe's word — which is the one way this column could tell a lie:
-- "3 blob" resolved against a batch that makes 20 of something else. Refused
-- here rather than policed by every reader, exactly as 0023 refuses a
-- default measure that is not the ingredient's own.
--
-- Reads are the invoker's, so under `authenticated` a foreign household's
-- measure is simply invisible and this reads nothing and refuses; as
-- service_role it is visible and the household comparison refuses. Either way
-- the pointer stays inside (0017's fence, same shape).
--
-- LIVENESS is checked only when the pointer is being SET — on insert, or on an
-- update that changes it. An existing line whose measure was tombstoned out
-- from under it must stay editable: the retirement rule keeps the number and
-- names the refusal, and a guard that blocked every later save of that row
-- would trap the line instead of letting somebody fix it.
create or replace function recipe_measure_line_is_the_components_own()
returns trigger
language plpgsql
as $$
declare
  m_recipe    uuid;
  m_household uuid;
  m_deleted   timestamptz;
  pointing_at_it_now boolean;
begin
  -- OLD is unassigned on an INSERT, so the two legs cannot share one
  -- expression: reading it there raises before the condition is evaluated.
  if tg_op = 'INSERT' then
    pointing_at_it_now := true;
  else
    pointing_at_it_now :=
      old.recipe_measure_id is distinct from new.recipe_measure_id;
  end if;

  select rm.recipe_id, rm.household_id, rm.deleted_at
    into m_recipe, m_household, m_deleted
  from recipe_measure rm
  where rm.id = new.recipe_measure_id;

  if not found or m_household <> new.household_id then
    raise exception
      'recipe_measure % is not a measure in this household',
      new.recipe_measure_id
      using errcode = '23503';
  end if;

  if new.sub_recipe_id is distinct from m_recipe then
    raise exception
      'recipe_measure % belongs to recipe %, not to the component recipe %',
      new.recipe_measure_id, m_recipe, new.sub_recipe_id
      using errcode = '23514';
  end if;

  if m_deleted is not null and pointing_at_it_now then
    raise exception
      'recipe_measure % has been retired — a line cannot be pointed at it',
      new.recipe_measure_id
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function recipe_measure_line_is_the_components_own() is
  'Fences a line''s recipe_measure_id to a live measure of the very recipe its '
  'sub_recipe_id names, in the same household. Liveness is only required when '
  'the pointer is being set, so a line whose word has gone stays editable.';

-- Fires only where the column is set, so ordinary lines and tombstones pay
-- nothing (0017's WHEN clause, same reason).
create trigger recipe_line_item_recipe_measure_guard
  before insert or update on recipe_line_item
  for each row
  when (new.recipe_measure_id is not null)
  execute function recipe_measure_line_is_the_components_own();

create trigger week_recipe_line_override_recipe_measure_guard
  before insert or update on week_recipe_line_override
  for each row
  when (new.recipe_measure_id is not null)
  execute function recipe_measure_line_is_the_components_own();

-- Operator surface only: nothing calls this by hand (0023's posture).
revoke execute on function recipe_measure_line_is_the_components_own()
  from public, anon, authenticated;
