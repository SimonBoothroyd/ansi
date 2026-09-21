// Reading the paper's printed strings: money, a date, a weight unit. The cases
// are forms real tills print.

import { assertEquals } from "@std/assert";
import {
  canonicalWeightUnit,
  parseCents,
  parseDiscountCents,
  parseReceiptDate,
} from "./receipt_parse.ts";

Deno.test("money — the ordinary forms", () => {
  assertEquals(parseCents("3.49"), 349);
  assertEquals(parseCents("$3.49"), 349);
  assertEquals(parseCents(" $ 3.49 "), 349);
  assertEquals(parseCents("0.10"), 10);
  assertEquals(parseCents("0.00"), 0);
  assertEquals(parseCents("84.12"), 8412);
  assertEquals(parseCents("1,234.56"), 123456);
  assertEquals(parseCents("USD 12.00"), 1200);
});

Deno.test("money — a comma decimal, and a comma that is a thousands mark", () => {
  assertEquals(parseCents("3,49"), 349);
  assertEquals(parseCents("1,234"), 123400);
});

Deno.test("money — every way a till prints a minus", () => {
  assertEquals(parseCents("-0.55"), -55);
  assertEquals(parseCents("−0.55"), -55); // the real minus sign
  assertEquals(parseCents("–0.55"), -55); // an en dash
  assertEquals(parseCents("0.55-"), -55); // trailing, the credit form
  assertEquals(parseCents("(0.55)"), -55);
  assertEquals(parseCents("-$1.00"), -100);
});

Deno.test("money — a bare integer is whole dollars", () => {
  assertEquals(parseCents("3"), 300);
  assertEquals(parseCents("0"), 0);
});

Deno.test("money — never through a float", () => {
  // parseFloat("3.49") * 100 is 348.99999999999994.
  assertEquals(parseCents("3.49"), 349);
  assertEquals(parseCents("1.10"), 110);
  assertEquals(parseCents("8.29"), 829);
  // More than two decimals is truncated, never rounded: the figure is a copy.
  assertEquals(parseCents("1.999"), 199);
});

Deno.test("money — unreadable is null, and null is not zero", () => {
  for (
    const bad of [
      null,
      undefined,
      "",
      "   ",
      "[illegible]",
      "abc",
      "3.4a",
      "3.",
      "$",
      "-",
    ]
  ) {
    assertEquals(parseCents(bad), null, `${bad}`);
  }
});

Deno.test("money — a discount is stated as the amount taken away", () => {
  // 0044's column is `check (discount_cents >= 0)`; the paper prints the sign.
  assertEquals(parseDiscountCents("-0.55"), 55);
  assertEquals(parseDiscountCents("0.55"), 55);
  assertEquals(parseDiscountCents("(1.00)"), 100);
  assertEquals(parseDiscountCents("nope"), null);
});

Deno.test("date — the forms a till prints", () => {
  assertEquals(parseReceiptDate("09/13/26 05:42 PM"), "2026-09-13T17:42:00");
  assertEquals(parseReceiptDate("9/13/2026"), "2026-09-13T00:00:00");
  assertEquals(parseReceiptDate("09-12-2026 16:13"), "2026-09-12T16:13:00");
  assertEquals(parseReceiptDate("9-12-26"), "2026-09-12T00:00:00");
  assertEquals(parseReceiptDate("2026-09-13 11:04"), "2026-09-13T11:04:00");
  assertEquals(parseReceiptDate("2026-09-13T11:04:09"), "2026-09-13T11:04:09");
  assertEquals(parseReceiptDate("SEP 13 2026 5:42PM"), "2026-09-13T17:42:00");
  assertEquals(parseReceiptDate("13 Sept 2026"), "2026-09-13T00:00:00");
  assertEquals(
    parseReceiptDate("TRADER JOE'S 09/13/26 05:42 PM LANE 3"),
    "2026-09-13T17:42:00",
  );
});

Deno.test("date — midnight and noon do not swap", () => {
  assertEquals(parseReceiptDate("09/13/26 12:01 AM"), "2026-09-13T00:01:00");
  assertEquals(parseReceiptDate("09/13/26 12:01 PM"), "2026-09-13T12:01:00");
  assertEquals(parseReceiptDate("09/13/26 23:15"), "2026-09-13T23:15:00");
});

Deno.test("date — a two-digit year is this century", () => {
  // A two-digit year is this century.
  assertEquals(parseReceiptDate("01/02/99"), "2099-01-02T00:00:00");
});

Deno.test("date — unreadable is null, and an impossible day is unreadable", () => {
  for (
    const bad of [
      null,
      "",
      "LANE 3 CASHIER 7",
      "13/13/26",
      "02/31/26",
      "[illegible]",
    ]
  ) {
    assertEquals(parseReceiptDate(bad), null, `${bad}`);
  }
});

Deno.test("date — no time zone is carried, ever", () => {
  const iso = parseReceiptDate("09/13/26 05:42 PM")!;
  assertEquals(iso.endsWith("Z"), false);
  assertEquals(/[+-]\d{2}:\d{2}$/.test(iso), false);
});

Deno.test("weight — the printed word becomes a units.dart id", () => {
  for (const printed of ["lb", "LB", "lbs", "Lb.", "#", "pounds"]) {
    assertEquals(canonicalWeightUnit(printed), "lb", printed);
  }
  assertEquals(canonicalWeightUnit("KG"), "kg");
  assertEquals(canonicalWeightUnit("kilograms"), "kg");
  assertEquals(canonicalWeightUnit("oz"), "oz");
  assertEquals(canonicalWeightUnit("OUNCE"), "oz");
  assertEquals(canonicalWeightUnit("g"), "g");
  assertEquals(canonicalWeightUnit("grams"), "g");
});

Deno.test("weight — anything that is not a weight we know is null", () => {
  // "ea" is a count, not a weight: a by-the-each line has no weight at all.
  for (const bad of [null, "", "ea", "each", "ct", "ml", "cup", "bunch"]) {
    assertEquals(canonicalWeightUnit(bad), null, `${bad}`);
  }
});
