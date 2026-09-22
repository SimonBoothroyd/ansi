// The label door's HTTP edge: what a body may be, what the answer looks like,
// and what a person is told when the read fails. The reading itself comes from
// a fake adapter, so nothing here dials out.

import { assert, assertEquals } from "@std/assert";
import type { LabelAdapter, LabelReading } from "../_shared/label_types.ts";
import { ProviderTimeoutError } from "../_shared/adapters/http.ts";
import {
  failureFor,
  ImportError,
  type LabelDeps,
  makeHandler,
  MAX_IMAGE_BYTES,
  parseRequestBody,
  readLabel,
} from "./index.ts";

const READING: LabelReading = {
  serving: { amount: 30, unit_printed: "g", text_printed: "per 30 g serving" },
  per_serving: {
    kcal: 113,
    protein_g: 4.1,
    carbohydrate_g: 18.6,
    fat_g: 1.9,
    fibre_g: 3.2,
  },
  per_100: {
    basis: "g",
    kcal: 377,
    protein_g: 13.7,
    carbohydrate_g: 62.1,
    fat_g: 6.2,
    fibre_g: 10.6,
  },
  notes: [],
};

/** A reader that answers with `READING`, and records what it was handed. */
function fakeAdapter(seen: Uint8Array[] = []): LabelAdapter {
  return {
    name: "fake-label",
    read: (image) => {
      seen.push(image);
      return Promise.resolve(READING);
    },
  };
}

function throwingAdapter(e: unknown): LabelAdapter {
  return { name: "throwing-label", read: () => Promise.reject(e) };
}

const post = (body: unknown) =>
  new Request("https://fn.test", {
    method: "POST",
    body: JSON.stringify(body),
  });

const B64_PIXEL = btoa("not really a jpeg, but it is bytes");

// --- The body ----------------------------------------------------------------

Deno.test("body — one image is the whole request", () => {
  const parsed = parseRequestBody({ images: [B64_PIXEL] });
  assert("request" in parsed);
  assertEquals(parsed.request.image.length, atob(B64_PIXEL).length);
});

Deno.test("body — a label is read from ONE photo, and says so", () => {
  const parsed = parseRequestBody({ images: [B64_PIXEL, B64_PIXEL] });
  assert("error" in parsed);
  assertEquals(parsed.error, "a label is read from one photo");
});

Deno.test("body — the refusals a person could act on", () => {
  for (
    const [body, expected] of [
      ["nope", "body must be a JSON object"],
      [[], "body must be a JSON object"],
      [{}, "body must include `images`"],
      [{ images: [] }, "`images` must not be empty"],
      [{ images: [42] }, "`images` must be an array of base64 strings"],
      [{ images: ["!!! not base64 !!!"] }, "image 1 is not valid base64"],
    ] as const
  ) {
    const parsed = parseRequestBody(body);
    assert("error" in parsed, `expected an error for ${JSON.stringify(body)}`);
    assertEquals(parsed.error, expected);
  }
});

Deno.test("body — an oversize photo is refused before it is decoded", () => {
  // Shares the import doors' cap: the app already downscales.
  const parsed = parseRequestBody({
    images: ["A".repeat(MAX_IMAGE_BYTES * 2)],
  });
  assert("error" in parsed);
  assert(parsed.error.includes("the limit is"));
});

// --- The reading -------------------------------------------------------------

Deno.test("read — the adapter is handed the decoded bytes, and its reading comes back", async () => {
  const seen: Uint8Array[] = [];
  const reading = await readLabel(
    { image: new Uint8Array([1, 2, 3]) },
    { adapter: fakeAdapter(seen) },
  );
  assertEquals(seen.length, 1);
  assertEquals([...seen[0]], [1, 2, 3]);
  assertEquals(reading, READING);
});

Deno.test("wire — a good read is a plain 200 JSON body, not a stream", async () => {
  const res = await makeHandler({ adapter: fakeAdapter() })(
    post({ images: [B64_PIXEL] }),
  );
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type"), "application/json");
  assertEquals(await res.json(), READING);
});

Deno.test("wire — GET is 405, a broken body is 400", async () => {
  const handler = makeHandler({ adapter: fakeAdapter() });
  const get = await handler(new Request("https://fn.test"));
  assertEquals(get.status, 405);

  const broken = await handler(
    new Request("https://fn.test", { method: "POST", body: "{" }),
  );
  assertEquals(broken.status, 400);
  assertEquals((await broken.json()).error, "invalid JSON body");
});

// --- What failure looks like -------------------------------------------------

Deno.test("failure — the three shared shapes, in this door's voice", () => {
  const acted = failureFor(new ImportError("that photo is too dark to read"));
  assertEquals(acted, {
    status: 422,
    error: "that photo is too dark to read",
  });

  const late = failureFor(new ProviderTimeoutError("Claude", 60_000));
  assertEquals(late.status, 504);
  assert(late.error.includes("read this label"));
  assert(late.error.includes("nothing has been saved"));

  // Anything else is logged, never returned: the detail can carry a provider
  // URL or a prompt fragment.
  const other = failureFor(new Error("https://api.anthropic.com blew up"));
  assertEquals(other, { status: 500, error: "import failed" });
  assert(!other.error.includes("anthropic"));
});

Deno.test("wire — a failed read is a status, and the form is told nothing else", async () => {
  const deps: LabelDeps = {
    adapter: throwingAdapter(new ImportError("we could not find a panel")),
  };
  const res = await makeHandler(deps)(post({ images: [B64_PIXEL] }));
  assertEquals(res.status, 422);
  assertEquals(await res.json(), { error: "we could not find a panel" });
});
