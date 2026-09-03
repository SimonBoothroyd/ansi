-- 0022_singularize_invariants.sql — "molasses" keeps its ending (plan 0023,
-- lane D).
--
-- The shared singularizer (`functions/_shared/normalize.ts` and its Dart
-- mirror) now carries an explicit invariant-word set. "molasses" is singular,
-- but the `-ss/-us/-is/-ous` guard never saw its `-sses` ending and the
-- sibilant rule wrote `molass` — the comment said one thing and the code did
-- another, on both sides. Both mirrors now write `molasses`. A stored
-- `molass` would be stranded: the query side no longer produces it, so an
-- exact search misses the row and the next import mints a second one beside
-- it. This rewrites the old form IN PLACE, whole word by whole word.
--
-- Row-preserving (docs/cloud-setup.md §2c): updates only — no delete, no
-- re-insert. A row keeps its id, and with it its measures, aliases and every
-- recipe line that points at it.
--
-- Affected today: no seeded vocab row (vocab.jsonl carries no molasses),
-- five `usda_food` rows (Molasses and four molasses cookies), and whatever a
-- household typed itself — a "Molasses" stub created in the picker carries
-- `molass`. The generated seed_usda.sql was given the identical whole-word
-- rewrite (the FDC bundles it regenerates from are not committed —
-- seed/README.md), so a fresh `db reset` and a migrated database agree.
--
-- Template guard. 0020's partial unique indexes hold ONE live template row
-- per match_text (ingredient) and per (ingredient, match_text) (alias). A
-- rewrite that would land on an existing live template row is refused here
-- with both rows named, rather than left to the index's bare 23505 — and
-- never skipped or merged, because which of the two rows should win is an
-- owner's call. Households carry no such index (two offline devices may
-- legitimately mint the same stub — 0020), so there the rewrite proceeds and
-- the client coalesces as it already does.
--
-- `updated_at` IS bumped, unlike 0018's diacritic repair: the rule moved on
-- the query side too, so a phone still holding `molass` would miss its own
-- row until the new text reached it. `usda_food` has no updated_at and never
-- syncs.
--
-- Idempotent: `molasses` does not contain the whole word `molass`, so a
-- second run matches nothing. The (old, new) pairs are a values list so the
-- next invariant word is one more row here — in its own migration, since a
-- merged one is immutable.

begin;

do $$
declare
  template constant uuid := '00000000-0000-0000-0000-0000000000aa';
  fix record;
  pattern text;
  clash text;
  n_ingredient int;
  n_alias int;
  n_usda int;
begin
  for fix in
    select * from (values ('molass', 'molasses')) as f(old_word, new_word)
  loop
    -- Whole-word: `\m`/`\M` are Postgres ARE word boundaries, so `molass`
    -- inside `molasses` (or `blackstrap molasses`) is not a hit.
    pattern := '\m' || fix.old_word || '\M';

    -- Guard: a template ingredient whose rewritten key is already live.
    select string_agg(
             format('ingredient %s "%s" -> "%s" already held by %s',
                    i.id, i.match_text,
                    regexp_replace(i.match_text, pattern, fix.new_word, 'g'),
                    j.id),
             '; ')
      into clash
      from ingredient i
      join ingredient j
        on j.household_id = template and j.deleted_at is null
       and j.id <> i.id
       and j.match_text
           = regexp_replace(i.match_text, pattern, fix.new_word, 'g')
     where i.household_id = template and i.deleted_at is null
       and i.match_text ~ pattern;
    if clash is not null then
      raise exception '0022: template match_text collision — %', clash;
    end if;

    -- Guard: a template alias whose rewritten key is already live on the
    -- same ingredient.
    select string_agg(
             format('alias %s "%s" -> "%s" already held by %s on ingredient %s',
                    a.id, a.match_text,
                    regexp_replace(a.match_text, pattern, fix.new_word, 'g'),
                    b.id, a.ingredient_id),
             '; ')
      into clash
      from ingredient_alias a
      join ingredient_alias b
        on b.household_id = template and b.deleted_at is null
       and b.ingredient_id = a.ingredient_id and b.id <> a.id
       and b.match_text
           = regexp_replace(a.match_text, pattern, fix.new_word, 'g')
     where a.household_id = template and a.deleted_at is null
       and a.match_text ~ pattern;
    if clash is not null then
      raise exception '0022: template alias collision — %', clash;
    end if;

    -- Every household, live and tombstoned alike: a tombstone that comes back
    -- (or is read for its history) should carry the current key too.
    update ingredient
       set match_text = regexp_replace(match_text, pattern, fix.new_word, 'g'),
           updated_at = now()
     where match_text ~ pattern;
    get diagnostics n_ingredient = row_count;

    update ingredient_alias
       set match_text = regexp_replace(match_text, pattern, fix.new_word, 'g'),
           updated_at = now()
     where match_text ~ pattern;
    get diagnostics n_alias = row_count;

    update usda_food
       set match_text = regexp_replace(match_text, pattern, fix.new_word, 'g')
     where match_text ~ pattern;
    get diagnostics n_usda = row_count;

    raise notice
      '0022: "%" -> "%": % ingredient, % alias, % usda_food rows rewritten',
      fix.old_word, fix.new_word, n_ingredient, n_alias, n_usda;
  end loop;
end $$;

commit;
