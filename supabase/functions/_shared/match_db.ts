// The Postgres side of the match cascade: the parameterized SQL the pure
// cascade in `match.ts` drives. Server-side only (ADR-0004).
//
// The trigram tier uses the `%` operator so the GIN indexes from 0002 apply,
// then `similarity()` supplies the score; the bands are applied in TS.
//
// The driver is injected as a {@link SqlExecutor}, so this module has no
// external imports and is testable with a fake. Placeholders are Postgres
// positional ($1, $2, …).

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
// Both tiers take every identity as one `text[]` parameter and answer for all
// of them, keyed by `match_text`: two round trips per recipe whatever its
// length.

// Exact `match_text` equality across ingredient + alias, one row per distinct
// (identity, ingredient). Household-scoped and soft-delete aware. The alias
// branches scope on both `a.household_id` and `i.household_id`: this
// connection is service-role, so RLS does not apply, and nothing in the schema
// forces an alias to carry its ingredient's household.
//
// The sort is total, so the order of tied candidates never depends on the plan.
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
// ingredient), score-desc, capped at `limit` per identity with a
// `row_number()` window. `% q.match_text` uses the GIN index and pg_trgm's
// default threshold (0.3), below BAND_SUGGEST_MIN; see match.ts TRIGRAM_FLOOR.
//
// The sort is total (score, canonical_name, id): trigram ties are common, and
// an unstable order would make candidate lists and golden fixtures flaky.
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
 * A {@link VocabMatcher} backed by Postgres, bound to one household. The
 * `matchTexts` are already normalized, and each tier costs one query.
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

// --- The sub-recipe tier: household recipe titles ----------------------------

// Every live recipe in the household, id + title, in one query. A recipe has
// no stored `match_text`, so titles are normalized by the shared normalizer
// and scored with `trigramSimilarity` in TS; the list is small. Ordered so
// tie-breaking is stable.
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
 * title list is loaded lazily, once per instance.
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

// Stubs and correction aliases (§8, §9) are written by the client through the
// sync queue, not here. Nothing fills a row from `usda_food` on its own; the
// app offers `probe_usda` results and the person applies the pick.
