-- 0052_ingredient_base_price_store.sql — where a base price is paid.
--
-- A base price (0051) is what the household usually pays for a pack of a row,
-- typed on the ingredient page and kept on no receipt. The owner ruled that it
-- names the shop it is paid at, when there is one, so a cost read from it says
-- `TJ's, Sep` as a receipt price does. The store is a word, as `receipt.store`
-- is (no store table), and it is optional: a base price with none reads as
-- `base price, Sep`.
--
-- Additive and nullable: the last shipped build does not declare the column
-- and never writes it. The backfill gives a base price 0051 copied from a
-- hand-typed receipt that receipt's store — the receipt 0051 retired, found
-- by the row, the source and the date it was copied with.

alter table ingredient
  add column base_price_store text;

comment on column ingredient.base_price_store is
  'The shop the base price is paid at, as the household''s own word (the '
  'receipt.store vocabulary; no store table). Optional; null names none.';

-- Only a row that states a base price can name where it is paid.
alter table ingredient
  add constraint ingredient_base_price_store_needs_a_price check (
    base_price_store is null or base_price_cents is not null
  );

with copied as (
  select distinct on (l.ingredient_id)
         l.ingredient_id,
         nullif(trim(r.store), '') as store
    from receipt_line l
    join receipt r on r.id = l.receipt_id
    join ingredient i on i.id = l.ingredient_id
   where r.source = 'manual'
     and l.kind = 'item'
     and r.purchased_at = i.base_price_set_at
   order by l.ingredient_id, l.created_at desc, l.id desc
)
update ingredient i
   set base_price_store = c.store
  from copied c
 where i.id = c.ingredient_id
   and i.base_price_cents is not null
   and i.base_price_store is null
   and c.store is not null;
