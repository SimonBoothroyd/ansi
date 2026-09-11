// The match cascade (docs/product-specs/import-and-matching.md §6; the ⑥ stage
// of the import spine — see docs/exec-plans/completed/0016-import-matching.md).
//
// Deterministic, server-side matching (ADR-0004). Consumes sanitized `RawLineItem`s
// and returns a `MatchedLine` per input line: a confidence band plus the top-N
// candidates. It runs cheap→expensive and stops when confident:
//
//   1. exact normalized  → `match_text` equality vs ingredient + ingredient_alias
//   2. trigram           → pg_trgm similarity(); high → auto, mid → suggest (top-3)
//   3. no match          → band `none`, empty candidates (NO silent auto-stub —
//                          0014 surfaces `none` to the user; the app owns the UI)
//
// There is deliberately NO embedding tier (back-pocket per 0014's decision log).
//
// This module is DB-agnostic and pure: it drives a {@link VocabMatcher}, which is
// the seam to Postgres. The Postgres-backed matcher (parameterized pg_trgm SQL) and
// the stub/alias write contracts live in `match_db.ts`; an in-memory matcher for
// offline tests/calibration lives in `match_trgm.ts`. Keeping the cascade pure is
// what makes band calibration testable without a live database.
//
// The seam is SET-SHAPED: a tier takes every identity still unanswered and
// returns candidates for all of them, so a whole import costs ONE round trip
// per tier rather than one per line. The tiers themselves still run in order,
// and the trigram tier still only sees what the exact tier did not answer — the
// cascade is unchanged, it is the fan-out underneath it that is gone.

import { normalize, stripParentheticals } from "./normalize.ts";
import type {
  MatchBand,
  MatchCandidate,
  MatchedLine,
  RawLineItem,
  RecipeCandidate,
} from "./types.ts";

// --- Band calibration (§6) ---------------------------------------------------
// Starting points from the spec's §6 table, tuned by the eval harness — NOT a
// merge gate. `auto` auto-accepts (with an undo affordance); `suggest` shows the
// top-3 "did you mean?"; below `suggest` is `none` (create-new / stub).
export const BAND_AUTO_MIN = 0.85;
export const BAND_SUGGEST_MIN = 0.55;

/**
 * pg_trgm's default `%` similarity threshold. The SQL matcher retrieves with `%`
 * (so the GIN index is used) which prunes anything below this; it never hides a
 * candidate we'd surface, because BAND_SUGGEST_MIN (0.55) > this floor. The
 * in-memory matcher mirrors it so offline scoring matches Postgres.
 */
export const TRIGRAM_FLOOR = 0.3;

/** How many candidates a `suggest`/`auto` line carries. §6: top-3 "did you mean?". */
export const TOP_N = 3;

/**
 * Candidates for a set of identities, keyed by the identity that found them. A
 * key with nothing to show may be absent rather than mapped to `[]` — callers
 * read it as "no candidates" either way.
 */
export type CandidatesByText = Map<string, MatchCandidate[]>;

/**
 * The database seam, ONE CALL PER TIER PER IMPORT. Both methods take a set of
 * identities and compare against the NORMALIZED `match_text` (§7) — the caller
 * passes already-normalized strings. Implementations are household-scoped (they
 * capture the household at construction) and search the household `ingredient` +
 * `ingredient_alias` vocab only — never `usda_food` (ADR-0005). See
 * `sqlVocabMatcher` in `match_db.ts`.
 */
export interface VocabMatcher {
  /** Exact `match_text` equality. One candidate per distinct ingredient, per text. */
  exact(matchTexts: string[]): Promise<CandidatesByText>;
  /** Trigram similarity, best-per-ingredient, score-desc, at most `limit` per text. */
  trigram(matchTexts: string[], limit: number): Promise<CandidatesByText>;
}

/** Classifies a similarity score into a band. Exact hits bypass this (always auto). */
export function bandForScore(score: number): MatchBand {
  if (score >= BAND_AUTO_MIN) return "auto";
  if (score >= BAND_SUGGEST_MIN) return "suggest";
  return "none";
}

