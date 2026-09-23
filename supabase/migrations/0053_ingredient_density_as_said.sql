-- 0053_ingredient_density_as_said.sql — a density keeps the sentence it was
-- said in.
--
-- `density_g_per_ml` is the one number every conversion reads, and it stays
-- that. What it lost was the sentence: a jar's "1/3 cup (40g)" went in and came
-- back as 0.507 g/ml, the same fact in words nobody said. The row now keeps
-- "[density_amount] [density_unit] weighs [density_weighs_amount]
-- [density_weighs_unit]" beside the number, the way a receipt line keeps its
-- pack as entered (0046). The app derives the g/ml from the sentence at write
-- time; nothing reads the sentence to convert.
--
-- Additive and nullable. The last shipped build does not declare these
-- columns, so it writes `density_g_per_ml` alone; the sentence it leaves behind
-- then no longer states the number, and the app shows the number instead
-- (`densitySaidOf`). That is why there is no check tying the two together:
-- such a check would refuse the older build's upload.

alter table ingredient
  add column density_amount        numeric check (density_amount > 0),
  add column density_unit          text,
  add column density_weighs_amount numeric check (density_weighs_amount > 0),
  add column density_weighs_unit   text;

-- A sentence is whole or absent: half of one says nothing.
alter table ingredient
  add constraint ingredient_density_said_whole check (
    (density_amount is null) = (density_unit is null)
    and (density_amount is null) = (density_weighs_amount is null)
    and (density_amount is null) = (density_weighs_unit is null)
  );

comment on column ingredient.density_amount is
  'The density as said, left side: the amount in density_unit ("1/3" of '
  '"1/3 cup weighs 40 g"). Words only; density_g_per_ml is the number read.';
comment on column ingredient.density_unit is
  'The units.dart canonical unit id of density_amount (''cup'', ''tbsp'', '
  '''oz''). One side is a volume and the other a weight, in either order.';
comment on column ingredient.density_weighs_amount is
  'The density as said, right side: what density_amount weighs (or, said the '
  'other way round, measures), in density_weighs_unit.';
comment on column ingredient.density_weighs_unit is
  'The units.dart canonical unit id of density_weighs_amount.';
