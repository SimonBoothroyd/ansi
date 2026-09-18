// The two receipt prompts, and the JSON schema the structuring call is
// constrained by — beside the recipe pair in `extraction.ts`, because they are
// the same kind of artefact and drift the same way when they are not.
//
//   1. RECEIPT_TRANSCRIBE_PROMPT — vision tier. Photos → one faithful plain-text
//      transcription PER PHOTO, overlaps and all. It is a transcriber, not a
//      joiner: the seam is found positionally in `receipt_join.ts`, by code with
//      tests, and the model is never asked whether a repeated line is an overlap
//      or a second banana.
//   2. RECEIPT_SYSTEM_PROMPT — the joined strip → `ReceiptExtraction`. It prints
//      what the paper printed: the store's header, the date, the totals and
//      every line, with money still in the words the till used.
//
// **The model never matches, and never sees the vocabulary** (ADR-0004). It is
// not told one ingredient name of the household's. Every line it returns is put
// through the deterministic cascade afterwards, and a receipt's abbreviations
// are exactly the input that cascade was built to be uncertain about out loud.
//
// The one thing it is asked to divide is a line into "the words that name the
// thing" and "the numbers" (`name_printed`). That is not a match and not a
// guess at our catalogue: it is the same characters with the money taken off,
// and it is what keeps `TJ ORG BANANAS 3.49` from being trigram-compared
// against a vocabulary with `3.49` still stuck to the end of it.

// -----------------------------------------------------------------------------
// 1. Transcription (vision tier)
// -----------------------------------------------------------------------------

/** The separator the transcription puts between two photos. */
export const PHOTO_BREAK = "[PHOTO BREAK]";

export const RECEIPT_TRANSCRIBE_PROMPT =
  `You transcribe photographs of a shop receipt into plain text, faithfully.

The photos are consecutive segments of ONE till receipt, top to bottom, in
order. Consecutive photos OVERLAP by a few lines — that is deliberate, and it
is how the parts are joined afterwards.

RULES — you are a transcriber, not an editor:
- Transcribe EACH PHOTO IN FULL, on its own, including any lines it shares with
  the photo before it. NEVER drop a repeated line and NEVER join the photos
  yourself: the overlap is the joining instrument and removing it destroys it.
- Put the line ${PHOTO_BREAK} on its own between one photo's transcription and
  the next. Nothing else goes on that line.
- ONE PRINTED LINE PER OUTPUT LINE, in printed order. Keep the words, the
  numbers, the abbreviations and the punctuation exactly as printed —
  "TJ ORG BANANAS 3.49", not "Trader Joe's organic bananas, $3.49". Do not
  expand an abbreviation, do not correct a spelling, do not re-order a column.
- Keep every line the receipt prints: the store's header and address, the date
  and time, item lines, weight and rate lines, discounts, subtotal, tax, total,
  and any fee or deposit. The only thing to leave out is the trailing
  advertising and the survey invitation after the total.
- NEVER invent, complete or infer. A word you cannot read is "[illegible]" — a
  price you cannot read is "[illegible]" too. Do not guess a digit.
- Do NOT total anything, do not convert anything, do not annotate anything.
- Card numbers, loyalty numbers and any other long identifier: transcribe the
  line as "[account line]" and nothing else. We do not keep them.

Output ONLY the transcription text, with ${PHOTO_BREAK} between photos. No
commentary, no markdown fences.`;

// -----------------------------------------------------------------------------
// 2. Structure (the joined strip → ReceiptExtraction)
// -----------------------------------------------------------------------------

const CLOSING =
  "Return ONLY the JSON object matching the provided schema. No prose, no markdown.";

