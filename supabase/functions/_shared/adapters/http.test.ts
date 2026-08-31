import { assert, assertEquals, assertRejects } from "@std/assert";
import {
  extractJson,
  jpegDimensions,
  MAX_RETRY_AFTER_MS,
  postJson,
  ProviderHttpError,
  ProviderTimeoutError,
  retryAfterDelayMs,
  toBase64,
  UPLOAD_MAX_EDGE,
} from "./http.ts";

// A scripted fetch: one entry per attempt, so retry behaviour is observable
// without a network. Backoff is driven down to ~1ms via `baseBackoffMs`, so a
// retry test costs microseconds instead of seconds.
type Step = Response | Error;
function scriptedFetch(steps: Step[]) {
  const calls: { url: string; body: unknown }[] = [];
  let i = 0;
  const fetchImpl = ((url: string | URL | Request, init?: RequestInit) => {
    calls.push({
      url: String(url),
      body: init?.body ? JSON.parse(String(init.body)) : null,
    });
    const step = steps[Math.min(i++, steps.length - 1)];
    return step instanceof Error
      ? Promise.reject(step)
      : Promise.resolve(step.clone());
  }) as typeof fetch;
  return { fetchImpl, calls, attempts: () => calls.length };
}

const json = (body: unknown, init: ResponseInit = {}) =>
  new Response(JSON.stringify(body), {
    headers: { "content-type": "application/json" },
    ...init,
  });

const call = (
  steps: Step[],
  over: Partial<Parameters<typeof postJson>[0]> = {},
) => {
  const { fetchImpl, calls, attempts } = scriptedFetch(steps);
  const promise = postJson({
    url: "https://provider.test/v1",
    headers: { "x-test": "1" },
    body: { hello: "world" },
    provider: "TestCo",
    baseBackoffMs: 1,
    fetchImpl,
    ...over,
  });
  return { promise, calls, attempts };
};

Deno.test("postJson — a 200 returns parsed JSON and sends our headers/body", async () => {
  const { promise, calls } = call([json({ ok: true })]);
  assertEquals(await promise, { ok: true });
  assertEquals(calls.length, 1);
  assertEquals(calls[0].url, "https://provider.test/v1");
  assertEquals(calls[0].body, { hello: "world" });
});

Deno.test("postJson — a NON-JSON 200 becomes a ProviderHttpError, not a raw SyntaxError", async () => {
  // A proxy's HTML error page arrives with a 200. Callers catch one contract.
  const { promise } = call([
    new Response("<html>gateway</html>", {
      headers: { "content-type": "text/html" },
    }),
  ]);
  const e = await assertRejects(() => promise, ProviderHttpError);
  assertEquals((e as ProviderHttpError).provider, "TestCo");
  assert(e.message.includes("non-JSON body"));
});

Deno.test("postJson — a non-transient status fails immediately", async () => {
  const { promise, attempts } = call([
    json({ error: "bad key" }, { status: 401 }),
  ]);
  const e = await assertRejects(() => promise, ProviderHttpError);
  assertEquals((e as ProviderHttpError).status, 401);
  assertEquals(attempts(), 1); // 4xx is not retried
});

Deno.test("postJson — retries a transient status, then succeeds", async () => {
  const { promise, attempts } = call([
    json({ e: "overloaded" }, { status: 503 }),
    json({ ok: 1 }),
  ]);
  assertEquals(await promise, { ok: 1 });
  assertEquals(attempts(), 2);
});

Deno.test("postJson — retries a network error, then succeeds", async () => {
  const { promise, attempts } = call([
    new Error("connection reset"),
    json({ ok: 1 }),
  ]);
  assertEquals(await promise, { ok: 1 });
  assertEquals(attempts(), 2);
});

Deno.test("postJson — gives up after 3 attempts, surfacing the last status", async () => {
  const { promise, attempts } = call([
    json({}, { status: 503 }),
    json({}, { status: 503 }),
    json({}, { status: 503 }),
    json({ never: "reached" }),
  ]);
  const e = await assertRejects(() => promise, ProviderHttpError);
  assertEquals((e as ProviderHttpError).status, 503);
  assertEquals(attempts(), 3); // not the old 5
});

Deno.test("retryAfterDelayMs — clamps what a provider asks us to sleep", () => {
  // `Retry-After: 600` used to mean a ten-minute sleep inside a request handler.
  assertEquals(retryAfterDelayMs("600"), MAX_RETRY_AFTER_MS);
  assertEquals(retryAfterDelayMs("3600"), MAX_RETRY_AFTER_MS);
  assertEquals(retryAfterDelayMs("2"), 2_000); // a reasonable one is honoured
  for (const bad of [null, "", "0", "-5", "Wed, 21 Oct 2026 07:28:00 GMT"]) {
    assertEquals(retryAfterDelayMs(bad), null, `${bad} should fall back`);
  }
});

