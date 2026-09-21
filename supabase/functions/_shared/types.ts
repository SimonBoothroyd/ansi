// Shared types for the import pipeline: the server boundary contracts. Types
// only.
//
// Mirrors docs/product-specs/import-and-matching.md §4.4 and the gold schema at
// evals/datasets/extraction/gold/_SCHEMA.md; keep them in step.
//
// Extraction never invents: an absent or ambiguous value is flagged
// (parse_warnings, low confidence, a range), never guessed. Nullable numbers,
// ranges and `unit_mappable` make that expressible. The commit contract is
// built app-side in Dart.

export type ImageQuality = "ok" | "degraded" | "poor";

/** A time span. A single printed time → low_seconds === high_seconds. */
export interface TimeRange {
  low_seconds: number;
  high_seconds: number;
}

/** Recipe-level printed time: a single value, a printed range, or absent. */
export type TimeField = number | TimeRange | null;

// --- Extraction input: RawBlob (§3, §4.1–4.2) --------------------------------
// `jsonld.ts` produces `jsonld`/`page_text`; vision transcription produces
// `transcription`. Sanitize sees only this, never the URL or the image.

export type RawBlobSource = "jsonld" | "page_text" | "transcription";

export interface RawBlob {
  source: RawBlobSource;
  url: string | null; // provenance only; the sanitize stage ignores it
  jsonld: Record<string, unknown> | null; // raw schema.org/Recipe when source=jsonld
  text: string | null; // page text or vision transcription
  /**
   * The fetched page's visible text, bounded, for the app's source column.
   * Never an input to sanitize. Set on both link branches; absent from a
   * transcription blob.
   */
  page_text?: string;
}

// --- Extraction output: ExtractionResult (§4.4) ------------------------------
// Emitted by ① sanitize·structure·align. Ingredient-blind, unit-aware.

export interface RawLineItem {
  qty: number | null; // a SINGLE value; null when a range (see qty_low/qty_high)
  qty_low: number | null; // range low ("4 to 6" → 4)
  qty_high: number | null; // range high ("4 to 6" → 6)
  unit: string | null; // normalized toward the unit vocab; else the printed word
  unit_mappable: boolean; // false → `unit` holds the raw phrase, UI resolves it
  ingredient_text: string; // identity, AS WRITTEN — feeds §7 normalize + learning loop
  notes: string | null; // non-identity cook-prep / usage note: "juiced" | "zested" | null
  raw_amount: string; // full printed amount, verbatim; "" when the line prints
  // none (coercion maps a model null to ""). NB: gold fixtures predate coercion
  // and use `null` for amount-less lines — the scorer accepts both.
  optional: boolean;
  confidence: number; // model self-reported, per line
}

export interface RawGroup {
  name: string | null; // printed sub-heading; null when the recipe has no grouping
  line_items: RawLineItem[];
}

export type MentionKind = "new" | "rementioned" | "fraction";

/**
 * A sub-amount named in a step for one reference (§4.6): a number transcribed
 * from the step prose, or a relative word.
 */
export interface RefPortion {
  qty: number | null; // single step sub-amount
  qty_low: number | null; // step-range low
  qty_high: number | null; // step-range high
  unit: string | null;
  qualifier: string | null; // relative word: "the rest" | "half" | "for garnish"
}

export interface TextToken {
  t: "text";
  s: string;
}

export interface RefToken {
  t: "ref";
  refs: number[]; // flattened line_index list; a set → collective chip
  label: string; // surface text to show as the chip
  mention: MentionKind;
  portion: RefPortion | null;
}

export interface TimerToken {
  t: "timer";
  low_seconds: number; // single time → low_seconds === high_seconds
  high_seconds: number;
}

/** A step is an ordered token stream (§4.6). */
export type StepToken = TextToken | RefToken | TimerToken;

export interface Step {
  tokens: StepToken[];
}

export interface ExtractionResult {
  title: string;
  servings_base: number | null; // best-effort portions; null when unclear (flagged)
  servings_raw: string | null; // exact printed serving text
  yield_raw: string | null; // printed yield that isn't portions ("Makes 1 cup")
  total_time_seconds: TimeField;
  cook_time_seconds: TimeField;
  truncated: boolean; // true only for a deliberately-incomplete source (missing page)
  image_quality: ImageQuality;
  parse_warnings: string[];
  groups: RawGroup[];
  steps: Step[];
}

// --- The provider seam (the edge function + the eval harness) ----------------
// `unitHints` = our canonical units + accepted imprecise/size words, not the
// ingredient vocab.

export interface UnitHints {
  units: string[]; // canonical unit ids: g, ml, tsp, tbsp, cup, piece…
  imprecise: string[]; // accepted vague amounts: dash, pinch, handful
  size_words: string[]; // large, medium, small
  measures: string[]; // generic count-measure nouns: clove, head, can, slice…
}

