// The match cascade (docs/product-specs/import-and-matching.md §6).
//
// STUB — contract only. Runs cheap→expensive, stops when confident:
//   1. exact normalized  → auto
//   2. trigram/token-set → auto (high) | suggest (mid)
//   3. semantic embedding (stretch; likely unnecessary for v1)
//   4. no match          → stub
// Server-side only (ADR-0004). Never invoked from the device.

import type { MatchedLine, RawLineItem } from "./types.ts";

export function matchLines(_lines: RawLineItem[]): Promise<MatchedLine[]> {
  // TODO(step-8): implement the cascade against the household vocabulary.
  throw new Error("matchLines() not implemented — roadmap step 8");
}
