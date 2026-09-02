// Claude Haiku adapter — the Haiku tier behind the frozen ExtractAdapter.
//
// Model id pinned via the `claude-api` reference: `claude-haiku-4-5` (the Haiku
// tier; 200K context). Vision: yes (image content blocks, base64). Native
// structured output: `output_config.format` with a `json_schema` (the current
// Messages-API mechanism; the deprecated `output_format` is not used). Raw HTTP
// to POST /v1/messages keeps the three adapters uniform and dependency-free.
//
// Prompt caching (GA, no beta header): the stable sanitize system prompt is sent
// as a content block with `cache_control: {type:"ephemeral"}` so repeated calls
// read it from cache instead of re-billing the full prefix each time.
//
// KEYLESS: constructing/`deno check`ing this is free; a live call needs
// ANTHROPIC_API_KEY. Without it the benchmark uses the mock adapter.

import type {
  ExtractAdapter,
  ExtractionResult,
  ProviderCallSink,
  RawBlob,
  TokenUsage,
  UnitHints,
} from "../types.ts";
import { ImportError } from "../errors.ts";
import { anthropicUsage, emitCall } from "./usage.ts";
import {
  coerceExtractionResult,
  EXTRACTION_JSON_SCHEMA,
  ExtractionParseError,
  STEPS_JSON_SCHEMA,
  validateExtractionResult,
} from "./schema.ts";
import {
  linesSystemPrompt,
  sanitizeSystemPrompt,
  sanitizeUserPrompt,
  stepsSystemPrompt,
  stepsUserPrompt,
  TRANSCRIBE_PROMPT,
} from "../prompts/extraction.ts";
import {
  extractJson,
  IMAGE_MEDIA_TYPE,
  postJson,
  requireKey,
  resizeForUpload,
  toBase64,
} from "./http.ts";

export const CLAUDE_HAIKU_MODEL = "claude-haiku-4-5";
/** Benchmark alternates (lane D): the current Sonnet and Opus tiers. */
export const CLAUDE_SONNET_MODEL = "claude-sonnet-5";
export const CLAUDE_OPUS_MODEL = "claude-opus-5";
const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
/**
 * `max_tokens` is a CEILING, not a target — an unreached one costs nothing, and
 * a reached one truncates the JSON mid-object. claude-haiku-4-5 tops out at 64K
 * output tokens; we ask for half of that, which no real recipe approaches while
 * keeping a non-streaming request comfortably inside its HTTP timeout. (Was
 * 8192, which a long multi-page recipe could genuinely hit.)
 */
const DEFAULT_MAX_TOKENS = 32_000;

export interface ClaudeAdapterOptions {
  apiKey?: string; // defaults to ANTHROPIC_API_KEY
  model?: string; // defaults to CLAUDE_HAIKU_MODEL
  maxTokens?: number;
  name?: string; // provider label in benchmark/usage rows; defaults to "claude-haiku"
  /**
   * `output_config.effort` for models that take it (Sonnet 5 / Opus 5 tiers —
   * controls adaptive-thinking depth and total token spend; default "high").
   * Leave unset for Haiku 4.5, which rejects the parameter.
   */
  effort?: "low" | "medium" | "high";
  /**
   * Run sanitize as TWO calls (lines, then steps against the finished keyed
   * line list) instead of one. Benchmarked 2026-09-02: ref F1 flat vs the
   * one-shot keys pipeline (91.1±0.9 vs 91.0±0.4) with a slightly better
   * never-invent ledger, at +40% cost — so production ships ONE-SHOT (owner
   * call) and this stays as the benchmark seam for revisiting collectives.
   */
  twoPhase?: boolean;
  /**
   * Per-attempt / total HTTP budgets forwarded to `postJson`. The defaults
   * (45s/60s) are tuned for the edge function's spinner; an adaptive-thinking
   * model can legitimately reason past 45s on one call, so benchmark lanes for
   * the Sonnet/Opus tiers MUST raise these or every call aborts (observed:
   * eleven "signal has been aborted" transcribes in a row).
   */
  timeoutMs?: number;
  deadlineMs?: number;
}

interface AnthropicContentBlock {
  type: string;
  text?: string;
}
interface AnthropicResponse {
  content?: AnthropicContentBlock[];
  stop_reason?: string | null;
}

function firstText(res: AnthropicResponse): string {
  const block = (res.content ?? []).find((b) => b.type === "text" && b.text);
  if (!block?.text) {
    throw new ExtractionParseError("Claude returned no text content", res);
  }
  return block.text;
}

/**
 * A `max_tokens` stop means the JSON was cut off mid-object. Parsing it would
 * either throw a confusing syntax error or — worse, if the truncation happens
 * to land on a valid boundary — silently drop the tail of a recipe. Fail with
 * something the user can act on instead (⇒ 422).
 */
function assertComplete(res: AnthropicResponse): void {
  if (res.stop_reason === "max_tokens") {
    throw new ImportError(
      "this recipe is too long to import in one go — try importing it in parts",
    );
  }
}

