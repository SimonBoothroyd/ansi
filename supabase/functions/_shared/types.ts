// Shared types for the import pipeline. Contract mirrors the extraction output
// in docs/product-specs/import-and-matching.md §4.4. Types only — no logic.

export type ImageQuality = "ok" | "degraded" | "poor";

export interface RawLineItem {
  qty: number | null;
  unit: string | null;
  ingredient_text: string; // as written; normalized server-side (§7)
  confidence: number; // model self-reported, per line
}

export interface RawGroup {
  name: string;
  line_items: RawLineItem[];
}

export interface ExtractionResult {
  title: string;
  servings_base: number;
  image_quality: ImageQuality;
  parse_warnings: string[];
  groups: RawGroup[];
  // steps: tokenized, refs aligned by line-item index (§4.6) — omitted in stub.
}

export type MatchBand = "auto" | "suggest" | "none";

export interface MatchCandidate {
  ingredient_id: string;
  canonical_name: string;
  score: number;
}

export interface MatchedLine {
  raw: RawLineItem;
  band: MatchBand;
  candidates: MatchCandidate[]; // top-N; empty for `none`
}
