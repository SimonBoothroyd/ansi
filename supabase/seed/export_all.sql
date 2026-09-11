-- READ-ONLY. One row per household that is either the template or has a
-- member: its identity plus a full snapshot of its live vocabulary
-- (ingredient + aliases + measures), with the timestamps the edit audit needs.
select h.id, h.name, h.is_template, h.created_at,
       (select count(*) from household_member m
         where m.household_id = h.id and m.deleted_at is null) as members,
       (select jsonb_agg(r order by r->>'match_text') from (
          select jsonb_strip_nulls(jsonb_build_object(
            'id',                 i.id,
            'canonical_name',     i.canonical_name,
            'category',           i.category,
            'default_unit',       i.default_unit,
            'macros_basis',       i.macros_basis,
            'density_g_per_ml',   i.density_g_per_ml,
            'macros',             i.macros,
            'status',             i.status,
            'source',             i.source,
            'source_label',       i.source_label,
            'source_score',       i.source_score,
            'source_edited',      i.source_edited,
            'piece_basis_amount', i.piece_basis_amount,
            'piece_source',       i.piece_source,
            'allowed_units',      i.allowed_units,
            'match_text',         i.match_text,
            'created_at',         i.created_at,
            'updated_at',         i.updated_at,
            'derived_allowed_units', default_allowed_units(
               i.default_unit, i.macros_basis, i.density_g_per_ml, i.category,
               i.piece_basis_amount),
            'aliases', coalesce((
              select jsonb_agg(jsonb_build_object(
                       'alias_text', a.alias_text,
                       'match_text', a.match_text,
                       'source',     a.source,
                       'updated_at', a.updated_at)
                     order by a.alias_text)
              from ingredient_alias a
              where a.ingredient_id = i.id and a.deleted_at is null), '[]'::jsonb),
            'measures', coalesce((
              select jsonb_agg(jsonb_build_object(
                       'id',           m.id,
                       'label',        m.label,
                       'basis_amount', m.basis_amount,
                       'sort_order',   m.sort_order,
                       'source',       m.source,
                       'updated_at',   m.updated_at)
                     order by m.sort_order, m.label)
              from ingredient_measure m
              where m.ingredient_id = i.id and m.deleted_at is null), '[]'::jsonb)
          )) as r
          from ingredient i
          where i.household_id = h.id and i.deleted_at is null
       ) s) as snapshot
from household h
where h.deleted_at is null
  and (h.is_template
       or exists (select 1 from household_member m
                  where m.household_id = h.id and m.deleted_at is null))
order by h.is_template desc, h.created_at;