/** Distinct-by-ingredient, preserving first-seen (highest-score) order. */
function dedupeById(cands: MatchCandidate[]): MatchCandidate[] {
  const seen = new Set<string>();
  const out: MatchCandidate[] = [];
  for (const c of cands) {
    if (seen.has(c.ingredient_id)) continue;
    seen.add(c.ingredient_id);
    out.push(c);
  }
  return out;
}

/** One identity's outcome: the band, and the candidates that earned it. */
export interface LineMatch {
  band: MatchBand;
  candidates: MatchCandidate[];
}

/**
 * The cascade's ruling for one identity, given what each tier returned for it.
 * PURE — no I/O — so `matchOne` and `matchLines` reach the same verdict from
 * the same rows, whether those rows came one at a time or in a batch.
 */
function classify(
  exactRows: MatchCandidate[],
  trigramRows: MatchCandidate[],
): LineMatch {
  // Tier 1 — exact. Authoritative: an exact hit short-circuits the trigram tier.
  const exact = dedupeById(exactRows);
  if (exact.length === 1) {
    return { band: "auto", candidates: exact };
  }
  if (exact.length > 1) {
    // Genuinely ambiguous (e.g. two ingredients sharing an alias's match_text):
    // don't auto-commit — surface the choice for the human to disambiguate.
    return { band: "suggest", candidates: exact.slice(0, TOP_N) };
  }

  // Tier 2 — trigram / typo tolerance.
  const trig = dedupeById(trigramRows).slice(0, TOP_N);
  const best = trig[0]?.score ?? 0;
  const band = bandForScore(best);
  // Tier 3 — no match: empty candidates, the user creates-new (§9 stub). 0014:
  // no silent auto-stub here.
  if (band === "none") return { band: "none", candidates: [] };
  return { band, candidates: trig };
}

/**
 * Match a single already-normalized identity through the cascade. Exposed for
 * targeted tests and the eval scorer; `matchLines` is the batch entry point and
 * is what production calls.
 */
export async function matchOne(
  matchText: string,
  matcher: VocabMatcher,
): Promise<LineMatch> {
  if (!matchText) return { band: "none", candidates: [] };
  const exact = (await matcher.exact([matchText])).get(matchText) ?? [];
  // The exact tier being authoritative is what lets the trigram tier be skipped
  // entirely here, and what lets the batch below narrow tier 2 to a remainder.
  if (exact.length > 0) return classify(exact, []);
  const trigram = (await matcher.trigram([matchText], TOP_N)).get(matchText) ??
    [];
  return classify([], trigram);
}

// --- The sub-recipe tier (step 8.6, exec plan 0021 D6) -----------------------
//
// A printed component line — `"¼ cup Romesco Aioli (page 38)"` — is an ordinary
// ingredient line to extraction, and stays one unless a human links it. This
// tier only ever *offers*: it runs the SAME shared normalizer over the line's
// identity text against the household's live recipe TITLES and returns whatever
// it finds as a separate field. Never a band, never an auto-link (0021's first
// non-goal), never a reason to skip the ingredient cascade — a line may match a
// vocab row AND a recipe, and the review card lets the human choose.
//
// It is deliberately STRICTER than the ingredient cascade: only exact
// normalized-title hits and trigram scores at or above BAND_SUGGEST_MIN
// survive, because an unwanted "↪ your recipe" chip on a plain ingredient line
// is pure noise, and a missing one costs nothing (D7's picker links it by hand).

/**
 * The recipe-title seam, mirroring {@link VocabMatcher}: household-scoped,
 * soft-delete aware, comparing NORMALIZED text. Titles have no stored
 * `match_text` column, so implementations normalize on read — see
 * `sqlRecipeTitleMatcher` in `match_db.ts`.
 */
export interface RecipeTitleMatcher {
  /** Exact normalized-title equality. One candidate per recipe. */
  exact(matchText: string): Promise<RecipeCandidate[]>;
  /** Trigram similarity over titles, score-desc, at most `limit` rows. */
  trigram(matchText: string, limit: number): Promise<RecipeCandidate[]>;
}

