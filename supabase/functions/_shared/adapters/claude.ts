// Claude Haiku adapter: the Haiku tier behind the frozen ExtractAdapter.
//
// Raw HTTP to POST /v1/messages, like the other adapters. Vision uses base64
// image blocks; structured output uses `output_config.format` with a
// `json_schema`. Both calls stream, and `#assembler` folds the frames back
// into the non-streaming response shape, so decoders, usage parsing and saved
// responses in `evals/runs/` are unaffected. Streaming lets an idle timer tell
// a long answer from a hung one and drives `onProgress` heartbeats.
//
// The stable system prompt carries `cache_control: {type:"ephemeral"}`.
// A live call needs ANTHROPIC_API_KEY; constructing the adapter does not.

import type {
  ExtractAdapter,
  ExtractionResult,
  ProgressSink,
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
  ProviderHttpError,
  requireKey,
  resizeForUpload,
  type StreamAssembler,
  streamJson,
  toBase64,
} from "./http.ts";

/**
 * The pinned model every production import is extracted with, and what
 * `ProviderCall.model` reports. The id is the version: there is no alias or
 * `-latest`. Changing it means re-running the extraction eval (`evals/`,
 * `runner/EXTRACTION.md`) and adding a `runner/pricing.ts` row for the new id.
 */
export const CLAUDE_HAIKU_MODEL = "claude-haiku-4-5";
/** Benchmark alternates for the eval harness. Production never sends these. */
export const CLAUDE_SONNET_MODEL = "claude-sonnet-5";
export const CLAUDE_OPUS_MODEL = "claude-opus-5";
const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
/**
 * A ceiling, not a target: a reached one truncates the JSON mid-object.
 * claude-haiku-4-5 tops out at 64K output tokens; half of that is far above
 * any real recipe, and safe only because the call streams.
 */
const DEFAULT_MAX_TOKENS = 32_000;

// --- The model rung of the timeout ladder ------------------------------------
//
// Budgets are per op, because transcribe and sanitize are different sizes of
// work. Both are backstops sized from `evals/runs/`; the idle timer in
// `streamJson` is what catches a hang.

/**
 * Total budget for one sanitize call: a little over twice the longest measured
 * answer (4,962 output tokens at 92 tok/s, ~54s).
 */
export const SANITIZE_DEADLINE_MS = 120_000;
/**
 * Total budget for one transcribe call. Sized from its output, the page text:
 * ~5k tokens at `MAX_IMAGES` = 8 pages, ~54s at 92 tok/s.
 */
export const TRANSCRIBE_DEADLINE_MS = 60_000;

export interface ClaudeAdapterOptions {
  apiKey?: string; // defaults to ANTHROPIC_API_KEY
  model?: string; // defaults to CLAUDE_HAIKU_MODEL
  maxTokens?: number;
  name?: string; // provider label in benchmark/usage rows; defaults to "claude-haiku"
  /**
   * `output_config.effort` for the Sonnet 5 / Opus 5 tiers. Leave unset for
   * Haiku 4.5, which rejects the parameter.
   */
  effort?: "low" | "medium" | "high";
  /**
   * Run sanitize as two calls (lines, then steps against the keyed line list)
   * instead of one. Benchmark only: it measured flat on ref F1 at +40% cost,
   * so production is one-shot.
   */
  twoPhase?: boolean;
  /**
   * Budgets forwarded to `streamJson`. `idleTimeoutMs` is the silence an
   * attempt is allowed (default 20s); `deadlineMs` overrides both per-op totals
   * ({@link SANITIZE_DEADLINE_MS}, {@link TRANSCRIBE_DEADLINE_MS}). An
   * adaptive-thinking model streams a long empty thinking block first, so
   * Sonnet/Opus benchmark lanes must raise the idle budget.
   */
  idleTimeoutMs?: number;
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

function obj(v: unknown): Record<string, unknown> | null {
  return typeof v === "object" && v !== null
    ? v as Record<string, unknown>
    : null;
}

/**
 * Folds an Anthropic message stream back into the object the non-streaming
 * endpoint returns (`{id, model, content, stop_reason, usage, …}`), so nothing
 * downstream can tell which way it arrived.
 *
 * Frames: `message_start` carries the shell and the input half of `usage`;
 * `content_block_start`/`content_block_delta` build a block; `message_delta`
 * carries `stop_reason` and the output half of `usage`; `message_stop` ends
 * it. `ping` is a keep-alive. An `error` frame is the provider failing.
 */
export function anthropicAssembler(provider: string): StreamAssembler {
  const blocks: AnthropicContentBlock[] = [];
  let shell: Record<string, unknown> = {};
  let stopped = false;
  return {
    push(event: string, data: unknown): boolean {
      const d = obj(data) ?? {};
      switch (event) {
        case "message_start": {
          shell = { ...(obj(d.message) ?? {}) };
          return false;
        }
        case "content_block_start": {
          const index = typeof d.index === "number" ? d.index : blocks.length;
          const start = obj(d.content_block) ?? {};
          blocks[index] = {
            ...start,
            type: typeof start.type === "string" ? start.type : "text",
            text: typeof start.text === "string" ? start.text : "",
          } as AnthropicContentBlock;
          return false;
        }
        case "content_block_delta": {
          const index = typeof d.index === "number" ? d.index : 0;
          const delta = obj(d.delta) ?? {};
          const block = blocks[index] ??= { type: "text", text: "" };
          if (delta.type === "text_delta" && typeof delta.text === "string") {
            block.text = (block.text ?? "") + delta.text;
          }
          // True for every delta, text or not: the provider is generating.
          return true;
        }
        case "message_delta": {
          shell = { ...shell, ...(obj(d.delta) ?? {}) };
          const usage = obj(d.usage);
          // Merged, not replaced: `message_start` holds the input and cache
          // counts, `message_delta` the final output count.
          if (usage) shell.usage = { ...(obj(shell.usage) ?? {}), ...usage };
          return false;
        }
        case "message_stop":
          stopped = true;
          return false;
        case "error":
          // The provider gave up mid-answer (`overloaded_error`, usually).
          // Classified as 503 so the retry policy has one thing to read.
          throw new ProviderHttpError(provider, 503, JSON.stringify(data));
        default:
          return false; // `ping`, and anything a later API version adds
      }
    },
    finish(): unknown | null {
      // No `message_stop` means the connection died mid-answer: a failure,
      // never a partial success.
      if (!stopped) return null;
      return { ...shell, content: blocks.filter((b) => b !== undefined) };
    },
  };
}

function firstText(res: AnthropicResponse): string {
  const block = (res.content ?? []).find((b) => b.type === "text" && b.text);
  if (!block?.text) {
    throw new ExtractionParseError("Claude returned no text content", res);
  }
  return block.text;
}

/**
 * A `max_tokens` stop means the JSON was cut off mid-object, which could
 * silently drop the tail of a recipe. Fail with a 422 instead.
 */
function assertComplete(res: AnthropicResponse): void {
  if (res.stop_reason === "max_tokens") {
    throw new ImportError(
      "this recipe is too long to import in one go — try importing it in parts",
    );
  }
}

/**
 * Verbatim response → `ExtractionResult`, split out of `sanitize` so a saved
 * raw response can be re-decoded without a second paid call (evals
 * `--rescore`). It includes the truncation check.
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
    // Two-phase: merge the lines JSON with the steps JSON and coerce once, so
    // the steps' key refs resolve as a one-shot response's would.
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

/** Verbatim response → the transcription text. */
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
  /** Told on every delta while a call streams (see `ExtractAdapter`). */
  onProgress?: ProgressSink;

