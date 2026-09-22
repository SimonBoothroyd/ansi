// Provider JSON → `LabelReading`: the round trip, what a null survives as, and
// what an unusable figure becomes. Plus the two things about the adapter that
// can be checked without a key.

import { assert, assertEquals, assertThrows } from "@std/assert";
import type { LabelReading } from "../label_types.ts";
import {
  ClaudeLabelAdapter,
  decodeClaudeLabel,
  LABEL_DEADLINE_MS,
} from "./claude_label.ts";
import {
  coerceLabelReading,
  MAX_LABEL_FIGURE,
  MAX_LABEL_NOTES,
  validateLabelReading,
} from "./label_schema.ts";
import { ExtractionParseError } from "./schema.ts";
import { CLAUDE_HAIKU_MODEL } from "./claude.ts";
import { ImportError } from "../errors.ts";

/** A verbatim Anthropic response carrying `text` as its one text block. */
const response = (text: string) => ({
  content: [{ type: "text", text }],
  stop_reason: "end_turn",
});

const EU_LABEL: LabelReading = {
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

Deno.test("decode — an EU label comes back whole, both columns", () => {
  const reading = decodeClaudeLabel(response(JSON.stringify(EU_LABEL)));
  assertEquals(reading, EU_LABEL);
});

Deno.test("decode — a fenced answer is still JSON", () => {
  const reading = decodeClaudeLabel(
    response("```json\n" + JSON.stringify(EU_LABEL) + "\n```"),
  );
  assertEquals(reading.per_serving.kcal, 113);
});

Deno.test("decode — a US panel prints no per-100 column, and none is invented", () => {
  const reading = decodeClaudeLabel(response(JSON.stringify({
    serving: {
      amount: 55,
      unit_printed: "g",
      text_printed: "Serving size 2/3 cup (55g)",
    },
    per_serving: {
      kcal: 230,
      protein_g: 3,
      carbohydrate_g: 37,
      fat_g: 8,
      fibre_g: 4,
    },
    per_100: null,
    notes: [],
  })));
  assertEquals(reading.per_100, null);
  assertEquals(reading.per_serving.kcal, 230);
});

Deno.test("decode — a figure the label did not print stays null", () => {
  const reading = decodeClaudeLabel(response(JSON.stringify({
    serving: { amount: null, unit_printed: null, text_printed: null },
    per_serving: {
      kcal: 90,
      protein_g: null,
      carbohydrate_g: 21,
      fat_g: null,
      fibre_g: null,
    },
    per_100: null,
    notes: ["the fat row was cut off at the edge of the photo"],
  })));
  assertEquals(reading.per_serving.protein_g, null);
  assertEquals(reading.per_serving.fibre_g, null);
  assertEquals(reading.serving.amount, null);
  assertEquals(reading.notes.length, 1);
});

Deno.test("coerce — a missing key reads as null, not as an exception", () => {
  const reading = coerceLabelReading({ per_serving: { kcal: 120 } });
  assertEquals(reading.serving, {
    amount: null,
    unit_printed: null,
    text_printed: null,
  });
  assertEquals(reading.per_serving.fat_g, null);
  assertEquals(reading.per_100, null);
  assertEquals(reading.notes, []);
});

Deno.test("coerce — a figure that cannot be a printed figure reads null", () => {
  const reading = coerceLabelReading({
    per_serving: {
      kcal: -12, // a label never prints a negative
      protein_g: "4.1", // a number sent as a string is still a number
      carbohydrate_g: "not a number",
      fat_g: MAX_LABEL_FIGURE + 1, // a misread decimal point
      fibre_g: 0, // and zero is a figure, not an absence
    },
  });
  assertEquals(reading.per_serving.kcal, null);
  assertEquals(reading.per_serving.protein_g, 4.1);
  assertEquals(reading.per_serving.carbohydrate_g, null);
  assertEquals(reading.per_serving.fat_g, null);
  assertEquals(reading.per_serving.fibre_g, 0);
});

Deno.test("coerce — a per-100 column whose basis is not g or ml is dropped whole", () => {
  // We would not know which 100 it was, and the form would convert by it.
  const reading = coerceLabelReading({
    per_serving: { kcal: 100 },
    per_100: { basis: "oz", kcal: 350 },
  });
  assertEquals(reading.per_100, null);
});

Deno.test("coerce — the basis is taken in any case the model prints it", () => {
  const reading = coerceLabelReading({
    per_serving: { kcal: 100 },
    per_100: { basis: " ML ", kcal: 42 },
  });
  assertEquals(reading.per_100?.basis, "ml");
  assertEquals(reading.per_100?.kcal, 42);
});

Deno.test("coerce — notes are capped, and an empty one is not a note", () => {
  const reading = coerceLabelReading({
    per_serving: { kcal: 100 },
    notes: ["  ", "the panel is at an angle", ...Array(50).fill("x")],
  });
  assertEquals(reading.notes.length, MAX_LABEL_NOTES);
  assertEquals(reading.notes[0], "the panel is at an angle");
});

Deno.test("validate — a reading with nothing in it is refused, not filled in", () => {
  assertThrows(
    () => validateLabelReading(coerceLabelReading({})),
    ExtractionParseError,
  );
  // One note is enough to be a reading: it says why the fields are empty.
  const withNote = validateLabelReading(
    coerceLabelReading({ notes: ["we could not find a nutrition panel"] }),
  );
  assertEquals(withNote.notes.length, 1);
});

Deno.test("decode — a cut-off answer is a sentence a person can act on", () => {
  const err = assertThrows(
    () =>
      decodeClaudeLabel({
        content: [{ type: "text", text: "{" }],
        stop_reason: "max_tokens",
      }),
    ImportError,
  );
  assert((err as ImportError).message.includes("closer photo"));
});

// --- The adapter, without a key ----------------------------------------------

Deno.test("adapter — constructing it needs no key, and it holds the shared pin", () => {
  const adapter = new ClaudeLabelAdapter({ apiKey: "test-key-not-used" });
  assertEquals(adapter.model, CLAUDE_HAIKU_MODEL);
  assertEquals(adapter.name, "claude-haiku-label");
  // One image and one call, so the budget has to fit the platform's idle
  // timeout on its own — this door sends no heartbeat.
  assert(LABEL_DEADLINE_MS < 150_000);
});
