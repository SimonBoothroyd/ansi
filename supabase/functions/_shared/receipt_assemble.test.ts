// Assembly: the reconcile arithmetic, the discount fold, the weight lines, the
// photo a line came from, and what happens to a figure nobody can read.

import { assert, assertEquals } from "@std/assert";
import {
  assembleReceipt,
  itemMatchInputs,
  linesSumCents,
} from "./receipt_assemble.ts";
import { joinPhotoTranscripts } from "./receipt_join.ts";
import type { ExtractedLine, ReceiptExtraction } from "./receipt_types.ts";
import type { MatchedLine, RawLineItem } from "./types.ts";

function line(p: Partial<ExtractedLine> = {}): ExtractedLine {
  return {
    printed_text: "THING 1.00",
    name_printed: "THING",
    amount_printed: "1.00",
    discount_printed: null,
    kind: "item",
    weight: null,
    low_confidence: false,
    ...p,
  };
}

function extraction(
  lines: ExtractedLine[],
  head: Partial<ReceiptExtraction> = {},
): ReceiptExtraction {
  return {
    store_printed: "TRADER JOE'S #135",
    purchased_at_printed: "09/13/26 05:42 PM",
    subtotal_printed: null,
    tax_printed: null,
    total_printed: null,
    lines,
    notes: [],
    ...head,
  };
}

/** A transcript that contains every line, on one photo — the boring case. */
function flatTranscript(e: ReceiptExtraction) {
  return joinPhotoTranscripts([e.lines.map((l) => l.printed_text).join("\n")]);
}

/** `none`-banded matches, one per item line: assembly under no vocabulary at all. */
function unmatched(e: ReceiptExtraction): MatchedLine[] {
  return itemMatchInputs(e).map((raw: RawLineItem) => ({
    raw,
    band: "none" as const,
    candidates: [],
  }));
}

function assemble(e: ReceiptExtraction) {
  return assembleReceipt(e, flatTranscript(e), unmatched(e));
}

Deno.test("reconcile — items less their discounts, plus not_food, plus fees; tax out", () => {
  const e = extraction([
    line({ printed_text: "A 3.49", amount_printed: "3.49" }),
    line({
      printed_text: "B 6.04",
      amount_printed: "6.04",
      discount_printed: "-0.55",
    }),
    line({
      printed_text: "PAPER TOWELS 6.99",
      amount_printed: "6.99",
      kind: "not_food",
    }),
    line({ printed_text: "TAX 0.82", amount_printed: "0.82", kind: "tax" }),
    line({
      printed_text: "COUPON -1.00",
      amount_printed: "-1.00",
      kind: "fee",
    }),
  ], { subtotal_printed: "14.97" });
  const p = assemble(e);
  // 349 + (604 - 55) + 699 + (-100) = 1497. The tax is not in it.
  assertEquals(p.lines_sum_cents, 1497);
  assertEquals(p.printed.subtotal_cents, 1497);
  assertEquals(p.lines.length, 5);
});

Deno.test("reconcile — the server states BOTH numbers and refuses nothing", () => {
  const e = extraction([line({ amount_printed: "3.49" })], {
    subtotal_printed: "99.99",
  });
  const p = assemble(e);
  assertEquals(p.lines_sum_cents, 349);
  assertEquals(p.printed.subtotal_cents, 9999);
  // No exception, no flag field, no "valid" boolean: two numbers, side by
  // side. The review draws the join card.
  assert(!("reconciled" in p));
});

Deno.test("reconcile — a receipt with no printed subtotal still sums", () => {
  const e = extraction([line({ amount_printed: "3.49" })]);
  const p = assemble(e);
  assertEquals(p.printed.subtotal_cents, null);
  assertEquals(p.lines_sum_cents, 349);
});

Deno.test("discount — folded onto the item, kept beside its cents", () => {
  const e = extraction([
    line({
      printed_text: "ATLANTIC SALMON 6.04",
      amount_printed: "6.04",
      discount_printed: "-0.55", // as the PRIME SAVINGS line under it printed
    }),
  ]);
  const p = assemble(e);
  // Both printed figures survive (0044): the sum is not subtracted into cents.
  assertEquals(p.lines[0].cents, 604);
  assertEquals(p.lines[0].discount_cents, 55);
  assertEquals(p.lines_sum_cents, 549);
});

