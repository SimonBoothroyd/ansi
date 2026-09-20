// The receipt contract — what `import-receipt` promises the app, and what the
// model is asked for on the way there. Two shapes, deliberately separate:
//
//   * `ReceiptExtraction` — what the MODEL returns. Printed strings, in printed
//     order, money still in the words the paper used. The model prints what the
//     paper printed; it never converts, never sums and never matches (ADR-0004).
//   * `ReceiptPayload` — what the APP receives. Money is integer cents, the
//     photos' seams are named, every item line carries the server's own match,
//     and the reconcile figure sits beside the paper's own subtotal.
//
// The second is the FROZEN one: `app/lib/features/receipts` mirrors it by hand
// and a golden fixture (`import-receipt/__fixtures__/receipt_payload.golden.json`)
// pins it, exactly as `ReconciliationPayload` is pinned for recipes.
//
// Money is integer cents, USD, and nothing else — migration 0044's rule, from
// the table the client writes down to the wire it reads. Nothing here is a
// float dollar amount, and nothing here is rounded twice.

// --- What the app receives ---------------------------------------------------

/**
 * What kind of line the paper printed. The MODEL decides this from the words
 * (`not_food` for paper towels, a bag fee, a deposit) — the review can move a
 * line either way afterwards. Tax and fee lines are kept, never dropped, which
 * is what lets the reconcile close.
 */
export type ReceiptLineKind = "item" | "not_food" | "tax" | "fee";

/** A by-weight line's printed facts: `1.32 lb @ 1.99/lb`. */
export interface ReceiptWeight {
  /** The printed weight, in `unit` ("1.32"). */
  amount: number;
  /** The units.dart canonical unit id — `lb`, `kg`, `oz`, `g`. Never a printed word. */
  unit: string;
  /** The printed per-unit rate, in integer cents ("1.99/lb" ⇒ 199). */
  rate_cents: number;
}

/** The best match the cascade found for an item line, when it found one. */
export interface ReceiptMatch {
  ingredient_id: string;
  confidence: number;
  /**
   * `auto` above the cascade's auto threshold, `suggest` below it. A receipt's
   * words are a store's abbreviations, so `suggest` is the common answer here
   * where a recipe line would usually earn `auto` — expect, and draw, more of it.
   */
  kind: "auto" | "suggest";
  /**
   * True where this is the household's OWN past answer for these printed words
   * rather than the cascade's reading of them (`_shared/receipt_memory.ts`).
   * It overrides the cascade and arrives `auto` at `confidence: 1`, because it
   * is not a guess — somebody said it.
   *
   * The review says so on the card. A remembered match is the one kind of
   * `auto` that can be wrong for a reason the person can see and fix, and the
   * fix is to change it: the correction is itself the most recent answer.
   */
  remembered: boolean;
}

/** One "did you mean" candidate. */
export interface ReceiptSuggestion {
  ingredient_id: string;
  name: string;
  confidence: number;
}

/** One line of the receipt, as the review draws it. */
export interface ReceiptLineOut {
  /** 0-based printed order, across every kind. */
  index: number;
  /** The line verbatim — item name and price as printed. */
  printed_text: string;
  /**
   * The words that NAME the thing, with the figures taken off — what the match
   * cascade was asked about, and what an unmatched card is titled with (the
   * money is already on the card, in its own column). Empty when the model
   * split nothing out; the app then falls back to `printed_text`.
   */
  name_printed: string;
  /** The printed figure for this line, in cents. Positive; a `fee` may be negative. */
  cents: number;
  /**
   * How many of this thing the line rang up — the count printed on the
   * sub-row UNDER it (`Qty 4 $2.39 ea`, `8 @ $2.99`). One unless the paper
   * said otherwise, and never less.
   *
   * `cents` already includes it: the till printed the line's whole figure.
   * What the count is for is the PRICE — eight blocks of tofu for $23.92 is
   * the price of eight blocks, and dividing it by one pack would make each
   * block cost eight times what it did.
   */
  count: number;
  /**
   * The per-one figure printed beside the count ("$2.39 ea", "@ $2.99"), in
   * cents — kept because the paper printed it, and it is what the check
   * below is run against. Null where the sub-row printed no rate.
   *
   * Nothing is derived from it: what was paid is `cents`, and a line whose
   * `count × each_cents` disagrees with `cents` keeps the printed line total
   * and arrives `low_confidence` with a note.
   */
  each_cents: number | null;
  /**
   * The deduction printed directly under this item, folded in here and kept
   * BESIDE `cents` rather than subtracted into it (0044): both printed figures
   * survive. Non-negative — a discount is stated as the amount taken away.
   */
  discount_cents: number;
  kind: ReceiptLineKind;
  /** The printed weight and rate, on a by-weight line; null on every other. */
  weight: ReceiptWeight | null;
  /** The cascade's best answer, auto or top suggestion; null when nothing was close. */
  match: ReceiptMatch | null;
  /** At most three, for "Did you mean". Empty when nothing cleared the floor. */
  suggestions: ReceiptSuggestion[];
  /** The EXTRACTION's own doubt about this line — cut off, faint, half a seam. */
  low_confidence: boolean;
  /** Which photo it came from; the FIRST one, for a line inside a seam. */
  photo: number;
}

