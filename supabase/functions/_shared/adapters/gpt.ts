// GPT-5 Mini adapter — behind the frozen ExtractAdapter.
//
// Model id: `gpt-5.4-mini` (the `GPT_MINI_MODEL` constant below; overridable via
// options). NOTE: model id +
// capability facts for OpenAI come from general provider knowledge, not the
// `claude-api` reference (Anthropic-only) — re-confirm against OpenAI's docs
// before the live compare. Vision: yes (image_url data-URI parts). Native
// structured output: Chat Completions `response_format: { type: "json_schema" }`.
// We pass `strict: false` because the token object is an intentionally loose
// tagged shape (only `t` is required), which strict mode forbids; the prompt +
// coercion carry the rest. Raw HTTP keeps the three adapters uniform.
//
// KEYLESS: needs OPENAI_API_KEY for a live call.

import type {
  ExtractAdapter,
  ExtractionResult,
  RawBlob,
  UnitHints,
} from "../types.ts";
import { ImportError } from "../errors.ts";
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

export const GPT_MINI_MODEL = "gpt-5.4-mini";
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

export class GptMiniAdapter implements ExtractAdapter {
  readonly name = "gpt-5-mini";
  readonly #model: string;
  readonly #apiKey: string;
  readonly #maxTokens: number;

  constructor(opts: GptAdapterOptions = {}) {
    this.#model = opts.model ?? GPT_MINI_MODEL;
    this.#apiKey = opts.apiKey ?? requireKey("OPENAI_API_KEY", "GPT");
    this.#maxTokens = opts.maxTokens ?? DEFAULT_MAX_TOKENS;
  }

  #headers(): Record<string, string> {
    return { authorization: `Bearer ${this.#apiKey}` };
  }

  /** `finish_reason: "length"` ⇒ the payload is cut off; never parse it. */
  #assertComplete(res: OpenAiResponse): void {
    if (res.choices?.[0]?.finish_reason === "length") {
      throw new ImportError(
        "this recipe is too long to import in one go — try importing it in parts",
      );
    }
  }

  #firstText(res: OpenAiResponse): string {
    const content = res.choices?.[0]?.message?.content;
    if (!content || content.trim() === "") {
      throw new ExtractionParseError("GPT returned no content", res);
    }
    return content;
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
    const res = await postJson({
      url: OPENAI_URL,
      headers: this.#headers(),
      provider: "GPT",
      body: {
        model: this.#model,
        max_completion_tokens: this.#maxTokens,
        messages: [{ role: "user", content }],
      },
    }) as OpenAiResponse;
    this.#assertComplete(res);
    return {
      source: "transcription",
      url: null,
      jsonld: null,
      text: this.#firstText(res),
    };
  }

  async sanitize(blob: RawBlob, hints: UnitHints): Promise<ExtractionResult> {
    const res = await postJson({
      url: OPENAI_URL,
      headers: this.#headers(),
      provider: "GPT",
      body: {
        model: this.#model,
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
    }) as OpenAiResponse;
    this.#assertComplete(res); // never JSON.parse a truncated payload
    const json = JSON.parse(extractJson(this.#firstText(res)));
    return validateExtractionResult(coerceExtractionResult(json));
  }
}
