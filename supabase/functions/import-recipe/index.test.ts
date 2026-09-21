import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "@std/assert";
import {
  type ImportDeps,
  ImportError,
  importRecipe,
  type ImportStageId,
  makeHandler,
  MAX_IMAGE_BYTES,
  MAX_IMAGES,
  parseRequestBody,
  PHOTO_STAGES,
  URL_STAGES,
} from "./index.ts";
import { collectSse, type SseEvent } from "./sse_test_helper.ts";
import type {
  ExtractAdapter,
  ExtractionResult,
  MatchedLine,
  RawBlob,
  RawLineItem,
} from "../_shared/types.ts";

// --- Canned extraction: 2 groups of 2 lines, steps by index. No disk access.
function cannedExtraction(): ExtractionResult {
  const line = (ingredient_text: string, qty: number | null): RawLineItem => ({
    qty,
    qty_low: null,
    qty_high: null,
    unit: qty === null ? null : "g",
    unit_mappable: true,
    ingredient_text,
    notes: null,
    raw_amount: qty === null ? "to taste" : `${qty} g`,
    optional: false,
    confidence: 0.9,
  });
  return {
    title: "Test Curry",
    servings_base: 4,
    servings_raw: "Serves 4",
    yield_raw: null,
    total_time_seconds: 1800,
    cook_time_seconds: { low_seconds: 600, high_seconds: 900 },
    truncated: false,
    image_quality: "ok",
    parse_warnings: ["light grey type on the amounts column"],
    groups: [
      {
        name: "for the curry",
        line_items: [line("chicken thighs, boneless", 900), line("onion", 150)],
      },
      {
        name: "for the sauce",
        line_items: [line("coconut milk", 400), line("salt", null)],
      },
    ],
    steps: [
      {
        tokens: [
          { t: "text", s: "Dice the " },
          {
            t: "ref",
            refs: [1],
            label: "onion",
            mention: "new",
            portion: null,
          },
          { t: "text", s: " and simmer " },
          { t: "timer", low_seconds: 600, high_seconds: 900 },
          { t: "text", s: "." },
        ],
      },
    ],
  };
}

// A fake sanitize adapter: returns the canned extraction and records the hints
// it received. `transcribe` is present only when `withVision`.
function fakeAdapter(
  opts: {
    withVision?: boolean;
    seen?: { blob?: RawBlob };
    /** Run inside `sanitize`, so a test can model a model that is producing. */
    whileSanitizing?: (self: ExtractAdapter) => void;
  } = {},
): ExtractAdapter {
  const adapter: ExtractAdapter = {
    name: "fake",
    sanitize(blob: RawBlob): Promise<ExtractionResult> {
      if (opts.seen) opts.seen.blob = blob;
      opts.whileSanitizing?.(adapter);
      return Promise.resolve(cannedExtraction());
    },
  };
  if (opts.withVision) {
    adapter.transcribe = (images: Uint8Array[]): Promise<RawBlob> =>
      Promise.resolve({
        source: "transcription",
        url: null,
        jsonld: null,
        text: `transcribed ${images.length} image(s)`,
      });
  }
  return adapter;
}

// A fake matcher: bands every line `auto` and echoes its index as the
// candidate score, so re-grouping order is observable.
function fakeMatcher(seen?: { lines?: RawLineItem[] }) {
  return (lines: RawLineItem[]): Promise<MatchedLine[]> => {
    if (seen) seen.lines = lines;
    return Promise.resolve(lines.map((raw, i) => ({
      raw,
      band: "auto" as const,
      candidates: [{
        ingredient_id: `ing-${i}`,
        canonical_name: raw.ingredient_text,
        score: i,
      }],
    })));
  };
}

function deps(over: Partial<ImportDeps> = {}): ImportDeps {
  return {
    adapter: fakeAdapter(),
    matchLines: fakeMatcher(),
    fetchBlob: (url) =>
      Promise.resolve({
        source: "jsonld",
        url,
        jsonld: { name: "x" },
        text: null,
      }),
    ...over,
  };
}

