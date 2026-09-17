-- 0044_receipts.sql — the price fact: what was paid, for what pack, where,
-- and when.
--
-- A recipe cannot say what it costs until the vocabulary can say what one of
-- its rows costs, and a price is not a number on the ingredient: it is an
-- **event**. Cents change, a shop's shelf differs from another's, and last
-- month's jar was bought at last month's price. So the fact stored is the one
-- that happened — `$3.49 for a 454 g bag at TJ's on 13 Sep` — and every
-- figure a screen reads (77¢ / 100 g) is derived from it at read time, in the
-- row's own basis unit, never written back.
--
-- **Receipts are the price table.** There is no separate observation table: a
-- shop's receipt is already a list of what was paid for what, and a price
-- typed by hand on the ingredient page is the same fact with a smaller piece
-- of paper behind it — one `receipt` with `source = 'manual'`, one
-- `receipt_line`, the store as the chip word and `purchased_at` as now. One
-- fact, one ledger: when the photo pipeline lands, a scanned line and a typed
-- one are the same row read the same way, and the spend ledger sums them
-- together without knowing which was which.
--
-- **Money is integer cents, USD, and nothing else.** No currency column, no
-- numeric money, no sale flag, no average: latest wins, and the owner's
-- kitchen buys in dollars. A discount rides BESIDE the line's own cents
-- rather than inside them, so the paper keeps both printed figures; what was
-- paid is `cents - discount_cents`, and what you paid is the price.
--
-- **The pack is stated in the row's basis unit.** `pack_basis_amount` is what
-- the cents bought, in g or ml (`ingredient.macros_basis`, ADR-0008) — the
-- same denomination `ingredient_measure.basis_amount` and
-- `ingredient.piece_basis_amount` already use, for the same reason: one
-- dimension per row, so a per-basis figure needs no conversion at read time
-- and no reader has to know which unit the person happened to type. The
-- conversion happens once, where the person can see it refused: a pack
-- entered in a volume unit on a g-basis row resolves only through the row's
-- density, and without one there is no number to store (invariant 3).
--
-- ---------------------------------------------------------------------------
-- A receipt line and a retired ingredient
-- ---------------------------------------------------------------------------
--
-- 0041 made a live line's ingredient un-retirable, and re-pointed the lines a
-- hand statement had already stranded. A receipt line is **deliberately not**
-- one of those lines, and is not added to `ingredient_live_line_uses()`:
--
-- - a recipe line, a planned meal and a week override are all statements about
--   what the household is *going to* cook, and a retired ingredient breaks
--   them — the macro engine drops them and the shop degrades them, silently.
--   A receipt is a statement about what already happened, and pruning a row
--   from the vocabulary does not make last month's shop untrue;
-- - counting it would refuse the retire outright and forever. Every row the
--   household has ever bought would be un-prunable, with nothing a person
--   could do about it — the shape 0041's own header calls strictly worse than
--   the bug being fixed (`shopping_list_entry` is left out for the same
--   reason, one table over).
--
-- It must still never dangle, so the retire **detaches** it instead, in the
-- database where every writer meets it: the line follows the single live twin
-- of the retired row where there is one (0041's `single_live_twin_of` — what
-- a de-duplication leaves behind, the only case the intent is not in doubt),
-- and otherwise loses its `ingredient_id`. The paper is kept whole either way
-- — the cents, the store, the date and the printed words are what a receipt
-- is — and what it stops being is a price for a row that no longer exists.

-- ---------------------------------------------------------------------------
-- 1. The paper.
-- ---------------------------------------------------------------------------

