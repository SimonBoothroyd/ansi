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
 * The database seam. Both methods compare against the NORMALIZED `match_text`
 * (§7) — the caller passes an already-normalized string. Implementations are
 * household-scoped (they capture the household at construction) and search the
 * household `ingredient` + `ingredient_alias` vocab only — never `usda_food`
 * (ADR-0005). See `sqlVocabMatcher` in `match_db.ts`.
 */
export interface VocabMatcher {
  /** Exact `match_text` equality. Returns one candidate per distinct ingredient. */
  exact(matchText: string): Promise<MatchCandidate[]>;
  /** Trigram similarity, best-per-ingredient, score-desc, at most `limit` rows. */
  trigram(matchText: string, limit: number): Promise<MatchCandidate[]>;
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

/**
 * Match a single already-normalized identity through the cascade. Exposed for
 * targeted tests; `matchLines` is the batch entry point.
 */
export async function matchOne(
  matchText: string,
  matcher: VocabMatcher,
): Promise<{ band: MatchBand; candidates: MatchCandidate[] }> {
  if (!matchText) return { band: "none", candidates: [] };

  // Tier 1 — exact. Authoritative: an exact hit short-circuits the trigram tier.
  const exact = dedupeById(await matcher.exact(matchText));
  if (exact.length === 1) {
    return { band: "auto", candidates: exact };
  }
  if (exact.length > 1) {
    // Genuinely ambiguous (e.g. two ingredients sharing an alias's match_text):
    // don't auto-commit — surface the choice for the human to disambiguate.
    return { band: "suggest", candidates: exact.slice(0, TOP_N) };
  }

  // Tier 2 — trigram / typo tolerance.
  const trig = dedupeById(await matcher.trigram(matchText, TOP_N)).slice(
    0,
    TOP_N,
  );
  const best = trig[0]?.score ?? 0;
  const band = bandForScore(best);
  // Tier 3 — no match: empty candidates, the user creates-new (§9 stub). 0014:
  // no silent auto-stub here.
  if (band === "none") return { band: "none", candidates: [] };
  return { band, candidates: trig };
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
 * The batch entry point (§6 — "called once per import with all lines batched").
 * Normalizes each line's `ingredient_text` (§7) and runs the cascade. Order is
 * preserved 1:1 with the input; lines are matched concurrently.
 *
 * `recipeMatcher` is OPTIONAL (8.6): supply it and each line additionally
 * carries `recipe_candidates` when its text names a household recipe; leave it
 * out and the result is byte-identical to what this returned before.
 */
export function matchLines(
  lines: RawLineItem[],
  matcher: VocabMatcher,
  recipeMatcher?: RecipeTitleMatcher,
): Promise<MatchedLine[]> {
  return Promise.all(
    lines.map(async (raw): Promise<MatchedLine> => {
      const [{ band, candidates }, recipes] = await Promise.all([
        matchOne(normalize(raw.ingredient_text), matcher),
        recipeMatcher
          ? matchRecipeTitles(raw.ingredient_text, recipeMatcher)
          : Promise.resolve<RecipeCandidate[]>([]),
      ]);
      const line: MatchedLine = { raw, band, candidates };
      // Additive and OMITTED when empty: no matcher, or no hit, ⇒ the exact
      // shape the pre-8.6 client already decodes.
      if (recipes.length > 0) line.recipe_candidates = recipes;
      return line;
    }),
  );
}
