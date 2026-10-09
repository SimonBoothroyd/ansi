// The rows a recipe's share page renders from, for one live token.
//
// One query, as service role, by token alone. It answers only when the token
// names a live share of a live recipe in the share's own household, and it
// reaches the recipe's sub-recipes through their component lines — each
// once, never outside that household, never round a cycle.
//
// The payload is the database's own rows with the recipe page's aliases
// (`app/lib/features/recipes/domain/recipe_rows.dart` reads them, as the app
// reads its SQLite). Its contract by example is
// `app/test/features/share/testdata/share_payload.json`. Only what a cook
// needs leaves the database: no prices, no book, no household.

/** Runs one parameterised statement; the shape `_shared/match_db.ts` uses. */
export type SqlExecutor = <T = Record<string, unknown>>(
  text: string,
  params: unknown[],
) => Promise<T[]>;

/** 22 url-safe characters: the shape `share_recipe()` mints (0054). */
export const TOKEN_SHAPE = /^[A-Za-z0-9_-]{22}$/;

export const PAYLOAD_SQL = `
with recursive share as (
  select s.recipe_id, s.household_id
    from recipe_share s
    join recipe r
      on r.id = s.recipe_id
     and r.household_id = s.household_id
     and r.deleted_at is null
   where s.token = $1
     and s.deleted_at is null
),
reach (id, depth, path) as (
  select recipe_id, 0, array[recipe_id] from share
  union all
  select li.sub_recipe_id, reach.depth + 1, reach.path || li.sub_recipe_id
    from reach
    join ingredient_group g
      on g.recipe_id = reach.id and g.deleted_at is null
    join recipe_line_item li
      on li.group_id = g.id and li.deleted_at is null
    join recipe sub
      on sub.id = li.sub_recipe_id
     and sub.deleted_at is null
     and sub.household_id = (select household_id from share)
   where li.sub_recipe_id <> all (reach.path)
),
ids as (select id, min(depth) as depth from reach group by id)
select json_build_object(
  'recipes', (
    select coalesce(json_agg(json_build_object(
      'id', r.id, 'title', r.title, 'servings_base', r.servings_base,
      'steps', r.steps,
      'cook_time_seconds', r.cook_time_seconds,
      'total_time_seconds', r.total_time_seconds,
      'yield_qty', r.yield_qty, 'yield_unit', r.yield_unit,
      'yield_qty_2', r.yield_qty_2, 'yield_unit_2', r.yield_unit_2
    ) order by ids.depth, r.title, r.id), '[]'::json)
      from recipe r join ids on ids.id = r.id
  ),
  'groups', (
    select coalesce(json_agg(json_build_object(
      'id', g.id, 'recipe_id', g.recipe_id, 'name', g.name
    ) order by g.sort_order, g.created_at), '[]'::json)
      from ingredient_group g join ids on ids.id = g.recipe_id
     where g.deleted_at is null
  ),
  'lines', (
    select coalesce(json_agg(json_build_object(
      'id', li.id, 'group_id', li.group_id,
      'ingredient_id', li.ingredient_id, 'sub_recipe_id', li.sub_recipe_id,
      'quantity', li.quantity, 'unit', li.unit,
      'recipe_measure_id', li.recipe_measure_id,
      'optional', li.optional, 'note', li.note, 'measure_id', li.measure_id,
      'ingredient_name', ing.canonical_name,
      'ingredient_basis', ing.macros_basis,
      'ingredient_macros', ing.macros,
      'ingredient_density', ing.density_g_per_ml,
      'ingredient_piece_weight', ing.piece_basis_amount,
      'ingredient_status', ing.status,
      'ingredient_deleted_at', ing.deleted_at,
      'measure_label', im.label, 'measure_amount', im.basis_amount,
      'measure_sort', im.sort_order, 'measure_source', im.source,
      'measure_deleted_at', imx.deleted_at,
      'sub_title', sub.title,
      'sub_yield_qty', sub.yield_qty, 'sub_yield_unit', sub.yield_unit,
      'sub_yield_qty_2', sub.yield_qty_2, 'sub_yield_unit_2', sub.yield_unit_2
    ) order by li.sort_order, li.created_at), '[]'::json)
      from recipe_line_item li
      join ingredient_group g
        on g.id = li.group_id and g.deleted_at is null
      join ids on ids.id = g.recipe_id
      left join ingredient ing
        on ing.id = li.ingredient_id and ing.household_id = li.household_id
      left join ingredient_measure im
        on im.id = li.measure_id and im.deleted_at is null
      left join ingredient_measure imx on imx.id = li.measure_id
      left join recipe sub
        on sub.id = li.sub_recipe_id
       and sub.deleted_at is null
       and sub.household_id = li.household_id
     where li.deleted_at is null
  ),
  'recipe_measures', (
    select coalesce(json_agg(json_build_object(
      'id', rm.id, 'recipe_id', rm.recipe_id, 'label', rm.label,
      'amount', rm.amount, 'unit', rm.unit, 'sort_order', rm.sort_order,
      'created_at', rm.created_at
    )), '[]'::json)
      from recipe_measure rm join ids on ids.id = rm.recipe_id
     where rm.deleted_at is null
  )
)::text as payload
where exists (select 1 from share)
`;

/**
 * The payload for [token] as JSON text, or null when the token names nothing
 * live — revoked, never minted, or its recipe deleted. A token of the wrong
 * shape never reaches the database.
 */
export async function loadSharePayload(
  exec: SqlExecutor,
  token: string,
): Promise<string | null> {
  if (!TOKEN_SHAPE.test(token)) return null;
  const rows = await exec<{ payload: string }>(PAYLOAD_SQL, [token]);
  return rows[0]?.payload ?? null;
}
