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
  UnitHints,
} from "../types.ts";
import { ImportError } from "../errors.ts";
import { anthropicUsage, emitCall } from "./usage.ts";
import {
  coerceExtractionResult,
  EXTRACTION_JSON_SCHEMA,
  ExtractionParseError,
  validateExtractionResult,
} from "./schema.ts";
import {
  sanitizeSystemPrompt,
  sanitizeUserPrompt,
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
export function decodeClaudeSanitize(res: unknown): ExtractionResult {
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
  readonly name = "claude-haiku";
  readonly model: string;
  readonly #apiKey: string;
  readonly #maxTokens: number;
  /** Optional benchmark observer; unset in production (see `ExtractAdapter`). */
  onCall?: ProviderCallSink;

  constructor(opts: ClaudeAdapterOptions = {}) {
    this.model = opts.model ?? CLAUDE_HAIKU_MODEL;
    this.#apiKey = opts.apiKey ?? requireKey("ANTHROPIC_API_KEY", "Claude");
    this.#maxTokens = opts.maxTokens ?? DEFAULT_MAX_TOKENS;
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
      body: {
        model: this.model,
        max_tokens: this.#maxTokens,
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

  async sanitize(blob: RawBlob, hints: UnitHints): Promise<ExtractionResult> {
    const startedAt = performance.now();
    const res = await postJson({
      url: ANTHROPIC_URL,
      headers: this.#headers(),
      provider: "Claude",
      body: {
        model: this.model,
        max_tokens: this.#maxTokens,
        // Prompt caching (GA, no beta header): the sanitize system prompt is
        // stable across every call for a given hint set, so mark it as a cache
        // breakpoint. Render order is tools → system → messages, so a breakpoint
        // on the (only) system block reuses the whole ~stable prefix; the volatile
        // per-recipe blob stays in the user turn after it. Cuts repeated input cost
        // (verify via usage.cache_read_input_tokens). The prompt is well over the
        // ~1024-token minimum cacheable prefix.
        system: [
          {
            type: "text",
            text: sanitizeSystemPrompt(hints),
            cache_control: { type: "ephemeral" },
          },
        ],
        messages: [{ role: "user", content: sanitizeUserPrompt(blob) }],
        // Native structured output (Messages API): constrain the response to the
        // extraction schema.
        output_config: {
          format: {
            type: "json_schema",
            schema: EXTRACTION_JSON_SCHEMA,
          },
        },
      },
    });
    this.#emit("sanitize", res, startedAt);
    return decodeClaudeSanitize(res);
  }
}
