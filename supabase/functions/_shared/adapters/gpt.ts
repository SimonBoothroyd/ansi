// GPT budget-tier adapter, behind the frozen ExtractAdapter. Benchmark only.
//
// `GPT_MINI_MODEL` is an exact id (the models list carries no dated snapshot
// of it), overridable via options. Vision uses image_url data-URI parts;
// structured output uses Chat Completions
// `response_format: { type: "json_schema" }` with `strict: false`, because the
// token object is a loose tagged shape (only `t` is required), which strict
// mode forbids. Raw HTTP, like the other adapters.
//
// A live call needs OPENAI_API_KEY.

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
/** The id this adapter was pinned to previously; kept for A/B reruns. */
export const GPT_MINI_MODEL_PREVIOUS = "gpt-5.4-mini";
const OPENAI_URL = "https://api.openai.com/v1/chat/completions";
/** A ceiling, not a target: a reached one truncates the JSON. */
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
 * Verbatim response → `ExtractionResult`. Split out of `sanitize` so a saved
 * raw response can be rescored without a second paid call (evals `--rescore`).
 */
export function decodeGptSanitize(res: unknown): ExtractionResult {
  const typed = res as OpenAiResponse;
  assertComplete(typed); // never JSON.parse a truncated payload
  const json = JSON.parse(extractJson(firstText(typed)));
  return validateExtractionResult(coerceExtractionResult(json));
}

/** Verbatim response → the transcription text. */
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
        // No temperature pin: GPT-5-family models reject the parameter.
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