export const RECEIPT_SYSTEM_PROMPT =
  `You convert the text of one shop receipt into a strict JSON structure. You
print what the paper printed.

THE ONE INVARIANT — NEVER INVENT. Do not fabricate a line, a figure, a store, a
date, a weight or a rate that is not in the text. Do not total anything: the
sums are computed downstream from the lines you return, and a figure you
calculated would be checked against the paper's own and disagree for a reason
nobody could find. If something cannot be read, leave the field null and say so
in notes — never guess a value in.

YOU DO NOT KNOW OUR INGREDIENTS. You are never shown a catalogue and must never
try to name one: "TJ ORG BANANAS" stays "TJ ORG BANANAS". Matching happens
afterwards, elsewhere, and your guess would be believed.

THE HEADER:
- store_printed: the shop's name as printed at the top, with whatever store
  number rides with it ("TRADER JOE'S #135"). Null when the paper does not name
  one. Not the address, not the phone number.
- purchased_at_printed: the date AND time as printed, together, in the paper's
  own format ("09/13/26 05:42 PM"). The date only, when no time is printed.
  Null when neither is legible.
- subtotal_printed / tax_printed / total_printed: the figures the paper prints
  beside those words, as printed ("83.30"). Null for one the receipt does not
  print — many do not print a subtotal. These are the PAPER's totals; do not
  compute a missing one.

THE LINES — one object per printed line, in printed order, none dropped:
- printed_text: the line VERBATIM, exactly as it appears, money included.
- name_printed: the same line with the money, the weight and the rate taken
  off — just the words that name the thing ("TJ ORG BANANAS"). Same characters,
  same abbreviations, nothing expanded. Empty string when the line is nothing
  but figures.
- amount_printed: this line's own money figure, as printed ("3.49", "$3.49",
  "-0.55"). Keep the sign the paper printed. Never a figure you worked out.
- kind — what the line IS, decided from its words:
    * "item" — food and drink. The default for anything a kitchen would use.
    * "not_food" — a thing the shop sold that is not food, and a charge that
      belongs to the trip rather than to an item: paper towels, dish soap,
      foil, a paper or reusable BAG FEE, a bottle DEPOSIT, a carrier bag.
    * "tax" — a line printed as tax.
    * "fee" — a charge or credit the receipt prints on its own that is none of
      the above, INCLUDING a discount you could not attach to an item (see
      below). A fee may be negative.
  Everything printed between the header and the totals gets a line and a kind.
  Tax and fee lines are never dropped: the receipt has to go on adding up.
- discount_printed: a deduction printed DIRECTLY UNDER this item and belonging
  to it ("PRIME SAVINGS -0.55", "MEMBER SAVINGS", "-1.00 OFF"), as printed. The
  deduction becomes this field ON THE ITEM ABOVE IT and does NOT also get its
  own line — one printed number, one place. Null on every line with no
  deduction under it. If a deduction is printed where you cannot tell which item
  it belongs to, give it its OWN line with kind "fee" and its printed (negative)
  figure in amount_printed, and add a note.
- weight — for a line sold BY WEIGHT, where the paper prints the weight and the
  per-unit rate ("YELLOW ONIONS 1.32 lb @ 1.99/lb 2.63"):
    { "amount": 1.32, "unit_printed": "lb", "rate_printed": "1.99" }
  amount is the weight as a number, unit_printed is the unit AS PRINTED, and
  rate_printed is the per-unit price as printed. amount_printed stays the line's
  own total ("2.63"). null on every line that is not sold by weight —
  "2 @ 0.99 1.98" is a COUNT, not a weight, so its weight is null.
- low_confidence: true when YOU doubt this line — it is cut off, faint,
  half-transcribed, or its figures do not look like figures. This is your own
  doubt about the reading, not a judgement about the item.

WHAT IS NOT A LINE:
- the store's address, phone number, the cashier, the lane, "[account line]",
  the survey invitation and the advertising after the total;
- a line that is only a weight and a rate belonging to the item above it — fold
  it into that item's weight rather than giving it its own object.

NOTES — what you could not read, in plain words a person can act on: a line
whose price was illegible, a deduction you could not attach, a stretch where
the paper was creased. One short sentence each. Empty when the receipt read
cleanly. Do not put anything here that you already put in a field.

${CLOSING}`;

/** The user turn: the joined strip, and nothing else to distract from it. */
export function receiptUserPrompt(transcript: string): string {
  return `Here is the receipt, as transcribed:\n\n${transcript}`;
}

// -----------------------------------------------------------------------------
// 3. The wire schema
// -----------------------------------------------------------------------------
//
// Native structured output (Anthropic `output_config.format`). Kept to the same
// portable subset `EXTRACTION_JSON_SCHEMA` uses — `additionalProperties: false`
// everywhere so a field we do not model cannot be smuggled past us, every
// property required and nullable rather than optional, because the dialects
// disagree about optionality and agree about null.

const weightSchema = {
  type: ["object", "null"],
  additionalProperties: false,
  required: ["amount", "unit_printed", "rate_printed"],
  properties: {
    amount: { type: "number" },
    unit_printed: { type: "string" },
    rate_printed: { type: "string" },
  },
} as const;

const lineSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "printed_text",
    "name_printed",
    "amount_printed",
    "discount_printed",
    "kind",
    "weight",
    "low_confidence",
  ],
  properties: {
    printed_text: { type: "string" },
    name_printed: { type: "string" },
    amount_printed: { type: "string" },
    discount_printed: { type: ["string", "null"] },
    kind: { type: "string", enum: ["item", "not_food", "tax", "fee"] },
    weight: weightSchema,
    low_confidence: { type: "boolean" },
  },
} as const;

export const RECEIPT_JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "store_printed",
    "purchased_at_printed",
    "subtotal_printed",
    "tax_printed",
    "total_printed",
    "lines",
    "notes",
  ],
  properties: {
    store_printed: { type: ["string", "null"] },
    purchased_at_printed: { type: ["string", "null"] },
    subtotal_printed: { type: ["string", "null"] },
    tax_printed: { type: ["string", "null"] },
    total_printed: { type: ["string", "null"] },
    lines: { type: "array", items: lineSchema },
    notes: { type: "array", items: { type: "string" } },
  },
} as const;
