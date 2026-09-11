// Postgres-backed side of the match cascade — the parameterized SQL the
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
import {
  type CandidatesByText,
  type RecipeTitleMatcher,
  TOP_N,
  type VocabMatcher,
} from "./match.ts";
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
//
// Both tiers take the WHOLE set of identities as one `text[]` parameter and
// answer for all of them at once, keyed by `match_text`. That is what keeps a
// 35-line recipe to two round trips rather than seventy fanned out through a
// pool of ten against the transaction pooler. `unnest($2::text[])` is what
// makes it one query instead of a generated `in (…)` list: the driver binds one
// parameter whatever the line count, so nothing about this SQL grows with the
// recipe.

// Exact `match_text` equality across ingredient + alias, one row per distinct
// (identity, ingredient). Household-scoped and soft-delete aware (mirrors RLS +
// spec §5.2). The alias branches scope on BOTH `a.household_id` and
// `i.household_id`: an alias row is supposed to carry its ingredient's
// household, but nothing in the schema forces that, and this connection is
// service-role (RLS does not apply). Two predicates cost nothing and mean a
// single mis-written alias row can never leak another household's ingredient
// into a candidate list.
//
// The sort is total for the same reason the trigram tier's is: when two
// ingredients share a surface the cascade surfaces BOTH for the human to
// disambiguate, and which one it lists first must not depend on the plan.
const EXACT_SQL = `
  select q.match_text, i.id::text as ingredient_id, i.canonical_name,
         1.0::float8 as score
  from unnest($2::text[]) as q(match_text)
  join ingredient i
    on i.household_id = $1 and i.deleted_at is null
   and i.match_text = q.match_text
  union
  select q.match_text, i.id::text, i.canonical_name, 1.0::float8
  from unnest($2::text[]) as q(match_text)
  join ingredient_alias a
    on a.household_id = $1 and a.deleted_at is null
   and a.match_text = q.match_text
  join ingredient i
    on i.id = a.ingredient_id and i.deleted_at is null and i.household_id = $1
  order by match_text asc, canonical_name asc, ingredient_id asc`;

// Trigram similarity across ingredient + alias, best score per (identity,
// ingredient), score-desc, capped at `limit` PER IDENTITY. `% q.match_text`
// uses the GIN index (0002) and pg_trgm's default threshold (0.3) — safely
// below BAND_SUGGEST_MIN, so no surfaced candidate is pruned. See match.ts
// TRIGRAM_FLOOR.
//
// The cap is a `row_number()` window rather than a `limit`, because one query
// now carries many identities and each is entitled to its own top-N.
//
// The sort is TOTAL (score, then canonical_name, then id): ties are common in
// trigram space, and `order by score desc` alone lets Postgres return either
// row first — which would make the candidate list, the band, and every golden
// fixture built on it non-deterministic across runs and plan changes.
const TRIGRAM_SQL = `
  select match_text, ingredient_id, canonical_name, score
  from (
    select b.match_text, b.ingredient_id, b.canonical_name, b.score,
           row_number() over (
             partition by b.match_text
             order by b.score desc, b.canonical_name asc, b.ingredient_id asc
           ) as rank
    from (
      select s.match_text, s.ingredient_id, s.canonical_name,
             max(s.score) as score
      from (
        select q.match_text, i.id::text as ingredient_id, i.canonical_name,
               similarity(i.match_text, q.match_text) as score
        from unnest($2::text[]) as q(match_text)
        join ingredient i
          on i.household_id = $1 and i.deleted_at is null
         and i.match_text % q.match_text
        union all
        select q.match_text, i.id::text, i.canonical_name,
               similarity(a.match_text, q.match_text)
        from unnest($2::text[]) as q(match_text)
        join ingredient_alias a
          on a.household_id = $1 and a.deleted_at is null
         and a.match_text % q.match_text
        join ingredient i
          on i.id = a.ingredient_id and i.deleted_at is null
         and i.household_id = $1
      ) s
      group by s.match_text, s.ingredient_id, s.canonical_name
    ) b
  ) c
  where c.rank <= $3
  order by c.match_text asc, c.rank asc`;

interface CandidateRow {
  match_text: string;
  ingredient_id: string;
  canonical_name: string;
  score: number;
}

/** Groups the flat result set back onto the identity that asked for it. */
function byMatchText(rows: CandidateRow[]): CandidatesByText {
  const out: CandidatesByText = new Map();
  for (const r of rows) {
    const candidate: MatchCandidate = {
      ingredient_id: r.ingredient_id,
      canonical_name: r.canonical_name,
      score: Number(r.score),
    };
    const bucket = out.get(r.match_text);
    if (bucket) bucket.push(candidate);
    else out.set(r.match_text, [candidate]);
  }
  return out;
}

/**
 * A {@link VocabMatcher} backed by Postgres, bound to one household. Pass to
 * `matchLines`. The `matchTexts` arguments are already normalized by the
 * cascade, and each tier costs exactly one query however many there are.
 */
export function sqlVocabMatcher(
  exec: SqlExecutor,
  householdId: string,
): VocabMatcher {
  return {
    async exact(matchTexts) {
      const rows = await exec<CandidateRow>(EXACT_SQL, [
        householdId,
        matchTexts,
      ]);
      return byMatchText(rows);
    },
    async trigram(matchTexts, limit = TOP_N) {
      const rows = await exec<CandidateRow>(TRIGRAM_SQL, [
        householdId,
        matchTexts,
        limit,
      ]);
      return byMatchText(rows);
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
// a server-side `createImportStub` had no production caller and was deleted
// rather than left as a second, drifting way to write the same row.
//
// The USDA PREFILL is not here either, and no longer exists anywhere: NOTHING
// fills a row from `usda_food` on its own. A trigger did for a while, because
// the reference set never syncs to a device (ADR-0005) and the only surface
// that sees a stub arriving is the sync queue's INSERT, which no edge function
// is in the path of. 0029 dropped it: a silent write that names a food nobody
// chose is a guess wearing a citation. What replaced it is `probe_usda`, a
// read-only ranked search over the same reference set, which the app offers to
// a person — and the person applies the pick through the ordinary local write
// path. So there is no server-side prefill to keep in step with here.

// --- §8: the learning loop ---------------------------------------------------
//
// Also not here, for the same reason: the correction alias
// (`source='import_correction'`) is written by the client through the sync
// queue when the user corrects a match. The server-side `writeCorrectionAlias`
// contract had no production caller and was deleted. Reads of those aliases are
// what this module does — see EXACT_SQL/TRIGRAM_SQL above, which is where the
// absorbed phrasing comes back into the cascade.
