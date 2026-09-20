// The count sub-row, over two whole receipts shaped like the owner's.
//
// Both fixtures are synthetic and both are the real thing in shape: a count
// printed on its OWN line under the item it belongs to, which is how Whole
// Foods and Trader Joe's print nearly every multiple. Before this, that
// sub-row became a junk line of its own and the item above kept the whole
// figure against ONE pack — eight blocks of tofu priced as one block, eight
// times too dear.
//
// The replay path is the subject: the saved transcriptions go through the REAL
// join (so a seam falling between an item and its sub-row is exercised), the
// REAL Claude decoder, the REAL coercion, and the REAL assembly. Nothing here
// calls a model and nothing here needs a network.

import { assert, assertEquals } from "@std/assert";
import { replayReceiptAdapter } from "./replay.ts";
import { joinPhotoTranscripts } from "../_shared/receipt_join.ts";
import {
  assembleReceipt,
  itemMatchInputs,
} from "../_shared/receipt_assemble.ts";
import type {
  ReceiptLineOut,
  ReceiptPayload,
} from "../_shared/receipt_types.ts";
import type { MatchedLine } from "../_shared/types.ts";

/** One fixture, read and assembled under no vocabulary at all. */
async function read(file: string): Promise<ReceiptPayload> {
  const saved = JSON.parse(
    await Deno.readTextFile(new URL(`./testdata/${file}`, import.meta.url)),
  );
  const adapter = replayReceiptAdapter(saved, file);
  const photos = await adapter.transcribe([]);
  const transcript = joinPhotoTranscripts(photos);
  const extraction = await adapter.structure(transcript.text);
  const matched: MatchedLine[] = itemMatchInputs(extraction).map((raw) => ({
    raw,
    band: "none" as const,
    candidates: [],
  }));
  return assembleReceipt(extraction, transcript, matched);
}

function of(p: ReceiptPayload, starts: string): ReceiptLineOut {
  const line = p.lines.find((l) => l.printed_text.startsWith(starts));
  assert(line, `no line starting "${starts}"`);
  return line;
}

/** Every count sub-row, as a line of its own, would show up here. */
function strayCountLines(p: ReceiptPayload): ReceiptLineOut[] {
  return p.lines.filter((l) =>
    /^(qty\b|\d+\s*@)/i.test(l.printed_text.trim()) && l.weight === null
  );
}

Deno.test("Whole Foods — the counts ride on their items, and the strip adds up", async () => {
  const p = await read("whole_foods_counts.json");

  assertEquals(p.store_printed, "WHOLE FOODS MARKET");
  assertEquals(p.purchased_at, "2026-09-20T11:04:00");

  // Five skyr lines, counted off the sub-rows under them — not five lines and
  // five junk rows, and not one bought thirteen times.
  const skyr = p.lines.filter((l) => l.printed_text.includes("SKYR"));
  assertEquals(skyr.length, 5);
  assertEquals(skyr.map((l) => l.count), [2, 4, 4, 2, 1]);
  assertEquals(skyr.map((l) => l.cents), [478, 956, 956, 478, 239]);
  for (const l of skyr) assertEquals(l.each_cents, 239);

  // `Qty 0.73 lb @ $2.99/lb` is a WEIGHT. The word "Qty" decides nothing.
  const onion = of(p, "OG RED ONION");
  assertEquals(onion.weight, { amount: 0.73, unit: "lb", rate_cents: 299 });
  assertEquals(onion.count, 1);
  const serrano = of(p, "OG SERRANO PEPPER");
  assertEquals(serrano.weight, { amount: 0.31, unit: "lb", rate_cents: 499 });
  assertEquals(serrano.count, 1);

  // The bag charge printed no money on its own line: the figure is in the
  // totals block, and it is ONE fee line carrying it.
  const bags = of(p, "CARRY OUT BAG CHARGE");
  assertEquals(bags.kind, "fee");
  assertEquals(bags.cents, 10);
  assertEquals(bags.count, 2);

  assertEquals(strayCountLines(p), [], "no sub-row became a line");
  assertEquals(p.lines.length, 12);
  assertEquals(p.printed.subtotal_cents, 5966);
  assertEquals(p.lines_sum_cents, 5966, "the lines are the printed subtotal");
  assertEquals(p.notes, [], "nothing was left unread");

  // The seam fell between the last skyr and its own `Qty 1` sub-row, and the
  // join put the two back in order.
  assertEquals(p.photos_joined, [{ from: 0, to: 1, overlap_lines: 1 }]);
});

Deno.test("Trader Joe's — no subtotal printed, and the lines plus tax are the total", async () => {
  const p = await read("trader_joes_counts.json");

  assertEquals(p.store_printed, "TRADER JOE'S #542");
  assertEquals(p.purchased_at, "2026-09-20T12:12:00");

  // THE ONE THAT WAS EIGHT TIMES TOO DEAR.
  const tofu = of(p, "TOFU SPR FRM HGH PRTN OR");
  assertEquals(tofu.cents, 2392);
  assertEquals(tofu.count, 8);
  assertEquals(tofu.each_cents, 299);

  assertEquals(of(p, "IMPOSSIBLE BURGER").count, 2);
  assertEquals(of(p, "CASHEW MOZZARELLA").count, 2);
  assertEquals(of(p, "ORG EDAMAME").count, 2);
  assertEquals(of(p, "ORG YELLOW ONION").count, 2);
  assertEquals(of(p, "LIME EACH").count, 4);
  assertEquals(of(p, "LIME EACH").cents, 196);

  // Two identical single lines are TWO lines. A receipt honestly prints the
  // same thing twice when it was rung up twice, and neither is a count.
  const yeast = p.lines.filter((l) => l.printed_text.includes("NUTRITIONAL"));
  assertEquals(yeast.length, 2);
  assertEquals(yeast.map((l) => l.count), [1, 1]);
  assertEquals(yeast.map((l) => l.cents), [349, 349]);

  assertEquals(strayCountLines(p), [], "no sub-row became a line");
  assertEquals(p.lines.length, 14);
  // `Items in Transaction` and `Balance to pay` are bookkeeping, not lines.
  assert(
    !p.lines.some((l) =>
      /items in transaction|balance to pay/i.test(l.printed_text)
    ),
  );

  // This strip prints no subtotal at all — so the reconcile is the total less
  // the tax, which is the figure the review holds the lines against.
  assertEquals(p.printed.subtotal_cents, null);
  assertEquals(p.printed.tax_cents, 11);
  assertEquals(p.printed.total_cents, 10445);
  assertEquals(p.lines_sum_cents, 10434);
  assertEquals(p.lines_sum_cents + p.printed.tax_cents!, p.printed.total_cents);
  assertEquals(p.notes, []);

  // Both seams fell on an item and its sub-row, and both were found.
  assertEquals(p.photos_joined, [
    { from: 0, to: 1, overlap_lines: 2 },
    { from: 1, to: 2, overlap_lines: 2 },
  ]);
});
