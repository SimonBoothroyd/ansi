// The keyless replay switch, and the locks that keep it out of a deployed
// environment. See `replay.ts`.

import { assert, assertEquals, assertThrows } from "@std/assert";
import {
  REPLAY_FIXTURE_ENV,
  replayReceiptAdapter,
  replayReceiptAdapterFromEnv,
} from "./replay.ts";
import { joinPhotoTranscripts } from "../_shared/receipt_join.ts";

const fixture = (name: string): unknown =>
  JSON.parse(
    Deno.readTextFileSync(
      new URL(`./testdata/${name}.json`, import.meta.url).pathname,
    ),
  );

/** Sets the env for one case and restores whatever was there. */
function withEnv(vars: Record<string, string | null>, run: () => void): void {
  const before = Object.keys(vars).map(
    (k) => [k, Deno.env.get(k) ?? null] as const,
  );
  try {
    for (const [k, v] of Object.entries(vars)) {
      if (v === null) Deno.env.delete(k);
      else Deno.env.set(k, v);
    }
    run();
  } finally {
    for (const [k, v] of before) {
      if (v === null) Deno.env.delete(k);
      else Deno.env.set(k, v);
    }
  }
}

Deno.test("replay — a saved reading comes back through the live decoder, with no key", async () => {
  const adapter = replayReceiptAdapter(
    fixture("tj_three_photos"),
    "tj_three_photos",
  );
  const photos = await adapter.transcribe([new Uint8Array([1])]);
  assertEquals(photos.length, 3);

  const extraction = await adapter.structure(photos.join("\n"));
  assertEquals(extraction.store_printed, "TRADER JOE'S #135");
  assertEquals(extraction.lines.length, 9);
  // Coerced and validated on the way through, exactly as a live answer is.
  assertEquals(extraction.lines[1].weight?.unit_printed, "lb");
});

Deno.test("replay — the photos come back UNJOINED, so the join is exercised", async () => {
  // The point of holding one transcription per photo rather than a finished
  // strip: a replay run puts the real seam-finder to work.
  const adapter = replayReceiptAdapter(
    fixture("tj_three_photos"),
    "tj_three_photos",
  );
  const photos = await adapter.transcribe([]);
  const joined = joinPhotoTranscripts(photos);
  assertEquals(joined.seams, [
    { from: 0, to: 1, overlap_lines: 2 },
    { from: 1, to: 2, overlap_lines: 2 },
  ]);
});

Deno.test("replay — the Whole Foods fixture: a seam, and a PRIME SAVINGS fold", async () => {
  const adapter = replayReceiptAdapter(
    fixture("whole_foods_two_photos"),
    "whole_foods_two_photos",
  );
  const photos = await adapter.transcribe([]);
  assertEquals(joinPhotoTranscripts(photos).seams, [
    { from: 0, to: 1, overlap_lines: 2 },
  ]);
  const extraction = await adapter.structure("");
  const spinach = extraction.lines.find((l) =>
    l.printed_text.includes("SPINACH")
  )!;
  // The deduction is ON the item, not a line of its own.
  assertEquals(spinach.discount_printed, "-1.00");
  assertEquals(
    extraction.lines.filter((l) => l.printed_text.includes("PRIME")).length,
    0,
  );
});

Deno.test("replay — refuses a fixture recorded from another provider", () => {
  assertThrows(
    () => replayReceiptAdapter({ provider: "gpt-5-mini", raw: {} }, "x"),
    Error,
    "replay decodes Claude responses",
  );
});

Deno.test("replay — a file that is not a fixture fails at wiring, not as an empty receipt", () => {
  assertThrows(
    () => replayReceiptAdapter({ store_printed: "TJ" }, "x"),
    Error,
    "not a receipt replay fixture",
  );
});

Deno.test("replay — a fixture with no photos is refused", () => {
  // Without them the join would be skipped, and a replay that skips the join
  // is a replay of half the pipeline.
  assertThrows(
    () =>
      replayReceiptAdapter({ provider: "claude", raw: {}, photos: [] }, "x"),
    Error,
    'has no "photos"',
  );
});

Deno.test("replay — off unless the env var names something", () => {
  withEnv({ [REPLAY_FIXTURE_ENV]: null, ANTHROPIC_API_KEY: null }, () => {
    assertEquals(replayReceiptAdapterFromEnv(), null);
  });
  withEnv({ [REPLAY_FIXTURE_ENV]: "   ", ANTHROPIC_API_KEY: null }, () => {
    assertEquals(replayReceiptAdapterFromEnv(), null);
  });
});

Deno.test("replay — REFUSES to load where a real key can read", () => {
  // The lock that matters: a deployed environment always has the key, so even
  // if the switch were somehow set there it can never serve a canned receipt.
  withEnv(
    { [REPLAY_FIXTURE_ENV]: "/does/not/matter", ANTHROPIC_API_KEY: "sk-ant-x" },
    () => {
      assertThrows(
        replayReceiptAdapterFromEnv,
        Error,
        "refusing to serve a saved receipt",
      );
    },
  );
});

Deno.test("replay — the committed fixtures carry no real receipt", async () => {
  // The repo is public and a real receipt carries a card's last four and a
  // loyalty number. What is committed is written by hand; the owner's real
  // ones live in `__fixtures__/local/`, which is gitignored.
  for (const name of ["tj_three_photos", "whole_foods_two_photos"]) {
    const src = await Deno.readTextFile(
      new URL(`./testdata/${name}.json`, import.meta.url),
    );
    assert(
      JSON.parse(src)._comment?.startsWith("SYNTHETIC"),
      `${name} must say, in the file, that it is synthetic`,
    );
    // No long digit runs: a card tail, a loyalty number, a phone number.
    const digits = src.match(/\d{5,}/g) ?? [];
    assertEquals(digits, [], `${name} carries a long number`);
  }
});
