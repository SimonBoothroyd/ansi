// Adapter registry + re-exports. Lane D swaps adapters by name to compare
// providers; lane A wires the chosen one at the tail. The three real adapters
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
import { CLAUDE_HAIKU_MODEL, ClaudeHaikuAdapter } from "./claude.ts";
import { GEMINI_FLASH_MODEL, GeminiFlashAdapter } from "./gemini.ts";
import { GPT_MINI_MODEL, GptMiniAdapter } from "./gpt.ts";
import { decodeClaudeSanitize } from "./claude.ts";
import { decodeGeminiSanitize } from "./gemini.ts";
import { decodeGptSanitize } from "./gpt.ts";

/** The provider adapters lane D benchmarks (the mock is constructed separately). */
export type ProviderName = "claude-haiku" | "gemini-flash" | "gpt-5-mini";

export const PROVIDER_NAMES: ProviderName[] = [
  "claude-haiku",
  "gemini-flash",
  "gpt-5-mini",
];

/**
 * Builds a live provider adapter by name. Throws `MissingKeyError` when the
 * provider's key env var is unset — callers doing keyless runs should catch it
 * and fall back to the mock.
 */
export function buildProvider(name: ProviderName): ExtractAdapter {
  switch (name) {
    case "claude-haiku":
      return new ClaudeHaikuAdapter();
    case "gemini-flash":
      return new GeminiFlashAdapter();
    case "gpt-5-mini":
      return new GptMiniAdapter();
  }
}

/** The pinned model id each provider name sends — no key or network needed. */
export const PROVIDER_MODELS: Record<ProviderName, string> = {
  "claude-haiku": CLAUDE_HAIKU_MODEL,
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
  "gemini-flash": decodeGeminiSanitize,
  "gpt-5-mini": decodeGptSanitize,
};
