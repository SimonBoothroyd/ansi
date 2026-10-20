// The ask adapter: one Messages API call per turn, tools declared, nothing
// executed here (plan 0053).
//
// Its own model pin, not `CLAUDE_HAIKU_MODEL`: the import doors' pin was
// chosen by their extraction evals, and this door's is chosen by its own
// (`evals/ask`). Claude Haiku 5.5 takes no sampling parameters and no
// prefill, runs adaptive thinking by default, and binds a thinking block to
// the history before it — so the request sends no `temperature`, the app
// keeps the conversation append-only, and blocks come back verbatim.
//
// Not streamed. An answer is a sentence or a tool call, well inside one
// plain call's budget, and the stream assembler (`claude.ts`) folds text only;
// tool calls and thinking signatures would need their own deltas assembled.
//
// A live call needs ANTHROPIC_API_KEY; constructing the adapter does not
// when a key is passed.

import type {
  AskAdapter,
  AskBlock,
  AskMessage,
  AskReply,
} from "../ask_types.ts";
import { ImportError } from "../errors.ts";
import type { ProviderCallSink } from "../types.ts";
import { ASK_SYSTEM_PROMPT, ASK_TOOLS } from "../prompts/ask.ts";
import { postJson, requireKey } from "./http.ts";
import { anthropicUsage, emitCall } from "./usage.ts";

/** The ask door's pin. The complete id: no alias, no date suffix. */
export const CLAUDE_ASK_MODEL = "claude-haiku-5-5";

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

/** Room for adaptive thinking plus a two-sentence answer or a tool call. */
const DEFAULT_MAX_TOKENS = 4_000;

/**
 * The whole turn's budget, retries included. The app waits
 * `askTurnTimeout` (60 s, `remote_ask_repository.dart`), so this sits below
 * it: the server gives up with a sentence before the app gives up on silence.
 */
export const ASK_DEADLINE_MS = 30_000;

/** One attempt's wall clock, so a hung socket leaves room for a retry. */
const ASK_ATTEMPT_TIMEOUT_MS = 20_000;

/** The block types a reply may carry back to the app. */
const KEPT_BLOCKS = new Set([
  "thinking",
  "redacted_thinking",
  "text",
  "tool_use",
]);

interface AnthropicResponse {
  content?: unknown[];
  stop_reason?: string | null;
}

/** The verbatim response → the reply the app is sent. Replayable. */
export function decodeAskReply(res: unknown): AskReply {
  const typed = res as AnthropicResponse;
  const stop = typeof typed?.stop_reason === "string"
    ? typed.stop_reason
    : "end_turn";
  if (stop === "refusal") {
    // The app drops the question rather than store half an answer.
    return { content: [], stop_reason: "refusal" };
  }
  const content = (typed?.content ?? []).filter((b): b is AskBlock =>
    typeof b === "object" && b !== null &&
    typeof (b as AskBlock).type === "string" &&
    KEPT_BLOCKS.has((b as AskBlock).type)
  );
  if (!content.some((b) => b.type === "text" || b.type === "tool_use")) {
    throw new ImportError(
      "Ansi did not finish an answer — try asking again",
    );
  }
  return { content, stop_reason: stop };
}

export interface ClaudeAskAdapterOptions {
  apiKey?: string; // defaults to ANTHROPIC_API_KEY
  model?: string; // defaults to CLAUDE_ASK_MODEL
  maxTokens?: number;
  /** Fetch seam for tests. */
  fetchImpl?: typeof fetch;
}

export class ClaudeAskAdapter implements AskAdapter {
  readonly model: string;
  readonly #apiKey: string;
  readonly #maxTokens: number;
  readonly #fetchImpl?: typeof fetch;
  /** Optional observer (evals); unset in production. */
  onCall?: ProviderCallSink;

  constructor(opts: ClaudeAskAdapterOptions = {}) {
    this.model = opts.model ?? CLAUDE_ASK_MODEL;
    this.#apiKey = opts.apiKey ?? requireKey("ANTHROPIC_API_KEY", "Claude");
    this.#maxTokens = opts.maxTokens ?? DEFAULT_MAX_TOKENS;
    this.#fetchImpl = opts.fetchImpl;
  }

  /** The request body for [messages]. Exposed for the pin and cache tests. */
  body(messages: AskMessage[]): Record<string, unknown> {
    return {
      model: this.model,
      max_tokens: this.#maxTokens,
      // The tools render before the system block, so this one breakpoint
      // caches both: neither varies between requests.
      system: [
        {
          type: "text",
          text: ASK_SYSTEM_PROMPT,
          cache_control: { type: "ephemeral" },
        },
      ],
      tools: ASK_TOOLS,
      tool_choice: { type: "auto" },
      // The conversation, cached too: the API puts this breakpoint on the
      // last block and moves it as the thread grows, so a question's tool
      // rounds (seconds apart) and a follow-up within five minutes read the
      // thread back at a tenth of the price instead of sending it again. A
      // write costs 1.25x, and only on what the last turn added.
      cache_control: { type: "ephemeral" },
      // Resolving "how much tamari" is a lookup, not a puzzle.
      output_config: { effort: "low" },
      messages,
    };
  }

  async turn(messages: AskMessage[]): Promise<AskReply> {
    const startedAt = performance.now();
    const res = await postJson({
      url: ANTHROPIC_URL,
      headers: {
        "x-api-key": this.#apiKey,
        "anthropic-version": ANTHROPIC_VERSION,
      },
      provider: "Claude",
      body: this.body(messages),
      deadlineMs: ASK_DEADLINE_MS,
      timeoutMs: ASK_ATTEMPT_TIMEOUT_MS,
      fetchImpl: this.#fetchImpl,
    });
    const usage = anthropicUsage(res);
    // One line per turn, so the spend can be read off the function log.
    console.log(
      `ask: ${this.model} in=${usage?.input_tokens ?? "?"} ` +
        `out=${usage?.output_tokens ?? "?"} ` +
        `cache_read=${usage?.cache_read_tokens ?? "?"}`,
    );
    emitCall(this.onCall, {
      provider: "claude-ask",
      model: this.model,
      op: "ask",
      usage,
      latency_ms: Math.round(performance.now() - startedAt),
      raw: res,
    });
    return decodeAskReply(res);
  }
}