Deno.test("discount — always non-negative, whichever sign the paper printed", () => {
  for (const printed of ["-0.55", "0.55", "(0.55)"]) {
    const p = assemble(extraction([line({ discount_printed: printed })]));
    assertEquals(p.lines[0].discount_cents, 55, printed);
  }
});

Deno.test("discount — one that could not be attached rides as a negative fee", () => {
  // The model's escape hatch when it cannot tell which item a deduction
  // belongs to. The reconcile still closes, because a fee counts.
  const e = extraction([
    line({ amount_printed: "3.49" }),
    line({
      printed_text: "MEMBER SAVINGS -1.00",
      amount_printed: "-1.00",
      kind: "fee",
    }),
  ]);
  const p = assemble(e);
  assertEquals(p.lines[1].cents, -100);
  assertEquals(p.lines[1].discount_cents, 0);
  assertEquals(p.lines_sum_cents, 249);
});

Deno.test("weight — the printed weight and rate, the unit as a units.dart id", () => {
  const e = extraction([
    line({
      printed_text: "YELLOW ONIONS 1.32 lb @ 1.99/lb 2.63",
      amount_printed: "2.63",
      weight: { amount: 1.32, unit_printed: "LB", rate_printed: "$1.99" },
    }),
  ]);
  const p = assemble(e);
  assertEquals(p.lines[0].weight, {
    amount: 1.32,
    unit: "lb",
    rate_cents: 199,
  });
  assertEquals(p.lines[0].cents, 263);
});

Deno.test("weight — everything else carries none", () => {
  const p = assemble(extraction([
    line({ printed_text: "2 @ 0.99 1.98", amount_printed: "1.98" }),
    line({ printed_text: "TJ SRIRACHA 3.99", amount_printed: "3.99" }),
  ]));
  assertEquals(p.lines[0].weight, null);
  assertEquals(p.lines[1].weight, null);
});

Deno.test("weight — an unreadable unit or rate loses the weight, not the line", () => {
  const e = extraction([
    line({
      printed_text: "ODD 2.00",
      amount_printed: "2.00",
      weight: { amount: 1, unit_printed: "bushel", rate_printed: "2.00" },
    }),
  ]);
  const p = assemble(e);
  assertEquals(p.lines[0].weight, null);
  assertEquals(p.lines[0].cents, 200); // the price stands as printed
  assertEquals(p.notes.length, 1);
  assert(p.notes[0].includes("ODD 2.00"));
});

Deno.test("an unreadable price counts as nothing, says so, and flags itself", () => {
  const e = extraction([
    line({ printed_text: "FAINT [illegible]", amount_printed: "[illegible]" }),
    line({ amount_printed: "3.49" }),
  ]);
  const p = assemble(e);
  assertEquals(p.lines[0].cents, 0);
  assertEquals(p.lines[0].low_confidence, true);
  assertEquals(p.lines_sum_cents, 349);
  assert(p.notes.some((n) => n.includes("FAINT [illegible]")));
});

Deno.test("the date is read off the paper, and an unreadable one is named", () => {
  const ok = assemble(extraction([line()], {
    purchased_at_printed: "09/13/26 05:42 PM",
  }));
  assertEquals(ok.purchased_at_printed, "09/13/26 05:42 PM");
  assertEquals(ok.purchased_at, "2026-09-13T17:42:00");
  assertEquals(ok.notes, []);

  const bad = assemble(extraction([line()], {
    purchased_at_printed: "LANE 3 CASHIER 7",
  }));
  assertEquals(bad.purchased_at, null);
  assert(bad.notes.some((n) => n.includes("LANE 3 CASHIER 7")));

  const none = assemble(extraction([line()], { purchased_at_printed: null }));
  assertEquals(none.purchased_at, null);
  assertEquals(none.notes, []); // nothing printed is not a failure to read
});

