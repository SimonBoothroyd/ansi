// The nutrition-label prompt and the JSON schema its one call is constrained
// by. Beside the recipe and receipt prompts because they drift the same way
// when they are not.
//
// One call, one image, one reading. The model is a READER: it reports the
// figures the label prints and nothing else. Everything the form does with
// those figures afterwards — the per-serving → per-100 arithmetic, the unit
// parsing — is ours, deterministic and tested, because a model asked to
// convert would be believed.

export const LABEL_SYSTEM_PROMPT =
  `You read ONE photograph of a nutrition label and report the figures PRINTED
on it.

THE ONE INVARIANT — NEVER INVENT AND NEVER COMPUTE. Every number you return is
a number printed on the label. Do not derive a per-serving figure from a
per-100 column, do not derive a per-100 column from a per-serving one, do not
convert a unit, do not add anything up. A figure that is not printed, or that
you cannot read, is null and says so in notes.

THE SERVING SIZE — as the label prints it:
- text_printed: the whole serving line, verbatim ("Serving size 2/3 cup (55g)",
  "Per 30 g serving"). Null when the label prints none.
- amount and unit_printed: the one amount a person would type, with its unit in
  the label's own words. Where the label prints a household measure AND a
  metric weight — "2/3 cup (55g)" — take the METRIC one: 55 and "g". A fraction
  becomes a decimal only when it is the amount you keep ("1/2 cup" -> 0.5,
  "cup").

PER SERVING — the column the label prints for one serving:
- kcal: the energy in kilocalories ("Calories", "kcal"). A label printing only
  kilojoules gives null and a note — do not divide by 4.184.
- protein_g, carbohydrate_g, fat_g, fibre_g: grams.
- carbohydrate_g is TOTAL carbohydrate, never "of which sugars".
- fat_g is TOTAL fat, never "of which saturates" or "Saturated Fat".
- fibre_g is "Dietary Fiber" / "Fibre". Null when the label does not print it.
- "<0.5g", "Less than 1g" and "trace" read as 0.
- Strip the unit and any symbol: "12g" is 12, "6.2 g" is 6.2.

PER 100 — ONLY where the label PRINTS a per-100 column. EU labels usually
print "per 100 g" or "per 100 ml" beside the per-serving column; US "Nutrition
Facts" panels usually print no such column at all. Where the label prints none,
per_100 is null. NEVER compute one. basis is "g" or "ml", whichever the
column's own heading says.

Where the label prints ONLY a per-100 column and no per-serving column, fill
per_100 and leave every per_serving figure null. Do not move the figures across.

NOTES — one short sentence each, in plain words, for what you could not read: a
figure that was cut off, a column that was too faint, a panel photographed at an
angle. Empty when the label read cleanly. Do not repeat here what you already
put in a field.

WORKED EXAMPLE — a label printing

    NUTRITION             per 100 g            per 30 g serving
    Energy                1580 kJ / 377 kcal   474 kJ / 113 kcal
    Fat                   6.2 g                1.9 g
      of which saturates  1.1 g                0.3 g
    Carbohydrate          62.1 g               18.6 g
      of which sugars     1.2 g                0.4 g
    Fibre                 10.6 g               3.2 g
    Protein               13.7 g               4.1 g
    Salt                  0.01 g               0.00 g

reads as

    serving:     { amount: 30, unit_printed: "g",
                   text_printed: "per 30 g serving" }
    per_serving: { kcal: 113, protein_g: 4.1, carbohydrate_g: 18.6,
                   fat_g: 1.9, fibre_g: 3.2 }
    per_100:     { basis: "g", kcal: 377, protein_g: 13.7,
                   carbohydrate_g: 62.1, fat_g: 6.2, fibre_g: 10.6 }
    notes:       []

Return ONLY the JSON object matching the provided schema. No prose, no markdown.`;

/** The user turn. The image is the content; this only says what to do with it. */
export const LABEL_USER_PROMPT =
  "Here is the photograph of the label. Read it.";

// -----------------------------------------------------------------------------
// The wire schema
// -----------------------------------------------------------------------------
//
// Native structured output, the same portable subset the other two schemas use:
// `additionalProperties: false` everywhere, every property required and
// nullable rather than optional. No numeric or string constraint keywords —
// structured outputs refuse them (`schema_keywords.test.ts`).

const macroProperties = {
  kcal: { type: ["number", "null"] },
  protein_g: { type: ["number", "null"] },
  carbohydrate_g: { type: ["number", "null"] },
  fat_g: { type: ["number", "null"] },
  fibre_g: { type: ["number", "null"] },
} as const;

const MACRO_KEYS = [
  "kcal",
  "protein_g",
  "carbohydrate_g",
  "fat_g",
  "fibre_g",
];

const perServingSchema = {
  type: "object",
  additionalProperties: false,
  required: MACRO_KEYS,
  properties: macroProperties,
} as const;

const per100Schema = {
  type: ["object", "null"],
  additionalProperties: false,
  required: ["basis", ...MACRO_KEYS],
  properties: {
    basis: { type: "string", enum: ["g", "ml"] },
    ...macroProperties,
  },
} as const;

const servingSchema = {
  type: "object",
  additionalProperties: false,
  required: ["amount", "unit_printed", "text_printed"],
  properties: {
    amount: { type: ["number", "null"] },
    unit_printed: { type: ["string", "null"] },
    text_printed: { type: ["string", "null"] },
  },
} as const;

export const LABEL_JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["serving", "per_serving", "per_100", "notes"],
  properties: {
    serving: servingSchema,
    per_serving: perServingSchema,
    per_100: per100Schema,
    notes: { type: "array", items: { type: "string" } },
  },
} as const;
