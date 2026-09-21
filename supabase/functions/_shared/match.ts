// The match cascade (docs/product-specs/import-and-matching.md §6), the ⑥
// stage of the import spine.
//
// Deterministic, server-side (ADR-0004). Consumes sanitized `RawLineItem`s and
// returns a `MatchedLine` per line: a confidence band plus the top-N
// candidates. It runs cheap to expensive and stops when confident:
//
//   1. exact normalized → `match_text` equality vs ingredient + ingredient_alias
//   2. trigram          → pg_trgm similarity(); high → auto, mid → suggest
//   3. no match         → band `none`, empty candidates, no auto-stub
//
// There is no embedding tier. The module is pure: it drives a
// {@link VocabMatcher}, implemented over Postgres in `match_db.ts` and in
// memory in `match_trgm.ts`. The seam is set-shaped: a tier takes every
// unanswered identity at once, so an import costs one round trip per tier,
// and a ruling depends on the identity text alone.

import { normalize, stripParentheticals } from "./normalize.ts";
import type {
  MatchBand,
  MatchCandidate,
  MatchedLine,
  RawLineItem,
  RecipeCandidate,
} from "./types.ts";

// --- Band calibration (§6) ---------------------------------------------------
// Tuned by the eval harness. `auto` auto-accepts (with undo); `suggest` shows
// the top-3 "did you mean?"; below that is `none`.
export const BAND_AUTO_MIN = 0.85;
export const BAND_SUGGEST_MIN = 0.55;

/**
 * pg_trgm's default `%` similarity threshold. The SQL matcher retrieves with
 * `%` so the GIN index is used; this floor is below BAND_SUGGEST_MIN, so no
 * surfaced candidate is pruned. The in-memory matcher mirrors it.
 */
export const TRIGRAM_FLOOR = 0.3;

/** How many candidates a `suggest`/`auto` line carries. */
export const TOP_N = 3;

/**
 * Candidates for a set of identities, keyed by identity. A key with nothing to
 * show may be absent.
 */
export type CandidatesByText = Map<string, MatchCandidate[]>;

/**
 * The database seam: one call per tier per import. Both methods take
 * already-normalized `match_text` strings (§7). Implementations are
 * household-scoped and search `ingredient` + `ingredient_alias` only, never
 * `usda_food` (ADR-0005). See `sqlVocabMatcher` in `match_db.ts`.
 */
export interface VocabMatcher {
  /** Exact `match_text` equality. One candidate per distinct ingredient, per text. */
  exact(matchTexts: string[]): Promise<CandidatesByText>;
  /** Trigram similarity, best-per-ingredient, score-desc, at most `limit` per text. */
  trigram(matchTexts: string[], limit: number): Promise<CandidatesByText>;
}

/** Classifies a similarity score into a band. Exact hits bypass this. */
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
 * The cascade's ruling for one identity, given what each tier returned for
 * it. Pure, so `matchOne` and `matchLines` reach the same verdict.
 */
function classify(
  exactRows: MatchCandidate[],
  trigramRows: MatchCandidate[],
): LineMatch {
  // Tier 1: exact. An exact hit short-circuits the trigram tier.
  const exact = dedupeById(exactRows);
  if (exact.length === 1) {
    return { band: "auto", candidates: exact };
  }
  if (exact.length > 1) {
    // Ambiguous (two ingredients share a match_text): let the human choose.
    return { band: "suggest", candidates: exact.slice(0, TOP_N) };
  }

  // Tier 2: trigram / typo tolerance.
  const trig = dedupeById(trigramRows).slice(0, TOP_N);
  const best = trig[0]?.score ?? 0;
  const band = bandForScore(best);
  // Tier 3: no match. Empty candidates; the user creates new (§9).
  if (band === "none") return { band: "none", candidates: [] };
  return { band, candidates: trig };
}

/**
 * Matches one already-normalized identity through the cascade, for targeted
 * tests and the eval scorer. Production calls `matchLines`.
 */
export async function matchOne(
  matchText: string,
  matcher: VocabMatcher,
): Promise<LineMatch> {
  if (!matchText) return { band: "none", candidates: [] };
  const exact = (await matcher.exact([matchText])).get(matchText) ?? [];
  if (exact.length > 0) return classify(exact, []);
  const trigram = (await matcher.trigram([matchText], TOP_N)).get(matchText) ??
    [];
  return classify([], trigram);
}

// --- The sub-recipe tier -----------------------------------------------------
//
// A printed component line ("¼ cup Romesco Aioli (page 38)") stays an
// ingredient line unless a human links it. This tier only offers: it compares
// the line's normalized identity text with the household's recipe titles and
// returns hits as a separate field, never a band or an auto-link. It is
// stricter than the ingredient cascade: only exact hits and trigram scores at
// or above BAND_SUGGEST_MIN survive.

/**
 * The recipe-title seam, mirroring {@link VocabMatcher}: household-scoped,
 * soft-delete aware, comparing normalized text. Titles are normalized on
 * read; see `sqlRecipeTitleMatcher` in `match_db.ts`.
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
 * The identity text a recipe-title lookup compares: `ingredient_text` with
 * parenthetical cross-references dropped, then normalized (§7). Falls back to
 * the un-stripped text when the aside was the whole line.
 */
export function recipeMatchText(ingredientText: string): string {
  const stripped = normalize(stripParentheticals(ingredientText));
  return stripped || normalize(ingredientText);
}

/**
 * Recipe-title candidates for one line's identity text: exact hits, otherwise
 * trigram hits that clear {@link BAND_SUGGEST_MIN}. May be empty.
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
 * The batch entry point (§6) production calls: two round trips per recipe.
 *
 * Normalizes each line's `ingredient_text` (§7), asks the exact tier for every
 * distinct identity at once, then the trigram tier for the rest. Repeated
 * identities are asked once. Order is preserved 1:1 with the input.
 *
 * With the optional `recipeMatcher`, a line also carries `recipe_candidates`
 * when its text names a household recipe.
 */
export async function matchLines(
  lines: RawLineItem[],
  matcher: VocabMatcher,
  recipeMatcher?: RecipeTitleMatcher,
): Promise<MatchedLine[]> {
  const identities = lines.map((raw) => normalize(raw.ingredient_text));
  const distinct = [...new Set(identities)].filter((t) => t !== "");

  // One query regardless of line count (match_db.ts); started here so it
  // overlaps the vocab tiers.
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
    // Omitted when empty, so the payload shape is unchanged without a hit.
    if (recipes[i].length > 0) line.recipe_candidates = recipes[i];
    return line;
  });
}
