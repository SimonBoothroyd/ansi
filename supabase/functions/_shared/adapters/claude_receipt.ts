// The receipt adapter — the same Haiku tier, the same plumbing, a different
// document.
//
// It shares everything that can be shared with `claude.ts`: THE PIN
// (`CLAUDE_HAIKU_MODEL` — imported, never re-declared, so a receipt can never
// drift onto a different model than a recipe), the streaming transport and its
// idle timer (`streamJson`), the frame assembler, the per-op budgets, prompt
// caching on the static system block, the phone-side-downscale safety net
// (`resizeForUpload`), and native JSON-schema structured output.
//
// What is its own is the shape of the work:
//
//   * `transcribe` returns ONE STRING PER PHOTO. The prompt asks for a
//     `[PHOTO BREAK]` between segments and this splits on it, because the join
//     is positional and ours (`receipt_join.ts`) — the model is never asked
//     whether a repeated line is an overlap or a second banana.
//   * `structure` reads the JOINED strip and prints what the paper printed. It
//     is not shown the vocabulary and it does not match (ADR-0004).
//
// KEYLESS to construct and to `deno check`; a live call needs ANTHROPIC_API_KEY.

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

/**
 * Same ceiling as the recipe pipeline's, and for the same reason: an unreached
 * ceiling costs nothing, a reached one truncates JSON mid-object. A receipt is
 * a far smaller document than a multi-page recipe, so this is never approached.
 */
const DEFAULT_MAX_TOKENS = 32_000;

/**
 * The budgets are the recipe pipeline's, imported rather than re-chosen.
 *
 * That is a claim, so it is worth stating: a receipt transcribe emits less text
 * than a recipe transcribe (a till strip is short lines and few of them) and a
 * receipt structure emits a flat line list where a recipe emits groups, steps
 * and token arrays. Both calls here are strictly smaller than the calls those
 * numbers were sized for in `evals/runs/`, so the ladder in
 * `_shared/timeouts.test.ts` covers this function without a second set of rungs
 * to keep in step. If a receipt ever needs MORE than a recipe, it needs its own
 * constants and its own row in that test — not a nudge to these.
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
 * The verbatim response's text block. The twin of `claude.ts`'s private
 * `firstText`/`assertComplete` pair, separate only because the sentence a
 * person is shown when the answer was cut off has to name what they were
 * doing — "this receipt", not "this recipe" — and a shared one would name
 * neither.
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
 * VERBATIM response → one transcription per photo. Split out so a saved
 * response can be replayed through the same decoder the live call used.
 *
 * `expected` is how many photos were sent. A model that dropped or merged a
 * break leaves us with a different count — which is a real reading of the
 * paper, not a failure, so the segments come back as they are and the
 * orchestrator notes the mismatch for the review.
 */
export function decodeClaudeReceiptTranscribe(res: unknown): string[] {
  return receiptText(res)
    .split(PHOTO_BREAK)
    .map((s) => s.trim())
    .filter((s) => s !== "");
}

/** VERBATIM response → the frozen `ReceiptExtraction`, coercion and all. */
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
  /** Overrides BOTH per-op budgets with one number (benchmark lanes only). */
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
  /** Told on every delta while a call streams ⇒ the function's `heartbeat` frames. */
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

  /** Haiku still takes the sampling params; reading paper is deterministic work. */
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
        // Prompt caching (GA, no beta header): the system block is identical on
        // every receipt this app will ever send, so it is a cache breakpoint
        // and the volatile strip stays in the user turn after it.
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
