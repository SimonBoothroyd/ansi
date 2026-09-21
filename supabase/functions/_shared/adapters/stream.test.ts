// `streamJson` + the Anthropic assembler: the plumbing a user waits on.
//
// The failure these guard against: a per-attempt wall clock aborts a sanitize
// that is streaming well, a retry starts into too little budget and aborts
// too. Two billed answers and a 504.

import { assert, assertEquals, assertRejects } from "@std/assert";
import {
  DEFAULT_IDLE_TIMEOUT_MS,
  DEFAULT_MIN_ATTEMPT_MS,
  ProviderHttpError,
  ProviderTimeoutError,
  streamJson,
} from "./http.ts";
import { anthropicAssembler, decodeClaudeSanitize } from "./claude.ts";
import { anthropicUsage } from "./usage.ts";
import {
  anthropicFrames,
  anthropicStream,
  sseFrame,
  sseResponse,
} from "./stream_test_helper.ts";

/**
 * A scripted fetch: one step per attempt. A step is handed the caller's abort
 * signal, since a stub that ignores it can never show an idle timer firing.
 */
type Step = Response | Error | ((signal: AbortSignal | null) => Response);
function scripted(steps: Step[]) {
  const bodies: Record<string, unknown>[] = [];
  const headers: Record<string, string>[] = [];
  let i = 0;
  const fetchImpl = ((_url: string | URL | Request, init?: RequestInit) => {
    bodies.push(JSON.parse(String(init?.body)));
    headers.push({ ...(init?.headers as Record<string, string>) });
    const step = steps[Math.min(i++, steps.length - 1)];
    if (step instanceof Error) return Promise.reject(step);
    return Promise.resolve(
      typeof step === "function" ? step(init?.signal ?? null) : step,
    );
  }) as typeof fetch;
  return { fetchImpl, bodies, headers, attempts: () => i };
}

/** A stream that goes quiet after `frames` and only ends when it is aborted. */
const stalls = (frames: string[]) => (signal: AbortSignal | null) =>
  sseResponse(frames, { stall: true, signal });

function call(steps: Step[], over: Record<string, unknown> = {}) {
  const s = scripted(steps);
  const promise = streamJson({
    url: "https://provider.test/v1/messages",
    headers: { "x-test": "1" },
    body: { model: "test-model", messages: [] },
    provider: "TestCo",
    assembler: () => anthropicAssembler("TestCo"),
    baseBackoffMs: 1,
    fetchImpl: s.fetchImpl,
    ...over,
  });
  return { promise, ...s };
}

// --- Assembly -----------------------------------------------------------------

Deno.test("the deltas are reassembled into the response the non-streaming call returned", async () => {
  const { promise } = call([
    anthropicStream({
      deltas: ['{"title":', '"Dirty ', 'Rice"}'],
      inputUsage: { input_tokens: 900, cache_read_input_tokens: 40 },
      outputUsage: { output_tokens: 3300 },
    }),
  ]);
  const res = await promise as Record<string, unknown>;
  // The three pieces are one text block, the shape every decoder expects.
  assertEquals(res.content, [{ type: "text", text: '{"title":"Dirty Rice"}' }]);
  assertEquals(res.stop_reason, "end_turn");
  assertEquals(res.model, "test-model");
  // Usage is merged, not replaced: the input half arrives with
  // `message_start` and the output half with `message_delta`.
  const usage = anthropicUsage(res)!;
  assertEquals(usage.input_tokens, 900);
  assertEquals(usage.cache_read_tokens, 40);
  assertEquals(usage.output_tokens, 3300);
});

Deno.test("an assembled answer decodes exactly as a non-streamed one does", async () => {
  // What arrives frame by frame has to survive `decodeClaudeSanitize`, the
  // function rescoring and the replay adapter use.
  const recipe = JSON.stringify({
    title: "Dirty Rice",
    groups: [{ name: null, line_items: [] }],
    steps: [],
  });
  const { promise } = call([
    anthropicStream({ deltas: [...recipe.match(/.{1,7}/g)!] }),
  ]);
  assertEquals(decodeClaudeSanitize(await promise).title, "Dirty Rice");
});

Deno.test("a truncated answer still says it was truncated", async () => {
  // `stop_reason: max_tokens` has to survive the stream, or a half-written
  // recipe parses as a whole one.
  const { promise } = call([
    anthropicStream({ deltas: ['{"title":"Dir'], stopReason: "max_tokens" }),
  ]);
  assertEquals(
    (await promise as Record<string, unknown>).stop_reason,
    "max_tokens",
  );
});

Deno.test("the request asks for a stream and says it can read one", async () => {
  const { promise, bodies, headers } = call([
    anthropicStream({ deltas: ["x"] }),
  ]);
  await promise;
  assertEquals(bodies[0].stream, true);
  assertEquals(bodies[0].model, "test-model");
  assertEquals(headers[0].accept, "text/event-stream");
  assertEquals(headers[0]["x-test"], "1");
});

Deno.test("a `ping` is not output — it keeps the socket honest and nothing else", async () => {
  const frames = anthropicFrames({ deltas: ["a"] });
  frames.splice(1, 0, sseFrame("ping", { type: "ping" }));
  let beats = 0;
  const { promise } = call([sseResponse(frames)], { onDelta: () => beats++ });
  await promise;
  assertEquals(beats, 1); // the delta, not the ping
});

