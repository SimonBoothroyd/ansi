// Adapter registry + re-exports. Lane D swaps adapters by name to compare
// providers; lane A wires the chosen one at the tail. The three real adapters
// build keyless (their constructors only demand a key when actually
// instantiated live); the mock needs no key at all.

export { fixedMock, MockAdapter } from "./mock.ts";
export type { MockAdapterOptions } from "./mock.ts";
export { CLAUDE_HAIKU_MODEL, ClaudeHaikuAdapter } from "./claude.ts";
export { GEMINI_FLASH_MODEL, GeminiFlashAdapter } from "./gemini.ts";
export { GPT_MINI_MODEL, GptMiniAdapter } from "./gpt.ts";
export {
  coerceExtractionResult,
  EXTRACTION_JSON_SCHEMA,
  ExtractionParseError,
  flattenLines,
  structuralIssues,
  validateExtractionResult,
} from "./schema.ts";
export { MissingKeyError, ProviderHttpError } from "./http.ts";

import type { ExtractAdapter } from "../types.ts";
import { ClaudeHaikuAdapter } from "./claude.ts";
import { GeminiFlashAdapter } from "./gemini.ts";
import { GptMiniAdapter } from "./gpt.ts";

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
