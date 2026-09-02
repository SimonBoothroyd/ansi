// GPT budget-tier adapter — behind the frozen ExtractAdapter.
//
// Model id: `gpt-5.6-luna` (the `GPT_MINI_MODEL` constant below; overridable via
// options). CONFIRMED 2026-08-31 against OpenAI's own model-list endpoint
// (`GET /v1/models`) and https://developers.openai.com/api/docs/models — the
// GPT-5.6 family renamed its tiers (sol = flagship, terra = mid, luna = budget),
// so `luna` is the successor to the `-mini` tier this adapter was pinned to
// (`gpt-5.4-mini`). It is an EXACT id, not an alias: the models list carries no
// dated `gpt-5.6-luna-YYYY-MM-DD` snapshot, so this string IS the pin.
// Vision: yes (image_url data-URI parts). Native structured output: Chat
// Completions `response_format: { type: "json_schema" }`. We pass
// `strict: false` because the token object is an intentionally loose tagged
// shape (only `t` is required), which strict mode forbids; the prompt +
// coercion carry the rest. Raw HTTP keeps the three adapters uniform.
//
// KEYLESS: needs OPENAI_API_KEY for a live call.

import type {
  ExtractAdapter,
  ExtractionResult,
  ProviderCallSink,
  RawBlob,
  UnitHints,
} from "../types.ts";
import { ImportError } from "../errors.ts";
import { emitCall, openAiUsage } from "./usage.ts";
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

export const GPT_MINI_MODEL = "gpt-5.6-luna";
/** The id this adapter was pinned to before 2026-08-31 — kept for A/B reruns. */
export const GPT_MINI_MODEL_PREVIOUS = "gpt-5.4-mini";
const OPENAI_URL = "https://api.openai.com/v1/chat/completions";
/**
 * A ceiling, not a target — unreached it costs nothing, reached it truncates the
 * JSON. Well inside this tier's output limit and far above any real recipe.
 * (Was 8192, which a long multi-page recipe could genuinely hit.)
 */
const DEFAULT_MAX_TOKENS = 32_000;

export interface GptAdapterOptions {
  apiKey?: string; // defaults to OPENAI_API_KEY
  model?: string;
  maxTokens?: number;
}

interface OpenAiResponse {
  choices?: { message?: { content?: string }; finish_reason?: string | null }[];
}

/** `finish_reason: "length"` ⇒ the payload is cut off; never parse it. */
function assertComplete(res: OpenAiResponse): void {
  if (res.choices?.[0]?.finish_reason === "length") {
    throw new ImportError(
      "this recipe is too long to import in one go — try importing it in parts",
    );
  }
}

function firstText(res: OpenAiResponse): string {
  const content = res.choices?.[0]?.message?.content;
  if (!content || content.trim() === "") {
    throw new ExtractionParseError("GPT returned no content", res);
  }
  return content;
}

/**
 * VERBATIM response → `ExtractionResult`. Split out of `sanitize` so a saved raw
 * response can be rescored later with no second paid call (evals `--rescore`).
 */
export function decodeGptSanitize(res: unknown): ExtractionResult {
  const typed = res as OpenAiResponse;
  assertComplete(typed); // never JSON.parse a truncated payload
  const json = JSON.parse(extractJson(firstText(typed)));
  return validateExtractionResult(coerceExtractionResult(json));
}

/** VERBATIM response → the transcription text (the D1 half of the decode). */
export function decodeGptTranscribe(res: unknown): string {
  const typed = res as OpenAiResponse;
  assertComplete(typed);
  return firstText(typed);
}

export class GptMiniAdapter implements ExtractAdapter {
  readonly name = "gpt-5-mini";
  readonly model: string;
  readonly #apiKey: string;
  readonly #maxTokens: number;
  /** Optional benchmark observer; unset in production (see `ExtractAdapter`). */
  onCall?: ProviderCallSink;

  constructor(opts: GptAdapterOptions = {}) {
    this.model = opts.model ?? GPT_MINI_MODEL;
    this.#apiKey = opts.apiKey ?? requireKey("OPENAI_API_KEY", "GPT");
    this.#maxTokens = opts.maxTokens ?? DEFAULT_MAX_TOKENS;
  }

  #headers(): Record<string, string> {
    return { authorization: `Bearer ${this.#apiKey}` };
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
      usage: openAiUsage(raw),
      latency_ms: Math.round(performance.now() - startedAt),
      raw,
    });
  }

  async transcribe(images: Uint8Array[]): Promise<RawBlob> {
    const resized = await Promise.all(images.map(resizeForUpload));
    const content = [
      { type: "text", text: TRANSCRIBE_PROMPT },
      ...resized.map((img) => ({
        type: "image_url",
        image_url: {
          url: `data:${IMAGE_MEDIA_TYPE};base64,${toBase64(img)}`,
        },
      })),
    ];
    const startedAt = performance.now();
    const res = await postJson({
      url: OPENAI_URL,
      headers: this.#headers(),
      provider: "GPT",
      body: {
        model: this.model,
        max_completion_tokens: this.#maxTokens,
        // No temperature pin here, unlike claude.ts/gemini.ts: GPT-5-family
        // models reject the parameter (only the default is supported).
        messages: [{ role: "user", content }],
      },
    });
    this.#emit("transcribe", res, startedAt);
    return {
      source: "transcription",
      url: null,
      jsonld: null,
      text: decodeGptTranscribe(res),
    };
  }

  async sanitize(blob: RawBlob, hints: UnitHints): Promise<ExtractionResult> {
    const startedAt = performance.now();
    const res = await postJson({
      url: OPENAI_URL,
      headers: this.#headers(),
      provider: "GPT",
      body: {
        model: this.model,
        max_completion_tokens: this.#maxTokens,
        messages: [
          { role: "system", content: sanitizeSystemPrompt(hints) },
          { role: "user", content: sanitizeUserPrompt(blob) },
        ],
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "extraction_result",
            strict: false,
            schema: EXTRACTION_JSON_SCHEMA,
          },
        },
      },
    });
    this.#emit("sanitize", res, startedAt);
    return decodeGptSanitize(res);
  }
}
