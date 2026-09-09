// The model pin, held mechanically rather than by a comment.
//
// Two things have to stay true or the pin is decorative: the id on the WIRE is
// the constant (nothing else can slip in as a default), and the id a run record
// reports is that same value — a record that names a model the request did not
// send makes every dated comparison in `evals/runs/` a lie.

import { assert, assertEquals } from "@std/assert";
import { CLAUDE_HAIKU_MODEL, ClaudeHaikuAdapter } from "./claude.ts";
import type { ProviderCall, RawBlob, UnitHints } from "../types.ts";

const HINTS: UnitHints = {
  units: ["g", "cup"],
  imprecise: ["pinch"],
  size_words: ["large"],
  measures: ["clove"],
};

const BLOB: RawBlob = {
  source: "page_text",
  url: "https://example.test/dirty-rice",
  jsonld: null,
  text: "dirty rice\n2 cups long-grain white rice",
};

/** The narrowest response `decodeClaudeSanitize` accepts. */
const RESPONSE = {
  content: [{
    type: "text",
    text: JSON.stringify({
      title: "Dirty Rice",
      groups: [{ name: null, line_items: [] }],
      steps: [],
    }),
  }],
  stop_reason: "end_turn",
  usage: { input_tokens: 10, output_tokens: 20 },
};

/** Runs one sanitize against a stubbed provider; returns what was posted. */
async function capture(
  adapter: ClaudeHaikuAdapter,
): Promise<{ body: Record<string, unknown>; calls: ProviderCall[] }> {
  const original = globalThis.fetch;
  let body: Record<string, unknown> = {};
  globalThis.fetch = ((_url: string | URL | Request, init?: RequestInit) => {
    body = JSON.parse(String(init?.body)) as Record<string, unknown>;
    return Promise.resolve(
      new Response(JSON.stringify(RESPONSE), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
  }) as typeof fetch;
  const calls: ProviderCall[] = [];
  adapter.onCall = (c) => calls.push(c);
  try {
    await adapter.sanitize(BLOB, HINTS);
  } finally {
    globalThis.fetch = original;
  }
  return { body, calls };
}

Deno.test("the id on the wire is the pinned constant, and it carries no date suffix", async () => {
  const adapter = new ClaudeHaikuAdapter({ apiKey: "test-key" });
  assertEquals(adapter.model, CLAUDE_HAIKU_MODEL);
  const { body } = await capture(adapter);
  assertEquals(body.model, CLAUDE_HAIKU_MODEL);
  // A date-suffixed variant is not a stricter pin here, it is a different id —
  // and one the provider does not serve for this tier.
  assert(!/-\d{8}$/.test(CLAUDE_HAIKU_MODEL));
  assert(!CLAUDE_HAIKU_MODEL.endsWith("-latest"));
});

Deno.test("the run record reports the id that was sent — one source of truth", async () => {
  const adapter = new ClaudeHaikuAdapter({ apiKey: "test-key" });
  const { body, calls } = await capture(adapter);
  assertEquals(calls.length, 1);
  assertEquals(calls[0].model, body.model);
  assertEquals(calls[0].model, CLAUDE_HAIKU_MODEL);
});
