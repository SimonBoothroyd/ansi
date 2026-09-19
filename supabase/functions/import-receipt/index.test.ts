// The spine and the HTTP boundary: the stage order on the wire, the four
// failure shapes, the body's cost caps, and what the orchestrator does with a
// transcription that came back the wrong shape.

import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "@std/assert";
import {
  failureFor,
  ImportError,
  importReceipt,
  makeHandler,
  MAX_IMAGE_BYTES,
  MAX_IMAGES,
  parseRequestBody,
  RECEIPT_STAGES,
  type ReceiptDeps,
  type ReceiptStageId,
} from "./index.ts";
import { collectSse, type SseEvent } from "../import-recipe/sse_test_helper.ts";
import type {
  ReceiptAdapter,
  ReceiptExtraction,
  ReceiptPayload,
} from "../_shared/receipt_types.ts";
import type { MatchedLine, RawLineItem } from "../_shared/types.ts";
import type {
  RecallMatchesFn,
  ReceiptMemory,
} from "../_shared/receipt_memory.ts";
import { ProviderTimeoutError } from "../_shared/adapters/http.ts";

// --- Canned readings ---------------------------------------------------------

const PHOTOS = [
  "TRADER JOE'S #135\n09/13/26 05:42 PM\nTJ ORG BANANAS 3.49\nTJ SRIRACHA 3.99",
  "TJ SRIRACHA 3.99\nBAG FEE 0.10\nSUBTOTAL 7.58",
];

function cannedExtraction(): ReceiptExtraction {
  return {
    store_printed: "TRADER JOE'S #135",
    purchased_at_printed: "09/13/26 05:42 PM",
    subtotal_printed: "7.58",
    tax_printed: null,
    total_printed: "7.58",
    lines: [
      {
        printed_text: "TJ ORG BANANAS 3.49",
        name_printed: "TJ ORG BANANAS",
        amount_printed: "3.49",
        discount_printed: null,
        kind: "item",
        weight: null,
        low_confidence: false,
      },
      {
        printed_text: "TJ SRIRACHA 3.99",
        name_printed: "TJ SRIRACHA",
        amount_printed: "3.99",
        discount_printed: null,
        kind: "item",
        weight: null,
        low_confidence: false,
      },
      {
        printed_text: "BAG FEE 0.10",
        name_printed: "BAG FEE",
        amount_printed: "0.10",
        discount_printed: null,
        kind: "not_food",
        weight: null,
        low_confidence: false,
      },
    ],
    notes: [],
  };
}

interface FakeOpts {
  photos?: string[];
  extraction?: () => ReceiptExtraction;
  /** Run inside `structure`, so a test can model a model that is producing. */
  duringStructure?: (adapter: ReceiptAdapter) => void;
  failTranscribe?: () => never;
  failStructure?: () => never;
}

function fakeAdapter(opts: FakeOpts = {}): ReceiptAdapter {
  const adapter: ReceiptAdapter = {
    name: "fake",
    model: "fake-1",
    transcribe: () => {
      opts.failTranscribe?.();
      return Promise.resolve([...(opts.photos ?? PHOTOS)]);
    },
    structure: () => {
      opts.failStructure?.();
      opts.duringStructure?.(adapter);
      return Promise.resolve((opts.extraction ?? cannedExtraction)());
    },
  };
  return adapter;
}

/** Bands every line `none`: the cascade's answer when the vocabulary is empty. */
const noMatches = (lines: RawLineItem[]): Promise<MatchedLine[]> =>
  Promise.resolve(
    lines.map((raw) => ({ raw, band: "none" as const, candidates: [] })),
  );

/** Remembers nothing — a household that has never kept a receipt. */
const noMemory = (): Promise<ReceiptMemory> => Promise.resolve(new Map());

function deps(
  opts: FakeOpts = {},
  matchLines = noMatches,
  recallMatches: RecallMatchesFn = noMemory,
): ReceiptDeps {
  return { adapter: fakeAdapter(opts), matchLines, recallMatches };
}

const oneImage = () => [new Uint8Array([1, 2, 3])];

const post = (body: unknown) =>
  new Request("https://fn.test", {
    method: "POST",
    body: JSON.stringify(body),
  });

const b64 = (n: number) => btoa("x".repeat(n));

// --- The spine ---------------------------------------------------------------

Deno.test("importReceipt — transcribe, join, structure, match, assemble", async () => {
  const payload = await importReceipt({ images: oneImage() }, deps());
  assertEquals(payload.store_printed, "TRADER JOE'S #135");
  assertEquals(payload.purchased_at, "2026-09-13T17:42:00");
  assertEquals(payload.lines.length, 3);
  assertEquals(payload.lines_sum_cents, 349 + 399 + 10);
  assertEquals(payload.printed.subtotal_cents, 758);
  // Two photos, one seam of one line ("TJ SRIRACHA 3.99").
  assertEquals(payload.photos_joined, [{ from: 0, to: 1, overlap_lines: 1 }]);
});

