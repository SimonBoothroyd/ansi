// The ask adapter: the pin on the wire, the request Claude Haiku 5.5 accepts,
// and what a response decodes to. The provider is a stubbed fetch.

import { assert, assertEquals, assertRejects } from "@std/assert";
import type { AskMessage } from "../ask_types.ts";
import { ASK_TOOLS } from "../prompts/ask.ts";
import {
  CLAUDE_ASK_MODEL,
  ClaudeAskAdapter,
  decodeAskReply,
} from "./claude_ask.ts";

const QUESTION: AskMessage[] = [{ role: "user", content: "how much tamari?" }];

function stub(response: unknown, seen: Record<string, unknown>[] = []) {
  return ((_url: string | URL | Request, init?: RequestInit) => {
    seen.push(JSON.parse(String(init?.body)) as Record<string, unknown>);
    return Promise.resolve(
      new Response(JSON.stringify(response), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
  }) as typeof fetch;
}

const TOOL_CALL = {
  content: [
    { type: "thinking", thinking: "", signature: "sig" },
    {
      type: "tool_use",
      id: "toolu_1",
      name: "recipe_lines",
      input: {
        recipe_id: "r1",
        servings: null,
        ingredient: "tamari",
        for_week: null,
      },
    },
  ],
  stop_reason: "tool_use",
  usage: { input_tokens: 10, output_tokens: 5 },
};

Deno.test("the pin — the id on the wire is the constant, complete, with no date suffix", async () => {
  assertEquals(CLAUDE_ASK_MODEL, "claude-haiku-5-5");
  assert(!/-\d{8}$/.test(CLAUDE_ASK_MODEL));
  const seen: Record<string, unknown>[] = [];
  const adapter = new ClaudeAskAdapter({
    apiKey: "test-key",
    fetchImpl: stub(TOOL_CALL, seen),
  });
  await adapter.turn(QUESTION);
  assertEquals(seen[0].model, CLAUDE_ASK_MODEL);
});

Deno.test("the request — what Claude Haiku 5.5 accepts: no sampling, no prefill, auto tools", () => {
  const body = new ClaudeAskAdapter({ apiKey: "k" }).body(QUESTION);
  // Non-default sampling parameters are a 400 on this model.
  for (const key of ["temperature", "top_p", "top_k"]) {
    assert(!(key in body), key);
  }
  // Forced tool use would skip thinking; the prompt says when to call.
  assertEquals(body.tool_choice, { type: "auto" });
  assertEquals(body.output_config, { effort: "low" });
  // The messages go through as sent, ending on the member: no prefill.
  assertEquals(body.messages, QUESTION);
  // One breakpoint, on the system block, caches tools and system together.
  const system = body.system as Record<string, unknown>[];
  assertEquals(system.length, 1);
  assertEquals(system[0].cache_control, { type: "ephemeral" });
});

Deno.test("the tools — the six slice-1 names the app executes, every one strict", () => {
  assertEquals(ASK_TOOLS.map((t) => t.name), [
    "find_recipe",
    "recipe_lines",
    "method_step",
    "start_step_timer",
    "set_servings",
    "open_recipe",
  ]);
  for (const tool of ASK_TOOLS) {
    assertEquals(tool.strict, true);
    const schema = tool.input_schema;
    assertEquals(schema.additionalProperties, false, tool.name);
    // Strict tools have no optional fields: every property is required.
    assertEquals(
      [...(schema.required as string[])].sort(),
      Object.keys(schema.properties as Record<string, unknown>).sort(),
      tool.name,
    );
  }
});

Deno.test("decode — a tool call keeps its thinking block verbatim", () => {
  const reply = decodeAskReply(TOOL_CALL);
  assertEquals(reply.stop_reason, "tool_use");
  assertEquals(reply.content, TOOL_CALL.content);
});

Deno.test("decode — a refusal comes back empty, so the app drops the question", () => {
  const reply = decodeAskReply({
    content: [{ type: "text", text: "partial" }],
    stop_reason: "refusal",
  });
  assertEquals(reply, { content: [], stop_reason: "refusal" });
});

Deno.test("decode — unknown blocks are dropped; a reply with nothing to say throws", () => {
  const reply = decodeAskReply({
    content: [{ type: "server_thing" }, { type: "text", text: "Done." }],
    stop_reason: "end_turn",
  });
  assertEquals(reply.content, [{ type: "text", text: "Done." }]);
  let threw = false;
  try {
    decodeAskReply({
      content: [{ type: "thinking", thinking: "", signature: "s" }],
      stop_reason: "max_tokens",
    });
  } catch {
    threw = true;
  }
  assert(threw);
});

Deno.test("turn — a provider error surfaces, nothing is invented", async () => {
  const adapter = new ClaudeAskAdapter({
    apiKey: "k",
    fetchImpl: (() =>
      Promise.resolve(
        new Response("bad request", { status: 400 }),
      )) as typeof fetch,
  });
  await assertRejects(() => adapter.turn(QUESTION));
});
