import { assertEquals } from "@std/assert";
import { deriveUnitHints } from "./unit_hints.ts";

Deno.test("deriveUnitHints — mappable canonical units, no imprecise leak", () => {
  const { units } = deriveUnitHints();
  // The mass/volume/count catalog ids ① should land qty/unit in.
  for (
    const id of [
      "g",
      "kg",
      "mg",
      "oz",
      "lb",
      "ml",
      "l",
      "tsp",
      "tbsp",
      "fl_oz",
      "cup",
      "piece",
    ]
  ) {
    assertEquals(units.includes(id), true, `units should include ${id}`);
  }
  // Imprecise units live in `imprecise`, never in `units`.
  for (const id of ["pinch", "dash", "to_taste"]) {
    assertEquals(units.includes(id), false, `units should NOT include ${id}`);
  }
});

Deno.test("deriveUnitHints — imprecise carries unit-system + accepted vague words", () => {
  const { imprecise } = deriveUnitHints();
  for (const w of ["pinch", "dash", "to_taste", "handful"]) {
    assertEquals(imprecise.includes(w), true, `imprecise should include ${w}`);
  }
});

Deno.test("deriveUnitHints — size words mirror normalize.ts SIZES", () => {
  const { size_words } = deriveUnitHints();
  for (const w of ["large", "medium", "small"]) {
    assertEquals(
      size_words.includes(w),
      true,
      `size_words should include ${w}`,
    );
  }
});

Deno.test("deriveUnitHints — count-measure nouns are a DISTINCT list", () => {
  // Generic count-measure nouns ("2 garlic cloves", "1 head", "One 400 g can")
  // are emittable units so ① stops force-fitting them to "piece" — but they are
  // NOT canonical convertible units, imprecise words, or size words, so they
  // stay out of those three lists (ADR-0004: not the per-ingredient gram basis).
  const { units, imprecise, size_words, measures } = deriveUnitHints();
  const others = [...units, ...imprecise, ...size_words];
  for (
    const noun of [
      "clove",
      "head",
      "sprig",
      "loaf",
      "block",
      "slice",
      "can",
      "bunch",
      "stalk",
    ]
  ) {
    assertEquals(
      measures.includes(noun),
      true,
      `measures should include ${noun}`,
    );
    assertEquals(
      others.includes(noun),
      false,
      `${noun} belongs only in measures`,
    );
  }
  // "tin" is normalised to "can" in the prompt — it is not itself a hint noun.
  assertEquals(measures.includes("tin"), false, "tin normalises to can");
});

Deno.test("deriveUnitHints — deterministic", () => {
  assertEquals(deriveUnitHints(), deriveUnitHints());
});
