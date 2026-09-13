import { assertEquals } from "@std/assert";
import { locateSourceSpan } from "./source_span.ts";
import type { RawLineItem } from "./types.ts";

function line(over: Partial<RawLineItem> = {}): RawLineItem {
  return {
    qty: 900,
    qty_low: null,
    qty_high: null,
    unit: "g",
    unit_mappable: true,
    ingredient_text: "chicken thighs, boneless",
    notes: null,
    raw_amount: "900 g",
    optional: false,
    confidence: 0.9,
    ...over,
  };
}

const page = "Weeknight curry. Ingredients: 900 g chicken thighs, boneless; " +
  "2-3 cloves garlic; a good pinch chilli flakes.";

Deno.test("locateSourceSpan — the amount through the identity, as printed", () => {
  const span = locateSourceSpan(page, line())!;
  assertEquals(
    page.slice(span.start, span.end),
    "900 g chicken thighs, boneless",
  );
});

Deno.test("locateSourceSpan — the identity alone when the amount is not on the page", () => {
  const span = locateSourceSpan(
    page,
    line({ raw_amount: "", ingredient_text: "garlic" }),
  )!;
  assertEquals(page.slice(span.start, span.end), "garlic");
});

Deno.test("locateSourceSpan — the amount alone when the identity was rewritten", () => {
  // Extraction turned "2-3 cloves garlic" into an identity the page never
  // printed. The amount is still verbatim, so that is what can be pointed at.
  const span = locateSourceSpan(
    page,
    line({ raw_amount: "2-3 cloves", ingredient_text: "garlic clove, peeled" }),
  )!;
  assertEquals(page.slice(span.start, span.end), "2-3 cloves");
});

Deno.test("locateSourceSpan — case is not identity", () => {
  const span = locateSourceSpan(
    "Ingredients: 400 G Coconut Milk",
    line({ raw_amount: "400 g", ingredient_text: "coconut milk" }),
  )!;
  assertEquals(span.start, 13);
  assertEquals(span.end, 31);
});

Deno.test("locateSourceSpan — an ambiguous phrase is no span", () => {
  // Two occurrences: nothing here can say which one the line was read from,
  // and a lit range on the wrong one is a lie about the page.
  assertEquals(
    locateSourceSpan(
      "200 g flour, then 200 g flour again",
      line({ raw_amount: "200 g", ingredient_text: "flour" }),
    ),
    null,
  );
});

Deno.test("locateSourceSpan — words the page never printed are no span", () => {
  assertEquals(
    locateSourceSpan(
      page,
      line({ raw_amount: "1 tbsp", ingredient_text: "rose harissa" }),
    ),
    null,
  );
});

Deno.test("locateSourceSpan — a needle too short to be unique is refused", () => {
  // "1" and "g" occur everywhere; a two-character match is never evidence.
  assertEquals(
    locateSourceSpan(
      "1 g salt",
      line({ raw_amount: "1", ingredient_text: "g" }),
    ),
    null,
  );
});

Deno.test("locateSourceSpan — a far-away identity does not weld into one span", () => {
  const text = "300 g butter" + " filler".repeat(30) + " dark chocolate";
  const span = locateSourceSpan(
    text,
    line({ raw_amount: "300 g", ingredient_text: "dark chocolate" }),
  )!;
  assertEquals(text.slice(span.start, span.end), "dark chocolate");
});
