// Gemini Flash adapter — behind the frozen ExtractAdapter.
//
// Model id: `gemini-flash-latest` (the `GEMINI_FLASH_MODEL` constant below —
// the current Flash tier; overridable via options). NOTE: model id + capability
// facts for Gemini come from general
// provider knowledge, not the `claude-api` reference (which is Anthropic-only) —
// re-confirm against Google's docs before the live compare. Vision: yes
// (inline_data image parts). Native structured output: `responseMimeType:
// "application/json"` + `responseSchema` in generationConfig. Raw HTTP to the
// Generative Language REST endpoint keeps the three adapters uniform.
//
// KEYLESS: needs GEMINI_API_KEY (or GOOGLE_API_KEY) for a live call.

import type {
  ExtractAdapter,
  ExtractionResult,
  RawBlob,
  UnitHints,
} from "../types.ts";
import { ImportError } from "../errors.ts";
import {
  coerceExtractionResult,
  ExtractionParseError,
  validateExtractionResult,
} from "./schema.ts";
import { toGeminiSchema } from "./gemini_schema.ts";
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

export const GEMINI_FLASH_MODEL = "gemini-flash-latest";
const GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta/models";

export interface GeminiAdapterOptions {
  apiKey?: string; // defaults to GEMINI_API_KEY, then GOOGLE_API_KEY
  model?: string;
}

/**
 * A ceiling, not a target — unreached it costs nothing, reached it truncates the
 * JSON. Well inside the Flash tier's output limit.
 */
const DEFAULT_MAX_OUTPUT_TOKENS = 32_000;

interface GeminiPart {
  text?: string;
}
interface GeminiResponse {
  candidates?: {
    content?: { parts?: GeminiPart[] };
    finishReason?: string | null;
  }[];
}

function resolveKey(explicit?: string): string {
  if (explicit) return explicit;
  const g = Deno.env.get("GEMINI_API_KEY") ?? Deno.env.get("GOOGLE_API_KEY");
  if (g && g.trim() !== "") return g;
  return requireKey("GEMINI_API_KEY", "Gemini");
}

export class GeminiFlashAdapter implements ExtractAdapter {
  readonly name = "gemini-flash";
  readonly #model: string;
  readonly #apiKey: string;

  constructor(opts: GeminiAdapterOptions = {}) {
    this.#model = opts.model ?? GEMINI_FLASH_MODEL;
    this.#apiKey = resolveKey(opts.apiKey);
  }

  #url(): string {
    return `${GEMINI_BASE}/${this.#model}:generateContent`;
  }

  /**
   * The key goes in a HEADER, never the query string: URLs are the most-logged
   * string in any stack (proxies, error reporters, our own ProviderHttpError
   * message), and `?key=…` leaks the secret into every one of them.
   */
  #headers(): Record<string, string> {
    return { "x-goog-api-key": this.#apiKey };
  }

  /** `finishReason: "MAX_TOKENS"` ⇒ the payload is cut off; never parse it. */
  #assertComplete(res: GeminiResponse): void {
    if (res.candidates?.[0]?.finishReason === "MAX_TOKENS") {
      throw new ImportError(
        "this recipe is too long to import in one go — try importing it in parts",
      );
    }
  }

  #firstText(res: GeminiResponse): string {
    const parts = res.candidates?.[0]?.content?.parts ?? [];
    const text = parts.map((p) => p.text ?? "").join("");
    if (text.trim() === "") {
      throw new ExtractionParseError("Gemini returned no text", res);
    }
    return text;
  }

  async transcribe(images: Uint8Array[]): Promise<RawBlob> {
    const resized = await Promise.all(images.map(resizeForUpload));
    const parts = [
      ...resized.map((img) => ({
        inline_data: { mime_type: IMAGE_MEDIA_TYPE, data: toBase64(img) },
      })),
      { text: TRANSCRIBE_PROMPT },
    ];
    const res = await postJson({
      url: this.#url(),
      headers: this.#headers(),
      provider: "Gemini",
      body: {
        contents: [{ role: "user", parts }],
        generationConfig: { maxOutputTokens: DEFAULT_MAX_OUTPUT_TOKENS },
      },
    }) as GeminiResponse;
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
      url: this.#url(),
      headers: this.#headers(),
      provider: "Gemini",
      body: {
        systemInstruction: { parts: [{ text: sanitizeSystemPrompt(hints) }] },
        contents: [{
          role: "user",
          parts: [{ text: sanitizeUserPrompt(blob) }],
        }],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: toGeminiSchema(),
          maxOutputTokens: DEFAULT_MAX_OUTPUT_TOKENS,
        },
      },
    }) as GeminiResponse;
    this.#assertComplete(res); // never JSON.parse a truncated payload
    const json = JSON.parse(extractJson(this.#firstText(res)));
    return validateExtractionResult(coerceExtractionResult(json));
  }
}