// --- The idle timer -----------------------------------------------------------

Deno.test("slow but FLOWING output is not a timeout — the gap is what is bounded", async () => {
  // Six frames, 25ms apart, against a 90ms idle budget: the call outlasts the
  // budget and must still succeed.
  const { promise, attempts } = call(
    [anthropicStream({ deltas: ["a", "b", "c", "d"] }, { pauseMs: 25 })],
    { idleTimeoutMs: 90, deadlineMs: 5_000, minAttemptMs: 50 },
  );
  const res = await promise as Record<string, unknown>;
  assertEquals((res.content as { text: string }[])[0].text, "abcd");
  assertEquals(attempts(), 1);
});

Deno.test("SILENCE mid-answer ends the attempt, and is never retried", async () => {
  // Three frames, then nothing: the answer was generated and billed, so a
  // second attempt would buy a second copy.
  const started = anthropicFrames({ deltas: ["a"] }).slice(0, 3);
  const { promise, attempts } = call([stalls(started)], {
    idleTimeoutMs: 60,
    deadlineMs: 5_000,
    minAttemptMs: 50,
  });
  const e = await assertRejects(() => promise);
  assertEquals((e as Error).name, "AbortError"); // ⇒ isTimeoutFailure ⇒ 504
  assertEquals(attempts(), 1);
});

Deno.test("silence BEFORE the first delta is retried — nothing was generated yet", async () => {
  const { promise, attempts } = call(
    [stalls([]), stalls([]), () => anthropicStream({ deltas: ["ok"] })],
    { idleTimeoutMs: 40, deadlineMs: 5_000, minAttemptMs: 50 },
  );
  const res = await promise as Record<string, unknown>;
  assertEquals((res.content as { text: string }[])[0].text, "ok");
  assertEquals(attempts(), 3);
});

// --- Not retrying, and not starting ------------------------------------------

Deno.test("a stream that dies mid-message fails rather than handing over half a recipe", async () => {
  const { promise, attempts } = call([
    anthropicStream({ deltas: ["{", '"title"'], unterminated: true }),
  ]);
  const e = await assertRejects(() => promise, ProviderHttpError);
  assertEquals(e.status, 502);
  assertEquals(attempts(), 1); // past the first delta ⇒ never again
});

Deno.test("a provider error frame mid-answer is not retried either", async () => {
  const frames = anthropicFrames({ deltas: ["a"] });
  frames.splice(
    3,
    0,
    sseFrame("error", { type: "error", error: { type: "overloaded_error" } }),
  );
  const { promise, attempts } = call([sseResponse(frames)]);
  const e = await assertRejects(() => promise, ProviderHttpError);
  assertEquals(e.status, 503);
  assert(e.body.includes("overloaded_error"));
  assertEquals(attempts(), 1);
});

Deno.test("a transient status BEFORE any output is retried, as it always was", async () => {
  const { promise, attempts } = call([
    new Response("{}", { status: 503 }),
    anthropicStream({ deltas: ["ok"] }),
  ]);
  const res = await promise as Record<string, unknown>;
  assertEquals((res.content as { text: string }[])[0].text, "ok");
  assertEquals(attempts(), 2);
});

Deno.test("a non-transient status fails immediately", async () => {
  const { promise, attempts } = call([
    new Response('{"error":"bad request"}', { status: 400 }),
  ]);
  const e = await assertRejects(() => promise, ProviderHttpError);
  assertEquals(e.status, 400);
  assertEquals(attempts(), 1);
});

Deno.test("a call with no budget left never dials out at all", async () => {
  const { promise, attempts } = call([anthropicStream({ deltas: ["ok"] })], {
    deadlineMs: -1,
  });
  await assertRejects(() => promise, ProviderTimeoutError);
  assertEquals(attempts(), 0);
});

Deno.test("a short budget still dials ONCE — the minimum is a bar for retries", async () => {
  // The minimum gates a retry, not the call: a 500ms budget, far under
  // DEFAULT_MIN_ATTEMPT_MS, must still dial.
  const { promise, attempts } = call([anthropicStream({ deltas: ["ok"] })], {
    deadlineMs: 500,
  });
  const res = await promise as Record<string, unknown>;
  assertEquals((res.content as { text: string }[])[0].text, "ok");
  assertEquals(attempts(), 1);
});

Deno.test("a RETRY is never STARTED into a budget it cannot finish in", async () => {
  // A retry into too little budget would bill a whole answer only to abort it;
  // the call reports a timeout instead.
  const started = Date.now();
  const { promise, attempts } = call(
    [stalls([]), () => anthropicStream({ deltas: ["never reached"] })],
    { idleTimeoutMs: 150, deadlineMs: 1_000, minAttemptMs: 900 },
  );
  await assertRejects(() => promise, ProviderTimeoutError);
  assertEquals(attempts(), 1);
  assert(Date.now() - started < 1_000, "it waited out the whole budget");
});

Deno.test("the defaults are the ones the ladder is drawn with", () => {
  // Named here so a change to either shows up as a diff on a test.
  assertEquals(DEFAULT_IDLE_TIMEOUT_MS, 20_000);
  assertEquals(DEFAULT_MIN_ATTEMPT_MS, 30_000);
  assert(DEFAULT_MIN_ATTEMPT_MS > DEFAULT_IDLE_TIMEOUT_MS);
});