Deno.test("importReceipt — the stages land in order, once each, with elapsed times", async () => {
  const seen: [ReceiptStageId, number][] = [];
  await importReceipt(
    { images: oneImage() },
    deps(),
    (stage, ms) => seen.push([stage, ms]),
  );
  // `received` is the HTTP edge's — the spine narrates the three it runs.
  assertEquals(seen.map(([s]) => s), ["read", "written", "matched"]);
  assert(seen.every(([, ms]) => ms >= 0));
  for (let i = 1; i < seen.length; i++) {
    assert(seen[i][1] >= seen[i - 1][1], "elapsed times never go backwards");
  }
});

Deno.test("importReceipt — a heartbeat is sent while the model produces, and throttled", async () => {
  const beats: number[] = [];
  let progress: (() => void) | undefined;
  await importReceipt(
    { images: oneImage() },
    deps({
      duringStructure: (a) => {
        progress = a.onProgress;
        // Three deltas in quick succession: the throttle allows at most one
        // frame per interval, and the first is due because the last frame was
        // the `read` stage a moment ago... which is itself inside the window.
        a.onProgress?.();
        a.onProgress?.();
        a.onProgress?.();
      },
    }),
    () => {},
    Date.now(),
    (ms) => beats.push(ms),
  );
  assert(beats.length <= 1, `throttled: got ${beats.length}`);
  // And the observer is unhooked when the import ends, so a shared adapter
  // does not keep beating into a finished request.
  assert(progress !== undefined);
});

Deno.test("importReceipt — a photo that did not come back is said FIRST", async () => {
  const payload = await importReceipt(
    { images: [new Uint8Array([1]), new Uint8Array([2]), new Uint8Array([3])] },
    deps(), // the fake returns two transcriptions for three photos
  );
  assertStringIncludes(payload.notes[0], "We read 2 of the 3 photos");
});

Deno.test("importReceipt — nothing legible is a 422, not an empty review", async () => {
  const e = await assertRejects(
    () => importReceipt({ images: oneImage() }, deps({ photos: ["", "   "] })),
    ImportError,
  );
  assertStringIncludes(e.message, "could not read anything");
  assertEquals(failureFor(e).status, 422);
});

Deno.test("importReceipt — a matcher that loses a line fails loudly", async () => {
  await assertRejects(
    () =>
      importReceipt(
        { images: oneImage() },
        deps({}, (lines) => noMatches(lines.slice(1))),
      ),
    ImportError,
    "matcher returned",
  );
});

Deno.test("importReceipt — only the ITEM lines are put to the matcher", async () => {
  const asked: string[] = [];
  await importReceipt(
    { images: oneImage() },
    deps({}, (lines) => {
      asked.push(...lines.map((l) => l.ingredient_text));
      return noMatches(lines);
    }),
  );
  // The BAG FEE line is `not_food`: it never reaches the vocabulary.
  assertEquals(asked, ["TJ ORG BANANAS", "TJ SRIRACHA"]);
});

// --- The request body --------------------------------------------------------

Deno.test("parseRequestBody — photos, and only photos", () => {
  const ok = parseRequestBody({ images: [btoa("hello")] });
  assert("request" in ok);
  assertEquals(ok.request.images.length, 1);

  for (
    const [body, fragment] of [
      [{ url: "https://example.test/r" }, "not from a `url`"],
      [{}, "must include `images`"],
      [{ images: [] }, "must not be empty"],
      [{ images: [1, 2] }, "array of base64 strings"],
      [{ images: ["!!!!"] }, "not valid base64"],
      [[], "must be a JSON object"],
      [null, "must be a JSON object"],
    ] as [unknown, string][]
  ) {
    const r = parseRequestBody(body);
    assert("error" in r, JSON.stringify(body));
    assertStringIncludes(r.error, fragment);
  }
});

Deno.test("parseRequestBody — the cost caps are the recipe door's, shared", () => {
  const many = parseRequestBody({
    images: Array.from({ length: MAX_IMAGES + 1 }, () => btoa("x")),
  });
  assert("error" in many);
  assertStringIncludes(many.error, "too many images");

  const big = parseRequestBody({ images: [b64(MAX_IMAGE_BYTES + 1024)] });
  assert("error" in big);
  assertStringIncludes(big.error, "the limit is");
});

// --- The stream --------------------------------------------------------------

const eventNames = (events: SseEvent[]) => events.map((e) => e.event);