Deno.test("indexes are printed order across every kind", () => {
  const e = extraction([
    line({ printed_text: "A 1.00" }),
    line({ printed_text: "TAX 0.10", kind: "tax", amount_printed: "0.10" }),
    line({ printed_text: "B 2.00", amount_printed: "2.00" }),
  ]);
  const p = assemble(e);
  assertEquals(p.lines.map((l) => l.index), [0, 1, 2]);
  assertEquals(p.lines.map((l) => l.kind), ["item", "tax", "item"]);
});

Deno.test("photo — a line is attributed to the photo it was shot on", () => {
  const e = extraction([
    line({ printed_text: "A 1.00", amount_printed: "1.00" }),
    line({ printed_text: "B 2.00", amount_printed: "2.00" }),
    line({ printed_text: "C 3.00", amount_printed: "3.00" }),
    line({ printed_text: "D 4.00", amount_printed: "4.00" }),
  ]);
  const transcript = joinPhotoTranscripts([
    "A 1.00\nB 2.00\nC 3.00",
    "B 2.00\nC 3.00\nD 4.00",
  ]);
  const p = assembleReceipt(e, transcript, unmatched(e));
  // A seam line belongs to the FIRST photo it appeared on.
  assertEquals(p.lines.map((l) => l.photo), [0, 0, 0, 1]);
  assertEquals(p.photos_joined, [{ from: 0, to: 1, overlap_lines: 2 }]);
});

Deno.test("photo — the same item printed twice is attributed to its OWN occurrence", () => {
  const e = extraction([
    line({ printed_text: "TJ ORG BANANAS 3.49", amount_printed: "3.49" }),
    line({ printed_text: "MILK 2.99", amount_printed: "2.99" }),
    line({ printed_text: "TJ ORG BANANAS 3.49", amount_printed: "3.49" }),
  ]);
  const transcript = joinPhotoTranscripts([
    "TJ ORG BANANAS 3.49\nMILK 2.99",
    "MILK 2.99\nTJ ORG BANANAS 3.49",
  ]);
  const p = assembleReceipt(e, transcript, unmatched(e));
  // The cursor is forward-only, so the second bunch is the second bunch.
  assertEquals(p.lines.map((l) => l.photo), [0, 0, 1]);
  assertEquals(p.lines_sum_cents, 349 + 299 + 349);
});

Deno.test("the join's own notes lead — they explain everything under them", () => {
  const e = extraction([line({ printed_text: "A 1.00" })], {
    notes: ["the second column was creased"],
  });
  const transcript = joinPhotoTranscripts(["A 1.00", "ZZZ 9.99"]);
  const p = assembleReceipt(e, transcript, unmatched(e));
  assert(p.notes[0].includes("could not find where"));
  assertEquals(p.notes[1], "the second column was creased");
});

Deno.test("matching — only ITEM lines are asked about, in printed order", () => {
  const e = extraction([
    line({
      printed_text: "TJ ORG BANANAS 3.49",
      name_printed: "TJ ORG BANANAS",
    }),
    line({ printed_text: "TAX 0.82", name_printed: "TAX", kind: "tax" }),
    line({ printed_text: "TJ SRIRACHA 3.99", name_printed: "TJ SRIRACHA" }),
  ]);
  const inputs = itemMatchInputs(e);
  assertEquals(inputs.length, 2);
  // The NAME goes to the cascade, never the line with its price stuck on.
  assertEquals(inputs.map((i) => i.ingredient_text), [
    "TJ ORG BANANAS",
    "TJ SRIRACHA",
  ]);
  // Money never reaches the matcher, and neither does a quantity.
  assert(inputs.every((i) => i.qty === null && i.unit === null));
});

Deno.test("matching — a line the model gave no name falls back to its whole text", () => {
  const e = extraction([
    line({ printed_text: "2 @ 0.99 1.98", name_printed: "" }),
  ]);
  assertEquals(itemMatchInputs(e)[0].ingredient_text, "2 @ 0.99 1.98");
});

