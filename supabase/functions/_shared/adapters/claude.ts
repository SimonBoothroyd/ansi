// Claude Haiku adapter — the Haiku tier behind the frozen ExtractAdapter.
//
// Model id pinned via the `claude-api` reference: `CLAUDE_HAIKU_MODEL` below is
// the one source of truth for what production sends, and the same constant is
// what `ProviderCall.model` reports (see `#emit`), so the id in a run record is
// the id that was on the wire. `claude-haiku-4-5` is the Haiku tier; 200K
// context. Vision: yes (image content blocks, base64). Native
// structured output: `output_config.format` with a `json_schema` (the current
// Messages-API mechanism; the deprecated `output_format` is not used). Raw HTTP
// to POST /v1/messages keeps the three adapters uniform and dependency-free.
//
// STREAMING (`stream: true`). Both calls a user waits on stream, and
// `#assembler` folds the frames back into exactly the response shape the
// non-streaming call returned — so the decoders, the usage parsing and every
// saved response in `evals/runs/` are unchanged. It is not about showing text
// as it arrives (nobody reads a JSON payload being typed): it is that a
// streaming call can tell a long answer from a hung one, and can say so out
// loud while it works (`onProgress` ⇒ the function's `heartbeat` frames).
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
 * THE PIN. This exact string is the model every production import is extracted
 * with — there is no alias, no `-latest`, and no date suffix to append: the id
 * IS the version, and a new Haiku generation arrives under a new id rather than
 * re-pointing this one. So the app cannot silently be moved onto a different
 * model by the provider; only an edit here moves it.
 *
 * Which is the point of stating it this plainly. A newer or larger model is not
 * automatically a better extractor — this tier was chosen by measurement, and
 * measured against a blessed gold — so changing this string means RE-RUNNING
 * the extraction eval (`evals/`, `runner/EXTRACTION.md`) and reading its
 * never-invent ledger before the change ships. Adding a `runner/pricing.ts` row
 * for the new id is part of that, or the cost columns go quiet.
 */
export const CLAUDE_HAIKU_MODEL = "claude-haiku-4-5";
/**
 * Benchmark alternates for the eval harness: the current Sonnet and Opus tiers,
 * pinned the same way. Production never sends these — they are what a compare
 * run measures the pin against.
 */
export const CLAUDE_SONNET_MODEL = "claude-sonnet-5";
export const CLAUDE_OPUS_MODEL = "claude-opus-5";
const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
/**
 * `max_tokens` is a CEILING, not a target — an unreached one costs nothing, and
 * a reached one truncates the JSON mid-object. claude-haiku-4-5 tops out at 64K
 * output tokens; we ask for half of that, which no real recipe approaches. (Was
 * 8192, which a long multi-page recipe could genuinely hit.) A ceiling this far
 * above the real answers is only safe BECAUSE the call streams: nothing waits
 * on a whole `max_tokens` worth of generation, it waits on the next delta.
 */
const DEFAULT_MAX_TOKENS = 32_000;

// --- The model rung of the timeout ladder ------------------------------------
//
// Per-OP, because the two calls are not the same size of work and pretending
// they were is what broke a real import: one 60s budget covered transcribe
// (12s) and then aborted sanitize mid-generation, retried into the 13s that
// were left, and aborted again — two paid answers, nothing shown.
//
// Both numbers are sized from `evals/runs/` and both are BACKSTOPS. What
// actually catches a hang is the idle timer in `streamJson`; these bound the
// pathological case where output dribbles out forever.

/**
 * TOTAL budget for one sanitize call. The corpus's biggest structured answer is
 * 4,962 output tokens and its slowest generation ran at 92 tok/s — ~54s for the
 * worst case on the worst day — so this is a little over two times the longest
 * answer we have ever measured. The previous 60s was under it.
 */
export const SANITIZE_DEADLINE_MS = 120_000;
/**
 * TOTAL budget for one transcribe call. No transcribe rows exist in
 * `evals/runs/` (the corpus was recorded through the page-text door), so this
 * is sized from what transcribe EMITS: its output is the page text, and the
 * corpus's source texts run 1.1k–4.7k characters (~280–1,190 tokens) for a one-
 * to two-page recipe. At `MAX_IMAGES` = 8 pages that is ~5k tokens, ~54s at the
 * same 92 tok/s floor. A live two-page import measured 12s.
 */
export const TRANSCRIBE_DEADLINE_MS = 60_000;

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
   * Budgets forwarded to `streamJson`. `idleTimeoutMs` is the SILENCE an
   * attempt is allowed (default 20s); `deadlineMs` overrides BOTH per-op totals
   * ({@link SANITIZE_DEADLINE_MS}, {@link TRANSCRIBE_DEADLINE_MS}) with one
   * number. An adaptive-thinking model streams a long, empty thinking block
   * before it says anything, so benchmark lanes for the Sonnet/Opus tiers MUST
   * raise the idle budget or every call aborts (observed: eleven "signal has
   * been aborted" transcribes in a row).
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
 * Folds an Anthropic message stream back into the SAME object the
 * non-streaming endpoint returns: `{id, model, content, stop_reason, usage,
 * …}`. That equivalence is the whole contract — `decodeClaudeSanitize`,
 * `assertComplete`, `anthropicUsage` and the run records in `evals/runs/` all
 * read the assembled value and none of them can tell which way it arrived.
 *
 * The frames (Messages API, `stream: true`): `message_start` carries the
 * message shell and the input half of `usage`; `content_block_start` opens a
 * block; `content_block_delta` appends to it; `message_delta` carries the final
 * `stop_reason` and the output half of `usage`; `message_stop` ends it. `ping`
 * is a keep-alive. An `error` frame is the provider failing mid-answer.
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
          // TRUE for every delta, text or not: the provider is generating, and
          // that is what makes a retry waste and what a heartbeat reports.
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
          // The provider gave up mid-answer (`overloaded_error` is the common
          // one). 503 is OUR transport classification of it, so the retry
          // policy has one thing to read; the provider's own words ride along
          // in the body for the log.
          throw new ProviderHttpError(provider, 503, JSON.stringify(data));
        default:
          return false; // `ping`, and anything a later API version adds
      }
    },
    finish(): unknown | null {
      // No `message_stop` means the connection died mid-answer. The blocks we
      // have would parse as a truncated recipe — silently losing its tail — so
      // this is a failure, never a partial success.
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
   * `this.onProgress` at call time, so an observer attached after construction
   * (which is how the orchestrator wires heartbeats) is still heard.
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
    const res = await streamJson({
      url: ANTHROPIC_URL,
      headers: this.#headers(),
      ...this.#streamOpts(TRANSCRIBE_DEADLINE_MS),
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
    return await streamJson({
      url: ANTHROPIC_URL,
      headers: this.#headers(),
      ...this.#streamOpts(SANITIZE_DEADLINE_MS),
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