create table receipt (
  id             uuid primary key default gen_random_uuid(),
  household_id   uuid not null references household(id),
  -- The store as a word, not a row (no store table): whatever the household
  -- calls it — "TJ's", "Whole Foods" — offered back as a chip next time.
  store          text not null,
  -- When the shopping happened, which is the receipt's own date and never the
  -- scan's. A week's spend is filed by this.
  purchased_at   timestamptz not null,
  -- As PRINTED, when there is a printed figure to keep. Null on a hand-typed
  -- price, where subtotal is simply the line's own cents; null on a photo
  -- whose paper did not print one. Never re-derived from the lines: the sum
  -- of the lines checked against the printed subtotal is the review's
  -- reconcile figure, and two numbers that must be able to disagree cannot be
  -- stored as one.
  subtotal_cents int,
  tax_cents      int,
  total_cents    int,
  -- 'manual' — typed on an ingredient page, one line, no photo.
  -- 'photo'  — read off a picture through the import pipeline.
  source         text not null check (source in ('manual', 'photo')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz           -- soft-delete tombstone (spec §3)
);

comment on table receipt is
  'One shop, or one hand-typed price. The household''s price ledger: every '
  'ingredient price is a line on one of these, so a typed price and a scanned '
  'one are the same fact read the same way.';

-- ---------------------------------------------------------------------------
-- 2. The lines.
-- ---------------------------------------------------------------------------

create table receipt_line (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references household(id),
  receipt_id    uuid not null references receipt(id),
  -- The vocabulary row this line is about, when it is about one. Null is an
  -- ordinary answer: a `not_food` line, a tax line, a fee — and a line whose
  -- ingredient was retired out from under it (see the header).
  ingredient_id uuid references ingredient(id),
  -- What the paper said, verbatim ("ORG BANANA 2LB"). Null on a hand-typed
  -- price: nothing printed it, and the ingredient names the line.
  printed_text  text,
  -- What the line rang up as, in integer cents — the figure the paper
  -- printed, kept verbatim so the receipt still adds up against its own
  -- subtotal. A `fee` line may carry a negative figure: that is how a
  -- discount the scanner could not attach to an item still lets the
  -- reconcile close.
  cents         int not null,
  -- The deduction printed under the item, kept BESIDE the sum rather than
  -- subtracted into it, so both printed numbers survive and the review can
  -- show what was knocked off. Non-negative: a discount is stated as the
  -- amount taken away. **What was paid is `cents - discount_cents`**, and
  -- that is the figure a price is derived from — what you paid is the price.
  discount_cents int not null default 0 check (discount_cents >= 0),
  -- 'item'     — food, and the only kind that can carry a price;
  -- 'not_food' — paper towels, a bag fee, a bottle deposit: counts toward the
  --              total, never toward a price;
  -- 'tax', 'fee' — the paper's own lines, kept so the receipt adds up.
  kind          text not null check (kind in ('item', 'not_food', 'tax', 'fee')),
  -- What the cents bought, in the INGREDIENT's basis unit (g or ml) — see the
  -- header. Null where nobody has said what the pack is, which is the honest
  -- state of a matched line whose pack is still unknown: the line is kept, and
  -- it simply is not a price yet.
  pack_basis_amount numeric check (pack_basis_amount > 0),
  -- The row's own word for that pack ("bag (454 g)"), when the pack was named
  -- as one. Null where it was typed as a plain amount. It is a LABEL, never
  -- the amount: `pack_basis_amount` above is the number, so a measure
  -- re-weighed later does not silently re-price a shop that already happened.
  measure_id    uuid references ingredient_measure(id),
  sort_order    int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  -- Only a food line can be about an ingredient or carry a pack. A tax line
  -- with a pack weight would be a price nobody could read.
  constraint receipt_line_only_items_are_priced check (
    kind = 'item'
    or (ingredient_id is null
        and pack_basis_amount is null
        and measure_id is null)
  )
);

comment on table receipt_line is
  'One line of a receipt. An item line naming an ingredient AND stating a '
  'pack is a price observation: (cents - discount_cents) per '
  'pack_basis_amount of the row''s basis unit.';

-- Foreign-key lookup indexes, and the two reads that matter: a receipt's own
-- lines, and one ingredient's prices newest-first.
create index receipt_household_idx      on receipt (household_id);
create index receipt_purchased_at_idx   on receipt (household_id, purchased_at);
create index receipt_line_receipt_idx   on receipt_line (receipt_id);
create index receipt_line_household_idx on receipt_line (household_id);
create index receipt_line_ingredient_idx on receipt_line (ingredient_id);
create index receipt_line_measure_idx   on receipt_line (measure_id);

-- ---------------------------------------------------------------------------
-- 3. RLS + grants, in 0009's shape.
-- ---------------------------------------------------------------------------
--
-- RLS filters; GRANTs gate — both are needed (supabase/AGENTS.md). Deletes are
-- soft, so there is no delete policy and no DELETE grant.

alter table receipt enable row level security;

create policy receipt_read on receipt
  for select using (household_id = current_household_id());
create policy receipt_write on receipt
  for insert with check (household_id = current_household_id());
create policy receipt_update on receipt
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

alter table receipt_line enable row level security;

create policy receipt_line_read on receipt_line
  for select using (household_id = current_household_id());
create policy receipt_line_write on receipt_line
  for insert with check (household_id = current_household_id());
create policy receipt_line_update on receipt_line
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

grant select, insert, update on receipt      to authenticated;
grant select, insert, update on receipt_line to authenticated;
grant all on receipt      to service_role;
grant all on receipt_line to service_role;

-- Both tables sync with the household's vocabulary (docker/powersync.yaml and
-- docker/powersync-cloud.streams.yaml gain the matching rules in this change).
alter publication powersync add table receipt;
alter publication powersync add table receipt_line;

-- ---------------------------------------------------------------------------
-- 4. A retired ingredient takes its prices' pointer with it, not the paper.
-- ---------------------------------------------------------------------------
--
-- The header says why this detaches rather than refuses. It runs AFTER the
-- update, so 0041's BEFORE guard has already had its say about the lines that
-- do refuse; a retire that got this far is one the household is allowed to
-- make.
--
-- The measure always goes: a measure is part of the ingredient row and is
-- tombstoned with it, so keeping the label would point the line at a word
-- nothing says any more. `pack_basis_amount` stays — it is a number about a
-- purchase that really happened, and it is still true.
create or replace function receipt_lines_detach_from_retired_ingredient()
returns trigger
language plpgsql
as $$
declare
  twin uuid := single_live_twin_of(old.id);
  moved bigint;
begin
  update receipt_line
     set ingredient_id = twin,
         measure_id    = null,
         updated_at    = now()
   where ingredient_id = old.id
     and deleted_at is null;
  get diagnostics moved = row_count;

  if moved > 0 then
    raise notice
      '% receipt line(s) of a retired ingredient %',
      moved,
      case when twin is null
           then 'lost their ingredient — the paper is kept as paid'
           else 'followed its single live twin' end;
  end if;
  return null;
end;
$$;

comment on function receipt_lines_detach_from_retired_ingredient() is
  'AFTER UPDATE: when an ingredient is retired, its receipt lines follow the '
  'single live row of the same (household_id, match_text) where there is one, '
  'and otherwise lose their ingredient_id. A receipt is history and is kept '
  'whole; it simply stops being a price for a row that is gone.';

drop trigger if exists receipt_line_follows_retired_ingredient on ingredient;
create trigger receipt_line_follows_retired_ingredient
  after update on ingredient
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function receipt_lines_detach_from_retired_ingredient();
