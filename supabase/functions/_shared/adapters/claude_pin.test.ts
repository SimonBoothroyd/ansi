// The model pin, held by a test: the id on the wire is the constant, and the
// id a run record reports is that same value.

import { assert, assertEquals } from "@std/assert";
import {
  CLAUDE_HAIKU_MODEL,
  CLAUDE_IMPORT_MODEL,
  ClaudeHaikuAdapter,
} from "./claude.ts";
import { anthropicText } from "./stream_test_helper.ts";
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

/** The narrowest text `decodeClaudeSanitize` accepts. */
const ANSWER = JSON.stringify({
  title: "Dirty Rice",
  groups: [{ name: null, line_items: [] }],
  steps: [],
});

/** Runs one sanitize against a stubbed provider; returns what was posted. */
async function capture(
  adapter: ClaudeHaikuAdapter,
): Promise<{ body: Record<string, unknown>; calls: ProviderCall[] }> {
  const original = globalThis.fetch;
  let body: Record<string, unknown> = {};
  globalThis.fetch = ((_url: string | URL | Request, init?: RequestInit) => {
    body = JSON.parse(String(init?.body)) as Record<string, unknown>;
    return Promise.resolve(anthropicText(ANSWER));
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
  assertEquals(adapter.model, CLAUDE_IMPORT_MODEL);
  const { body } = await capture(adapter);
  assertEquals(body.model, CLAUDE_IMPORT_MODEL);
  // A date-suffixed variant is a different id, not a stricter pin.
  assert(!/-\d{8}$/.test(CLAUDE_IMPORT_MODEL));
  assert(!CLAUDE_IMPORT_MODEL.endsWith("-latest"));
});

Deno.test("production asks for a STREAM — the budgets assume one", async () => {
  // The per-op deadlines are only safe because an idle timer watches the wire.
  // Without `stream: true` a request would sit silent until the platform cut
  // it off.
  const adapter = new ClaudeHaikuAdapter({ apiKey: "test-key" });
  const { body } = await capture(adapter);
  assertEquals(body.stream, true);
});

Deno.test("the run record reports the id that was sent — one source of truth", async () => {
  const adapter = new ClaudeHaikuAdapter({ apiKey: "test-key" });
  const { body, calls } = await capture(adapter);
  assertEquals(calls.length, 1);
  assertEquals(calls[0].model, body.model);
  assertEquals(calls[0].model, CLAUDE_IMPORT_MODEL);
});

Deno.test("Haiku 5.5 with thinking off says so on the wire, and gets no temperature", async () => {
  const { body } = await capture(
    new ClaudeHaikuAdapter({
      apiKey: "test-key",
      model: "claude-haiku-5-5",
      thinking: "disabled",
    }),
  );
  assertEquals(body.thinking, { type: "disabled" });
  assert(!("temperature" in body));
});

Deno.test("the production import sends Haiku 5.5 with thinking off", async () => {
  const { body } = await capture(
    new ClaudeHaikuAdapter({ apiKey: "test-key" }),
  );
  assertEquals(body.model, "claude-haiku-5-5");
  assertEquals(body.thinking, { type: "disabled" });
  assertEquals("temperature" in body, false);
});

Deno.test("Haiku 4.5, named, sends no thinking and is pinned to temperature 0", async () => {
  const { body } = await capture(
    new ClaudeHaikuAdapter({ apiKey: "test-key", model: CLAUDE_HAIKU_MODEL }),
  );
  assertEquals(body.model, "claude-haiku-4-5");
  assert(!("thinking" in body));
  assertEquals(body.temperature, 0);
});
