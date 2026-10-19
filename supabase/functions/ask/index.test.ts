// The ask door's HTTP edge: what a conversation may be, what the answer looks
// like, and what a member is told when the turn fails. The model is a fake
// adapter, so nothing here dials out.

import { assert, assertEquals } from "@std/assert";
import type { AskAdapter, AskMessage, AskReply } from "../_shared/ask_types.ts";
import { ProviderTimeoutError } from "../_shared/adapters/http.ts";
import {
  failureFor,
  ImportError,
  makeHandler,
  MAX_MESSAGES,
  parseRequestBody,
} from "./index.ts";

const REPLY: AskReply = {
  content: [{ type: "text", text: "3 tbsp tamari — Ragù, serves 6." }],
  stop_reason: "end_turn",
};

function fakeAdapter(seen: AskMessage[][] = []): AskAdapter {
  return {
    model: "fake",
    turn: (messages) => {
      seen.push(messages);
      return Promise.resolve(REPLY);
    },
  };
}

const throwingAdapter = (e: unknown): AskAdapter => ({
  model: "fake",
  turn: () => Promise.reject(e),
});

const post = (body: unknown) =>
  new Request("https://fn.test", {
    method: "POST",
    body: JSON.stringify(body),
  });

const QUESTION: AskMessage = {
  role: "user",
  content: [{
    type: "text",
    text: '<screen>{"route":"recipe"}</screen>\nhow much tamari?',
  }],
};

/** A whole tool round trip, thinking block included, ending on the result. */
const ROUND_TRIP: AskMessage[] = [
  QUESTION,
  {
    role: "assistant",
    content: [
      { type: "thinking", thinking: "", signature: "sig-abc" },
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
  },
  {
    role: "user",
    content: [{
      type: "tool_result",
      tool_use_id: "toolu_1",
      content: "3 tbsp",
    }],
  },
];

Deno.test("parse — a question, and a full tool round trip, are accepted verbatim", () => {
  const one = parseRequestBody({ messages: [QUESTION] });
  assert("request" in one);
  const trip = parseRequestBody({ messages: ROUND_TRIP });
  assert("request" in trip);
  // Blocks pass through untouched: a thinking block is valid only as produced.
  assertEquals(trip.request.messages, ROUND_TRIP);
});

Deno.test("parse — turns alternate from the member, and end on the member", () => {
  const assistantFirst = parseRequestBody({
    messages: [{ role: "assistant", content: "hello" }],
  });
  assert("error" in assistantFirst);
  const endsOnAssistant = parseRequestBody({
    messages: ROUND_TRIP.slice(0, 2),
  });
  assert("error" in endsOnAssistant);
  assertEquals(
    endsOnAssistant.error,
    "the conversation must end on the member's turn",
  );
});

Deno.test("parse — a member cannot send a tool call or a thinking block", () => {
  for (const type of ["tool_use", "thinking", "image"]) {
    const r = parseRequestBody({
      messages: [{ role: "user", content: [{ type }] }],
    });
    assert("error" in r, type);
  }
});

Deno.test("parse — empty, malformed and oversized conversations are 400s", () => {
  for (const body of [null, [], {}, { messages: [] }, { messages: "hi" }]) {
    assert("error" in parseRequestBody(body), JSON.stringify(body));
  }
  assert(
    "error" in
      parseRequestBody({ messages: [{ role: "user", content: "  " }] }),
  );
  const long: AskMessage[] = [];
  for (let i = 0; i <= MAX_MESSAGES; i++) {
    long.push({ role: i % 2 === 0 ? "user" : "assistant", content: "x" });
  }
  assert("error" in parseRequestBody({ messages: long }));
  const heavy = parseRequestBody({
    messages: [{ role: "user", content: "x".repeat(300 * 1024) }],
  });
  assert("error" in heavy);
});

Deno.test("handler — answers with the adapter's blocks, handing it the whole conversation", async () => {
  const seen: AskMessage[][] = [];
  const res = await makeHandler({ adapter: fakeAdapter(seen) })(
    post({ messages: ROUND_TRIP }),
  );
  assertEquals(res.status, 200);
  assertEquals(await res.json(), REPLY);
  assertEquals(seen, [ROUND_TRIP]);
});

Deno.test("handler — GET is 405, bad JSON and bad bodies are 400", async () => {
  const handler = makeHandler({ adapter: fakeAdapter() });
  assertEquals((await handler(new Request("https://fn.test"))).status, 405);
  const badJson = await handler(
    new Request("https://fn.test", { method: "POST", body: "{" }),
  );
  assertEquals(badJson.status, 400);
  assertEquals((await handler(post({}))).status, 400);
});

Deno.test("failures — 422 in the raiser's words, 504 says retrying is safe, 500 says nothing", () => {
  assertEquals(failureFor(new ImportError("Ansi did not finish")), {
    status: 422,
    error: "Ansi did not finish",
  });
  const timeout = failureFor(new ProviderTimeoutError("Claude", 30_000));
  assertEquals(timeout.status, 504);
  assert(timeout.error.includes("safe to try again"));
  const other = failureFor(new Error("postgres://secret@host"));
  assertEquals(other.status, 500);
  assert(!other.error.includes("secret"));
  assert(!other.error.includes("import"));
});

Deno.test("handler — a thrown turn becomes its failure shape", async () => {
  const res = await makeHandler({
    adapter: throwingAdapter(new ProviderTimeoutError("Claude", 30_000)),
  })(post({ messages: [QUESTION] }));
  assertEquals(res.status, 504);
  assert(typeof (await res.json()).error === "string");
});
