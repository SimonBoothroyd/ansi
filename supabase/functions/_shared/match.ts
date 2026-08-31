// The match cascade (docs/product-specs/import-and-matching.md §6; lane B of the
// step-8 import DAG — see docs/exec-plans/active/0016-import-matching.md).
//
// Deterministic, server-side matching (ADR-0004). Consumes sanitized `RawLineItem`s
// and returns a `MatchedLine` per input line: a confidence band plus the top-N
// candidates. It runs cheap→expensive and stops when confident:
//
//   1. exact normalized  → `match_text` equality vs ingredient + ingredient_alias
//   2. trigram           → pg_trgm similarity(); high → auto, mid → suggest (top-3)
//   3. no match          → band `none`, empty candidates (NO silent auto-stub —
//                          0014 surfaces `none` to the user; lane C owns the UI)
//
// There is deliberately NO embedding tier (back-pocket per 0014's decision log).
//
// This module is DB-agnostic and pure: it drives a {@link VocabMatcher}, which is
// the seam to Postgres. The Postgres-backed matcher (parameterized pg_trgm SQL) and
// the stub/alias write contracts live in `match_db.ts`; an in-memory matcher for
// offline tests/calibration lives in `match_trgm.ts`. Keeping the cascade pure is
// what makes band calibration testable without a live database.

import { normalize } from "./normalize.ts";
import type {
  MatchBand,
  MatchCandidate,
  MatchedLine,
  RawLineItem,
} from "./types.ts";

// --- Band calibration (§6) ---------------------------------------------------
// Starting points from the spec's §6 table, to be tuned by lane D's eval — NOT a
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

/**
 * The batch entry point (§6 — "called once per import with all lines batched").
 * Normalizes each line's `ingredient_text` (§7) and runs the cascade. Order is
 * preserved 1:1 with the input; lines are matched concurrently.
 */
export function matchLines(
  lines: RawLineItem[],
  matcher: VocabMatcher,
): Promise<MatchedLine[]> {
  return Promise.all(
    lines.map(async (raw): Promise<MatchedLine> => {
      const { band, candidates } = await matchOne(
        normalize(raw.ingredient_text),
        matcher,
      );
      return { raw, band, candidates };
    }),
  );
}

/**
 * The within-import dedupe key for `none` lines (§6.4 / 0014 boundary). Identical
 * `none` lines share this key, so lane C can coalesce them onto a single
 * just-created stub. It is exactly the normalized `match_text`, so it is symmetric
 * with what `createImportStub` (match_db.ts) writes and looks up.
 */
export function noneDedupeKey(line: RawLineItem): string {
  return normalize(line.ingredient_text);
}