/**
 * VERBATIM response → `ExtractionResult`, split out of `sanitize` so a saved
 * raw response can be re-decoded and rescored later without a second paid call
 * (evals `--rescore`). This is the whole decode path, truncation check included,
 * so a rescore reproduces the live run exactly — including its failures.
 */
/** The persisted shape of a two-phase sanitize: both verbatim responses. */
interface TwoPhaseRaw {
  two_phase: true;
  lines: unknown;
  steps: unknown;
}

function isTwoPhase(res: unknown): res is TwoPhaseRaw {
  return typeof res === "object" && res !== null &&
    (res as Record<string, unknown>).two_phase === true;
}

export function decodeClaudeSanitize(res: unknown): ExtractionResult {
  if (isTwoPhase(res)) {
    // Two-phase: merge the phase-1 lines JSON with the phase-2 steps JSON and
    // coerce ONCE — the key map is built from the lines half, so the steps
    // half's key refs resolve exactly as a one-shot response's would.
    const linesTyped = res.lines as AnthropicResponse;
    const stepsTyped = res.steps as AnthropicResponse;
    assertComplete(linesTyped);
    assertComplete(stepsTyped);
    const linesJson = JSON.parse(extractJson(firstText(linesTyped)));
    const stepsJson = JSON.parse(extractJson(firstText(stepsTyped)));
    const merged = {
      ...(linesJson as Record<string, unknown>),
      steps: (stepsJson as Record<string, unknown>).steps ?? [],
    };
    return validateExtractionResult(coerceExtractionResult(merged));
  }
  const typed = res as AnthropicResponse;
  assertComplete(typed); // never JSON.parse a truncated payload
  const json = JSON.parse(extractJson(firstText(typed)));
  return validateExtractionResult(coerceExtractionResult(json));
}

/** VERBATIM response → the transcription text (the D1 half of the decode). */
export function decodeClaudeTranscribe(res: unknown): string {
  const typed = res as AnthropicResponse;
  assertComplete(typed);
  return firstText(typed);
}

export class ClaudeHaikuAdapter implements ExtractAdapter {
  readonly name: string;
  readonly model: string;
  readonly #apiKey: string;
  readonly #maxTokens: number;
  /** Optional benchmark observer; unset in production (see `ExtractAdapter`). */
  onCall?: ProviderCallSink;

  constructor(opts: ClaudeAdapterOptions = {}) {
    this.model = opts.model ?? CLAUDE_HAIKU_MODEL;
    this.name = opts.name ?? "claude-haiku";
    this.#apiKey = opts.apiKey ?? requireKey("ANTHROPIC_API_KEY", "Claude");
    this.#maxTokens = opts.maxTokens ?? DEFAULT_MAX_TOKENS;
    this.#effort = opts.effort;
    this.#timeoutMs = opts.timeoutMs;
    this.#twoPhase = opts.twoPhase ?? false;
    this.#deadlineMs = opts.deadlineMs;
  }

  readonly #effort?: "low" | "medium" | "high";
  readonly #twoPhase: boolean;
  readonly #timeoutMs?: number;
  readonly #deadlineMs?: number;

