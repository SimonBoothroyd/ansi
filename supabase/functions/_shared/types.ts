// Shared types for the import pipeline — the SERVER boundary contracts.
//
// Mirrors docs/product-specs/import-and-matching.md §4.4 and the finalized shapes
// in docs/exec-plans/completed/0014-import-foundation.md + the gold schema at
// evals/datasets/extraction/gold/_SCHEMA.md (one source — keep them in step).
// Types only — no logic.
//
// INVARIANT — extraction never invents (0014). No fabricated ingredient, quantity,
// unit, time, serving, or step: absent/ambiguous ⇒ flagged (parse_warnings, low
// confidence, a range the user resolves), never guessed. These types make that
// expressible (nullable numbers, ranges, `unit_mappable`) rather than forcing a
// value.
//
// The commit contract (resolved lines + stubs written through PowerSync, with step
// `line_index` refs remapped to real line_item_ids) is built on the APP side in
// Dart — it is not a server type and lives with the app, not here.

export type ImageQuality = "ok" | "degraded" | "poor";

/** A time span. A single printed time → low_seconds === high_seconds. */
export interface TimeRange {
  low_seconds: number;
  high_seconds: number;
}

/** Recipe-level printed time: a single value, a printed range, or absent. */
export type TimeField = number | TimeRange | null;

// --- Extraction input: RawBlob (§3, §4.1–4.2) --------------------------------
// The union output of intake. `jsonld.ts` produces `jsonld`/`page_text`; vision
// transcription produces `transcription`. The sanitize stage consumes only this —
// it never sees the URL or the image.

export type RawBlobSource = "jsonld" | "page_text" | "transcription";

export interface RawBlob {
  source: RawBlobSource;
  url: string | null; // provenance only; the sanitize stage ignores it
  jsonld: Record<string, unknown> | null; // raw schema.org/Recipe when source=jsonld
  text: string | null; // page text or vision transcription
  /**
   * ADDITIVE (0047): the fetched page's visible text, bounded, for the app's
   * source column — never an input to sanitize, which reads `text`/`jsonld`
   * alone. It is set on BOTH link branches (a JSON-LD page still has a page a
   * person can read), and absent from a transcription blob, whose pages are
   * images the phone already holds.
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
 * A sub-amount named IN A STEP for one reference (§4.6). Source-derived — the
 * number is transcribed from the step prose, never invented — or a relative word.
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

/** A step is an ordered token stream (§4.6) — rendered by a fold, not text-match. */
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
// `unitHints` = our canonical units + accepted imprecise/size words (NOT the
// ingredient vocab, NOT per-ingredient measures), so ① lands qty/unit in-system.

export interface UnitHints {
  units: string[]; // canonical unit ids: g, ml, tsp, tbsp, cup, piece…
  imprecise: string[]; // accepted vague amounts: dash, pinch, handful
  size_words: string[]; // large, medium, small
  measures: string[]; // generic count-measure nouns: clove, head, can, slice…
}

/**
 * Token usage for ONE provider call, NORMALIZED across providers so a cost
 * formula can be written once (evals/runner/pricing.ts). The three vendors
 * disagree about what their own totals include, so the adapters' parsers
 * (`_shared/adapters/usage.ts`) reduce them all to this contract:
 *
 * - `input_tokens` is the **uncached, non-cache-write** billable input. OpenAI
 *   and Gemini fold cached tokens INTO their prompt count and Anthropic does
 *   not; the parsers subtract, so every provider reports the same thing here.
 * - `output_tokens` INCLUDES reasoning/thinking tokens, which every provider
 *   bills at the output rate even when it reports them in a separate field.
 * - Any field the provider did not report stays `null` — never 0, so "not
 *   reported" is distinguishable from "genuinely zero" in a cost table.
 */
export interface TokenUsage {
  input_tokens: number | null;
  output_tokens: number | null;
  cache_read_tokens: number | null;
  cache_write_tokens: number | null;
  /** Reasoning/thinking tokens — already counted inside `output_tokens`. */
  reasoning_tokens: number | null;
  /** The provider's own total, verbatim, when it reports one. Audit only. */
  total_tokens: number | null;
}

/**
 * One completed provider HTTP call, handed to an optional observer. This is the
 * benchmark's side-channel: it carries the VERBATIM response so a paid run can
 * be persisted and rescored for free, plus usage and latency for the cost
 * columns. It is deliberately a callback rather than a change to `sanitize`'s
 * return type, so `import-recipe` (which never sets an observer) is untouched.
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
   * OPTIONAL observer, off by default. The edge function leaves it unset and
   * behaves exactly as before; the eval runner sets it to capture usage + the
   * raw response. An observer that throws must never fail an import — the
   * adapters swallow its errors.
   */
  onCall?: ProviderCallSink;
  /**
   * OPTIONAL observer, off by default: told whenever the model produced more
   * output during a call. Payload-free ON PURPOSE — the point is the TICK, not
   * the text. The orchestrator attaches one so the function can emit a
   * `heartbeat` frame while a long call runs (import spec §4.7); a model call
   * that does not stream simply never calls it, and the caller sees a gap, as
   * it always did. An observer that throws must never fail an import.
   */
  onProgress?: ProgressSink;
  transcribe?(images: Uint8Array[]): Promise<RawBlob>; // vision tier (LLM)
  sanitize(blob: RawBlob, hints: UnitHints): Promise<ExtractionResult>; // ①
}