Deno.test("matching — auto above the threshold, suggest below, nothing at none", () => {
  const e = extraction([
    line({ printed_text: "A 1.00", name_printed: "A" }),
    line({ printed_text: "B 1.00", name_printed: "B" }),
    line({ printed_text: "C 1.00", name_printed: "C" }),
  ]);
  const inputs = itemMatchInputs(e);
  const matched: MatchedLine[] = [
    {
      raw: inputs[0],
      band: "auto",
      candidates: [{ ingredient_id: "i-1", canonical_name: "Onion", score: 1 }],
    },
    {
      raw: inputs[1],
      band: "suggest",
      candidates: [
        { ingredient_id: "i-2", canonical_name: "Cheddar", score: 0.7 },
        { ingredient_id: "i-3", canonical_name: "Cheddar, mild", score: 0.6 },
      ],
    },
    { raw: inputs[2], band: "none", candidates: [] },
  ];
  const p = assembleReceipt(e, flatTranscript(e), matched);
  assertEquals(p.lines[0].match, {
    ingredient_id: "i-1",
    confidence: 1,
    kind: "auto",
    remembered: false,
  });
  assertEquals(p.lines[1].match, {
    ingredient_id: "i-2",
    confidence: 0.7,
    kind: "suggest",
    remembered: false,
  });
  assertEquals(p.lines[2].match, null);
  assertEquals(p.lines[1].suggestions.length, 2);
  assertEquals(p.lines[1].suggestions[0].name, "Cheddar");
  assertEquals(p.lines[2].suggestions, []);
});

Deno.test("matching — a non-item line is never matched and never consumes one", () => {
  const e = extraction([
    line({ printed_text: "TAX 0.82", kind: "tax", amount_printed: "0.82" }),
    line({ printed_text: "A 1.00", name_printed: "A" }),
  ]);
  const inputs = itemMatchInputs(e);
  const p = assembleReceipt(e, flatTranscript(e), [
    {
      raw: inputs[0],
      band: "auto",
      candidates: [{ ingredient_id: "i-1", canonical_name: "Apple", score: 1 }],
    },
  ]);
  assertEquals(p.lines[0].match, null); // the tax line
  assertEquals(p.lines[1].match?.ingredient_id, "i-1");
});

Deno.test("at most three suggestions ride on a line", () => {
  const e = extraction([line({ name_printed: "A" })]);
  const inputs = itemMatchInputs(e);
  const p = assembleReceipt(e, flatTranscript(e), [{
    raw: inputs[0],
    band: "suggest",
    candidates: [1, 2, 3, 4, 5].map((n) => ({
      ingredient_id: `i-${n}`,
      canonical_name: `N${n}`,
      score: 0.9 - n / 100,
    })),
  }]);
  assertEquals(p.lines[0].suggestions.length, 3);
});

Deno.test("linesSumCents is the whole arithmetic, and nothing else is", () => {
  assertEquals(
    linesSumCents([
      { kind: "item", cents: 349, discount_cents: 0 },
      { kind: "item", cents: 604, discount_cents: 55 },
      { kind: "not_food", cents: 699, discount_cents: 0 },
      { kind: "tax", cents: 82, discount_cents: 0 },
      { kind: "fee", cents: -100, discount_cents: 0 },
      // deno-lint-ignore no-explicit-any
    ] as any),
    349 + 549 + 699 - 100,
  );
});

// --- The household's own answers have the last word --------------------------
//
// The memory is read off this household's saved receipt lines
// (`receipt_memory.ts`). Here it is just a Map, which is the point: assembly
// stays pure, and the rule — what a remembered answer does to a line — is
// arithmetic with a test.

import type { ReceiptMemory, RememberedAnswer } from "./receipt_memory.ts";

/** One `suggest`-banded match per item line, so the override has something to beat. */
function suggested(e: ReceiptExtraction, id: string): MatchedLine[] {
  return itemMatchInputs(e).map((raw: RawLineItem) => ({
    raw,
    band: "suggest" as const,
    candidates: [{
      ingredient_id: id,
      canonical_name: "Quinoa, red",
      score: 0.56,
    }],
  }));
}

const memory = (entries: [string, RememberedAnswer][]): ReceiptMemory =>
  new Map(entries);