/** One seam: where photo `from` was joined to photo `to`, and by how much. */
export interface ReceiptSeam {
  from: number;
  to: number;
  /** Identical consecutive lines shared by the end of `from` and the start of `to`. */
  overlap_lines: number;
}

/** The paper's own totals, as printed. Any of them may be missing. */
export interface ReceiptPrintedTotals {
  subtotal_cents: number | null;
  tax_cents: number | null;
  total_cents: number | null;
}

/** The frozen wire contract: one photographed receipt, read and matched. */
export interface ReceiptPayload {
  /** The header as printed — "TRADER JOE'S #135". The review picks a store chip over it. */
  store_printed: string | null;
  /** The date and time as printed — "09/13/26 05:42 PM". */
  purchased_at_printed: string | null;
  /**
   * The same moment as ISO-8601 LOCAL WALL TIME, no zone, parsed best-effort;
   * null when the paper's date could not be read. A receipt's date is the
   * shop's, never the scan's, so there is no clock here but the paper's.
   */
  purchased_at: string | null;
  printed: ReceiptPrintedTotals;
  /**
   * The reconcile figure, summed SERVER-SIDE over the lines below:
   * `sum(item.cents − item.discount_cents) + sum(not_food.cents) + sum(fee.cents)`.
   * Tax is out — it is not part of a subtotal. The server returns this and the
   * printed subtotal and stops there; the review draws the join card and a
   * disagreement is a flag, never a refusal.
   */
  lines_sum_cents: number;
  /** Every line, in printed order. */
  lines: ReceiptLineOut[];
  /** One entry per seam, in order. Empty for a single photo. */
  photos_joined: ReceiptSeam[];
  /** "What we could not read", in the review's voice. */
  notes: string[];
}

// --- What the model returns --------------------------------------------------

/** A by-weight line, in the words the paper used. */
export interface ExtractedWeight {
  /** The printed weight as a number ("1.32 lb" ⇒ 1.32). */
  amount: number;
  /** The unit AS PRINTED — "lb", "LB", "kg". The server canonicalises it. */
  unit_printed: string;
  /** The per-unit rate as printed — "1.99", "$1.99". The server reads it as cents. */
  rate_printed: string;
}

/** One line the model read off the joined transcription. */
export interface ExtractedLine {
  /** The whole line verbatim, money included. */
  printed_text: string;
  /**
   * Just the words that NAME the thing — no money, no rate, no weight. This is
   * what the match cascade is run over, and it is the only reason the model is
   * asked to split the line at all. It is not a match and it is not a guess at
   * our vocabulary: it is the same characters, with the numbers taken off.
   */
  name_printed: string;
  /** The line's own money figure, as printed ("3.49", "$3.49", "−0.55"). */
  amount_printed: string;
  /**
   * How many of the thing the count sub-row under this item said — `Qty 4`,
   * `8 @ $2.99`. 1 when the paper printed no count, which is most lines.
   * A by-weight sub-row is a WEIGHT and never this.
   */
  count: number;
  /** The per-one figure printed on that sub-row ("2.39", "$2.99"); null when there is none. */
  each_printed: string | null;
  /** A deduction printed directly UNDER this item, as printed; null when there is none. */
  discount_printed: string | null;
  kind: ReceiptLineKind;
  weight: ExtractedWeight | null;
  /** The model's own doubt: a cut-off, faint or half-joined line. */
  low_confidence: boolean;
}

/** The model's whole answer for one receipt. */
export interface ReceiptExtraction {
  store_printed: string | null;
  purchased_at_printed: string | null;
  subtotal_printed: string | null;
  tax_printed: string | null;
  total_printed: string | null;
  lines: ExtractedLine[];
  /** Anything the model could not read, in its own words. */
  notes: string[];
}

/**
 * The two model-facing calls, behind one seam so the whole function is
 * offline-testable with a fake (and replayable with a saved answer).
 *
 * `transcribe` returns ONE STRING PER PHOTO — not one joined document. The
 * join is ours: it is positional, deterministic and unit-tested
 * (`receipt_join.ts`), and a model asked to splice two photos together would
 * be asked to decide whether a repeated line is an overlap or a second
 * banana. It is never asked.
 */
export interface ReceiptAdapter {
  name: string;
  /** The pinned model id this adapter sends (absent for the fakes). */
  readonly model?: string;
  /** Told whenever the model produced more output — drives the `heartbeat` frames. */
  onProgress?: () => void;
  /** Vision: photos in, one faithful transcription per photo out. */
  transcribe(images: Uint8Array[]): Promise<string[]>;
  /** Structure: the joined transcription in, the printed facts out. */
  structure(transcript: string): Promise<ReceiptExtraction>;
}
