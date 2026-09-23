-- 0051_ingredient_base_price.sql — a row's base price, kept on the row.
--
-- A price typed on an ingredient page was a one-line `manual` receipt (0044),
-- so setting what parsley or a jar of cumin usually costs put a "shop" into
-- the receipts ledger and into the week's spent figure. The household prices
-- cupboard staples by hand and buys them on no receipt worth keeping. A typed
-- price is therefore a BASE PRICE on the row itself: what was paid and for
-- what pack, kept the way a receipt line keeps it — the pack as entered
-- (`base_price_pack_amount` / `_unit` / `_measure_id`, 0046's two shapes) and
-- what it came to in the row's basis unit (`base_price_pack_basis_amount`),
-- which is the only number a figure is derived from, at read time.
--
-- A cost reads the newest receipt-line price for the row, else this, else
-- nothing (ADR-0017). Every column is nullable and additive: the last shipped
-- build ignores them (its schema does not declare them), and it can still
-- write a `manual` receipt, which reads as an ordinary receipt price.

alter table ingredient
  add column base_price_cents int check (base_price_cents > 0),
  add column base_price_pack_basis_amount numeric
    check (base_price_pack_basis_amount > 0),
  add column base_price_pack_amount numeric check (base_price_pack_amount > 0),
  add column base_price_pack_unit text,
  add column base_price_measure_id uuid references ingredient_measure(id),
  add column base_price_set_at timestamptz;

-- A base price is whole or absent: cents, the basis pack and the date travel
-- together. A unit with no number says nothing (0046's rule for a line).
alter table ingredient
  add constraint ingredient_base_price_whole check (
    (base_price_cents is null) = (base_price_pack_basis_amount is null)
    and (base_price_cents is null) = (base_price_set_at is null)
  ),
  add constraint ingredient_base_price_unit_needs_an_amount check (
    base_price_pack_unit is null or base_price_pack_amount is not null
  );

create index ingredient_base_price_measure_idx
  on ingredient (base_price_measure_id);

comment on column ingredient.base_price_cents is
  'The row''s base price: what was paid, in integer cents, for the pack below. '
  'Read only when no live receipt line prices the row.';
comment on column ingredient.base_price_pack_basis_amount is
  'What the base price bought, in the row''s basis unit (g or ml). The per-100 '
  'figure is derived from this and base_price_cents at read time.';
comment on column ingredient.base_price_pack_amount is
  'The base price''s pack as entered: an amount in base_price_pack_unit, or '
  'with that null and base_price_measure_id set, a COUNT of that measure.';
comment on column ingredient.base_price_pack_unit is
  'The units.dart canonical unit id the base price''s pack was entered in, '
  'or null when it was tapped as one of the row''s measures.';
comment on column ingredient.base_price_measure_id is
  'The measure the base price''s pack was named as. A label only.';
comment on column ingredient.base_price_set_at is
  'When the base price was last set; the month a cost read from it names.';

-- ---------------------------------------------------------------------------
-- The hand-typed receipts become base prices, and leave the ledger.
-- ---------------------------------------------------------------------------
--
-- Each row's newest live priced `manual` line is copied into its base price
-- (a count folds into the pack, so the figure is unchanged); then every live
-- `manual` receipt and its lines are soft-deleted. Nothing is hard-deleted,
-- and a row that already states a base price keeps it.
with newest as (
  select distinct on (l.ingredient_id)
         l.ingredient_id,
         l.cents - l.discount_cents        as paid,
         l.count * l.pack_basis_amount     as basis_amount,
         l.count * l.pack_amount           as pack_amount,
         l.pack_unit,
         l.measure_id,
         r.purchased_at
    from receipt_line l
    join receipt r on r.id = l.receipt_id
   where r.source = 'manual'
     and r.deleted_at is null
     and l.deleted_at is null
     and l.kind = 'item'
     and l.ingredient_id is not null
     and l.pack_basis_amount is not null
     and l.cents - l.discount_cents > 0
   order by l.ingredient_id, r.purchased_at desc, l.created_at desc, l.id desc
)
update ingredient i
   set base_price_cents             = n.paid,
       base_price_pack_basis_amount = n.basis_amount,
       base_price_pack_amount       = n.pack_amount,
       base_price_pack_unit         = case when n.pack_amount is null
                                           then null else n.pack_unit end,
       base_price_measure_id        = n.measure_id,
       base_price_set_at            = n.purchased_at
  from newest n
 where i.id = n.ingredient_id
   and i.base_price_cents is null;

update receipt_line l
   set deleted_at = now(), updated_at = now()
  from receipt r
 where r.id = l.receipt_id
   and r.source = 'manual'
   and r.deleted_at is null
   and l.deleted_at is null;

update receipt
   set deleted_at = now(), updated_at = now()
 where source = 'manual'
   and deleted_at is null;
