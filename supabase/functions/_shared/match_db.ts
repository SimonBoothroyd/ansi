// Postgres-backed side of the match cascade (lane B) — the parameterized SQL the
// pure cascade in `match.ts` drives, plus the one §9 write that has to live on
// the server (the USDA prefill). Server-side only (ADR-0004): all of this runs
// in the edge function against Postgres via the service role.
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

import type { MatchCandidate, RecipeCandidate } from "./types.ts";
import { type RecipeTitleMatcher, TOP_N, type VocabMatcher } from "./match.ts";
import {
  inMemoryRecipeTitleMatcher,
  type RecipeTitleEntry,
} from "./match_trgm.ts";

/** Minimal, driver-agnostic query seam: positional params in, rows out. */
export type SqlExecutor = <T = Record<string, unknown>>(
  text: string,
  params: unknown[],
) => Promise<T[]>;

// --- Tier 1 + 2: the household-scoped vocab matcher --------------------------

// Exact `match_text` equality across ingredient + alias, one row per distinct
// ingredient. Household-scoped and soft-delete aware (mirrors RLS + spec §5.2).
// The alias branches scope on BOTH `a.household_id` and `i.household_id`: an
// alias row is supposed to carry its ingredient's household, but nothing in the
// schema forces that, and this connection is service-role (RLS does not apply).
// Two predicates cost nothing and mean a single mis-written alias row can never
// leak another household's ingredient into a candidate list.
const EXACT_SQL = `
  select distinct i.id::text as ingredient_id, i.canonical_name, 1.0::float8 as score
  from ingredient i
  where i.household_id = $1 and i.deleted_at is null and i.match_text = $2
  union
  select distinct i.id::text, i.canonical_name, 1.0::float8
  from ingredient_alias a
  join ingredient i on i.id = a.ingredient_id and i.deleted_at is null
  where a.household_id = $1 and i.household_id = $1
    and a.deleted_at is null and a.match_text = $2`;

// Trigram similarity across ingredient + alias, best score per ingredient,
// score-desc, capped. `% $2` uses the GIN index (0002) and pg_trgm's default
// threshold (0.3) — safely below BAND_SUGGEST_MIN, so no surfaced candidate is
// pruned. See match.ts TRIGRAM_FLOOR.
//
// The sort is TOTAL (score, then canonical_name, then id): ties are common in
// trigram space, and `order by score desc` alone lets Postgres return either
// row first — which would make the candidate list, the band, and every golden
// fixture built on it non-deterministic across runs and plan changes.
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
    where a.household_id = $1 and i.household_id = $1
      and a.deleted_at is null and a.match_text % $2
  ) c
  group by ingredient_id, canonical_name
  order by score desc, canonical_name asc, ingredient_id asc
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

// --- The sub-recipe tier: household recipe titles (8.6 / 0021 D6) ------------

// Every LIVE recipe in the household, id + title. Deliberately the whole set in
// one query rather than a per-line lookup:
//
//   * a recipe has no stored `match_text` column, and the comparison must run
//     through the ONE shared normalizer (normalize.ts) — mirroring it in SQL
//     would be a second, drifting copy of the rule the whole cascade rests on;
//   * a household's recipe list is small (tens–hundreds of rows) next to the
//     8k-row vocab, so one read per import beats N trigram queries;
//   * scoring then reuses `trigramSimilarity`, which already mirrors pg_trgm
//     for exactly this offline-scoring purpose (match_trgm.ts).
//
// Ordered so the load is deterministic, which keeps tie-breaking stable.
const RECIPE_TITLES_SQL = `
  select r.id::text as recipe_id, r.title
  from recipe r
  where r.household_id = $1 and r.deleted_at is null
  order by r.title asc, r.id asc`;

interface RecipeTitleRow {
  recipe_id: string;
  title: string;
}

/**
 * A {@link RecipeTitleMatcher} backed by Postgres, bound to one household. The
 * title list is loaded LAZILY and ONCE per instance (an import matches many
 * lines against the same household), so a run with no lines costs no query.
 */
export function sqlRecipeTitleMatcher(
  exec: SqlExecutor,
  householdId: string,
): RecipeTitleMatcher {
  let loaded: Promise<RecipeTitleMatcher> | null = null;

  const load = (): Promise<RecipeTitleMatcher> => {
    loaded ??= exec<RecipeTitleRow>(RECIPE_TITLES_SQL, [householdId]).then(
      (rows) =>
        inMemoryRecipeTitleMatcher(
          rows.map((r): RecipeTitleEntry => ({
            recipe_id: r.recipe_id,
            title: r.title,
          })),
        ),
    );
    return loaded;
  };

  return {
    async exact(matchText: string): Promise<RecipeCandidate[]> {
      return await (await load()).exact(matchText);
    },
    async trigram(
      matchText: string,
      limit = TOP_N,
    ): Promise<RecipeCandidate[]> {
      return await (await load()).trigram(matchText, limit);
    },
  };
}

// --- §9: stub lifecycle ------------------------------------------------------
//
// Nothing of §9 is here any more, and that is deliberate.
//
// The stub WRITE never was: 0014's CommitPayload creates stubs through the
// PowerSync sync queue (a client insert), and that is the surface that shipped —
// lane B's server-side `createImportStub` had no production caller and was
// deleted rather than left as a second, drifting way to write the same row.
//
// The USDA PREFILL followed it in 0014_density_admission.sql (plan 0020 D7).
// It has to run server-side — `usda_food` never syncs to a device (ADR-0005) —
// and the only surface that sees a stub arriving is the sync queue's INSERT,
// which no edge function is in the path of. So it is now an `after insert`
// trigger (`ingredient_prefill_from_usda`, a plpgsql port of the same one
// trigram query + one guarded update, with the same 0.5 floor and the same
// "the row STAYS `status='stub'`" contract). `prefillStubFromUsda` was written,
// unit-tested and callerless from step 8 to step 8.5; it is deleted here for
// the third time under the same doctrine, rather than kept as a second,
// drifting way to write the same row.

// --- §8: the learning loop ---------------------------------------------------
//
// Also not here, for the same reason: the correction alias
// (`source='import_correction'`) is written by the client through the sync
// queue when the user corrects a match. The server-side `writeCorrectionAlias`
// contract had no production caller and was deleted. Reads of those aliases are
// what this module does — see EXACT_SQL/TRIGRAM_SQL above, which is where the
// absorbed phrasing comes back into the cascade.
