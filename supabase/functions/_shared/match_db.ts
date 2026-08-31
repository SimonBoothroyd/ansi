// Postgres-backed side of the match cascade (lane B) — the parameterized SQL the
// pure cascade in `match.ts` drives, plus the §9 stub lifecycle and §8 learning-loop
// write contracts. Server-side only (ADR-0004): all of this runs in the edge
// function against Postgres via the service role.
//
// DESIGN — in-function parameterized SQL, not a new RPC (per the lane-B charter):
// no DB migration is added here (W0 owns migration numbering). The trigram tier
// uses the `%` operator so the existing GIN indexes from 0002 are used, then
// `similarity()` supplies the score; the bands (match.ts) are applied in TS.
//
// The DB driver is injected as a {@link SqlExecutor} so this module has zero
// external imports (keeps `deno check` hermetic and the contracts unit-testable
// with a fake executor). Wire it in the edge function to your Postgres client,
// e.g. deno-postgres:
//   const exec: SqlExecutor = async (text, params) =>
//     (await client.queryObject({ text, args: params })).rows;
// Placeholders are $1,$2,… (Postgres positional) — the shape deno-postgres and
// postgres.js `unsafe(text, params)` both accept.

import { normalize } from "./normalize.ts";
import type { MatchCandidate } from "./types.ts";
import { TOP_N, type VocabMatcher } from "./match.ts";

/** Minimal, driver-agnostic query seam: positional params in, rows out. */
export type SqlExecutor = <T = Record<string, unknown>>(
  text: string,
  params: unknown[],
) => Promise<T[]>;

// --- Tier 1 + 2: the household-scoped vocab matcher --------------------------

// Exact `match_text` equality across ingredient + alias, one row per distinct
// ingredient. Household-scoped and soft-delete aware (mirrors RLS + spec §5.2).
const EXACT_SQL = `
  select distinct i.id::text as ingredient_id, i.canonical_name, 1.0::float8 as score
  from ingredient i
  where i.household_id = $1 and i.deleted_at is null and i.match_text = $2
  union
  select distinct i.id::text, i.canonical_name, 1.0::float8
  from ingredient_alias a
  join ingredient i on i.id = a.ingredient_id and i.deleted_at is null
  where a.household_id = $1 and a.deleted_at is null and a.match_text = $2`;

// Trigram similarity across ingredient + alias, best score per ingredient,
// score-desc, capped. `% $2` uses the GIN index (0002) and pg_trgm's default
// threshold (0.3) — safely below BAND_SUGGEST_MIN, so no surfaced candidate is
// pruned. See match.ts TRIGRAM_FLOOR.
const TRIGRAM_SQL = `
  select ingredient_id, canonical_name, max(score) as score
  from (
    select i.id::text as ingredient_id, i.canonical_name,
           similarity(i.match_text, $2) as score
    from ingredient i
    where i.household_id = $1 and i.deleted_at is null and i.match_text % $2
    union all
    select i.id::text, i.canonical_name, similarity(a.match_text, $2)
    from ingredient_alias a
    join ingredient i on i.id = a.ingredient_id and i.deleted_at is null
    where a.household_id = $1 and a.deleted_at is null and a.match_text % $2
  ) c
  group by ingredient_id, canonical_name
  order by score desc
  limit $3`;

interface CandidateRow {
  ingredient_id: string;
  canonical_name: string;
  score: number;
}

const toCandidate = (r: CandidateRow): MatchCandidate => ({
  ingredient_id: r.ingredient_id,
  canonical_name: r.canonical_name,
  score: Number(r.score),
});

/**
 * A {@link VocabMatcher} backed by Postgres, bound to one household. Pass to
 * `matchLines`. The `matchText` arguments are already normalized by the cascade.
 */
export function sqlVocabMatcher(
  exec: SqlExecutor,
  householdId: string,
): VocabMatcher {
  return {
    async exact(matchText) {
      const rows = await exec<CandidateRow>(EXACT_SQL, [
        householdId,
        matchText,
      ]);
      return rows.map(toCandidate);
    },
    async trigram(matchText, limit = TOP_N) {
      const rows = await exec<CandidateRow>(TRIGRAM_SQL, [
        householdId,
        matchText,
        limit,
      ]);
      return rows.map(toCandidate);
    },
  };
}

// --- §9: stub lifecycle ------------------------------------------------------

export interface CreateStubArgs {
  householdId: string;
  /** The line's identity AS WRITTEN — becomes canonical_name + normalizes to match_text. */
  ingredientText: string;
  /** Required (ingredient.default_unit is NOT NULL); lane C supplies the picked unit. */
  defaultUnit: string;
}

export interface StubResult {
  ingredient_id: string;
  /** false when an existing import stub with the same match_text was reused. */
  created: boolean;
}

/**
 * The create-new path (§9): write an `ingredient` with `status='stub'`,
 * `source='import_stub'`, density/macros left null (honest numbers — excluded from
 * conversions/totals until a human completes it). Idempotent by (household,
 * match_text) so identical `none` lines in one import coalesce onto one stub (the
 * within-import dedupe boundary in 0014 / §6.4). No silent auto-stub: this is only
 * ever called from a deliberate user create-new action (lane C).
 *
 * CONTRACT NOTE (flagged, not resolved): 0014's CommitPayload also permits stub
 * creation through the PowerSync sync queue (a client insert), "no new tables".
 * This is the SERVER counterpart — the USDA prefill below is unavoidably
 * server-side (usda_food never syncs), so co-locating create + prefill keeps the
 * stub idempotent and immediately prefillable. The tail should pick one surface;
 * both write the same row shape.
 */
