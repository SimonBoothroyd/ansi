// Per-provider token-usage parsing, normalized onto the `TokenUsage` contract
// in `../types.ts`.
//
// The vendors disagree: Anthropic's `input_tokens` excludes cache reads and
// writes, while OpenAI's `prompt_tokens` and Gemini's `promptTokenCount`
// include the cached part; Gemini reports thinking tokens outside
// `candidatesTokenCount`, OpenAI inside `completion_tokens`. Normalized:
// `input_tokens` = uncached, non-cache-write input; `output_tokens` =
// everything billed at the output rate. An unreported field is `null`.

import type { ProviderCall, ProviderCallSink, TokenUsage } from "../types.ts";

/** All-null usage: the provider reported nothing. */
export function emptyUsage(): TokenUsage {
  return {
    input_tokens: null,
    output_tokens: null,
    cache_read_tokens: null,
    cache_write_tokens: null,
    reasoning_tokens: null,
    total_tokens: null,
  };
}

/** A finite non-negative number, or null. Providers do send nulls and strings. */
function num(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : null;
}

/** `a - b`, clamped at 0, null-safe (null minuend ⇒ null). */
function less(a: number | null, b: number | null): number | null {
  if (a === null) return null;
  return Math.max(0, a - (b ?? 0));
}

interface Record_ {
  [k: string]: unknown;
}
function obj(v: unknown): Record_ | null {
  return typeof v === "object" && v !== null ? v as Record_ : null;
}

/** Anthropic `usage`. `input_tokens` already excludes both cache fields. */
export function anthropicUsage(res: unknown): TokenUsage | null {
  const u = obj(obj(res)?.usage);
  if (!u) return null;
  const input = num(u.input_tokens);
  const output = num(u.output_tokens);
  const read = num(u.cache_read_input_tokens);
  const write = num(u.cache_creation_input_tokens);
  return {
    input_tokens: input,
    output_tokens: output,
    cache_read_tokens: read,
    cache_write_tokens: write,
    reasoning_tokens: null, // not separately reported
    total_tokens: input === null && output === null
      ? null
      : (input ?? 0) + (output ?? 0) + (read ?? 0) + (write ?? 0),
  };
}

/**
 * OpenAI Chat Completions `usage`. `prompt_tokens` includes the cached part,
 * which is subtracted; `completion_tokens` already includes reasoning tokens,
 * which are reported but not added again.
 */
export function openAiUsage(res: unknown): TokenUsage | null {
  const u = obj(obj(res)?.usage);
  if (!u) return null;
  const cached = num(obj(u.prompt_tokens_details)?.cached_tokens);
  const prompt = num(u.prompt_tokens);
  return {
    input_tokens: less(prompt, cached),
    output_tokens: num(u.completion_tokens),
    cache_read_tokens: cached,
    cache_write_tokens: null, // OpenAI caching is automatic and not billed
    reasoning_tokens: num(obj(u.completion_tokens_details)?.reasoning_tokens),
    total_tokens: num(u.total_tokens),
  };
}

/**
 * Gemini `usageMetadata`. `promptTokenCount` includes the cached part, which
 * is subtracted; `thoughtsTokenCount` sits outside `candidatesTokenCount` but
 * is billed as output, so it is added in.
 */
export function geminiUsage(res: unknown): TokenUsage | null {
  const u = obj(obj(res)?.usageMetadata);
  if (!u) return null;
  const cached = num(u.cachedContentTokenCount);
  const prompt = num(u.promptTokenCount);
  const candidates = num(u.candidatesTokenCount);
  const thoughts = num(u.thoughtsTokenCount);
  return {
    input_tokens: less(prompt, cached),
    output_tokens: candidates === null && thoughts === null
      ? null
      : (candidates ?? 0) + (thoughts ?? 0),
    cache_read_tokens: cached,
    cache_write_tokens: null, // explicit cache creation is a separate endpoint
    reasoning_tokens: thoughts,
    total_tokens: num(u.totalTokenCount),
  };
}

/** Hands one completed call to an observer, if any, swallowing its errors. */
export function emitCall(
  sink: ProviderCallSink | undefined,
  call: ProviderCall,
): void {
  if (!sink) return;
  try {
    sink(call);
  } catch (e) {
    console.error(
      `onCall observer threw (ignored): ${
        e instanceof Error ? e.message : String(e)
      }`,
    );
  }
}
