// A pg_trgm-compatible trigram similarity in TypeScript, plus an in-memory
// {@link VocabMatcher} built on it. This is the OFFLINE side of lane B: it lets the
// cascade (match.ts) be tested and band-calibrated against the real household vocab
// without a live Postgres. The production path uses Postgres `similarity()` (see
// match_db.ts); this mirrors it closely enough for scoring/calibration.
//
// pg_trgm's algorithm (documented): split on non-alphanumerics into words; pad each
// word with two leading spaces and one trailing space; take the set of 3-char
// windows; similarity = |A ∩ B| / |A ∪ B| over the two trigram SETS.

import type { MatchCandidate } from "./types.ts";
import { TOP_N, TRIGRAM_FLOOR, type VocabMatcher } from "./match.ts";

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
  /** normalized match_text(s): normalize(canonical_name) + each normalized alias. */
  match_texts: string[];
}

/**
 * An in-memory {@link VocabMatcher} over `entries`, mirroring `sqlVocabMatcher`
 * semantics: exact `match_text` equality, and best-per-ingredient trigram scoring
 * with the same TRIGRAM_FLOOR prune the SQL `%` operator applies.
 */
export function inMemoryVocabMatcher(entries: VocabEntry[]): VocabMatcher {
  return {
    exact(matchText: string): Promise<MatchCandidate[]> {
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
      return Promise.resolve(out);
    },
    trigram(matchText: string, limit = TOP_N): Promise<MatchCandidate[]> {
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
      return Promise.resolve(scored.slice(0, limit));
    },
  };
}