/**
 * Token usage for one provider call, normalized across providers
 * (`_shared/adapters/usage.ts`) so one cost formula applies
 * (evals/runner/pricing.ts):
 *
 * - `input_tokens` is the uncached, non-cache-write billable input; parsers
 *   subtract cached tokens where a provider folds them in.
 * - `output_tokens` includes reasoning/thinking tokens.
 * - A field the provider did not report is `null`, never 0.
 */
export interface TokenUsage {
  input_tokens: number | null;
  output_tokens: number | null;
  cache_read_tokens: number | null;
  cache_write_tokens: number | null;
  /** Reasoning/thinking tokens, already counted inside `output_tokens`. */
  reasoning_tokens: number | null;
  /** The provider's own total, verbatim, when it reports one. Audit only. */
  total_tokens: number | null;
}

/**
 * One completed provider HTTP call, handed to an optional observer: the
 * verbatim response (so a paid run can be rescored) plus usage and latency.
 */
export interface ProviderCall {
  provider: string; // adapter name, e.g. "gpt-5-mini"
  model: string; // the PINNED model id actually sent
  op: "transcribe" | "sanitize";
  usage: TokenUsage | null;
  latency_ms: number;
  /** The provider's response body exactly as parsed from the wire. */
  raw: unknown;
}

export type ProviderCallSink = (call: ProviderCall) => void;

export interface ExtractAdapter {
  name: string; // "gemini-flash" | "gpt-5-mini" | "claude-haiku" | "jsonld"
  /** The pinned model id this adapter sends (absent for non-LLM adapters). */
  readonly model?: string;
  /**
   * Optional observer, unset in production; the eval runner uses it to capture
   * usage and the raw response. Adapters swallow its errors.
   */
  onCall?: ProviderCallSink;
  /**
   * Optional observer, told whenever the model produced more output during a
   * call. Payload-free. The orchestrator uses it to emit `heartbeat` frames
   * (import spec §4.7). Adapters swallow its errors.
   */
  onProgress?: ProgressSink;
  transcribe?(images: Uint8Array[]): Promise<RawBlob>; // vision tier (LLM)
  sanitize(blob: RawBlob, hints: UnitHints): Promise<ExtractionResult>; // ①
}

/** Told that the model produced more output. See `ExtractAdapter.onProgress`. */
export type ProgressSink = () => void;

// --- The match cascade output (§6) -------------------------------------------
// Band `none` carries empty candidates; the user resolves it at reconciliation.

export type MatchBand = "auto" | "suggest" | "none";

export interface MatchCandidate {
  ingredient_id: string;
  canonical_name: string;
  score: number;
}

/**
 * A household recipe whose title the line's identity text matched. Separate
 * from {@link MatchCandidate}: it carries no band and is never auto-linked.
 */
export interface RecipeCandidate {
  recipe_id: string;
  title: string; // the recipe's title as stored (display text for the chip)
  score: number; // 1 for an exact normalized-title hit, else trigram similarity
}

export interface MatchedLine {
  raw: RawLineItem;
  band: MatchBand;
  candidates: MatchCandidate[]; // top-N; empty for `none`
  /**
   * Household recipes whose title this line might be naming. Omitted when
   * there are none. Independent of `band`/`candidates`.
   */
  recipe_candidates?: RecipeCandidate[];
}

// --- Edge fn → app: ReconciliationPayload ------------------------------------
// What `import-recipe` returns. The Dart side pins this shape through
// `import-recipe/__fixtures__/reconciliation_payload.golden.json`. Step refs
// are by line_index; the app remaps them to line_item_ids on commit.

/**
 * Where a line was read from inside {@link ReconciliationPayload.source_text}:
 * a half-open character range `[start, end)`. `source_span.ts` emits one only
 * for an unambiguous verbatim occurrence.
 */
export interface SourceSpan {
  start: number;
  end: number;
}

export interface ReconLine {
  raw: RawLineItem;
  band: MatchBand;
  candidates: MatchCandidate[];
  /** See {@link MatchedLine.recipe_candidates} — present only when non-empty. */
  recipe_candidates?: RecipeCandidate[];
  /**
   * Where this line sits in {@link ReconciliationPayload.source_text}. Omitted
   * when there is no source text or the words cannot be located unambiguously.
   */
  source_span?: SourceSpan;
}

export interface ReconGroup {
  name: string | null;
  lines: ReconLine[];
}

export interface ReconciliationPayload {
  title: string;
  servings_base: number | null;
  servings_raw: string | null;
  yield_raw: string | null;
  total_time_seconds: TimeField;
  cook_time_seconds: TimeField;
  truncated: boolean;
  image_quality: ImageQuality;
  parse_warnings: string[];
  groups: ReconGroup[];
  steps: Step[];
  /**
   * The page's own text, for the wide review's source column, bounded at
   * `SOURCE_TEXT_MAX_CHARS` (jsonld.ts). Omitted for a photo import and when
   * intake produced no page text.
   */
  source_text?: string;
}