Deno.test("importRecipe — URL path builds a valid ReconciliationPayload", async () => {
  const seenBlob: { blob?: RawBlob } = {};
  const payload = await importRecipe(
    { url: "https://example.test/curry" },
    deps({ adapter: fakeAdapter({ seen: seenBlob }) }),
  );
  // Intake produced a jsonld blob from the URL and handed it to sanitize.
  assertEquals(seenBlob.blob?.source, "jsonld");
  // Metadata passes through untouched (never-invent).
  assertEquals(payload.title, "Test Curry");
  assertEquals(payload.servings_base, 4);
  assertEquals(payload.parse_warnings, [
    "light grey type on the amounts column",
  ]);
  assertEquals(payload.cook_time_seconds, {
    low_seconds: 600,
    high_seconds: 900,
  });
  // Group shape preserved.
  assertEquals(payload.groups.map((g) => g.name), [
    "for the curry",
    "for the sauce",
  ]);
  assertEquals(payload.groups.map((g) => g.lines.length), [2, 2]);
  // Steps pass through verbatim — refs still by line_index.
  assertEquals(payload.steps, cannedExtraction().steps);
});

Deno.test("importRecipe — images path calls transcribe", async () => {
  const payload = await importRecipe(
    { images: [new Uint8Array([1, 2, 3])] },
    deps({ adapter: fakeAdapter({ withVision: true }) }),
  );
  assertEquals(payload.title, "Test Curry");
});

Deno.test("importRecipe — flattens groups in order for the matcher", async () => {
  const seen: { lines?: RawLineItem[] } = {};
  await importRecipe({ url: "u" }, deps({ matchLines: fakeMatcher(seen) }));
  // Flattened line_index space: group0 lines then group1 lines, in order.
  assertEquals(seen.lines?.map((l) => l.ingredient_text), [
    "chicken thighs, boneless",
    "onion",
    "coconut milk",
    "salt",
  ]);
});

Deno.test("importRecipe — re-groups matched lines to the right groups", async () => {
  const payload = await importRecipe({ url: "u" }, deps());
  // The matcher stamped candidate.score = flattened index; re-grouping must keep
  // line 2 ("coconut milk", index 2) in group 1, not group 0.
  const scores = payload.groups.map((g) =>
    g.lines.map((l) => l.candidates[0].score)
  );
  assertEquals(scores, [[0, 1], [2, 3]]);
  assertEquals(payload.groups[1].lines[0].raw.ingredient_text, "coconut milk");
  assertEquals(
    payload.groups.every((g) => g.lines.every((l) => l.band === "auto")),
    true,
  );
});

Deno.test("importRecipe — a recipe suggestion rides through, and only when there is one", async () => {
  // The spine copies `recipe_candidates` onto the payload line when the matcher
  // supplied one, and omits the key otherwise.
  const withSuggestion: ImportDeps["matchLines"] = (lines) =>
    Promise.resolve(lines.map((raw) => ({
      raw,
      band: "none" as const,
      candidates: [],
      ...(raw.ingredient_text === "coconut milk"
        ? {
          recipe_candidates: [{
            recipe_id: "r-coconut",
            title: "Coconut Milk From Scratch",
            score: 1,
          }],
        }
        : {}),
    })));
  const payload = await importRecipe(
    { url: "u" },
    deps({ matchLines: withSuggestion }),
  );
  const flat = payload.groups.flatMap((g) => g.lines);
  assertEquals(
    flat.find((l) => l.raw.ingredient_text === "coconut milk")
      ?.recipe_candidates,
    [{ recipe_id: "r-coconut", title: "Coconut Milk From Scratch", score: 1 }],
  );
  // Every other line carries no such key at all (not an empty array).
  for (const l of flat) {
    if (l.raw.ingredient_text === "coconut milk") continue;
    assertEquals("recipe_candidates" in l, false);
  }
});

Deno.test("importRecipe — an empty recipe_candidates list is dropped, not emitted", async () => {
  const emptyList: ImportDeps["matchLines"] = (lines) =>
    Promise.resolve(lines.map((raw) => ({
      raw,
      band: "none" as const,
      candidates: [],
      recipe_candidates: [],
    })));
  const payload = await importRecipe(
    { url: "u" },
    deps({
      matchLines: emptyList,
    }),
  );
  for (const l of payload.groups.flatMap((g) => g.lines)) {
    assertEquals("recipe_candidates" in l, false);
  }
});

Deno.test("importRecipe — rejects both url and images", async () => {
  await assertRejects(
    () => importRecipe({ url: "u", images: [new Uint8Array()] }, deps()),
    ImportError,
    "not both",
  );
});

Deno.test("importRecipe — rejects empty request", async () => {
  await assertRejects(
    () => importRecipe({}, deps()),
    ImportError,
    "must include",
  );
});

Deno.test("importRecipe — rejects images when adapter can't transcribe", async () => {
  await assertRejects(
    () => importRecipe({ images: [new Uint8Array([1])] }, deps()), // fakeAdapter() has no transcribe
    ImportError,
    "cannot transcribe",
  );
});

