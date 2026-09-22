// The label adapter: the same Haiku tier and plumbing as `claude_receipt.ts`.
//
// It imports the model pin (`CLAUDE_HAIKU_MODEL`), so a label cannot drift onto
// a different model than a receipt, and shares the streaming transport, frame
// assembler, prompt caching, `resizeForUpload` and structured output.
//
// One call: the image plus the reading prompt, answered as the JSON the schema
// describes. There is no second tier, because there is nothing to structure
// afterwards — a label IS the structure.
//
// A live call needs ANTHROPIC_API_KEY; constructing the adapter does not.

import type { LabelAdapter, LabelReading } from "../label_types.ts";
import { ImportError } from "../errors.ts";
import type { ProviderCallSink } from "../types.ts";
import { anthropicUsage, emitCall } from "./usage.ts";
import {
  anthropicAssembler,
  CLAUDE_HAIKU_MODEL,
  TRANSCRIBE_DEADLINE_MS,
} from "./claude.ts";
import { coerceLabelReading, validateLabelReading } from "./label_schema.ts";
import { ExtractionParseError } from "./schema.ts";
import {
  LABEL_JSON_SCHEMA,
  LABEL_SYSTEM_PROMPT,
  LABEL_USER_PROMPT,
} from "../prompts/label.ts";
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

/** A label's reading is a few dozen numbers; this is never approached. */
const DEFAULT_MAX_TOKENS = 4_000;

/**
 * The budget for the one call. It is the recipe pipeline's vision budget,
 * imported: reading a label is strictly less work than transcribing a page of
 * receipt, so the ladder in `_shared/timeouts.test.ts` covers this door too.
 *
 * Unlike the two import doors, this one does NOT stream its answer to the app
 * and sends no heartbeat, so this budget has to fit inside the platform's idle
 * timeout on its own. `timeouts.test.ts` asserts exactly that.
 */
export const LABEL_DEADLINE_MS = TRANSCRIBE_DEADLINE_MS;

interface AnthropicContentBlock {
  type: string;
  text?: string;
}
interface AnthropicResponse {
  content?: AnthropicContentBlock[];
  stop_reason?: string | null;
}

/** The verbatim response's text block, in this door's words. */
function labelText(res: unknown): string {
  const typed = res as AnthropicResponse;
  if (typed?.stop_reason === "max_tokens") {
    throw new ImportError(
      "we could not finish reading that label — try a closer photo of the " +
        "nutrition panel on its own",
    );
  }
  const block = (typed?.content ?? []).find((b) => b.type === "text" && b.text);
  if (!block?.text) {
    throw new ExtractionParseError("Claude returned no text content", res);
  }
  return block.text;
}

/** Verbatim response → the frozen `LabelReading`, coerced. Replayable. */
export function decodeClaudeLabel(res: unknown): LabelReading {
  const json = JSON.parse(extractJson(labelText(res)));
  return validateLabelReading(coerceLabelReading(json));
}

export interface ClaudeLabelAdapterOptions {
  apiKey?: string; // defaults to ANTHROPIC_API_KEY
  model?: string; // defaults to the shared pin
  maxTokens?: number;
  name?: string;
  idleTimeoutMs?: number;
  /** Overrides the budget with one number (benchmark lanes only). */
  deadlineMs?: number;
}

export class ClaudeLabelAdapter implements LabelAdapter {
  readonly name: string;
  readonly model: string;
  readonly #apiKey: string;
  readonly #maxTokens: number;
  readonly #idleTimeoutMs?: number;
  readonly #deadlineMs?: number;
  /** Optional benchmark observer; unset in production. */
  onCall?: ProviderCallSink;

  constructor(opts: ClaudeLabelAdapterOptions = {}) {
    this.model = opts.model ?? CLAUDE_HAIKU_MODEL;
    this.name = opts.name ?? "claude-haiku-label";
    this.#apiKey = opts.apiKey ?? requireKey("ANTHROPIC_API_KEY", "Claude");
    this.#maxTokens = opts.maxTokens ?? DEFAULT_MAX_TOKENS;
    this.#idleTimeoutMs = opts.idleTimeoutMs;
    this.#deadlineMs = opts.deadlineMs;
  }

  /** Haiku still takes the sampling params; pin temperature 0. */
  #sampling(): { temperature?: number } {
    return this.model.includes("haiku") ? { temperature: 0 } : {};
  }

  async read(image: Uint8Array): Promise<LabelReading> {
    const resized = await resizeForUpload(image);
    const startedAt = performance.now();
    const res = await streamJson({
      url: ANTHROPIC_URL,
      headers: {
        "x-api-key": this.#apiKey,
        "anthropic-version": ANTHROPIC_VERSION,
      },
      provider: "Claude",
      assembler: () => anthropicAssembler("Claude"),
      deadlineMs: this.#deadlineMs ?? LABEL_DEADLINE_MS,
      idleTimeoutMs: this.#idleTimeoutMs,
      body: {
        model: this.model,
        max_tokens: this.#maxTokens,
        ...this.#sampling(),
        // Prompt caching: the system block is identical on every label, so it
        // is the cache breakpoint.
        system: [
          {
            type: "text",
            text: LABEL_SYSTEM_PROMPT,
            cache_control: { type: "ephemeral" },
          },
        ],
        messages: [{
          role: "user",
          content: [
            {
              type: "image",
              source: {
                type: "base64",
                media_type: IMAGE_MEDIA_TYPE,
                data: toBase64(resized),
              },
            },
            { type: "text", text: LABEL_USER_PROMPT },
          ],
        }],
        output_config: {
          format: { type: "json_schema", schema: LABEL_JSON_SCHEMA },
        },
      },
    });
    emitCall(this.onCall, {
      provider: this.name,
      model: this.model,
      op: "transcribe",
      usage: anthropicUsage(res),
      latency_ms: Math.round(performance.now() - startedAt),
      raw: res,
    });
    return decodeClaudeLabel(res);
  }
}