  /** `output_config.effort`, when configured — merged into any output_config. */
  #effortConfig(): { effort?: string } {
    return this.#effort ? { effort: this.#effort } : {};
  }

  /**
   * The temperature pin, where the API still takes one. Claude removed the
   * sampling params (`temperature`/`top_p`/`top_k`) on the Sonnet-5/Opus-5
   * generation — sending them is a 400 — while Haiku 4.5 still accepts them.
   * Extraction is deterministic work, so pin 0 whenever the model allows it.
   */
  #sampling(): { temperature?: number } {
    return this.model.includes("haiku") ? { temperature: 0 } : {};
  }

  #headers(): Record<string, string> {
    return {
      "x-api-key": this.#apiKey,
      "anthropic-version": ANTHROPIC_VERSION,
    };
  }

  #emit(
    op: "transcribe" | "sanitize",
    raw: unknown,
    startedAt: number,
  ): void {
    emitCall(this.onCall, {
      provider: this.name,
      model: this.model,
      op,
      usage: anthropicUsage(raw),
      latency_ms: Math.round(performance.now() - startedAt),
      raw,
    });
  }

  async transcribe(images: Uint8Array[]): Promise<RawBlob> {
    const resized = await Promise.all(images.map(resizeForUpload));
    const content = [
      ...resized.map((img) => ({
        type: "image",
        source: {
          type: "base64",
          media_type: IMAGE_MEDIA_TYPE,
          data: toBase64(img),
        },
      })),
      { type: "text", text: TRANSCRIBE_PROMPT },
    ];
    const startedAt = performance.now();
    const res = await postJson({
      url: ANTHROPIC_URL,
      headers: this.#headers(),
      provider: "Claude",
      timeoutMs: this.#timeoutMs,
      deadlineMs: this.#deadlineMs,
      body: {
        model: this.model,
        max_tokens: this.#maxTokens,
        // Transcription is deterministic work: unpinned, the API defaults to
        // temperature 1.0, and the same page transcribes differently run to
        // run (observed live: one paragraph → 1 step or 4, chips or none).
        ...this.#sampling(),
        ...(this.#effort ? { output_config: this.#effortConfig() } : {}),
        messages: [{ role: "user", content }],
      },
    });
    this.#emit("transcribe", res, startedAt);
    return {
      source: "transcription",
      url: null,
      jsonld: null,
      text: decodeClaudeTranscribe(res),
    };
  }

  /** One structured-output call: shared plumbing for the two sanitize phases. */
  async #structuredCall(
    system: string,
    user: string,
    // deno-lint-ignore no-explicit-any
    schema: any,
  ): Promise<unknown> {
    return await postJson({
      url: ANTHROPIC_URL,
      headers: this.#headers(),
      provider: "Claude",
      timeoutMs: this.#timeoutMs,
      deadlineMs: this.#deadlineMs,
      body: {
        model: this.model,
        max_tokens: this.#maxTokens,
        // Same pin as transcribe: extraction is deterministic work, and the
        // API's 1.0 default was the source of run-to-run step/chip variance.
        ...this.#sampling(),
        // Prompt caching (GA, no beta header): each phase's system prompt is
        // stable across every call for a given hint set, so mark it as a cache
        // breakpoint. Render order is tools → system → messages, so a breakpoint
        // on the (only) system block reuses the whole ~stable prefix; the volatile
        // per-recipe content stays in the user turn after it. Cuts repeated input
        // cost (verify via usage.cache_read_input_tokens).
        system: [
          {
            type: "text",
            text: system,
            cache_control: { type: "ephemeral" },
          },
        ],
        messages: [{ role: "user", content: user }],
        // Native structured output (Messages API): constrain the response.
        output_config: {
          format: { type: "json_schema", schema },
          ...this.#effortConfig(),
        },
      },
    });
  }

  /**
   * TWO-PHASE sanitize: lines first, then steps against the finished, keyed
   * line list. Step refs and collective membership need the WHOLE line list in
   * view — one-shot extraction made the model reference a list it was still
   * writing, which is where the missed collectives came from. Both verbatim
   * responses persist as one `{two_phase, lines, steps}` wrapper so the eval's
   * save-and-rescore contract holds; usage is emitted once, summed.
   */
  async sanitize(blob: RawBlob, hints: UnitHints): Promise<ExtractionResult> {
    // PRODUCTION PATH — one call, the full schema (keys + steps together).
    if (!this.#twoPhase) {
      const startedAt = performance.now();
      const res = await this.#structuredCall(
        sanitizeSystemPrompt(hints),
        sanitizeUserPrompt(blob),
        EXTRACTION_JSON_SCHEMA,
      );
      this.#emit("sanitize", res, startedAt);
      return decodeClaudeSanitize(res);
    }
    return await this.#sanitizeTwoPhase(blob, hints);
  }

  /** The benchmark-only two-phase path — see `ClaudeAdapterOptions.twoPhase`. */
  async #sanitizeTwoPhase(
    blob: RawBlob,
    hints: UnitHints,
  ): Promise<ExtractionResult> {
    const startedAt = performance.now();
    const linesRes = await this.#structuredCall(
      linesSystemPrompt(hints),
      sanitizeUserPrompt(blob),
      EXTRACTION_JSON_SCHEMA,
    );
    // The phase-2 table renders from the RAW phase-1 JSON (uncoerced) so it
    // shows exactly the keys the model minted. A phase-1 response that cannot
    // parse fails here — same failure surface as the one-shot path.
    const linesTyped = linesRes as AnthropicResponse;
    assertComplete(linesTyped);
    const linesJson = JSON.parse(extractJson(firstText(linesTyped)));
    const stepsRes = await this.#structuredCall(
      stepsSystemPrompt(),
      stepsUserPrompt(blob, linesJson),
      STEPS_JSON_SCHEMA,
    );
    const raw: unknown = { two_phase: true, lines: linesRes, steps: stepsRes };
    emitCall(this.onCall, {
      provider: this.name,
      model: this.model,
      op: "sanitize",
      usage: mergeUsage(anthropicUsage(linesRes), anthropicUsage(stepsRes)),
      latency_ms: Math.round(performance.now() - startedAt),
      raw,
    });
    return decodeClaudeSanitize(raw);
  }
}

/** Null-safe field-wise sum of two usage reports (null only when both are). */
function mergeUsage(
  a: TokenUsage | null,
  b: TokenUsage | null,
): TokenUsage | null {
  if (a === null) return b;
  if (b === null) return a;
  const add = (x: number | null, y: number | null): number | null =>
    x === null && y === null ? null : (x ?? 0) + (y ?? 0);
  return {
    input_tokens: add(a.input_tokens, b.input_tokens),
    output_tokens: add(a.output_tokens, b.output_tokens),
    cache_read_tokens: add(a.cache_read_tokens, b.cache_read_tokens),
    cache_write_tokens: add(a.cache_write_tokens, b.cache_write_tokens),
    reasoning_tokens: add(a.reasoning_tokens, b.reasoning_tokens),
    total_tokens: add(a.total_tokens, b.total_tokens),
  };
}