  constructor(opts: ClaudeAdapterOptions = {}) {
    this.model = opts.model ?? CLAUDE_HAIKU_MODEL;
    this.name = opts.name ?? "claude-haiku";
    this.#apiKey = opts.apiKey ?? requireKey("ANTHROPIC_API_KEY", "Claude");
    this.#maxTokens = opts.maxTokens ?? DEFAULT_MAX_TOKENS;
    this.#effort = opts.effort;
    this.#idleTimeoutMs = opts.idleTimeoutMs;
    this.#twoPhase = opts.twoPhase ?? false;
    this.#deadlineMs = opts.deadlineMs;
  }

  readonly #effort?: "low" | "medium" | "high";
  readonly #twoPhase: boolean;
  readonly #idleTimeoutMs?: number;
  readonly #deadlineMs?: number;

  /**
   * The budgets and the observer every model call shares. `onDelta` reads
   * `this.onProgress` at call time, so an observer attached later is heard.
   */
  #streamOpts(deadlineMs: number) {
    return {
      provider: "Claude",
      assembler: () => anthropicAssembler("Claude"),
      deadlineMs: this.#deadlineMs ?? deadlineMs,
      idleTimeoutMs: this.#idleTimeoutMs,
      onDelta: () => this.onProgress?.(),
    };
  }

  /** `output_config.effort`, when configured. */
  #effortConfig(): { effort?: string } {
    return this.#effort ? { effort: this.#effort } : {};
  }

  /**
   * Pins temperature 0 where the API takes one: Haiku 4.5 accepts sampling
   * params; the Sonnet-5/Opus-5 generation rejects them with a 400.
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
    const res = await streamJson({
      url: ANTHROPIC_URL,
      headers: this.#headers(),
      ...this.#streamOpts(TRANSCRIBE_DEADLINE_MS),
      body: {
        model: this.model,
        max_tokens: this.#maxTokens,
        // Unpinned, the API defaults to temperature 1.0 and the same page
        // transcribes differently run to run.
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
    return await streamJson({
      url: ANTHROPIC_URL,
      headers: this.#headers(),
      ...this.#streamOpts(SANITIZE_DEADLINE_MS),
      body: {
        model: this.model,
        max_tokens: this.#maxTokens,
        // Same pin as transcribe.
        ...this.#sampling(),
        // Prompt caching: the system prompt is stable per hint set, so it is
        // the cache breakpoint; the per-recipe content stays in the user turn.
        system: [
          {
            type: "text",
            text: system,
            cache_control: { type: "ephemeral" },
          },
        ],
        messages: [{ role: "user", content: user }],
        // Native structured output.
        output_config: {
          format: { type: "json_schema", schema },
          ...this.#effortConfig(),
        },
      },
    });
  }

  /**
   * One call in production. The two-phase path persists both verbatim
   * responses as one `{two_phase, lines, steps}` wrapper so save-and-rescore
   * holds; usage is emitted once, summed.
   */
  async sanitize(blob: RawBlob, hints: UnitHints): Promise<ExtractionResult> {
    // Production path: one call, the full schema.
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

  /** The benchmark-only two-phase path; see `ClaudeAdapterOptions.twoPhase`. */
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
    // The phase-2 table renders from the raw phase-1 JSON, so it shows exactly
    // the keys the model minted. An unparseable phase-1 response fails here.
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
