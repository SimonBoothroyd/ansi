-- 0029_usda_search_ranking.sql — the USDA leg becomes a search, and stops
-- guessing on its own (plan 0029's C-lane, finished on the server side).
--
-- The app half already landed: `enrichFromUsda` has no callers, the sheet's
-- "Fill it in from ▸ Look up in USDA" opens the short-list, and the query is
-- taken from the NAME IN THE FIELD rather than the stored row (which is what
-- retired F1). Every USDA fill now has a human pick in the middle of it.
--
-- Two things were left behind by that change, and this migration is both.
--
-- ## 1. The server was still guessing
--
-- `ingredient_usda_prefill` (0014/0015, body in 0016/0027) is an AFTER INSERT
-- OR UPDATE OF canonical_name trigger, and it was still armed. A bare stub
-- created by the new flow — one where the person deliberately did NOT use the
-- search — still uploaded, fired the trigger, and came back filled:
--
--     canonical_name       source           source_label   score  density
--     Zztest Broccoli Raw  usda_fdc:170379  Broccoli, raw  1.000  0.3846
--
-- That is the exact behaviour the redesign removed from the client, arriving
-- one sync round trip later and with nothing on screen expecting it. It is
-- worse-shaped than before, not better: no client path now re-reads the row
-- because of it, and the provenance card would report "Filled from USDA · not
-- confirmed" for a match that has no human anywhere in its history. It also
-- fired on RENAME, so renaming a bare stub silently re-matched it.
--
-- The trigger and its function go. Nothing replaces them: a stub with no
-- macros is a perfectly good stub, and D5 always said confirming is a human
-- act — this just makes *matching* one too.
--
-- ## 2. The search it opens was empty a third of the time
--
-- Removing the silent fill put the whole weight of the feature on
-- `probe_usda`, which was unchanged: plain trigram `similarity()` with a 0.5
-- floor. Measured against the 267 curated (match_text → fdc_id) pairs in
-- seed_prefill.sql — a hand-labelled gold set — the sheet showed:
--
--     97 of 267 queries ...... NOTHING AT ALL
--     average rows offered ... 1.28 of a possible 5
--     right row visible in 5 . 46%
--
-- `apple`, `black rice` and `olive oil` all opened a blank sheet. `black
-- rice` is the design board's own worked example.
--
-- The cause is that `similarity()` is Jaccard over trigram sets — symmetric,
-- normalised by the UNION — so it asks "are these the same string?", not
-- "is this row about this query". A one-word query cannot score well against
-- a nine-word description: `similarity('apple', 'apple with skin include
-- food for usda food distribution program raw')` is nowhere near 0.5. It is
-- a string-distance function that was being used as a relevance ranker.
--
-- ## What replaces it
--
-- Retrieve on shared tokens, rank with BM25 — the standard split. `match_text`
-- is already normalised and singularised by the app's phrase normalizer (D6),
-- so it tokenises on spaces with no stemming needed.
--
--   * **BM25** (k1=1.2, b=0.75) over the query's matched terms. IDF is what
--     makes this work where the trigram could not: `raw` (df 1562), `fat`
--     (1550) and `with` (1266) carry almost nothing, while `apple` (99) and
--     `kale` (8) carry the signal. The corpus is static and generated, so the
--     document frequencies are precomputed rather than guessed at.
--   * **Normalised by the query's own idf mass**, so the number means the
--     same thing for every query. Raw BM25 is not comparable across queries
--     and therefore cannot carry a threshold; this can.
--   * **A head-noun bonus.** USDA's inverted naming puts the food itself at
--     token 0 — `Apples, raw` → `apple raw` — so a row whose FIRST token is
--     one the person typed is about that food rather than merely mentioning
--     it. Worth separating `Apples, raw` from `Strudel, apple`.
--   * **A processed-form penalty.** A bare "banana" means the raw one; the
--     corpus is full of dehydrated, fried, canned and floured variants. A doc
--     token naming a transformation the query did NOT ask for costs 0.2.
--     This is the single largest error family in the measurement.
--
-- Held out on half the gold set and reported on the other half, so the
-- weights are not tuned on what they are scored against. They also sit on a
-- broad plateau — nine grid points tie at the top — so this is robust rather
-- than delicately fitted.
--
--     queries showing nothing ....... 97/267 → 3/267
--     average rows offered .......... 1.28  → 5
--     right row visible in 5 ........ 46%   → 83%
--     ... in 10 ..................... —     → 89.5%
--     top-1 (held out) .............. 31.1% → 52.3%
--
-- Measured and NOT adopted, so they are not re-tried: idf-weighted
-- containment (no gain — it fixes `sea salt` → *Sea cucumber* but breaks
-- long-but-correct rows like `apple`), RRF fusion with `word_similarity`
-- (46% vs 53%; fusion needs comparably strong rankers and word_similarity
-- alone scores 39%), AND-then-OR coverage tiering (exactly zero change), and
-- a branded-row penalty (redundant once tokens are de-duplicated per doc —
-- branded rows were winning by REPEATING their head noun, which is also why
-- the token table below is deduplicated: counting `banana` twice in
-- "Bananas, dehydrated, or banana powder" was worth six top-1 errors).
--
-- ## Two things this deliberately does not do
--
-- **No floor.** The 0.5 minimum existed to decide whether to WRITE without
-- asking. Nothing writes without asking any more, so there is nothing for a
-- floor to gate — and an empty sheet is a worse dead end than a mediocre row
-- the person can see and reject.
--
-- **No backfill.** Rows already stamped `usda_fdc:<id>` by the old trigger
-- keep their values, their labels and their scores. They are real data
-- somebody may have confirmed; re-matching them under a new ranker would
-- overwrite human decisions to make a number look tidier.
--
-- Reset-safe: guarded CREATEs, DROP IF EXISTS + CREATE for the function whose
-- body changes, explicit grants. Additive and row-preserving.

-- ---------------------------------------------------------------------------
-- 1. The search index — derived from usda_food, never synced.
-- ---------------------------------------------------------------------------
--
-- ADR-0005 covers these exactly as it covers `usda_food`: they are a
-- re-shaping of the same server-only reference set, so they are granted to no
-- client role and reached only through the security-definer probe.

create table if not exists usda_search_token (
  fdc_id int  not null references usda_food(fdc_id) on delete cascade,
  tok    text not null,
  pos    int  not null,          -- earliest position; 1 is the head noun
  primary key (fdc_id, tok)      -- deduplicated: match_text is a BAG of
);                               -- descriptors, a repeat is not more relevance

create index if not exists usda_search_token_tok on usda_search_token(tok);

create table if not exists usda_search_term (
  tok text primary key,
  df  int  not null,
  idf real not null
);

create table if not exists usda_search_doc (
  fdc_id int primary key references usda_food(fdc_id) on delete cascade,
  dl     int not null             -- distinct token count
);

-- One row. Keeps avgdl out of the function body so a re-seeded corpus of a
-- different shape does not silently rank against a stale constant.
create table if not exists usda_search_stats (
  only_row    bool primary key default true check (only_row),
  n_docs      int  not null,
  avg_doc_len real not null
);

revoke all on usda_search_token, usda_search_term, usda_search_doc,
              usda_search_stats from public;
revoke all on usda_search_token, usda_search_term, usda_search_doc,
              usda_search_stats from anon, authenticated;

comment on table usda_search_token is
  'Deduplicated tokens of usda_food.match_text with the earliest position of '
  'each (plan 0029). Server-only, like its source (ADR-0005). Rebuilt by '
  'usda_rebuild_search_index() -- see supabase/seed_usda_index.sql.';
comment on table usda_search_term is
  'Document frequency and BM25 idf per token over usda_food (plan 0029). The '
  'reason the ranker beats the trigram it replaced: "raw" and "with" are '
  'near-worthless, "apple" and "kale" are not.';

-- ---------------------------------------------------------------------------
-- 2. Rebuilding it.
-- ---------------------------------------------------------------------------
--
-- Migrations run BEFORE seeds (config.toml), so on a fresh `db reset` this
-- populates nothing and `supabase/seed_usda_index.sql` calls it again once
-- seed_usda.sql has loaded the reference set. On an existing database — cloud
-- included — the call at the end of this file fills it immediately.
--
-- Idempotent: truncate and rebuild. It is ~60k rows over 8.2k documents, so
-- it costs well under a second and there is no incremental path worth the
-- complexity of keeping correct.
create or replace function usda_rebuild_search_index()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  n int;
begin
  truncate usda_search_token, usda_search_term, usda_search_doc, usda_search_stats;

  insert into usda_search_token (fdc_id, tok, pos)
  select f.fdc_id, t.tok, min(t.pos)
    from usda_food f,
         unnest(string_to_array(f.match_text, ' ')) with ordinality as t(tok, pos)
   where t.tok <> ''
   group by f.fdc_id, t.tok;

  insert into usda_search_doc (fdc_id, dl)
  select fdc_id, count(*) from usda_search_token group by fdc_id;

  select count(*) into n from usda_search_doc;

  -- BM25 probabilistic idf, floored at zero so a token present in nearly
  -- every document contributes nothing rather than scoring negatively.
  insert into usda_search_term (tok, df, idf)
  select tok, count(*),
         greatest(ln((n - count(*) + 0.5) / (count(*) + 0.5) + 1.0), 0.0)
    from usda_search_token group by tok;

  insert into usda_search_stats (only_row, n_docs, avg_doc_len)
  select true, n, coalesce(avg(dl), 1.0) from usda_search_doc;

  analyze usda_search_token;
  analyze usda_search_term;
  analyze usda_search_doc;
end;
$$;

revoke execute on function usda_rebuild_search_index() from public;
revoke execute on function usda_rebuild_search_index() from anon, authenticated;

comment on function usda_rebuild_search_index() is
  'Rebuilds the usda_search_* index from usda_food (plan 0029). Run it after '
  'ANY change to the reference set -- seed_usda_index.sql does so at seed '
  'time, and docs/cloud-setup.md lists it in the cloud seed order. A stale '
  'index degrades search silently, which is the failure this plan exists to '
  'remove, so prefer re-running it over reasoning about whether you need to.';

-- ---------------------------------------------------------------------------
-- 3. The probe, re-ranked.
-- ---------------------------------------------------------------------------
--
-- Same name, same signature, same columns, same total order shape
-- (`score desc, fdc_id asc`) so every caller is unchanged. DROP + CREATE
-- because the body changes substantially; the return type does not.
--
-- `score` is the reported CONFIDENCE, not the sort key: it is the query's
-- idf-weighted coverage, which is 0..1 and means "how much of what you asked
-- for does this row account for". Ranking uses the full composite below,
-- which is unbounded and not comparable to the old trigram number. Keeping
-- the reported score on 0..1 is what lets `ingredient.source_score` (0027)
-- and the band word that reads it keep working without a second migration.
--
-- NB for whoever revisits that band: it was written to warn that a MACHINE
-- chose ("close match" ≥ 0.85, "a guess" below). A human picks now, so the
-- warning is largely redundant, and coverage rarely falls below 0.85 for a
-- single-word query. Retiring it is a copy decision for the board, not
-- something this migration should take.
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
    -- distinction a recipe cares about, and it is auditable.
    select a.fdc_id, count(*) as n
      from agg a
      join usda_search_token t on t.fdc_id = a.fdc_id
     where t.tok in ('cooked','boiled','fried','frozen','dehydrated','juice',
                     'flour','oil','powder','sweetened','prepared','roasted',
                     'extract','sauce','spread','cream','syrup','puree',
                     'concentrate','blanched','steamed','baked','sliced')
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

-- `probe_usda(name, "limit")` — the PostgREST door — is NOT recreated. Its
-- body is `select * from usda_probe(lower(btrim(name)), least(greatest(
-- "limit",1),10))`, plpgsql resolves the callee at run time, and neither the
-- signature nor the column list changed. It keeps its 0027 grant.

-- ---------------------------------------------------------------------------
-- 4. The silent prefill goes.
-- ---------------------------------------------------------------------------
--
-- Order matters: the trigger references the function.
drop trigger if exists ingredient_usda_prefill on ingredient;
drop function if exists ingredient_prefill_from_usda();

-- `usda_declined` (0027 U-D2) is left in place. It was created so a RENAME
-- could not re-fill a row somebody had refused; nothing re-fills anything
-- now, but the value is also how a person says "this is not from USDA" after
-- unlinking a pick, and rows in the wild already carry it. Retiring it is a
-- separate, data-touching decision.

-- ---------------------------------------------------------------------------
-- 5. Build the index for databases that already hold the reference set.
-- ---------------------------------------------------------------------------
--
-- No-op on a fresh `db reset` (usda_food is still empty at migration time);
-- seed_usda_index.sql runs it again after the seed. On cloud, where the
-- reference set is already loaded, this is the build.
select usda_rebuild_search_index();