Deno.test("postJson — a huge Retry-After never outlives the deadline", async () => {
  const started = Date.now();
  const { promise } = call(
    [new Response("{}", { status: 429, headers: { "retry-after": "600" } })],
    { deadlineMs: 300 },
  );
  await assertRejects(() => promise, ProviderHttpError);
  const elapsed = Date.now() - started;
  assert(
    elapsed < 2_000,
    `slept ${elapsed}ms — the clamp/deadline did not bind`,
  );
});

Deno.test("postJson — the total deadline is shared across attempts", async () => {
  // Every attempt 503s with a retry-after longer than the whole budget, so the
  // call must abandon rather than sleep past its deadline.
  const started = Date.now();
  const { promise, attempts } = call(
    [new Response("{}", { status: 503, headers: { "retry-after": "5" } })],
    { deadlineMs: 200 },
  );
  const e = await assertRejects(() => promise, ProviderHttpError);
  assertEquals((e as ProviderHttpError).status, 503);
  const elapsed = Date.now() - started;
  assert(elapsed < 2_000, `took ${elapsed}ms — the deadline did not bind`);
  assert(attempts() >= 1);
});

Deno.test("postJson — an exhausted deadline with no attempt made times out", async () => {
  const { promise, attempts } = call([json({ ok: 1 })], { deadlineMs: -1 });
  await assertRejects(() => promise, ProviderTimeoutError);
  assertEquals(attempts(), 0);
});

// --- extractJson --------------------------------------------------------------

Deno.test("extractJson — recovers from fences and stray prose", () => {
  const want = '{"a":1}';
  const cases: [string, string][] = [
    ["clean", '{"a":1}'],
    ["json fence", '```json\n{"a":1}\n```'],
    ["bare fence", '```\n{"a":1}\n```'],
    ["leading prose", 'Here you go:\n{"a":1}'],
    ["trailing prose", '{"a":1}\nHope that helps!'],
    ["whitespace", '  \n {"a":1}  \n'],
  ];
  for (const [label, input] of cases) {
    assertEquals(extractJson(input).replace(/\s/g, ""), want, label);
  }
  // Nothing object-shaped: hand it back and let JSON.parse be the judge.
  assertEquals(extractJson("no json here"), "no json here");
});

Deno.test("extractJson — a nested object survives the brace scan", () => {
  const src = 'prose {"a":{"b":[1,2]},"c":"}"} tail';
  assertEquals(JSON.parse(extractJson(src)).a.b, [1, 2]);
});

// --- misc helpers -------------------------------------------------------------

Deno.test("toBase64 — round-trips bytes", () => {
  const bytes = new Uint8Array([0, 1, 254, 255, 65]);
  assertEquals(atob(toBase64(bytes)).charCodeAt(3), 255);
});

/**
 * A minimal but structurally valid JPEG prefix: SOI, an APP0 segment that must
 * be skipped, then a SOF0 frame header carrying the dimensions (declared length
 * 17, as a real single-component-listing SOF0 does, padded to match).
 */
function jpegHeader(width: number, height: number): Uint8Array {
  const sofPayload = new Uint8Array(15); // 17 minus the 2 length bytes
  sofPayload[0] = 8; // sample precision
  sofPayload[1] = (height >> 8) & 0xff;
  sofPayload[2] = height & 0xff;
  sofPayload[3] = (width >> 8) & 0xff;
  sofPayload[4] = width & 0xff;
  return new Uint8Array([
    0xff,
    0xd8, // SOI
    0xff,
    0xe0,
    0x00,
    0x04,
    0x00,
    0x00, // APP0, length 4 — skipped
    0xff,
    0xc0,
    0x00,
    0x11, // SOF0, length 17
    ...sofPayload,
  ]);
}

Deno.test("jpegDimensions — reads the SOF header without decoding", () => {
  // The Pixel corpus size, and one already inside the upload budget.
  assertEquals(jpegDimensions(jpegHeader(4080, 3064)), {
    width: 4080,
    height: 3064,
  });
  assertEquals(jpegDimensions(jpegHeader(800, 600)), {
    width: 800,
    height: 600,
  });
});

Deno.test("jpegDimensions — anything it cannot read cheaply returns null", () => {
  // …and the caller then falls back to the real WASM decode, as before.
  const truncated = jpegHeader(800, 600).subarray(0, 12);
  for (
    const bad of [
      new Uint8Array([0x89, 0x50, 0x4e, 0x47]), // PNG
      new Uint8Array([0xff, 0xd8]), // SOI only
      new Uint8Array(0),
      truncated, // declares a segment longer than the bytes we have
    ]
  ) assertEquals(jpegDimensions(bad), null);
});

Deno.test("jpegDimensions — an in-budget photo is what lets resize skip the decode", () => {
  const small = jpegDimensions(jpegHeader(768, 512))!;
  assert(Math.max(small.width, small.height) <= UPLOAD_MAX_EDGE);
  const big = jpegDimensions(jpegHeader(4080, 3064))!;
  assert(Math.max(big.width, big.height) > UPLOAD_MAX_EDGE);
});