Deno.test("remembered — the household's answer overrides the cascade", () => {
  // The strip this was found on: a whole-string trigram cannot score
  // `ORG TRICOLOR QUINOA` against `Quinoa` above the suggest floor. Once
  // somebody has said it, it does not have to.
  const e = extraction([
    line({
      printed_text: "ORG TRICOLOR QUINOA 4.49",
      name_printed: "ORG TRICOLOR QUINOA",
    }),
  ]);
  const p = assembleReceipt(
    e,
    flatTranscript(e),
    suggested(e, "v-quinoa-red"),
    memory([["ORG TRICOLOR QUINOA", {
      kind: "item",
      ingredient_id: "v-quinoa",
    }]]),
  );
  assertEquals(p.lines[0].match, {
    ingredient_id: "v-quinoa",
    confidence: 1,
    kind: "auto",
    remembered: true,
  });
  assertEquals(p.lines[0].kind, "item");
  // The cascade's offers stand: a remembered answer is one the person can
  // change, and these are what they would change it to.
  assertEquals(p.lines[0].suggestions.length, 1);
  assertEquals(p.lines[0].suggestions[0].ingredient_id, "v-quinoa-red");
});

Deno.test("remembered — the key is the printed name, upper-cased", () => {
  const e = extraction([line({ name_printed: "tj sriracha" })]);
  const p = assembleReceipt(
    e,
    flatTranscript(e),
    unmatched(e),
    memory([["TJ SRIRACHA", { kind: "item", ingredient_id: "v-sriracha" }]]),
  );
  assertEquals(p.lines[0].match?.ingredient_id, "v-sriracha");
});

Deno.test("remembered — a line the household folded arrives folded", () => {
  const e = extraction([
    line({
      printed_text: "PAPER TOWELS 6.99",
      name_printed: "PAPER TOWELS",
      amount_printed: "6.99",
    }),
  ]);
  const p = assembleReceipt(
    e,
    flatTranscript(e),
    unmatched(e),
    memory([["PAPER TOWELS", { kind: "not_food" }]]),
  );
  assertEquals(p.lines[0].kind, "not_food");
  assertEquals(p.lines[0].match, null, "a folded line names no row");
  // It still counts toward what the trip cost, and toward nothing else.
  assertEquals(p.lines_sum_cents, 699);
});

Deno.test("remembered — nothing remembered is the cascade, exactly as before", () => {
  const e = extraction([line({ name_printed: "TJ SRIRACHA" })]);
  const bare = assembleReceipt(
    e,
    flatTranscript(e),
    suggested(e, "v-sriracha"),
  );
  const empty = assembleReceipt(
    e,
    flatTranscript(e),
    suggested(e, "v-sriracha"),
    memory([]),
  );
  assertEquals(bare, empty);
  assertEquals(bare.lines[0].match, {
    ingredient_id: "v-sriracha",
    confidence: 0.56,
    kind: "suggest",
    remembered: false,
  });
});

Deno.test("remembered — a line the reader named nothing on recalls nothing", () => {
  // It would be asking about a string no saved line was ever filed under.
  const e = extraction([
    line({ printed_text: "?????? 2.49", name_printed: "  " }),
  ]);
  const p = assembleReceipt(
    e,
    flatTranscript(e),
    unmatched(e),
    memory([["", { kind: "item", ingredient_id: "v-nope" }]]),
  );
  assertEquals(p.lines[0].match, null);
});

Deno.test("remembered — a non-item line is never recalled for", () => {
  // A tax line has no ingredient to be about (migration 0044's own fence), and
  // the cursor over `matched` walks the MODEL's item lines, not the recalled
  // ones.
  const e = extraction([
    line({
      printed_text: "TAX 0.82",
      name_printed: "TAX",
      amount_printed: "0.82",
      kind: "tax",
    }),
    line({
      printed_text: "TJ SRIRACHA 3.99",
      name_printed: "TJ SRIRACHA",
      amount_printed: "3.99",
    }),
  ]);
  const p = assembleReceipt(
    e,
    flatTranscript(e),
    unmatched(e),
    memory([
      ["TAX", { kind: "item", ingredient_id: "v-nope" }],
      ["TJ SRIRACHA", { kind: "item", ingredient_id: "v-sriracha" }],
    ]),
  );
  assertEquals(p.lines[0].kind, "tax");
  assertEquals(p.lines[0].match, null);
  assertEquals(p.lines[1].match?.ingredient_id, "v-sriracha");
});
