-- 0027_usda_source_label.sql — the USDA match, said out loud (exec plan 0027
-- front U; board section "The USDA match · shown, undone, re-chosen",
-- rulings U-D1 / U-D2 / U-D3 / U-D5).
--
-- Owner report #3: "show what the exact match was, and let the user undo".
-- A bare stub is prefilled on insert and on rename by the 0014/0015 trigger
-- and, since 0016, by the app's `applyUsdaProbe` — both writing density +
-- macros and stamping `source = 'usda_fdc:<id>'`. The probe returned
-- `fdc_id · density · macros · score · source` and no description, so the
-- phone could name the FDC id and nothing a person recognises. Three moves:
--
-- 1. **Two columns on `ingredient`** (U-D1): `source_label` — the
--    `usda_food.description` the prefill copied from — and `source_score` —
--    the trigram score that earned it. Both are written by BOTH prefill
--    writers in the same statement that stamps `source`, so a row never
--    carries a stamp without the name behind it. The score rides along
--    because the band word the form prints ("close match" at ≥ 0.85, "a
--    guess" below — the import's own bands) is a function of the score, the
--    row did not carry one, and the two alternatives are worse: asking
--    `probe_usda` when the form opens is online-only on an offline-first
--    screen (and after a rename would name a different food than the one
--    that filled the row — the board rejected it), and re-deriving a trigram
--    similarity on the phone is a second matcher under invariant 1. `real`,
--    matching `similarity()`'s return type.
--
-- 2. **The probe widened** (U-D1 / U-D3): `usda_probe` returns `description`
--    and `category` and takes a `p_limit` (default 1, so the trigger is
--    unchanged), ordered by the same total order as before — `(score desc,
--    fdc_id asc)` — so "the next five" are exactly the rows the trigger would
--    have picked had the first not existed. `probe_usda(name, "limit")` is
--    the client door, capped at ten: the reference set is still not
--    browsable through it (ADR-0005), it is now a short-list rather than a
--    single answer.
--
-- 3. **`usda_declined`** (U-D2): a new `source` value the app writes when a
--    person says *Not this food* — density and macros cleared, the stamp
--    replaced. No schema change is needed for it: the 0015 trigger's WHEN
--    clause lists the sources it may refill (`null · manual · import_stub`)
--    and `usda_declined` is deliberately not among them, so a rename never
--    re-fills a row someone refused once. (Resetting to `manual` instead
--    would re-arm the refill — you would decline the same food twice.)
--    `source_label` SURVIVES the decline: the form names the food that was
--    refused. The pgTAP block in tests/unit_admission.sql pins all of this.
--
-- Nothing here promotes a row (U-D4): the trigger's `status = 'stub'` guard
-- and the app's apply are unchanged in that respect — confirming stays a
-- human act (plan 0020 D5). RLS unchanged: the household-scoped UPDATE
-- policy already covers the new columns. Sync: both sync-rules files select
-- `*` from `ingredient`, so the columns ride down without a rule change;
-- `schema.dart` gains the two matching client columns.
--
-- Additive and row-preserving (docs/cloud-setup.md §2c): every existing row
-- reads null for both, which is the truth — nothing named those matches.
-- Reset-safe: guarded ALTERs, DROP IF EXISTS + CREATE for the two functions
-- whose signatures change (CREATE OR REPLACE cannot change a return type),
-- CREATE OR REPLACE for the trigger function, explicit grants.

-- ---------------------------------------------------------------------------
-- 1. The columns.
-- ---------------------------------------------------------------------------

alter table ingredient add column if not exists source_label text;
alter table ingredient add column if not exists source_score real;

comment on column ingredient.source_label is
  'The usda_food.description the USDA prefill copied from (plan 0027 U-D1). '
  'Written with source = ''usda_fdc:<id>'' by the prefill trigger and by the '
  'app''s applyUsdaProbe, in the same statement. Survives a decline (source '
  '= ''usda_declined'') so the form can name the food that was refused. '
  'Null on rows filled before 0027 and on rows nothing filled.';

comment on column ingredient.source_score is
  'The trigram similarity (0.5–1) that earned the USDA match named in '
  'source_label — stored so the band word (close match ≥ 0.85, a guess '
  'below) is readable offline. Shown, never acted on. Null where the label '
  'is null.';

-- ---------------------------------------------------------------------------
-- 2. The probe, widened: description + category, and a limit.
-- ---------------------------------------------------------------------------
--
-- Same SECURITY DEFINER / pinned search_path shape as 0016, for the same
-- reason: `usda_food` is granted to no client role. DROP + CREATE rather than
-- CREATE OR REPLACE because the return type changes. The trigger function
-- below is plpgsql and resolves the name at call time, so it is unaffected
-- by the drop; it is re-created anyway to write the new columns.
drop function if exists usda_probe(text);

create function usda_probe(p_match_text text, p_limit int default 1)
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
  -- The prefill floor — 0016's, unmoved. The only home of this number.
  min_score constant numeric := 0.5;
begin
  if p_match_text is null or btrim(p_match_text) = '' then
    return;
  end if;

  -- One indexed probe, the same total order as 0016 — (score desc, fdc_id
  -- asc) — so the first row is what the trigger copies and the rows after
  -- it are, in order, what it would have copied had each earlier one not
  -- existed. A limit below 1 reads as 1 rather than as "nothing".
  return query
    select f.fdc_id,
           f.description,
           f.category,
           f.density_g_per_ml,
           f.macros,
           similarity(f.match_text, p_match_text) as score,
           'usda_fdc:' || f.fdc_id::text
      from usda_food f
     where f.match_text % p_match_text
       and similarity(f.match_text, p_match_text) >= min_score
     order by similarity(f.match_text, p_match_text) desc, f.fdc_id asc
     limit greatest(coalesce(p_limit, 1), 1);
end;
$$;

comment on function usda_probe(text, int) is
  'The USDA trigram probe (ADR-0005; plan 0020 D7/D7b, widened by plan 0027 '
  'U-D1/U-D3): the best p_limit candidates (default 1) for a match_text, '
  'clearing the 0.5 floor, ordered totally by (score, fdc_id), each with its '
  'description and category so the app can NAME the match. SECURITY DEFINER '
  'so it can read the server-only usda_food without exposing it. One '
  'implementation, two callers — the ingredient prefill trigger and the '
  'probe_usda() RPC. Granted to no client role: clients go through '
  'probe_usda().';

revoke execute on function usda_probe(text, int) from public;
revoke execute on function usda_probe(text, int) from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. The trigger function, now writing the label and the score.
-- ---------------------------------------------------------------------------
--
-- 0016's body with two more columns in the SET list. Everything that made it
-- safe is unchanged: one probe, every error swallowed so a client upload can
-- never fail because of it, fill-null-only on density/macros, and the row
-- STAYS 'stub'. The trigger itself (0015's `after insert or update of
-- canonical_name`, with 0014's WHEN guards) is NOT recreated — it already
-- points at this name, and its WHEN clause is exactly what U-D2 relies on:
-- `source in ('manual', 'import_stub')` (or null) does not include
-- 'usda_declined', so a declined row is never re-probed.
create or replace function ingredient_prefill_from_usda()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  hit record;
begin
  begin
    select * into hit from usda_probe(new.match_text);

    if hit.fdc_id is null then
      return null;                         -- no confident hit
    end if;
    if hit.density_g_per_ml is null and hit.macros is null then
      return null;                         -- nothing to copy; don't churn source
    end if;

    -- The label and the score land in the SAME statement as the stamp: a
    -- row never says "usda_fdc:<id>" without being able to say which food
    -- and how sure. The density landing here still fires
    -- ingredient_density_unlocks_units (0014).
    update ingredient
       set density_g_per_ml = coalesce(hit.density_g_per_ml, density_g_per_ml),
           macros           = coalesce(hit.macros, macros),
           source           = hit.source,
           source_label     = hit.description,
           source_score     = hit.score,
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
  'from the server-only usda_food reference (ADR-0005; plan 0020 D7). '
  'Delegates the probe to usda_probe(), which the probe_usda() RPC also '
  'reads — one implementation, two callers. Since 0027 it also writes '
  'source_label and source_score beside the usda_fdc:<id> stamp. Runs inside '
  'the client upload transaction: every error swallowed so the upload can '
  'never fail because of it. Fires only for a BARE stub (no density, no '
  'macros) whose source is null, manual or import_stub — never for '
  'usda_declined (plan 0027 U-D2). The row stays status=''stub''.';

-- ---------------------------------------------------------------------------
-- 4. The client door, with a limit.
-- ---------------------------------------------------------------------------
--
-- `name` is still the ingredient's match text (see 0016). `"limit"` — quoted,
-- it is a reserved word, and named this way because it is the JSON key the
-- app sends — defaults to 1 so every existing caller is unchanged, and is
-- capped at ten: this is a short-list for a person to choose from (U-D3, the
-- form asks for five), not a way to page through the reference set.
--
-- WRITES NOTHING, as before: `stable`, no DML, and the only table it touches
-- is one the caller cannot reach on its own.
drop function if exists probe_usda(text);

create function probe_usda(name text, "limit" int default 1)
returns table (
  fdc_id           int,
  description      text,
  category         text,
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
  select * from usda_probe(lower(btrim(name)), least(greatest("limit", 1), 10));
$$;

comment on function probe_usda(text, int) is
  'Plan 0020 D7b, widened by plan 0027 U-D3: the USDA probe as a read-only '
  'RPC. Pass the ingredient''s match_text and, optionally, a limit (default '
  '1, capped at 10). Returns the best candidates'' copyable fields plus '
  'their description and category, ordered as the prefill trigger orders, '
  'and WRITES NOTHING; the caller applies a pick into a bare stub as an '
  'ordinary local write. ADR-0005 holds: usda_food itself is still '
  'unreachable from any client role.';

revoke execute on function probe_usda(text, int) from public;
revoke execute on function probe_usda(text, int) from anon;
grant execute on function probe_usda(text, int) to authenticated;
