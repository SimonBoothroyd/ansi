// The wire schema and its coercion, round-tripped: what the model is asked for
// is what the coercion accepts, and a malformed answer still lands as a known
// shape.

import { assert, assertEquals, assertThrows } from "@std/assert";
import {
  coerceReceiptExtraction,
  MAX_RECEIPT_LINES,
  RECEIPT_CAPS,
  validateReceiptExtraction,
} from "./receipt_schema.ts";
import { ExtractionParseError } from "./schema.ts";
import { RECEIPT_JSON_SCHEMA } from "../prompts/receipt.ts";
import type { ReceiptExtraction } from "../receipt_types.ts";

// deno-lint-ignore no-explicit-any
const schema = RECEIPT_JSON_SCHEMA as any;

// A model answer in exactly the schema's shape: every required key, nothing
// else.
const WIRE = {
  store_printed: "TRADER JOE'S #135",
  purchased_at_printed: "09/13/26 05:42 PM",
  subtotal_printed: "29.97",
  tax_printed: "0.82",
  total_printed: "30.79",
  lines: [
    {
      printed_text: "TJ ORG BANANAS 3.49",
      name_printed: "TJ ORG BANANAS",
      amount_printed: "3.49",
      count: 1,
      each_printed: null,
      discount_printed: null,
      kind: "item",
      weight: null,
      low_confidence: false,
    },
    {
      printed_text: "YELLOW ONIONS 1.32 lb @ 1.99/lb 2.63",
      name_printed: "YELLOW ONIONS",
      amount_printed: "2.63",
      count: 1,
      each_printed: null,
      discount_printed: null,
      kind: "item",
      weight: { amount: 1.32, unit_printed: "lb", rate_printed: "1.99" },
      low_confidence: false,
    },
    {
      printed_text: "BAG FEE 0.10",
      name_printed: "BAG FEE",
      amount_printed: "0.10",
      count: 2,
      each_printed: "0.05",
      discount_printed: null,
      kind: "not_food",
      weight: null,
      low_confidence: true,
    },
  ],
  notes: ["the bottom two lines were creased"],
};

Deno.test("schema — every key the schema requires is a key the coercion reads", () => {
  const coerced = coerceReceiptExtraction(WIRE);
  const top = coerced as unknown as Record<string, unknown>;
  for (const key of schema.required as string[]) {
    assert(key in top, `coercion dropped "${key}"`);
  }
  const firstLine = coerced.lines[0] as unknown as Record<string, unknown>;
  for (const key of schema.properties.lines.items.required as string[]) {
    assert(key in firstLine, `coercion dropped line "${key}"`);
  }
});

Deno.test("schema — round trip: nothing is lost and nothing is added", () => {
  const coerced = coerceReceiptExtraction(WIRE);
  assertEquals(coerced, WIRE as unknown as ReceiptExtraction);
});

Deno.test("schema — nothing un-modelled can be smuggled past us", () => {
  assertEquals(schema.additionalProperties, false);
  assertEquals(schema.properties.lines.items.additionalProperties, false);
  assertEquals(
    schema.properties.lines.items.properties.weight
      .additionalProperties,
    false,
  );
  // Every property is required and nullable rather than optional: the dialects
  // disagree about optionality and agree about null.
  assertEquals(
    (schema.required as string[]).sort(),
    Object.keys(schema.properties).sort(),
  );
  const line = schema.properties.lines.items;
  assertEquals(
    (line.required as string[]).sort(),
    Object.keys(line.properties).sort(),
  );
});

Deno.test("schema — the four kinds, and only the four", () => {
  assertEquals(schema.properties.lines.items.properties.kind.enum, [
    "item",
    "not_food",
    "tax",
    "fee",
  ]);
});

Deno.test("coercion — a kind nobody modelled reads as item, the reversible answer", () => {
  const r = coerceReceiptExtraction({
    lines: [{
      printed_text: "A 1.00",
      amount_printed: "1.00",
      kind: "produce",
    }],
  });
  assertEquals(r.lines[0].kind, "item");
});

Deno.test("coercion — a number where a string was asked for is read, not dropped", () => {
  const r = coerceReceiptExtraction({
    subtotal_printed: 29.97,
    lines: [{ printed_text: "A", amount_printed: 3.49 }],
  });
  assertEquals(r.subtotal_printed, "29.97");
  assertEquals(r.lines[0].amount_printed, "3.49");
});

