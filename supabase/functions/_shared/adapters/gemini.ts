// Gemini Flash adapter — behind the frozen ExtractAdapter.
//
// Model id: `gemini-3.7-flash` (the `GEMINI_FLASH_MODEL` constant below).
// CONFIRMED 2026-08-31 against Google's own model-list endpoint
// (`GET /v1beta/models`, which reports version `3.7-flash-08-2026` (verify on first live call)) and
// https://ai.google.dev/gemini-api/docs/models. This replaces the previous
// `gemini-flash-latest` pin, which was an ALIAS — the 0018 convention is exact
// ids, because an alias silently re-points and makes two dated benchmark runs
// incomparable. Vision: yes (inline_data image parts). Native structured
// output: `responseMimeType: "application/json"` + `responseSchema` in
// generationConfig. Raw HTTP to the Generative Language REST endpoint keeps the
// three adapters uniform.
//
// KEYLESS: needs GEMINI_API_KEY (or GOOGLE_API_KEY) for a live call.

import type {
  ExtractAdapter,
  ExtractionResult,
  ProviderCallSink,
  RawBlob,
  UnitHints,
} from "../types.ts";
import { ImportError } from "../errors.ts";
import { emitCall, geminiUsage } from "./usage.ts";
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

export const GEMINI_FLASH_MODEL = "gemini-3.7-flash";
/** The alias this adapter used before 2026-08-31 — kept for A/B reruns only. */
export const GEMINI_FLASH_MODEL_PREVIOUS = "gemini-flash-latest";
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

/** `finishReason: "MAX_TOKENS"` ⇒ the payload is cut off; never parse it. */
function assertComplete(res: GeminiResponse): void {
  if (res.candidates?.[0]?.finishReason === "MAX_TOKENS") {
    throw new ImportError(
      "this recipe is too long to import in one go — try importing it in parts",
    );
  }
}

function firstText(res: GeminiResponse): string {
  const parts = res.candidates?.[0]?.content?.parts ?? [];
  const text = parts.map((p) => p.text ?? "").join("");
  if (text.trim() === "") {
    throw new ExtractionParseError("Gemini returned no text", res);
  }
  return text;
}

/**
 * VERBATIM response → `ExtractionResult`. Split out of `sanitize` so a saved raw
 * response can be rescored later with no second paid call (evals `--rescore`).
 */
export function decodeGeminiSanitize(res: unknown): ExtractionResult {
  const typed = res as GeminiResponse;
  assertComplete(typed); // never JSON.parse a truncated payload
  const json = JSON.parse(extractJson(firstText(typed)));
  return validateExtractionResult(coerceExtractionResult(json));
}

/** VERBATIM response → the transcription text (the D1 half of the decode). */
export function decodeGeminiTranscribe(res: unknown): string {
  const typed = res as GeminiResponse;
  assertComplete(typed);
  return firstText(typed);
}

export class GeminiFlashAdapter implements ExtractAdapter {
  readonly name = "gemini-flash";
  readonly model: string;
  readonly #apiKey: string;
  /** Optional benchmark observer; unset in production (see `ExtractAdapter`). */
  onCall?: ProviderCallSink;

  constructor(opts: GeminiAdapterOptions = {}) {
    this.model = opts.model ?? GEMINI_FLASH_MODEL;
    this.#apiKey = resolveKey(opts.apiKey);
  }

  #url(): string {
    return `${GEMINI_BASE}/${this.model}:generateContent`;
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
      usage: geminiUsage(raw),
      latency_ms: Math.round(performance.now() - startedAt),
      raw,
    });
  }

  /**
   * The key goes in a HEADER, never the query string: URLs are the most-logged
   * string in any stack (proxies, error reporters, our own ProviderHttpError
   * message), and `?key=…` leaks the secret into every one of them.
   */
  #headers(): Record<string, string> {
    return { "x-goog-api-key": this.#apiKey };
  }

  async transcribe(images: Uint8Array[]): Promise<RawBlob> {
    const resized = await Promise.all(images.map(resizeForUpload));
    const parts = [
      ...resized.map((img) => ({
        inline_data: { mime_type: IMAGE_MEDIA_TYPE, data: toBase64(img) },
      })),
      { text: TRANSCRIBE_PROMPT },
    ];
    const startedAt = performance.now();
    const res = await postJson({
      url: this.#url(),
      headers: this.#headers(),
      provider: "Gemini",
      body: {
        contents: [{ role: "user", parts }],
        generationConfig: { maxOutputTokens: DEFAULT_MAX_OUTPUT_TOKENS },
      },
    });
    this.#emit("transcribe", res, startedAt);
    return {
      source: "transcription",
      url: null,
      jsonld: null,
      text: decodeGeminiTranscribe(res),
    };
  }

  async sanitize(blob: RawBlob, hints: UnitHints): Promise<ExtractionResult> {
    const startedAt = performance.now();
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
    });
    this.#emit("sanitize", res, startedAt);
    return decodeGeminiSanitize(res);
  }
}