/** Distinct-by-recipe, preserving first-seen (highest-score) order. */
function dedupeRecipes(cands: RecipeCandidate[]): RecipeCandidate[] {
  const seen = new Set<string>();
  const out: RecipeCandidate[] = [];
  for (const c of cands) {
    if (seen.has(c.recipe_id)) continue;
    seen.add(c.recipe_id);
    out.push(c);
  }
  return out;
}

/**
 * The identity text a recipe-title lookup compares: the line's
 * `ingredient_text` with parenthetical cross-references ("(page 38)") dropped,
 * then normalized (§7). Falls back to the un-stripped text when the aside was
 * the whole line, so `"(see the aioli recipe)"` still has something to match.
 * Exported for the tests that pin the "(page 38)" behaviour.
 */
export function recipeMatchText(ingredientText: string): string {
  const stripped = normalize(stripParentheticals(ingredientText));
  return stripped || normalize(ingredientText);
}

/**
 * Recipe-title candidates for one line's identity text. Exact hits win
 * outright; otherwise trigram hits that clear {@link BAND_SUGGEST_MIN}. Empty
 * when nothing is close enough — the caller then omits the field entirely.
 */
export async function matchRecipeTitles(
  ingredientText: string,
  matcher: RecipeTitleMatcher,
): Promise<RecipeCandidate[]> {
  const matchText = recipeMatchText(ingredientText);
  if (!matchText) return [];

  const exact = dedupeRecipes(await matcher.exact(matchText));
  if (exact.length > 0) return exact.slice(0, TOP_N);

  const trig = dedupeRecipes(await matcher.trigram(matchText, TOP_N));
  return trig.filter((c) => c.score >= BAND_SUGGEST_MIN).slice(0, TOP_N);
}

/**
 * The batch entry point (§6 — "called once per import with all lines batched"),
 * and the shape production runs: **two round trips for the whole recipe**, not
 * two per line.
 *
 * Normalizes each line's `ingredient_text` (§7), asks the exact tier for every
 * distinct identity at once, then asks the trigram tier for only the identities
 * exact did not answer. Repeated identities — a long recipe names `tamari`
 * three times — are asked about once and share the answer, which is sound
 * precisely because the cascade is a pure function of the identity text.
 *
 * Order is preserved 1:1 with the input.
 *
 * `recipeMatcher` is OPTIONAL (8.6): supply it and each line additionally
 * carries `recipe_candidates` when its text names a household recipe; leave it
 * out and the result is byte-identical to what this returned before.
 */
export async function matchLines(
  lines: RawLineItem[],
  matcher: VocabMatcher,
  recipeMatcher?: RecipeTitleMatcher,
): Promise<MatchedLine[]> {
  const identities = lines.map((raw) => normalize(raw.ingredient_text));
  const distinct = [...new Set(identities)].filter((t) => t !== "");

  // The sub-recipe tier reads the household's titles ONCE and scores in memory
  // (match_db.ts), so it is one query regardless of line count — started here so
  // it overlaps the vocab tiers instead of following them.
  const recipesByLine = recipeMatcher
    ? Promise.all(
      lines.map((raw) => matchRecipeTitles(raw.ingredient_text, recipeMatcher)),
    )
    : Promise.resolve(lines.map((): RecipeCandidate[] => []));

  const empty: CandidatesByText = new Map();
  const exact = distinct.length > 0 ? await matcher.exact(distinct) : empty;
  const remainder = distinct.filter((t) => (exact.get(t)?.length ?? 0) === 0);
  const trigram = remainder.length > 0
    ? await matcher.trigram(remainder, TOP_N)
    : empty;

  const verdicts = new Map<string, LineMatch>(
    distinct.map((t) => [
      t,
      classify(exact.get(t) ?? [], trigram.get(t) ?? []),
    ]),
  );
  const none: LineMatch = { band: "none", candidates: [] };

  const recipes = await recipesByLine;
  return lines.map((raw, i): MatchedLine => {
    const { band, candidates } = verdicts.get(identities[i]) ?? none;
    const line: MatchedLine = { raw, band, candidates };
    // Additive and OMITTED when empty: no matcher, or no hit, ⇒ the exact
    // shape the pre-8.6 client already decodes.
    if (recipes[i].length > 0) line.recipe_candidates = recipes[i];
    return line;
  });
}