Deno.test("coercion — a half-built weight is no weight; the line survives", () => {
  const bad = [
    { amount: 1.32, unit_printed: "lb", rate_printed: null },
    { amount: null, unit_printed: "lb", rate_printed: "1.99" },
    { amount: 0, unit_printed: "lb", rate_printed: "1.99" },
    "1.32 lb",
  ];
  for (const weight of bad) {
    const r = coerceReceiptExtraction({
      lines: [{ printed_text: "A 1.00", amount_printed: "1.00", weight }],
    });
    assertEquals(r.lines[0].weight, null, JSON.stringify(weight));
    assertEquals(r.lines.length, 1);
  }
});

Deno.test("coercion — a line with neither words nor a figure is not a line", () => {
  const r = coerceReceiptExtraction({
    lines: [
      { printed_text: "", amount_printed: "" },
      { printed_text: "A 1.00", amount_printed: "1.00" },
      null,
      "nope",
    ],
  });
  assertEquals(r.lines.length, 1);
  assertEquals(r.lines[0].printed_text, "A 1.00");
});

Deno.test("coercion — strings are capped, and a note storm is bounded", () => {
  const r = coerceReceiptExtraction({
    store_printed: "x".repeat(1000),
    notes: Array.from({ length: 500 }, (_, i) => `note ${i}`),
    lines: Array.from({ length: MAX_RECEIPT_LINES + 50 }, () => ({
      printed_text: "A 1.00",
      amount_printed: "1.00",
    })),
  });
  assertEquals(r.store_printed?.length, RECEIPT_CAPS.store);
  assertEquals(r.notes.length, 100);
  assertEquals(r.lines.length, MAX_RECEIPT_LINES);
});

Deno.test("coercion — missing everything is an empty receipt, not a crash", () => {
  const r = coerceReceiptExtraction({});
  assertEquals(r.store_printed, null);
  assertEquals(r.purchased_at_printed, null);
  assertEquals(r.lines, []);
  assertEquals(r.notes, []);
});

Deno.test("coercion — a top level that is not an object throws", () => {
  for (const bad of [null, "nope", [1, 2]]) {
    assertThrows(
      () => coerceReceiptExtraction(bad),
      ExtractionParseError,
      "expected an object",
    );
  }
});

Deno.test("validation — a receipt with no lines is a failure, not an empty review", () => {
  assertThrows(
    () => validateReceiptExtraction(coerceReceiptExtraction({})),
    ExtractionParseError,
    "no lines",
  );
  // Everything else a receipt can be missing is a real state of real paper.
  const thin = validateReceiptExtraction(coerceReceiptExtraction({
    lines: [{ printed_text: "A 1.00", amount_printed: "1.00" }],
  }));
  assertEquals(thin.store_printed, null);
  assertEquals(thin.subtotal_printed, null);
});

Deno.test("count — read as printed where it is a whole number of things", () => {
  const r = coerceReceiptExtraction({
    lines: [{
      printed_text: "TOFU 23.92",
      amount_printed: "23.92",
      count: 8,
      each_printed: "$2.99",
    }],
  });
  assertEquals(r.lines[0].count, 8);
  assertEquals(r.lines[0].each_printed, "$2.99");
  assertEquals(r.lines[0].low_confidence, false);
});

Deno.test("count — a count nobody can divide by reads as one, and flags the line", () => {
  // A fraction, a zero, a negative, an absurd figure and a word. The count is
  // a divisor, so an unusable one must be flagged.
  for (const bad of [2.5, 0, -3, 1000, "four", null]) {
    const r = coerceReceiptExtraction({
      lines: [{ printed_text: "A 1.00", amount_printed: "1.00", count: bad }],
    });
    assertEquals(r.lines[0].count, 1, `${bad}`);
    // An absent count is not a coercion: most lines print none.
    assertEquals(r.lines[0].low_confidence, bad !== null, `${bad}`);
  }
});

Deno.test("count — a missing one is one, quietly", () => {
  const r = coerceReceiptExtraction({
    lines: [{ printed_text: "A 1.00", amount_printed: "1.00" }],
  });
  assertEquals(r.lines[0].count, 1);
  assertEquals(r.lines[0].each_printed, null);
  assertEquals(r.lines[0].low_confidence, false);
});