export async function createImportStub(
  exec: SqlExecutor,
  args: CreateStubArgs,
): Promise<StubResult> {
  const matchText = normalize(args.ingredientText);
  const existing = await exec<{ id: string }>(
    `select id::text from ingredient
     where household_id = $1 and match_text = $2
       and source = 'import_stub' and deleted_at is null
     limit 1`,
    [args.householdId, matchText],
  );
  if (existing.length > 0) {
    return { ingredient_id: existing[0].id, created: false };
  }
  const inserted = await exec<{ id: string }>(
    `insert into ingredient
       (household_id, canonical_name, default_unit, status, source, match_text)
     values ($1, $2, $3, 'stub', 'import_stub', $4)
     returning id::text`,
    [args.householdId, args.ingredientText, args.defaultUnit, matchText],
  );
  return { ingredient_id: inserted[0].id, created: true };
}

/** Minimum usda_food trigram score to accept a background prefill. */
export const USDA_PREFILL_MIN = 0.5;

export interface PrefillResult {
  prefilled: boolean;
  fdc_id: number | null;
  score: number;
}

/**
 * The background job (§9): search `usda_food` by the stub's `match_text` and, on a
 * confident hit that actually carries values, prefill density + macros and record
 * the FDC provenance. The row STAYS `status='stub'` until the user confirms — the
 * prefill just means the New-ingredient screen opens pre-populated. `usda_food` is
 * server-only (ADR-0005); this is the only place it is read at import-time-adjacent
 * work, and never as a match target.
 */
export async function prefillStubFromUsda(
  exec: SqlExecutor,
  ingredientId: string,
): Promise<PrefillResult> {
  const stub = await exec<{ match_text: string }>(
    `select match_text from ingredient
     where id = $1 and status = 'stub' and deleted_at is null`,
    [ingredientId],
  );
  if (stub.length === 0) return { prefilled: false, fdc_id: null, score: 0 };

  const hits = await exec<{
    fdc_id: number;
    density_g_per_ml: number | null;
    macros: unknown;
    score: number;
  }>(
    `select fdc_id, density_g_per_ml, macros, similarity(match_text, $1) as score
     from usda_food
     where match_text % $1
     order by score desc
     limit 1`,
    [stub[0].match_text],
  );
  const hit = hits[0];
  if (!hit || Number(hit.score) < USDA_PREFILL_MIN) {
    return {
      prefilled: false,
      fdc_id: hit?.fdc_id ?? null,
      score: Number(hit?.score ?? 0),
    };
  }
  if (hit.density_g_per_ml == null && hit.macros == null) {
    // Nothing to copy — don't churn provenance for an empty reference row.
    return { prefilled: false, fdc_id: hit.fdc_id, score: Number(hit.score) };
  }
  await exec(
    `update ingredient
     set density_g_per_ml = coalesce($2, density_g_per_ml),
         macros           = coalesce($3, macros),
         source           = 'usda_fdc:' || $4::text,
         updated_at       = now()
     where id = $1 and status = 'stub' and deleted_at is null`,
    [ingredientId, hit.density_g_per_ml, hit.macros, hit.fdc_id],
  );
  return { prefilled: true, fdc_id: hit.fdc_id, score: Number(hit.score) };
}

// --- §8: the learning loop ---------------------------------------------------

export interface CorrectionArgs {
  householdId: string;
  /** The ingredient the user chose (undo→pick, or accept-suggestion). */
  ingredientId: string;
  /** The original raw line text that mis-matched — stored verbatim as the alias. */
  rawText: string;
}

export interface AliasResult {
  alias_id: string;
  created: boolean;
}

/**
 * The learning loop (§8): on a user correction, write the raw string back as an
 * `ingredient_alias` (`source='import_correction'`) on the chosen ingredient, so
 * the household's own phrasing is absorbed and future imports exact-match it — zero
 * ML. The trigger is a lane-C reconciliation action; this is the server write
 * contract. Idempotent by (ingredient, match_text) so re-correcting the same line
 * doesn't pile up duplicate aliases.
 */
export async function writeCorrectionAlias(
  exec: SqlExecutor,
  args: CorrectionArgs,
): Promise<AliasResult> {
  const matchText = normalize(args.rawText);
  const existing = await exec<{ id: string }>(
    `select id::text from ingredient_alias
     where ingredient_id = $1 and match_text = $2 and deleted_at is null
     limit 1`,
    [args.ingredientId, matchText],
  );
  if (existing.length > 0) {
    return { alias_id: existing[0].id, created: false };
  }
  const inserted = await exec<{ id: string }>(
    `insert into ingredient_alias
       (household_id, ingredient_id, alias_text, match_text, source)
     values ($1, $2, $3, $4, 'import_correction')
     returning id::text`,
    [args.householdId, args.ingredientId, args.rawText, matchText],
  );
  return { alias_id: inserted[0].id, created: true };
}
