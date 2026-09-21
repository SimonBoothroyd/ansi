// The usage parsers feed every dollar figure the benchmark prints, so the
// vendors' disagreements about their own totals are pinned here.

import { assertEquals } from "@std/assert";
import {
  anthropicUsage,
  emitCall,
  emptyUsage,
  geminiUsage,
  openAiUsage,
} from "./usage.ts";
import { MockAdapter, mockUsage } from "./mock.ts";
import type { ProviderCall, RawBlob, UnitHints } from "../types.ts";
import { coerceExtractionResult } from "./schema.ts";

/** A minimal, valid ExtractionResult. */
function blank(title: string) {
  return coerceExtractionResult({ title });
}

const HINTS: UnitHints = {
  units: [],
  imprecise: [],
  size_words: [],
  measures: [],
};

Deno.test("anthropicUsage — input_tokens already excludes both cache fields", () => {
  const u = anthropicUsage({
    usage: {
      input_tokens: 100,
      output_tokens: 40,
      cache_read_input_tokens: 900,
      cache_creation_input_tokens: 50,
    },
  });
  // Passed through: Anthropic does not fold cached tokens into its prompt
  // count, so subtracting would double-count.
  assertEquals(u?.input_tokens, 100);
  assertEquals(u?.cache_read_tokens, 900);
  assertEquals(u?.cache_write_tokens, 50);
  assertEquals(u?.total_tokens, 1090);
});

Deno.test("openAiUsage — cached tokens are subtracted out of prompt_tokens", () => {
  const u = openAiUsage({
    usage: {
      prompt_tokens: 1000,
      completion_tokens: 200,
      total_tokens: 1200,
      prompt_tokens_details: { cached_tokens: 800 },
      completion_tokens_details: { reasoning_tokens: 120 },
    },
  });
  assertEquals(u?.input_tokens, 200); // 1000 − 800, NOT 1000
  assertEquals(u?.cache_read_tokens, 800);
  // reasoning is already inside completion_tokens — reported, never re-added.
  assertEquals(u?.output_tokens, 200);
  assertEquals(u?.reasoning_tokens, 120);
});

Deno.test("geminiUsage — cached subtracted from prompt, thoughts added to output", () => {
  const u = geminiUsage({
    usageMetadata: {
      promptTokenCount: 1000,
      cachedContentTokenCount: 250,
      candidatesTokenCount: 300,
      thoughtsTokenCount: 700,
      totalTokenCount: 2000,
    },
  });
  assertEquals(u?.input_tokens, 750);
  assertEquals(u?.cache_read_tokens, 250);
  // Gemini reports thinking outside candidatesTokenCount but bills it as
  // output, so the normalized output count includes it.
  assertEquals(u?.output_tokens, 1000);
  assertEquals(u?.reasoning_tokens, 700);
  assertEquals(u?.total_tokens, 2000);
});

Deno.test("usage parsers — a response with no usage block yields null", () => {
  assertEquals(anthropicUsage({ content: [] }), null);
  assertEquals(openAiUsage({ choices: [] }), null);
  assertEquals(geminiUsage({ candidates: [] }), null);
  assertEquals(anthropicUsage(null), null);
});

Deno.test("usage parsers — an unreported field stays null, never 0", () => {
  const u = anthropicUsage({ usage: { input_tokens: 10 } });
  // "Not reported" must stay distinguishable from zero.
  assertEquals(u?.cache_read_tokens, null);
  assertEquals(u?.output_tokens, null);
  assertEquals(emptyUsage().input_tokens, null);
});

Deno.test("usage parsers — a cached count larger than the prompt clamps at 0", () => {
  const u = openAiUsage({
    usage: {
      prompt_tokens: 100,
      prompt_tokens_details: { cached_tokens: 500 },
    },
  });
  assertEquals(u?.input_tokens, 0); // never negative
});

Deno.test("emitCall — an observer that throws is swallowed", () => {
  let reached = false;
  emitCall(() => {
    throw new Error("observer bug");
  }, {
    provider: "x",
    model: "m",
    op: "sanitize",
    usage: null,
    latency_ms: 0,
    raw: null,
  });
  reached = true;
  // A benchmark observer must never be able to fail a user's import.
  assertEquals(reached, true);
});

Deno.test("MockAdapter — emits deterministic usage and the result as raw", async () => {
  const result = blank("Test");
  const calls: ProviderCall[] = [];
  const adapter = new MockAdapter({ sanitizeWith: () => result });
  adapter.onCall = (c) => calls.push(c);
  const blob: RawBlob = {
    source: "page_text",
    url: null,
    jsonld: null,
    text: "a".repeat(400),
  };
  const got = await adapter.sanitize(blob, HINTS);
  assertEquals(calls.length, 1);
  assertEquals(calls[0].model, "mock-1");
  assertEquals(calls[0].op, "sanitize");
  // 400 chars ⇒ 100 estimated tokens, a tenth modelled as a cache hit.
  assertEquals(calls[0].usage?.input_tokens, 90);
  assertEquals(calls[0].usage?.cache_read_tokens, 10);
  assertEquals(calls[0].raw, got); // the mock's "raw response" IS the result
  // Deterministic: the same pair always yields the same numbers.
  assertEquals(mockUsage(blob.text ?? "", got), calls[0].usage);
});

Deno.test("MockAdapter — no observer set means no capture and no throw", async () => {
  const adapter = new MockAdapter({
    sanitizeWith: () => (blank("T")),
  });
  const got = await adapter.sanitize(
    { source: "page_text", url: null, jsonld: null, text: "x" },
    HINTS,
  );
  assertEquals(got.title, "T");
});
