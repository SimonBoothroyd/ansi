-- 0030_usda_search_hardening.sql — the search index gets the posture it claims,
-- and two rules that cannot fire are removed.
--
-- Three unrelated-looking edits, all of them about the same thing: the USDA
-- side saying what is actually true.
--
-- **RLS on the four `usda_search_*` tables.** 0029 created them, revoked every
-- client grant, and said in its own header that ADR-0005 "covers these exactly
-- as it covers `usda_food`". It does not, quite: `usda_food` is both revoked
-- AND `enable row level security` (0002), and the house rule is both — RLS
-- filters, GRANTs gate, and a table with only one of them is one careless
-- `grant` away from being readable. Nothing changes for any caller: no policy
-- exists, so RLS denies every row to every non-superuser role, and the probe
-- reads them as SECURITY DEFINER (owner) as it already did. It also stops
-- `docs/generated/db-schema.md` rendering four tables as **RLS not enabled**.
--
-- **`usda_match_trgm` goes.** The GIN trigram index on `usda_food.match_text`
-- existed for the one indexed `%` probe that 0016 and 0014 ran. 0029 replaced
-- that probe with BM25 over `usda_search_token`, and dropped the prefill
-- trigger outright, so nothing has read this index since. It is 8.2k rows of
-- index maintained for no reader, re-written on every reseed. The sibling
-- indexes on `ingredient` and `ingredient_alias` stay: the live import cascade
-- still runs `%` against both.
--
-- **`sliced` leaves the processed-form penalty.** `usda_probe` demotes a
-- document carrying a transformation the query did not ask for, and `sliced`
-- is on that list — but `sliced` is a PREP VERB in the shared normalizer, so
-- it is stripped from every `usda_food.match_text` before the index is built
-- and can never appear as a token. The entry reads as tuned and is dead. Its
-- near-neighbour `slice` is deliberately NOT added in its place: it is a
-- legitimate count-measure noun a person may genuinely be searching for
-- (`unit_hints.ts` hands it to the extractor as one), and demoting it would be
-- a new ranking decision, not a repair. Every other token on the list survives
-- normalization. The measured 0029 numbers are unaffected — a term with zero
-- occurrences contributed nothing to any score.
--
-- The function is dropped and recreated because plpgsql bodies cannot be
-- patched in place; `probe_usda`, the PostgREST door, resolves its callee at
-- run time and is untouched, exactly as in 0029. The revokes are re-applied
-- because a CREATE starts from default privileges.
--
-- Reset-safe and idempotent: `if exists` on the drop, `enable row level
-- security` is a no-op when already on, DROP + CREATE for the function. No row
-- is read or written.

begin;

-- ---------------------------------------------------------------------------
-- 1. RLS on the derived search index (deny-all, like usda_food).
-- ---------------------------------------------------------------------------

alter table usda_search_token  enable row level security;
alter table usda_search_term   enable row level security;
alter table usda_search_doc    enable row level security;
alter table usda_search_stats  enable row level security;

-- ---------------------------------------------------------------------------
-- 2. The trigram index nothing reads any more.
-- ---------------------------------------------------------------------------

drop index if exists usda_match_trgm;

-- ---------------------------------------------------------------------------
-- 3. usda_probe, minus the dead `sliced` penalty.
-- ---------------------------------------------------------------------------

drop function if exists usda_probe(text, int);

create function usda_probe(p_match_text text, p_limit int default 5)
returns table (
  fdc_id           int,
  description      text,
  category         text,
  density_g_per_ml numeric,
  macros           jsonb,
  score            real,
  source           text
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  k1     constant real := 1.2;   -- BM25 term saturation
  b      constant real := 0.75;  -- BM25 length normalisation
  w_head constant real := 0.35;  -- head-noun (token 0) bonus
  w_proc constant real := 0.2;   -- per unasked-for transformation token
  avgdl  real;
begin
  if p_match_text is null or btrim(p_match_text) = '' then
    return;
  end if;

  select avg_doc_len into avgdl from usda_search_stats;
  if avgdl is null or avgdl <= 0 then
    -- The index has never been built. Say so rather than quietly returning
    -- an empty short-list, which is indistinguishable from "no such food".
    raise exception
      'usda_search index is empty — run select usda_rebuild_search_index()';
  end if;

  return query
  with q as (
    select distinct tok
      from unnest(string_to_array(lower(btrim(p_match_text)), ' ')) tok
     where tok <> ''
  ),
  qm as (
    -- coalesce: a query made only of tokens the corpus has never seen still
    -- divides safely, and matches nothing anyway.
    select coalesce(sum(t.idf), 0.0001) as qmass
      from q join usda_search_term t on t.tok = q.tok
  ),
  agg as (
    select tk.fdc_id,
           sum(t.idf)                                as matched,
           max(case when tk.pos = 1 then 1 else 0 end) as head
      from q
      join usda_search_token tk on tk.tok = q.tok
      join usda_search_term  t  on t.tok  = q.tok
     group by tk.fdc_id
  ),
  proc as (
    -- Transformations the person did not ask for. Deliberately a short,
    -- readable list rather than a cleverer rule: it is the raw-vs-prepared
    -- distinction a recipe cares about, and it is auditable. Every token here
    -- has to survive the shared normalizer to reach an index row — a prep verb
    -- (sliced, chopped, grated…) never does.
    select a.fdc_id, count(*) as n
      from agg a
      join usda_search_token t on t.fdc_id = a.fdc_id
     where t.tok in ('cooked','boiled','fried','frozen','dehydrated','juice',
                     'flour','oil','powder','sweetened','prepared','roasted',
                     'extract','sauce','spread','cream','syrup','puree',
                     'concentrate','blanched','steamed','baked')
       and t.tok not in (select tok from q)
     group by a.fdc_id
  ),
  scored as (
    select a.fdc_id,
           (a.matched / (select qmass from qm))::real as coverage,
           ( a.matched * (k1 + 1)
             / (1 + k1 * (1 - b + b * d.dl / avgdl))
             / (select qmass from qm)
             + w_head * a.head
             - w_proc * coalesce(pr.n, 0)
           )::real as rank_score
      from agg a
      join usda_search_doc d on d.fdc_id = a.fdc_id
      left join proc pr on pr.fdc_id = a.fdc_id
  )
  select f.fdc_id,
         f.description,
         f.category,
         f.density_g_per_ml,
         f.macros,
         least(s.coverage, 1.0)::real,
         'usda_fdc:' || f.fdc_id::text
    from scored s
    join usda_food f on f.fdc_id = s.fdc_id
   order by s.rank_score desc, f.fdc_id asc
   limit greatest(coalesce(p_limit, 1), 1);
end;
$$;

comment on function usda_probe(text, int) is
  'The USDA search (plan 0029, replacing the trigram probe of 0016/0027): '
  'BM25 over usda_search_*, normalised by the query''s own idf mass, plus a '
  'head-noun bonus and a penalty for transformations the query did not ask '
  'for. No floor -- the 0.5 minimum existed to gate a silent write, and '
  'nothing writes without a human pick any more. Ordered totally by '
  '(rank_score desc, fdc_id asc); the returned `score` is the query''s '
  'coverage (0..1), reported as confidence, not the sort key. SECURITY '
  'DEFINER so it can read the server-only reference set without exposing it; '
  'clients go through probe_usda().';

revoke execute on function usda_probe(text, int) from public;
revoke execute on function usda_probe(text, int) from anon, authenticated;

commit;
