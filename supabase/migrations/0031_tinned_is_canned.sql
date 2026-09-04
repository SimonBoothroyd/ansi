-- 0031_tinned_is_canned.sql — a tin is a can, and the stored keys say so.
--
-- The shared normalizer (`functions/_shared/normalize.ts` and its Dart mirror)
-- now folds "tinned" onto "canned" before the state-word step. "tinned" was
-- already the marker that turns a cut word into identity (a can of chopped and
-- a can of crushed are different SKUs), but it was NOT a state word — so it
-- stayed a leading noun while "canned" trailed:
--
--     "canned chickpeas"  -> "chickpea canned"   auto
--     "tinned chickpeas"  -> "tinned chickpea"   suggest, 0.63
--
-- British phrasing cost the auto band on every canned row without a
-- hand-written alias, and the two spellings minted two rows for one shelf
-- product. Both now write "chickpea canned".
--
-- A stored "tinned …" is stranded by that change: the query side no longer
-- produces it, so an exact search misses the row and the next import creates a
-- second one beside it. This rewrites the old form in place.
--
-- **Not a word swap — a re-classification.** "tinned tomato chopped" does not
-- become "canned tomato chopped": the fold moves the word from the noun run
-- into the trailing state run, so the answer is "tomato canned chopped", which
-- is exactly what the normalizer writes for both spellings today. The helper
-- below reproduces that by splitting the stored key at the boundary of its
-- trailing state-word run — states are always a suffix in a stored key — and
-- inserting "canned" at the head of it. The state set is the normalizer's own,
-- plus the two canned-phrase cut words, which are state words in precisely the
-- rows this migration touches. The helper is dropped at the end (0018's
-- precedent) so it cannot drift out from under the normalizer.
--
-- Row-preserving (docs/cloud-setup.md §2c): updates only — no delete, no
-- re-insert. A row keeps its id, and with it its measures, aliases and every
-- recipe line that points at it.
--
-- **Counts, measured on the local stack before this ran.** No `ingredient`
-- row and no `usda_food` row carries the word — the FDC reference set is
-- American and the seeded vocabulary spells it "canned". The hits are all
-- aliases of the template's `Canned Diced Tomatoes`: two per household (its
-- "tinned chopped tomatoes" and "tinned diced tomatoes"), 126 across the 63
-- households the local database had accumulated. On a fresh `db reset` every
-- count is zero — migrations run before the seed, and `gen_seed.ts` no longer
-- emits those two rows at all: under the fold each normalizes onto a key its
-- own ingredient already holds, which is the generator's "already covered"
-- drop. The surface forms stay in `vocab.jsonl` as the words a person writes.
--
-- **Redundant aliases are tombstoned, not rewritten.** That same fold means a
-- rewritten alias can land on the key its ingredient (or a live sibling alias)
-- already holds — for the seeded pair it always does. Rewriting it would break
-- 0020's partial unique index in the template household and, everywhere else,
-- leave a duplicate row saying nothing. Nothing is lost: the surface it
-- covered now reaches the row through the normalizer instead of through the
-- alias, and a tombstone is reversible where a delete is not. This is the same
-- rule `gen_seed.ts` applies when it builds the seed, so a fresh reset and a
-- migrated database agree.
--
-- Idempotent: "canned" does not contain the whole word "tinned", so a second
-- run matches nothing.

begin;

-- The rewrite, as a function so the guard, the update and the notice all read
-- the same rule. Dropped below.
create function tinned_canned_key(mt text) returns text
language plpgsql immutable as $fn$
declare
  -- The normalizer's STATE_WORDS, plus the cut words that are state words
  -- inside a canned phrase — and every row here IS one.
  states constant text[] := array[
    'fresh','ground','dried','dry','frozen','canned','smoked','whole',
    'boneless','skinless','ripe','unsalted','salted','raw','toasted',
    'roasted','powdered','cooked','uncooked','shelled','sweetened',
    'unsweetened','chopped','diced'];
  words   text[] := string_to_array(mt, ' ');
  head    text[] := '{}';
  tail    text[] := '{}';
  n       int    := coalesce(array_length(words, 1), 0);
  cut     int;
  i       int;
begin
  -- Where the trailing state run begins. Walk back while the word is one.
  cut := n + 1;
  for i in reverse n .. 1 loop
    exit when not (words[i] = any(states));
    cut := i;
  end loop;
  for i in 1 .. n loop
    if words[i] = 'tinned' then continue; end if;
    if i < cut then head := head || words[i]; else tail := tail || words[i]; end if;
  end loop;
  -- "tinned canned tomatoes" would otherwise gain a second "canned".
  if 'canned' = any(words) then
    return array_to_string(head || tail, ' ');
  end if;
  return array_to_string(head || 'canned'::text || tail, ' ');
end
$fn$;

do $$
declare
  template constant uuid := '00000000-0000-0000-0000-0000000000aa';
  pattern  constant text := '\mtinned\M';  -- `\m`/`\M` are Postgres ARE word boundaries
  clash text;
  n_ingredient int;
  n_alias_dead int;
  n_alias int;
  n_usda int;
begin
  -- Guard: a template ingredient whose rewritten key is already live. Which of
  -- two real rows should win is an owner's call, not this migration's (0022).
  select string_agg(
           format('ingredient %s "%s" -> "%s" already held by %s',
                  i.id, i.match_text, tinned_canned_key(i.match_text), j.id),
           '; ')
    into clash
    from ingredient i
    join ingredient j
      on j.household_id = template and j.deleted_at is null
     and j.id <> i.id
     and j.match_text = tinned_canned_key(i.match_text)
   where i.household_id = template and i.deleted_at is null
     and i.match_text ~ pattern;
  if clash is not null then
    raise exception '0031: template match_text collision — %', clash;
  end if;

  -- Every household, live and tombstoned alike: a tombstone that comes back
  -- (or is read for its history) should carry the current key too.
  update ingredient
     set match_text = tinned_canned_key(match_text),
         updated_at = now()
   where match_text ~ pattern;
  get diagnostics n_ingredient = row_count;

  -- An alias the fold makes redundant — its rewritten key is one its own
  -- ingredient or a live sibling alias already carries — is tombstoned rather
  -- than rewritten. The surface still reaches the row, through the normalizer.
  update ingredient_alias a
     set deleted_at = now(),
         updated_at = now()
   where a.match_text ~ pattern
     and a.deleted_at is null
     and (exists (select 1 from ingredient i
                   where i.id = a.ingredient_id
                     and i.match_text = tinned_canned_key(a.match_text))
       or exists (select 1 from ingredient_alias b
                   where b.ingredient_id = a.ingredient_id and b.id <> a.id
                     and b.deleted_at is null
                     and b.match_text = tinned_canned_key(a.match_text)));
  get diagnostics n_alias_dead = row_count;

  -- The rest, tombstones included: a dead row read for its history — or
  -- restored — should carry the current key too. The rows tombstoned just
  -- above are rewritten here as well, which is why a second run finds nothing.
  update ingredient_alias
     set match_text = tinned_canned_key(match_text),
         updated_at = now()
   where match_text ~ pattern;
  get diagnostics n_alias = row_count;

  update usda_food
     set match_text = tinned_canned_key(match_text)
   where match_text ~ pattern;
  get diagnostics n_usda = row_count;

  raise notice
    '0031: tinned -> canned: % ingredient, % alias rewritten, % alias '
    'tombstoned as redundant, % usda_food rows',
    n_ingredient, n_alias, n_alias_dead, n_usda;
end $$;

drop function tinned_canned_key(text);

commit;
