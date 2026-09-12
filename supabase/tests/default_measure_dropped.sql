-- pgTAP: the retired default-measure machinery is gone (0042).
--
-- ADR-0015 moved "what does a bare count mean" onto the row as a number
-- (`piece_basis_amount`); 0023's pointer column, its own-measure trigger, its
-- partial index and its frozen-curation backfill were kept for one release
-- and then dropped. This suite is the negative space: none of it exists, and
-- the one function that used to carry the pointer into a fresh household
-- still exists without it.
begin;
select plan(6);

select hasnt_column('public', 'ingredient', 'default_measure_id',
  'ingredient.default_measure_id is dropped');
select hasnt_index('public', 'ingredient', 'ingredient_default_measure_idx',
  'its partial index is dropped');
select hasnt_trigger('public', 'ingredient', 'ingredient_default_measure_own',
  'the own-measure trigger is dropped');
select hasnt_function('public', 'ingredient_default_measure_is_own',
  'the trigger function is dropped');
select hasnt_function('public', 'ingredient_default_measure_backfill',
  'the frozen-curation backfill is dropped');
select has_function('public', 'ensure_onboarded',
  'ensure_onboarded() survives, without the carry');

select finish();
rollback;
