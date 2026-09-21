// The TS→Dart contract test for receipts: runs the real spine with no network
// and no LLM, and pins its `ReceiptPayload` as a committed golden JSON file the
// Flutter side parses. `receipt_types.ts` and the Dart mirror are written by
// hand and the Dart side defaults every field, so drift would decode silently
// (see `import-recipe/golden_payload.test.ts`).
//
// The replay adapter answers from a synthetic fixture (testdata/) through the
// real decoder and coercion; the real join runs over its three photos; the
// real cascade runs over a small vocab pinned here; the request goes through
// the real `makeHandler`.
//
// Regenerate after an intentional contract change:
//   cd supabase/functions && deno task golden-receipt
// Review the diff, then update the Dart assertions if a shape moved.

import { assert, assertEquals } from "@std/assert";
import { makeHandler, type ReceiptDeps } from "./index.ts";
import { replayReceiptAdapter } from "./replay.ts";
import { collectSse } from "../import-recipe/sse_test_helper.ts";
import type { ReceiptPayload } from "../_shared/receipt_types.ts";
import { matchLines } from "../_shared/match.ts";
import {
  inMemoryVocabMatcher,
  type VocabEntry,
} from "../_shared/match_trgm.ts";

const GOLDEN_PATH = new URL(
  "./__fixtures__/receipt_payload.golden.json",
  import.meta.url,
);
const FIXTURE_PATH = new URL(
  "./testdata/tj_three_photos.json",
  import.meta.url,
);

// --- The pinned vocab --------------------------------------------------------
//
// Small and committed, so the golden is reproducible. Chosen so all three
// bands appear in a receipt's usual mix: two exact hits, one trigram
// suggestion, and two store abbreviations nothing is close to.

const VOCAB: VocabEntry[] = [
  // exact → auto
  {
    ingredient_id: "v-onion",
    canonical_name: "Yellow onion",
    match_texts: ["yellow onion"],
  },
  // exact through an alias → auto
  {
    ingredient_id: "v-salmon",
    canonical_name: "Salmon fillet",
    match_texts: ["salmon fillet", "atlantic salmon"],
  },
  // trigram 0.75 → suggest
  {
    ingredient_id: "v-sriracha",
    canonical_name: "Sriracha",
    match_texts: ["sriracha"],
  },
  // trigram 0.50 → below the suggest floor → none
  {
    ingredient_id: "v-banana",
    canonical_name: "Bananas, organic",
    match_texts: ["banana organic"],
  },
  // nothing near "tj med chdr shrd" → none
  {
    ingredient_id: "v-cheddar",
    canonical_name: "Cheddar",
    match_texts: ["cheddar"],
  },
];

async function runPipeline(): Promise<ReceiptPayload> {
  const saved = JSON.parse(await Deno.readTextFile(FIXTURE_PATH));
  const deps: ReceiptDeps = {
    adapter: replayReceiptAdapter(saved, "tj_three_photos"),
    matchLines: (lines) => matchLines(lines, inMemoryVocabMatcher(VOCAB)),
    // The golden is the cascade's answer; a fixture has no household memory.
    recallMatches: () => Promise.resolve(new Map()),
  };
  // The replay adapter never reads the bytes, but the request must be real.
  const res = await makeHandler(deps)(
    new Request("https://fn.test", {
      method: "POST",
      body: JSON.stringify({ images: [btoa("a"), btoa("b"), btoa("c")] }),
    }),
  );
  assertEquals(res.status, 200);
  const events = await collectSse(res);
  const last = events[events.length - 1];
  assertEquals(last.event, "result", JSON.stringify(last.data));
  return last.data as ReceiptPayload;
}

Deno.test("golden — the payload the app receives, pinned", async () => {
  const payload = await runPipeline();

  if (Deno.env.get("UPDATE_GOLDEN") === "1") {
    await Deno.writeTextFile(
      GOLDEN_PATH,
      JSON.stringify(payload, null, 2) + "\n",
    );
    console.log(`rewrote ${GOLDEN_PATH.pathname}`);
    return;
  }

  const golden = JSON.parse(await Deno.readTextFile(GOLDEN_PATH));
  assertEquals(payload, golden);
});

Deno.test("golden — the shape it pins is the one worth pinning", async () => {
  const p = await runPipeline();

  // The header, read off the paper and parsed.
  assertEquals(p.store_printed, "TRADER JOE'S #135");
  assertEquals(p.purchased_at_printed, "09/13/26 05:42 PM");
  assertEquals(p.purchased_at, "2026-09-13T17:42:00");
  assertEquals(p.printed, {
    subtotal_cents: 3396,
    tax_cents: 82,
    total_cents: 3478,
  });

  // The reconcile closes on this receipt; a broken join would break it.
  assertEquals(p.lines_sum_cents, p.printed.subtotal_cents);

  // Three photos, two seams of two lines each.
  assertEquals(p.photos_joined, [
    { from: 0, to: 1, overlap_lines: 2 },
    { from: 1, to: 2, overlap_lines: 2 },
  ]);
  assertEquals(p.notes, []);

  // Every band is represented, and every kind.
  const kinds = new Set(p.lines.map((l) => l.kind));
  assertEquals([...kinds].sort(), ["item", "not_food", "tax"]);
  assertEquals(
    p.lines.filter((l) => l.match?.kind === "auto").length,
    2,
    "two exact hits",
  );
  assertEquals(
    p.lines.filter((l) => l.match?.kind === "suggest").length,
    1,
    "one trigram suggestion",
  );
  assert(
    p.lines.some((l) => l.kind === "item" && l.match === null),
    "a store's abbreviation nothing is close to",
  );

  // The by-weight lines price themselves off the printed rate.
  const onions = p.lines.find((l) => l.printed_text.startsWith("YELLOW"))!;
  assertEquals(onions.weight, { amount: 1.32, unit: "lb", rate_cents: 199 });
  assertEquals(onions.match?.ingredient_id, "v-onion");

  // The discount printed under the salmon is folded onto it, both figures kept.
  const salmon = p.lines.find((l) => l.printed_text.startsWith("ATLANTIC"))!;
  assertEquals(salmon.cents, 604);
  assertEquals(salmon.discount_cents, 55);
  assertEquals(salmon.weight, { amount: 1.1, unit: "lb", rate_cents: 549 });
  // The PRIME SAVINGS line does not also appear as a line of its own.
  assertEquals(p.lines.filter((l) => l.cents === -55).length, 0);

  // The count sub-row under the sriracha rides on the item: two bottles at
  // $3.99 rang up as $7.98 once.
  const sriracha = p.lines.find((l) =>
    l.printed_text.startsWith("TJ SRIRACHA")
  )!;
  assertEquals(sriracha.cents, 798);
  assertEquals(sriracha.count, 2);
  assertEquals(sriracha.each_cents, 399);
  assertEquals(p.lines.filter((l) => l.printed_text === "2 @ 3.99").length, 0);

  // Bananas were bought twice and are two lines, on two photos.
  const bananas = p.lines.filter((l) => l.printed_text.includes("BANANAS"));
  assertEquals(bananas.length, 2);
  assertEquals(bananas.map((l) => l.photo), [0, 1]);
});
