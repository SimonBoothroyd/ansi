// A pg_trgm-compatible trigram similarity in TypeScript, plus an in-memory
// {@link VocabMatcher} built on it, so the cascade (match.ts) can be tested
// and band-calibrated without Postgres. Production uses `similarity()` (see
// match_db.ts).
//
// pg_trgm's algorithm: split on non-alphanumerics into words; pad each word
// with two leading spaces and one trailing space; take the set of 3-char
// windows; similarity = |A ∩ B| / |A ∪ B|.

import type { MatchCandidate, RecipeCandidate } from "./types.ts";
import {
  type CandidatesByText,
  type RecipeTitleMatcher,
  TOP_N,
  TRIGRAM_FLOOR,
  type VocabMatcher,
} from "./match.ts";
import { normalize } from "./normalize.ts";

/** The distinct trigram set of a string, pg_trgm style (word-padded windows). */
export function trigrams(s: string): Set<string> {
  const words = s.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  const out = new Set<string>();
  for (const w of words) {
    const padded = "  " + w + " ";
    for (let i = 0; i < padded.length - 2; i++) {
      out.add(padded.slice(i, i + 3));
    }
  }
  return out;
}

/** Trigram similarity in [0,1], matching Postgres `similarity(a,b)`. */
export function trigramSimilarity(a: string, b: string): number {
  const A = trigrams(a);
  const B = trigrams(b);
  if (A.size === 0 || B.size === 0) return 0;
  let inter = 0;
  for (const t of A) if (B.has(t)) inter++;
  const union = A.size + B.size - inter;
  return union === 0 ? 0 : inter / union;
}

/** One household ingredient with all of its normalized surfaces (name + aliases). */
export interface VocabEntry {
  ingredient_id: string;
  canonical_name: string;
  /** normalize(canonical_name) plus each normalized alias. */
  match_texts: string[];
}

/**
 * An in-memory {@link VocabMatcher} over `entries`, mirroring
 * `sqlVocabMatcher`: exact `match_text` equality, and best-per-ingredient
 * trigram scoring with the same TRIGRAM_FLOOR prune.
 */
export function inMemoryVocabMatcher(entries: VocabEntry[]): VocabMatcher {
  const exactFor = (matchText: string): MatchCandidate[] => {
    const out: MatchCandidate[] = [];
    for (const e of entries) {
      if (e.match_texts.includes(matchText)) {
        out.push({
          ingredient_id: e.ingredient_id,
          canonical_name: e.canonical_name,
          score: 1,
        });
      }
    }
    return out;
  };

  const trigramFor = (matchText: string, limit: number): MatchCandidate[] => {
    const scored: MatchCandidate[] = [];
    for (const e of entries) {
      let best = 0;
      for (const mt of e.match_texts) {
        const s = trigramSimilarity(mt, matchText);
        if (s > best) best = s;
      }
      if (best >= TRIGRAM_FLOOR) {
        scored.push({
          ingredient_id: e.ingredient_id,
          canonical_name: e.canonical_name,
          score: best,
        });
      }
    }
    scored.sort((a, b) => b.score - a.score);
    return scored.slice(0, limit);
  };

  // Set-shaped like the SQL matcher, so the cascade drives both the same way.
  return {
    exact(matchTexts: string[]): Promise<CandidatesByText> {
      return Promise.resolve(
        new Map(matchTexts.map((t) => [t, exactFor(t)])),
      );
    },
    trigram(matchTexts: string[], limit = TOP_N): Promise<CandidatesByText> {
      return Promise.resolve(
        new Map(matchTexts.map((t) => [t, trigramFor(t, limit)])),
      );
    },
  };
}

// --- The sub-recipe tier's matcher -------------------------------------------

/** One household recipe as the title tier sees it. */
export interface RecipeTitleEntry {
  recipe_id: string;
  title: string;
}

/**
 * A {@link RecipeTitleMatcher} over an in-memory list of household recipes.
 * Titles have no stored `match_text`, so they are normalized here with the
 * shared normalizer (§7). Also the production path: `sqlRecipeTitleMatcher`
 * loads the titles and hands them to this function.
 */
export function inMemoryRecipeTitleMatcher(
  entries: RecipeTitleEntry[],
): RecipeTitleMatcher {
  const rows = entries.map((e) => ({ ...e, match_text: normalize(e.title) }));
  // A total order, as in TRIGRAM_SQL: trigram ties are common.
  const byScore = (a: RecipeCandidate, b: RecipeCandidate) =>
    b.score - a.score || a.title.localeCompare(b.title) ||
    a.recipe_id.localeCompare(b.recipe_id);

  return {
    exact(matchText: string): Promise<RecipeCandidate[]> {
      const out = rows
        .filter((r) => r.match_text === matchText && r.match_text !== "")
        .map((r) => ({ recipe_id: r.recipe_id, title: r.title, score: 1 }));
      out.sort(byScore);
      return Promise.resolve(out);
    },
    trigram(matchText: string, limit = TOP_N): Promise<RecipeCandidate[]> {
      const scored: RecipeCandidate[] = [];
      for (const r of rows) {
        const score = trigramSimilarity(r.match_text, matchText);
        if (score >= TRIGRAM_FLOOR) {
          scored.push({ recipe_id: r.recipe_id, title: r.title, score });
        }
      }
      scored.sort(byScore);
      return Promise.resolve(scored.slice(0, limit));
    },
  };
}
