import { assertEquals, assertRejects, assertStringIncludes } from "@std/assert";
import {
  type ImportDeps,
  ImportError,
  importRecipe,
  makeHandler,
  MAX_IMAGE_BYTES,
  MAX_IMAGES,
  parseRequestBody,
} from "./index.ts";
import type {
  ExtractAdapter,
  ExtractionResult,
  MatchedLine,
  RawBlob,
  RawLineItem,
} from "../_shared/types.ts";

// --- Canned extraction (gold-shaped: 2 groups of sizes 2 and 2, steps by index).
// Mirrors an ExtractionResult without touching disk (permission-free tests).
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

// A fake sanitize adapter: returns the canned extraction, records the hints it
// received (to assert vocab-blindness downstream if needed). `transcribe`
// present only when `withVision`.
function fakeAdapter(
  opts: { withVision?: boolean; seen?: { blob?: RawBlob } } = {},
): ExtractAdapter {
  const adapter: ExtractAdapter = {
    name: "fake",
    sanitize(blob: RawBlob): Promise<ExtractionResult> {
      if (opts.seen) opts.seen.blob = blob;
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

// A fake matcher: bands every line `auto` and echoes its index as a candidate
// score — so re-grouping order is observable. Records the flat input it saw.
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
  // 8.6 / D6: the spine copies `recipe_candidates` onto the payload line when
  // the matcher supplied one, and OMITS the key otherwise — a pre-8.6 client
  // decodes the same bytes it always did.
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
  // It used to let `url` win silently, so a confused client never found out.
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
  // `atob` throws; this runs BEFORE the handler's try/catch, so an escaping
  // throw was a 500 with a stack trace in it.
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
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body, { error: "import failed" });
  assertEquals("detail" in body, false);
});

Deno.test("makeHandler — POST url returns 200 payload", async () => {
  const handler = makeHandler(deps());
  const res = await handler(
    new Request("https://fn.test", {
      method: "POST",
      body: JSON.stringify({ url: "https://example.test/curry" }),
    }),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.title, "Test Curry");
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

  // A request that parses but fails IN orchestration → ImportError → 422. Images
  // reach a fake adapter with no `transcribe`, which throws "cannot transcribe".
  const noVision = await handler(
    new Request("https://fn.test", {
      method: "POST",
      body: JSON.stringify({ images: [btoa("x")] }),
    }),
  );
  assertEquals(noVision.status, 422);
});
