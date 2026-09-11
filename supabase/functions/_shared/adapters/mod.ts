// Adapter registry + re-exports. The eval harness swaps adapters by name to
// compare providers; the edge function wires the chosen one. The three real adapters
// build keyless (their constructors only demand a key when actually
// instantiated live); the mock needs no key at all.

export {
  decodeMockSanitize,
  fixedMock,
  MOCK_MODEL,
  MockAdapter,
  mockUsage,
} from "./mock.ts";
export type { MockAdapterOptions } from "./mock.ts";
export {
  CLAUDE_HAIKU_MODEL,
  CLAUDE_OPUS_MODEL,
  CLAUDE_SONNET_MODEL,
  ClaudeHaikuAdapter,
  decodeClaudeSanitize,
  decodeClaudeTranscribe,
} from "./claude.ts";
export {
  decodeGeminiSanitize,
  decodeGeminiTranscribe,
  GEMINI_FLASH_MODEL,
  GEMINI_FLASH_MODEL_PREVIOUS,
  GeminiFlashAdapter,
} from "./gemini.ts";
export {
  decodeGptSanitize,
  decodeGptTranscribe,
  GPT_MINI_MODEL,
  GPT_MINI_MODEL_PREVIOUS,
  GptMiniAdapter,
} from "./gpt.ts";
export {
  anthropicUsage,
  emptyUsage,
  geminiUsage,
  openAiUsage,
} from "./usage.ts";
export {
  coerceExtractionResult,
  EXTRACTION_JSON_SCHEMA,
  ExtractionParseError,
  flattenLines,
  structuralIssues,
  validateExtractionResult,
} from "./schema.ts";
export { MissingKeyError, ProviderHttpError } from "./http.ts";

import type { ExtractAdapter, ExtractionResult } from "../types.ts";
import {
  CLAUDE_HAIKU_MODEL,
  CLAUDE_OPUS_MODEL,
  CLAUDE_SONNET_MODEL,
  ClaudeHaikuAdapter,
} from "./claude.ts";
import { GEMINI_FLASH_MODEL, GeminiFlashAdapter } from "./gemini.ts";
import { GPT_MINI_MODEL, GptMiniAdapter } from "./gpt.ts";
import { decodeClaudeSanitize } from "./claude.ts";
import { decodeGeminiSanitize } from "./gemini.ts";
import { decodeGptSanitize } from "./gpt.ts";

/** The provider adapters the eval harness benchmarks (the mock is constructed separately). */
export type ProviderName =
  | "claude-haiku"
  | "claude-sonnet"
  | "claude-sonnet-low"
  | "claude-opus"
  | "claude-opus-low"
  | "gemini-flash"
  | "gpt-5-mini";

export const PROVIDER_NAMES: ProviderName[] = [
  "claude-haiku",
  "claude-sonnet",
  "claude-sonnet-low",
  "claude-opus",
  "claude-opus-low",
  "gemini-flash",
  "gpt-5-mini",
];

/**
 * HTTP budgets for the adaptive-thinking benchmark lanes. The production
 * defaults serve a user on a spinner and abort a Sonnet/Opus call that is
 * legitimately still thinking (observed: every claude-sonnet transcribe in the
 * first ref-recall run died "signal has been aborted"). Thinking streams as
 * empty blocks with `display: "omitted"`, so the SILENCE those lanes can
 * produce is real and long — hence four minutes of idle, and ten for the whole
 * call. Benchmarks have no user waiting. Production stays on the defaults —
 * Haiku answers well inside them.
 */
const BENCH_BUDGETS = { idleTimeoutMs: 240_000, deadlineMs: 600_000 };

/**
 * Builds a live provider adapter by name. Throws `MissingKeyError` when the
 * provider's key env var is unset — callers doing keyless runs should catch it
 * and fall back to the mock.
 */
export function buildProvider(name: ProviderName): ExtractAdapter {
  switch (name) {
    case "claude-haiku":
      return new ClaudeHaikuAdapter();
    case "claude-sonnet":
      return new ClaudeHaikuAdapter({
        model: CLAUDE_SONNET_MODEL,
        name,
        ...BENCH_BUDGETS,
      });
    case "claude-sonnet-low":
      return new ClaudeHaikuAdapter({
        model: CLAUDE_SONNET_MODEL,
        name,
        effort: "low",
        ...BENCH_BUDGETS,
      });
    case "claude-opus":
      return new ClaudeHaikuAdapter({
        model: CLAUDE_OPUS_MODEL,
        name,
        ...BENCH_BUDGETS,
      });
    case "claude-opus-low":
      return new ClaudeHaikuAdapter({
        model: CLAUDE_OPUS_MODEL,
        name,
        effort: "low",
        ...BENCH_BUDGETS,
      });
    case "gemini-flash":
      return new GeminiFlashAdapter();
    case "gpt-5-mini":
      return new GptMiniAdapter();
  }
}

/** The pinned model id each provider name sends — no key or network needed. */
export const PROVIDER_MODELS: Record<ProviderName, string> = {
  "claude-haiku": CLAUDE_HAIKU_MODEL,
  "claude-sonnet": CLAUDE_SONNET_MODEL,
  "claude-sonnet-low": CLAUDE_SONNET_MODEL,
  "claude-opus": CLAUDE_OPUS_MODEL,
  "claude-opus-low": CLAUDE_OPUS_MODEL,
  "gemini-flash": GEMINI_FLASH_MODEL,
  "gpt-5-mini": GPT_MINI_MODEL,
};

/**
 * VERBATIM provider response → `ExtractionResult`, by provider name. This is
 * what makes a paid run re-scoreable: the benchmark persists each raw response
 * and later replays it through the SAME decode the live call used, so a scorer
 * or gold fix never costs a second run.
 */
export const RESPONSE_DECODERS: Record<
  ProviderName,
  (raw: unknown) => ExtractionResult
> = {
  "claude-haiku": decodeClaudeSanitize,
  "claude-sonnet": decodeClaudeSanitize,
  "claude-sonnet-low": decodeClaudeSanitize,
  "claude-opus": decodeClaudeSanitize,
  "claude-opus-low": decodeClaudeSanitize,
  "gemini-flash": decodeGeminiSanitize,
  "gpt-5-mini": decodeGptSanitize,
};
