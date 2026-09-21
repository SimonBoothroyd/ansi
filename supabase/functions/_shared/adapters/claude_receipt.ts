// The receipt adapter: the same Haiku tier and plumbing as `claude.ts`.
//
// It imports the model pin (`CLAUDE_HAIKU_MODEL`), so a receipt cannot drift
// onto a different model than a recipe, and shares the streaming transport,
// frame assembler, per-op budgets, prompt caching, `resizeForUpload` and
// structured output.
//
//   * `transcribe` returns one string per photo, split on the `[PHOTO BREAK]`
//     the prompt asks for. The join is ours (`receipt_join.ts`).
//   * `structure` reads the joined strip. It never sees the vocabulary and
//     does not match (ADR-0004).
//
// A live call needs ANTHROPIC_API_KEY; constructing the adapter does not.

import type { ReceiptAdapter, ReceiptExtraction } from "../receipt_types.ts";
import { ImportError } from "../errors.ts";
import type { ProviderCallSink } from "../types.ts";
import { anthropicUsage, emitCall } from "./usage.ts";
import {
  anthropicAssembler,
  CLAUDE_HAIKU_MODEL,
  SANITIZE_DEADLINE_MS,
  TRANSCRIBE_DEADLINE_MS,
} from "./claude.ts";
import {
  coerceReceiptExtraction,
  validateReceiptExtraction,
} from "./receipt_schema.ts";
import { ExtractionParseError } from "./schema.ts";
import {
  PHOTO_BREAK,
  RECEIPT_JSON_SCHEMA,
  RECEIPT_SYSTEM_PROMPT,
  RECEIPT_TRANSCRIBE_PROMPT,
  receiptUserPrompt,
} from "../prompts/receipt.ts";
import {
  extractJson,
  IMAGE_MEDIA_TYPE,
  requireKey,
  resizeForUpload,
  streamJson,
  toBase64,
} from "./http.ts";

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

/** Same ceiling as the recipe pipeline's; a receipt never approaches it. */
const DEFAULT_MAX_TOKENS = 32_000;

/**
 * The budgets are the recipe pipeline's, imported: both receipt calls emit
 * less than the recipe calls those numbers were sized for, so the ladder in
 * `_shared/timeouts.test.ts` covers this function. If a receipt ever needs
 * more, it needs its own constants and its own row in that test.
 */
export const RECEIPT_TRANSCRIBE_DEADLINE_MS = TRANSCRIBE_DEADLINE_MS;
export const RECEIPT_STRUCTURE_DEADLINE_MS = SANITIZE_DEADLINE_MS;

interface AnthropicContentBlock {
  type: string;
  text?: string;
}
interface AnthropicResponse {
  content?: AnthropicContentBlock[];
  stop_reason?: string | null;
}

/**
 * The verbatim response's text block. Separate from `claude.ts`'s
 * `firstText`/`assertComplete` only so the cut-off message says "this
 * receipt".
 */
function receiptText(res: unknown): string {
  const typed = res as AnthropicResponse;
  if (typed?.stop_reason === "max_tokens") {
    throw new ImportError(
      "this receipt is too long to read in one go — try it in more, " +
        "shorter photos",
    );
  }
  const block = (typed?.content ?? []).find((b) => b.type === "text" && b.text);
  if (!block?.text) {
    throw new ExtractionParseError("Claude returned no text content", res);
  }
  return block.text;
}

/**
 * Verbatim response → one transcription per photo. Split out so a saved
 * response replays through the same decoder. A dropped or merged break gives a
 * different count than photos sent; the segments come back as they are and the
 * orchestrator notes the mismatch.
 */
export function decodeClaudeReceiptTranscribe(res: unknown): string[] {
  return receiptText(res)
    .split(PHOTO_BREAK)
    .map((s) => s.trim())
    .filter((s) => s !== "");
}

/** Verbatim response → the frozen `ReceiptExtraction`, coerced. */
export function decodeClaudeReceiptStructure(res: unknown): ReceiptExtraction {
  const json = JSON.parse(extractJson(receiptText(res)));
  return validateReceiptExtraction(coerceReceiptExtraction(json));
}