Deno.test("importRecipe — rejects a matcher line-count mismatch", async () => {
  const badMatcher = (_lines: RawLineItem[]): Promise<MatchedLine[]> =>
    Promise.resolve([]); // returns 0 for 4 inputs
  await assertRejects(
    () => importRecipe({ url: "u" }, deps({ matchLines: badMatcher })),
    ImportError,
    "returned 0 lines for 4",
  );
});

// --- HTTP boundary ------------------------------------------------------------

/** POSTs `body` through a default-`deps` handler. */
function post(body: unknown): Promise<Response> {
  return makeHandler(deps())(
    new Request("https://fn.test", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  );
}

const last = (events: SseEvent[]): SseEvent => events[events.length - 1];

/** The stage ids, in arrival order. */
const stageIds = (events: SseEvent[]): ImportStageId[] =>
  events
    .filter((e) => e.event === "stage")
    .map((e) => (e.data as { stage: ImportStageId }).stage);

Deno.test("parseRequestBody — url, images, and errors", () => {
  assertEquals(parseRequestBody({ url: "u" }), { request: { url: "u" } });
  const imgs = parseRequestBody({ images: [btoa("abc")] });
  assertEquals("request" in imgs && imgs.request.images?.length, 1);
  assertEquals("error" in parseRequestBody({}), true);
  assertEquals("error" in parseRequestBody("nope"), true);
  assertEquals("error" in parseRequestBody({ images: [1, 2] }), true);
  assertEquals("error" in parseRequestBody({ images: [] }), true);
  assertEquals("error" in parseRequestBody({ url: "   " }), true);
});

/** The error string `parseRequestBody` rejected with (fails if it accepted). */
function rejection(body: unknown): string {
  const r = parseRequestBody(body);
  if (!("error" in r)) throw new Error(`expected a rejection, got a request`);
  return r.error;
}

Deno.test("parseRequestBody — `url` and `images` together is a real error", () => {
  // `url` must not win silently.
  assertStringIncludes(
    rejection({ url: "https://x.test", images: [btoa("a")] }),
    "not both",
  );
});

Deno.test("parseRequestBody — caps the number of images", () => {
  const one = btoa("a");
  const ok = parseRequestBody({ images: Array(MAX_IMAGES).fill(one) });
  assertEquals("request" in ok && ok.request.images?.length, MAX_IMAGES);
  assertStringIncludes(
    rejection({ images: Array(MAX_IMAGES + 1).fill(one) }),
    `at most ${MAX_IMAGES}`,
  );
});

Deno.test("parseRequestBody — caps the size of one image", () => {
  // Encoded-length pre-check: a payload this size is refused without ever being
  // decoded into bytes.
  const huge = "A".repeat(Math.ceil((MAX_IMAGE_BYTES + 1_000_000) / 3) * 4);
  assertStringIncludes(rejection({ images: [huge] }), "the limit is");
  // And a payload that only reveals its size after decoding is refused too.
  const justOver = "A".repeat(Math.ceil((MAX_IMAGE_BYTES + 64) / 3) * 4);
  assertStringIncludes(rejection({ images: [justOver] }), "the limit is");
});

Deno.test("parseRequestBody — malformed base64 is a 400, not an unhandled throw", () => {
  // `atob` throws, and this runs before the handler's try/catch.
  assertStringIncludes(rejection({ images: ["not!valid!base64"] }), "base64");
});

Deno.test("makeHandler — an oversized/!malformed body is a 400 with a message", async () => {
  const handler = makeHandler(deps());
  const post = (body: unknown) =>
    handler(
      new Request("https://fn.test", {
        method: "POST",
        body: JSON.stringify(body),
      }),
    );
  for (
    const body of [
      { images: ["%%%%"] },
      { images: Array(MAX_IMAGES + 1).fill(btoa("a")) },
      { url: "https://x.test", images: [btoa("a")] },
    ]
  ) {
    const res = await post(body);
    assertEquals(res.status, 400);
    assertEquals(typeof (await res.json()).error, "string");
  }
});

Deno.test("makeHandler — an unexpected failure returns an OPAQUE 500", async () => {
  // The detail can carry provider URLs, prompts, or a connection string.
  const leaky = deps({
    matchLines: () => {
      throw new Error("postgres://user:hunter2@db.internal:5432 refused");
    },
  });
  const res = await makeHandler(leaky)(
    new Request("https://fn.test", {
      method: "POST",
      body: JSON.stringify({ url: "https://example.test/x" }),
    }),
  );
  // The status was committed before the failure; the sentence arrives as the
  // last event.
  assertEquals(res.status, 200);
  const events = await collectSse(res);
  assertEquals(last(events).event, "error");
  assertEquals(last(events).data, { error: "import failed" });
});

Deno.test("makeHandler — a model that ran long is a 504 that says so, not the opaque 500", async () => {
  // Intake's own timeout arrives as an ImportError (⇒ 422), so a timeout
  // reaching the handler ran long in the model. The sentence says it was the
  // reading, and that trying again costs nothing.
  for (const name of ["ProviderTimeoutError", "TimeoutError", "AbortError"]) {
    const slow = deps({
      adapter: {
        name: "slow",
        sanitize: () => {
          const e = new Error("Claude did not answer within 60000ms");
          e.name = name;
          return Promise.reject(e);
        },
      },
    });
    const res = await makeHandler(slow)(
      new Request("https://fn.test", {
        method: "POST",
        body: JSON.stringify({ url: "https://example.test/dirty-rice" }),
      }),
    );
    assertEquals(res.status, 200);
    const events = await collectSse(res);
    const failure = last(events);
    assertEquals(failure.event, "error");
    const { error } = failure.data as { error: string };
    assertStringIncludes(error, "took too long");
    assertStringIncludes(error, "safe to try again");
    // The provider's own words never reach the caller.
    assertEquals(error.includes("60000ms"), false);
  }
});

Deno.test("makeHandler — POST url streams its stages, then the payload LAST", async () => {
  const res = await post({ url: "https://example.test/curry" });
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type"), "text/event-stream");

  const events = await collectSse(res);
  assertEquals(events[0].event, "plan");
  assertEquals(events[0].data, { stages: URL_STAGES });
  // Every stage of the plan, in the plan's order, each one an event of its own.
  assertEquals(stageIds(events), URL_STAGES);
  // The payload is the last thing on the wire.
  assertEquals(last(events).event, "result");
  assertEquals((last(events).data as { title: string }).title, "Test Curry");
  assertEquals(events.filter((e) => e.event === "result").length, 1);
});

Deno.test("makeHandler — the photo door names the transcribe stage, and the clock only goes forwards", async () => {
  const handler = makeHandler(
    deps({ adapter: fakeAdapter({ withVision: true }) }),
  );
  const res = await handler(
    new Request("https://fn.test", {
      method: "POST",
      body: JSON.stringify({ images: [btoa("x")] }),
    }),
  );
  const events = await collectSse(res);
  assertEquals(events[0].data, { stages: PHOTO_STAGES });
  assertEquals(stageIds(events), PHOTO_STAGES);

  const elapsed = events
    .filter((e) => e.event === "stage")
    .map((e) => (e.data as { elapsed_ms: number }).elapsed_ms);
  assertEquals(elapsed.length, PHOTO_STAGES.length);
  for (let i = 1; i < elapsed.length; i++) {
    assert(
      elapsed[i] >= elapsed[i - 1],
      `elapsed went backwards: ${elapsed.join(",")}`,
    );
  }
});

/**
 * Freezes `Date.now` so a test can exercise the shipped heartbeat interval
 * without spending real seconds.
 */
function fakeClock(start = 1_700_000_000_000) {
  const real = Date.now;
  let now = start;
  Date.now = () => now;
  return {
    advance: (ms: number) => {
      now += ms;
    },
    restore: () => {
      Date.now = real;
    },
  };
}

Deno.test("makeHandler — a long model call HEARTBEATS, so the stream is never silent", async () => {
  // Five deltas six seconds apart ⇒ two frames: heartbeats report the model
  // producing, throttled, not a clock ticking.
  const clock = fakeClock();
  try {
    const adapter = fakeAdapter({
      withVision: true,
      whileSanitizing: (self) => {
        for (let i = 0; i < 5; i++) {
          clock.advance(6_000);
          self.onProgress?.();
        }
      },
    });
    const res = await makeHandler(deps({ adapter }))(
      new Request("https://fn.test", {
        method: "POST",
        body: JSON.stringify({ images: [btoa("x")] }),
      }),
    );
    const events = await collectSse(res);
    assertEquals(events[0].event, "plan");
    assertEquals(stageIds(events), PHOTO_STAGES);
    assertEquals(last(events).event, "result");

    const order = events.map((e) => e.event);
    const beats = events.filter((e) => e.event === "heartbeat");
    assertEquals(beats.length, 2, order.join(","));
    // They land inside the stage they report on.
    const firstBeat = order.indexOf("heartbeat");
    assert(firstBeat > order.indexOf("stage"));
    assert(order.lastIndexOf("heartbeat") < order.lastIndexOf("stage"));
    // One clock: a heartbeat's elapsed is the same elapsed a stage reports.
    const elapsed = (e: SseEvent) =>
      (e.data as { elapsed_ms: number }).elapsed_ms;
    assert(elapsed(beats[0]) < elapsed(beats[1]));
    assert(
      elapsed(beats[1]) <=
        elapsed(last(events.filter((e) => e.event === "stage"))),
    );
  } finally {
    clock.restore();
  }
});

Deno.test("importRecipe — the heartbeat observer is unhooked when the import ends", async () => {
  // The eval runner hangs its own observers on a shared adapter; an import
  // must hand back the one it had.
  const adapter = fakeAdapter();
  const mine = () => {};
  adapter.onProgress = mine;
  await importRecipe({ url: "https://example.test/x" }, deps({ adapter }));
  assertEquals(adapter.onProgress, mine);
});

Deno.test("makeHandler — a failure ends the stream with an error and NO result", async () => {
  const res = await post({ images: [btoa("x")] }); // the fake cannot transcribe
  const events = await collectSse(res);
  assertEquals(events.filter((e) => e.event === "result").length, 0);
  assertEquals(last(events).event, "error");
  assertStringIncludes(
    (last(events).data as { error: string }).error,
    "cannot transcribe",
  );
  // The stages that completed before it still arrived.
  assertEquals(stageIds(events), ["received"]);
});

Deno.test("makeHandler — method, body, and pipeline errors map to codes", async () => {
  const handler = makeHandler(deps());
  assertEquals((await handler(new Request("https://fn.test"))).status, 405);
  const badJson = await handler(
    new Request("https://fn.test", { method: "POST", body: "{" }),
  );
  assertEquals(badJson.status, 400);
  const empty = await handler(
    new Request("https://fn.test", { method: "POST", body: "{}" }),
  );
  assertEquals(empty.status, 400); // parseRequestBody rejects before orchestration

  // A failure in orchestration is a 200 carrying an `error` event (covered
  // above); pre-pipeline rejections are still plain statuses.
});

// --- The page's own text, and where each line sits in it ---------------------

/** A page that prints three of the canned extraction's four lines; no salt. */
const pageText = "Test Curry. Serves 4. Ingredients: 900 g chicken thighs, " +
  "boneless; 150 g onion, diced; 400 g coconut milk.";

function pageDeps(over: Partial<ImportDeps> = {}): ImportDeps {
  return deps({
    fetchBlob: (url) =>
      Promise.resolve({
        source: "page_text",
        url,
        jsonld: null,
        text: pageText,
        page_text: pageText,
      }),
    ...over,
  });
}

Deno.test("importRecipe — a link import carries the page's text and a span per line", async () => {
  const payload = await importRecipe({ url: "u" }, pageDeps());
  assertEquals(payload.source_text, pageText);

  const flat = payload.groups.flatMap((g) => g.lines);
  const chicken = flat.find((l) =>
    l.raw.ingredient_text === "chicken thighs, boneless"
  )!;
  const span = chicken.source_span!;
  // The span is a range into `source_text`, amount through identity.
  assertEquals(
    payload.source_text!.slice(span.start, span.end),
    "900 g chicken thighs, boneless",
  );
  // Every line the page printed can be pointed at.
  for (const l of flat) {
    if (l.raw.ingredient_text === "salt") continue;
    assert(l.source_span, `no span for ${l.raw.ingredient_text}`);
  }
});

Deno.test("importRecipe — a line the text cannot place carries no span, and the key is absent", async () => {
  // The page never printed the salt line, so the field is omitted.
  const payload = await importRecipe({ url: "u" }, pageDeps());
  const salt = payload.groups.flatMap((g) => g.lines).find((l) =>
    l.raw.ingredient_text === "salt"
  )!;
  assertEquals("source_span" in salt, false);
});

Deno.test("importRecipe — a photo import carries neither field", async () => {
  // A transcription blob has no `page_text`, so no `source_text` either.
  const payload = await importRecipe(
    { images: [new Uint8Array([1])] },
    deps({ adapter: fakeAdapter({ withVision: true }) }),
  );
  assertEquals("source_text" in payload, false);
  for (const l of payload.groups.flatMap((g) => g.lines)) {
    assertEquals("source_span" in l, false);
  }
});

Deno.test("importRecipe — no page text means no span, even on a link", async () => {
  const payload = await importRecipe({ url: "u" }, deps());
  assertEquals("source_text" in payload, false);
  for (const l of payload.groups.flatMap((g) => g.lines)) {
    assertEquals("source_span" in l, false);
  }
});
