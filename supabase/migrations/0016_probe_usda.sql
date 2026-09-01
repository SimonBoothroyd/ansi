-- 0016_probe_usda.sql — the USDA probe, exposed (roadmap step 8.5, exec plan
-- 0020 **D7b**: "enrichment should not wait for sync").
--
-- 0014 landed the probe as the body of an AFTER INSERT trigger and 0015 gave
-- it a rename leg. Both are *server-side reactions to an upload*, which means
-- an ingredient created on a phone is only enriched after a full round trip:
-- write → upload → trigger → sync down. The owner watched that round trip on
-- a real device and ruled it the wrong shape for two flows:
--
--   * **Creation.** A new ingredient should be born enriched when the device
--     is online, not enriched a few seconds later if you are still looking.
--   * **"Look up in USDA".** The button was a *re-read* of the local row —
--     honest about its limits, and useless: it could only report whether the
--     round trip had finished. D7b makes it a real query.
--
-- ADR-0005 is unmoved. `usda_food` still never syncs to a device and is still
-- granted to NO client role (0002). What ships here is a **security-definer
-- function** returning ONE candidate's copyable fields for ONE name — the
-- same row the trigger would have copied, and nothing else. The reference set
-- is not browsable, listable, or dumpable through it.
--
-- Three parts:
--
-- 1. **`usda_probe(match_text)`** — the probe itself, lifted out of the
--    trigger body into a function of its own. This is the same move 0014 made
--    with `density_unlocked_units()`: one stored copy of a rule, read by
--    every caller. It is the ONLY place the 0.5 floor and the total ordering
--    live. Granted to no client role.
--
-- 2. **`ingredient_prefill_from_usda()`** — recreated to call it. Behaviour
--    is unchanged, deliberately and verifiably: same floor, same
--    `(score desc, fdc_id asc)` tie-break, same "nothing to copy" bail, same
--    swallow-and-log so a client's upload can never fail, same rule that the
--    row STAYS `status='stub'` (D5). The pgTAP assertions 0014/0015 already
--    pin run unchanged against this version.
--
-- 3. **`probe_usda(name)`** — the PostgREST door, granted to `authenticated`.
--    **It writes nothing.** The app calls it before or instead of waiting for
--    the trigger, and applies the result into NULL fields of a bare stub as
--    an ordinary local write that syncs up like any other edit.
--
-- **Why the local apply and the trigger may race benignly.** Both are
-- fill-null-only on a bare stub, and both read the same function with the
-- same total ordering, so they compute the *same* candidate for the same
-- text. Two orders are possible and both converge:
--
--   * *App first.* The row is created with density/macros already filled, so
--     the trigger's WHEN clause (`density_g_per_ml is null and macros is
--     null`) is false and it never fires. Nothing to reconcile.
--   * *Trigger first.* The server fills the row during upload while the app's
--     apply lands locally; the app's write then uploads the identical values
--     (same probe, same candidate, same `usda_fdc:<id>` stamp). A PUT of
--     equal values over equal values is a no-op in effect.
--
-- The dangerous shape would be a probe that *overwrote* — then order would
-- decide whose numbers won. It cannot: the app's apply refuses any row that
-- is not a bare stub, exactly as the trigger's WHEN clause does. And neither
-- promotes the row to `complete`; confirming stays a human act (D5).
--
-- Reset-safe: CREATE OR REPLACE / explicit grants only.

-- ---------------------------------------------------------------------------
-- 1. The probe, on its own.
-- ---------------------------------------------------------------------------
--
-- SECURITY DEFINER because it must be: `usda_food` is granted to no client
-- role (0002 — the grant-layer enforcement of ADR-0005), so neither the
-- inserting `authenticated` session nor an RPC caller can read it. Definer
-- rights let this one function read the reference set without exposing it.
--
-- search_path is pinned (SECURITY DEFINER hygiene, as `ensure_onboarded` and
-- 0014's trigger function do) and includes `extensions` so `%`/`similarity()`
-- resolve wherever pg_trgm happens to live (locally `public`; Supabase cloud
-- can place it in `extensions`).
--
-- Returns AT MOST ONE row: the best trigram hit clearing the floor, or
-- nothing. "At most one" is the security property as much as the semantic
-- one — this is not a search endpoint over the reference set.
create or replace function usda_probe(p_match_text text)
returns table (
  -- `int`, matching usda_food.fdc_id (0002) — a widened return type makes
  -- RETURN QUERY reject the row outright ("structure of query does not match
  -- function result type"), which the trigger's swallow would then hide.
  fdc_id           int,
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
  -- Minimum trigram score to accept a prefill. Was USDA_PREFILL_MIN in the
  -- deleted match_db.ts, then a constant inside 0014's trigger body; this is
  -- now its only home, read by both callers.
  min_score constant numeric := 0.5;
begin
  if p_match_text is null or btrim(p_match_text) = '' then
    return;
  end if;

  -- One indexed probe: `%` uses usda_match_trgm (0002), similarity() supplies
  -- the score. The sort is total (score, then fdc_id) so ties in trigram
  -- space resolve the same way on every run, every plan, and — the point of
  -- D7b — on the server and in the app's copy of the answer.
  return query
    select f.fdc_id,
           f.density_g_per_ml,
           f.macros,
           similarity(f.match_text, p_match_text) as score,
           'usda_fdc:' || f.fdc_id::text
      from usda_food f
     where f.match_text % p_match_text
       and similarity(f.match_text, p_match_text) >= min_score
     order by similarity(f.match_text, p_match_text) desc, f.fdc_id asc
     limit 1;
end;
$$;

comment on function usda_probe(text) is
  'The USDA trigram probe (ADR-0005; plan 0020 D7/D7b): at most one candidate '
  'for a match_text, clearing the 0.5 floor, ordered totally by (score, '
  'fdc_id). SECURITY DEFINER so it can read the server-only usda_food without '
  'exposing it. One implementation, two callers — the ingredient prefill '
  'trigger and the probe_usda() RPC. Granted to no client role: clients go '
  'through probe_usda().';

-- No client role reaches the helper directly; `probe_usda` below is the door.
revoke execute on function usda_probe(text) from public;
revoke execute on function usda_probe(text) from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. The trigger, now a caller rather than a copy.
-- ---------------------------------------------------------------------------
--
-- 0014's body verbatim except that the probe is delegated. The trigger itself
-- (0015's `after insert or update of canonical_name`, with 0014's WHEN
-- guards) is NOT recreated here — it already points at this function name.
create or replace function ingredient_prefill_from_usda()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  hit record;
begin
  -- NEVER fail the inserting transaction. This runs inside the client's
  -- PowerSync upload: a stub that cannot be enriched is still a perfectly
  -- good stub, but an upload that rolls back is a sync failure the user
  -- cannot act on. Any error at all is swallowed and logged.
  begin
    select * into hit from usda_probe(new.match_text);

    if hit.fdc_id is null then
      return null;                         -- no confident hit
    end if;
    if hit.density_g_per_ml is null and hit.macros is null then
      return null;                         -- nothing to copy; don't churn source
    end if;

    -- The row STAYS 'stub': the prefill only means the flesh-out form opens
    -- pre-populated. Promotion to 'complete' is a human confirm (plan 0020
    -- D5) — a trigram guess must never walk into a macro total on its own.
    -- The density landing here fires ingredient_density_unlocks_units (0014),
    -- which extends allowed_units accordingly.
    --
    -- Fill-null-only, like the app's D7b apply: the WHEN clause already means
    -- both columns are null on the insert leg, and coalesce keeps the rename
    -- leg honest if that ever loosens.
    update ingredient
       set density_g_per_ml = coalesce(hit.density_g_per_ml, density_g_per_ml),
           macros           = coalesce(hit.macros, macros),
           source           = hit.source,
           updated_at       = now()
     where id = new.id and status = 'stub' and deleted_at is null;
  exception
    when others then
      raise warning
        'ingredient_prefill_from_usda: skipped for % [%] %',
        new.id, sqlstate, sqlerrm;
  end;
  return null;
end;
$$;

comment on function ingredient_prefill_from_usda() is
  'AFTER INSERT OR UPDATE OF canonical_name prefill of a stub ingredient '
  'from the server-only usda_food reference (ADR-0005; plan 0020 D7). Since '
  '0016 it delegates the probe to usda_probe(), which the probe_usda() RPC '
  'also reads — one implementation, two callers. Runs inside the client '
  'upload transaction: every error swallowed so the upload can never fail '
  'because of it. Fires only for a BARE stub (no density, no macros), so a '
  'rename never re-probes a row someone has filled in. The row stays '
  'status=''stub''.';

-- ---------------------------------------------------------------------------
-- 3. The client door.
-- ---------------------------------------------------------------------------
--
-- `p_name` is the ingredient's **match text** — the value the app already
-- computes with its port of the server's phrase normalizer (plan 0020 D6) and
-- stores in `ingredient.match_text`. The lower/btrim here is not a second
-- normalizer pretending to be the first; it only stops a raw name behaving
-- absurdly if a caller passes one. Pass the match text and the RPC and the
-- trigger probe identically, which is what makes the race in the header
-- benign.
--
-- WRITES NOTHING. It is `stable`, it has no INSERT/UPDATE/DELETE, and the
-- only table it touches is one the caller cannot reach on its own.
create or replace function probe_usda(name text)
returns table (
  fdc_id           int,
  density_g_per_ml numeric,
  macros           jsonb,
  score            real,
  source           text
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select * from usda_probe(lower(btrim(name)));
$$;

comment on function probe_usda(text) is
  'Plan 0020 D7b: the USDA probe as a read-only RPC, so a creation flow can '
  'enrich an ingredient at birth and "Look up in USDA" can be a real query '
  'instead of a re-read while the sync round trip finishes. Pass the '
  'ingredient''s match_text. Returns at most one candidate''s copyable '
  'fields and WRITES NOTHING; the caller applies them into NULL fields of a '
  'bare stub as an ordinary local write. ADR-0005 holds: usda_food itself is '
  'still unreachable from any client role.';

revoke execute on function probe_usda(text) from public;
revoke execute on function probe_usda(text) from anon;
grant execute on function probe_usda(text) to authenticated;