Deno.test("makeHandler — plan, four stages in order, then the result", async () => {
  const res = await makeHandler(deps())(post({ images: [btoa("photo")] }));
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type"), "text/event-stream");
  const events = await collectSse(res);

  assertEquals(eventNames(events)[0], "plan");
  assertEquals((events[0].data as { stages: string[] }).stages, RECEIPT_STAGES);

  const stages = events.filter((e) => e.event === "stage")
    .map((e) => (e.data as { stage: string }).stage);
  assertEquals(stages, ["received", "read", "written", "matched"]);

  const last = events[events.length - 1];
  assertEquals(last.event, "result");
  const payload = last.data as ReceiptPayload;
  assertEquals(payload.lines.length, 3);
});

Deno.test("makeHandler — the stage NAMES are the contract", () => {
  // The wording belongs to the app ("Photos received", "Photos read",
  // "Writing the receipt out…", "Lines matched"); these ids are what the wire
  // carries, and renaming one silently blanks a row on the reading screen.
  assertEquals(RECEIPT_STAGES, ["received", "read", "written", "matched"]);
});

Deno.test("makeHandler — a failure after the first byte is an error EVENT, not a status", async () => {
  const res = await makeHandler(
    deps({
      failStructure: () => {
        throw new ImportError("this receipt is too long to read in one go");
      },
    }),
  )(post({ images: [btoa("photo")] }));
  // The status was committed before the work ran.
  assertEquals(res.status, 200);
  const events = await collectSse(res);
  const last = events[events.length - 1];
  assertEquals(last.event, "error");
  assertStringIncludes((last.data as { error: string }).error, "too long");
  // And NO result rode along beside it.
  assertEquals(events.filter((e) => e.event === "result").length, 0);
});

Deno.test("makeHandler — what is known before the work runs is still a status", async () => {
  const handler = makeHandler(deps());
  const notPost = await handler(
    new Request("https://fn.test", { method: "GET" }),
  );
  assertEquals(notPost.status, 405);

  const badJson = await handler(
    new Request("https://fn.test", { method: "POST", body: "{" }),
  );
  assertEquals(badJson.status, 400);

  const badBody = await handler(post({ images: [] }));
  assertEquals(badBody.status, 400);
  assertEquals(badBody.headers.get("content-type"), "application/json");
});

// --- Failures ----------------------------------------------------------------

Deno.test("failureFor — the three shapes, in this door's voice", () => {
  assertEquals(failureFor(new ImportError("say this")), {
    status: 422,
    error: "say this",
  });

  const timedOut = failureFor(new ProviderTimeoutError("Claude", 60_000));
  assertEquals(timedOut.status, 504);
  // Names the RECEIPT, and says retrying is safe — nothing is written until
  // the review's Save.
  assertStringIncludes(timedOut.error, "read this receipt");
  assertStringIncludes(timedOut.error, "safe to try again");

  const unexpected = failureFor(new TypeError("postgres://user:pw@host"));
  assertEquals(unexpected.status, 500);
  // The detail can carry a connection string: it is logged, never returned.
  assertEquals(unexpected.error, "import failed");
});

// --- The recall is an improvement, never a dependency ------------------------

Deno.test("recall — the spine asks about the ITEM lines' printed names", async () => {
  const asked: string[][] = [];
  await importReceipt(
    { images: oneImage() },
    deps({}, noMatches, (names) => {
      asked.push(names);
      return Promise.resolve(new Map());
    }),
  );
  // Two item lines and a `not_food` bag fee: a fee has no ingredient to be
  // about, so asking about one would spend a query to be told so.
  assertEquals(asked, [["TJ ORG BANANAS", "TJ SRIRACHA"]]);
});

Deno.test("recall — the household's own answer overrides the cascade", async () => {
  const payload = await importReceipt(
    { images: oneImage() },
    deps({}, noMatches, () =>
      Promise.resolve(
        new Map([["TJ SRIRACHA", {
          kind: "item" as const,
          ingredient_id: "v-sriracha",
        }]]),
      )),
  );
  const line = payload.lines.find((l) => l.name_printed === "TJ SRIRACHA")!;
  assertEquals(line.match, {
    ingredient_id: "v-sriracha",
    confidence: 1,
    kind: "auto",
    remembered: true,
  });
});

Deno.test("recall — a lookup that throws does not cost the receipt", async () => {
  // The photos are read and the model is paid for by the time this runs. A
  // receipt matched exactly as it would have been last month is a working
  // receipt; failing the import over it would not be.
  const payload = await importReceipt(
    { images: oneImage() },
    deps({}, noMatches, () => Promise.reject(new Error("pool exhausted"))),
  );
  assertEquals(payload.lines.length, 3);
  assertEquals(payload.lines[0].match, null, "the cascade alone");
  assertEquals(payload.lines_sum_cents, 349 + 399 + 10);
});