export interface ClaudeReceiptAdapterOptions {
  apiKey?: string; // defaults to ANTHROPIC_API_KEY
  model?: string; // defaults to the shared pin
  maxTokens?: number;
  name?: string;
  idleTimeoutMs?: number;
  /** Overrides both per-op budgets with one number (benchmark lanes only). */
  deadlineMs?: number;
}

export class ClaudeReceiptAdapter implements ReceiptAdapter {
  readonly name: string;
  readonly model: string;
  readonly #apiKey: string;
  readonly #maxTokens: number;
  readonly #idleTimeoutMs?: number;
  readonly #deadlineMs?: number;
  /** Optional benchmark observer; unset in production. */
  onCall?: ProviderCallSink;
  /** Told on every delta while a call streams; drives `heartbeat` frames. */
  onProgress?: () => void;

  constructor(opts: ClaudeReceiptAdapterOptions = {}) {
    this.model = opts.model ?? CLAUDE_HAIKU_MODEL;
    this.name = opts.name ?? "claude-haiku-receipt";
    this.#apiKey = opts.apiKey ?? requireKey("ANTHROPIC_API_KEY", "Claude");
    this.#maxTokens = opts.maxTokens ?? DEFAULT_MAX_TOKENS;
    this.#idleTimeoutMs = opts.idleTimeoutMs;
    this.#deadlineMs = opts.deadlineMs;
  }

  #headers(): Record<string, string> {
    return {
      "x-api-key": this.#apiKey,
      "anthropic-version": ANTHROPIC_VERSION,
    };
  }

  #streamOpts(deadlineMs: number) {
    return {
      provider: "Claude",
      assembler: () => anthropicAssembler("Claude"),
      deadlineMs: this.#deadlineMs ?? deadlineMs,
      idleTimeoutMs: this.#idleTimeoutMs,
      onDelta: () => this.onProgress?.(),
    };
  }

  /** Haiku still takes the sampling params; pin temperature 0. */
  #sampling(): { temperature?: number } {
    return this.model.includes("haiku") ? { temperature: 0 } : {};
  }

  #emit(op: "transcribe" | "sanitize", raw: unknown, startedAt: number): void {
    emitCall(this.onCall, {
      provider: this.name,
      model: this.model,
      op,
      usage: anthropicUsage(raw),
      latency_ms: Math.round(performance.now() - startedAt),
      raw,
    });
  }

  async transcribe(images: Uint8Array[]): Promise<string[]> {
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
      { type: "text", text: RECEIPT_TRANSCRIBE_PROMPT },
    ];
    const startedAt = performance.now();
    const res = await streamJson({
      url: ANTHROPIC_URL,
      headers: this.#headers(),
      ...this.#streamOpts(RECEIPT_TRANSCRIBE_DEADLINE_MS),
      body: {
        model: this.model,
        max_tokens: this.#maxTokens,
        ...this.#sampling(),
        messages: [{ role: "user", content }],
      },
    });
    this.#emit("transcribe", res, startedAt);
    return decodeClaudeReceiptTranscribe(res);
  }

  async structure(transcript: string): Promise<ReceiptExtraction> {
    const startedAt = performance.now();
    const res = await streamJson({
      url: ANTHROPIC_URL,
      headers: this.#headers(),
      ...this.#streamOpts(RECEIPT_STRUCTURE_DEADLINE_MS),
      body: {
        model: this.model,
        max_tokens: this.#maxTokens,
        ...this.#sampling(),
        // Prompt caching: the system block is identical on every receipt, so
        // it is the cache breakpoint.
        system: [
          {
            type: "text",
            text: RECEIPT_SYSTEM_PROMPT,
            cache_control: { type: "ephemeral" },
          },
        ],
        messages: [{ role: "user", content: receiptUserPrompt(transcript) }],
        output_config: {
          format: { type: "json_schema", schema: RECEIPT_JSON_SCHEMA },
        },
      },
    });
    this.#emit("sanitize", res, startedAt);
    return decodeClaudeReceiptStructure(res);
  }
}