/** Told that the model produced more output. See `ExtractAdapter.onProgress`. */
export type ProgressSink = () => void;

// --- The match cascade output (§6) -------------------------------------------
// No silent auto-stub: band `none` carries empty candidates; the user resolves it
// (search / create-new) at reconciliation.

export type MatchBand = "auto" | "suggest" | "none";

export interface MatchCandidate {
  ingredient_id: string;
  canonical_name: string;
  score: number;
}

/**
 * A household RECIPE whose title the line's identity text matched (step 8.6,
 * exec plan 0021 D6). Deliberately a separate shape from {@link MatchCandidate}:
 * a recipe is not an ingredient, it never carries a band, and it is NEVER
 * auto-linked — a human taps the suggestion or ignores it.
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
   * ADDITIVE (8.6): household recipes whose title this line might be naming.
   * OMITTED entirely when there are none — and when no recipe-title matcher is
   * wired at all — so a client that predates the field decodes exactly what it
   * decoded before. Independent of `band`/`candidates`: a line can match an
   * ingredient AND a recipe, and the human picks.
   */
  recipe_candidates?: RecipeCandidate[];
}

// --- Edge fn → app: ReconciliationPayload ------------------------------------
// What the deployed `import-recipe` function returns and the app's reconciliation
// screen consumes. The Dart side pins this shape through the committed golden
// fixture (`import-recipe/__fixtures__/reconciliation_payload.golden.json`), so a
// change here is a change to that contract. Step refs are still by line_index;
// the app remaps them to line_item_ids on commit.

/**
 * Where a line was read from inside {@link ReconciliationPayload.source_text}:
 * a half-open character range `[start, end)` into that exact string.
 *
 * ADDITIVE (0047), and LOCATED rather than guessed — `source_span.ts` emits one
 * only for an unambiguous verbatim occurrence of what the line printed, and
 * omits the field otherwise. Never-invent: a span nobody can point at is no
 * span.
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
   * ADDITIVE (0047): where this line sits in {@link
   * ReconciliationPayload.source_text}. OMITTED when there is no source text,
   * or when the line's printed words cannot be pointed at unambiguously — so a
   * client that predates the field decodes exactly what it decoded before.
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
   * ADDITIVE (0047): the page's own text, for the wide review's source column.
   * Bounded server-side at `SOURCE_TEXT_MAX_CHARS` (jsonld.ts) — a page's text
   * is unbounded and this rides the same response as the recipe.
   *
   * OMITTED for a photo import (the pages are images the phone already holds)
   * and whenever intake produced no page text at all.
   */
  source_text?: string;
}
