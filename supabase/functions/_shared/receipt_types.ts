// The receipt contract. Two shapes:
//
//   * `ReceiptExtraction`: what the model returns. Printed strings in printed
//     order; it never converts, sums or matches (ADR-0004).
//   * `ReceiptPayload`: what the app receives. Frozen: mirrored by hand in
//     `app/lib/features/receipts` and pinned by
//     `import-receipt/__fixtures__/receipt_payload.golden.json`.
//
// Money is integer cents, USD (migration 0044).

// --- What the app receives ---------------------------------------------------

/**
 * What kind of line the paper printed, decided by the model from the words;
 * the review can change it. Tax and fee lines are kept so the reconcile can
 * close.
 */
export type ReceiptLineKind = "item" | "not_food" | "tax" | "fee";

/** A by-weight line's printed facts: `1.32 lb @ 1.99/lb`. */
export interface ReceiptWeight {
  /** The printed weight, in `unit` ("1.32"). */
  amount: number;
  /** The units.dart canonical unit id: `lb`, `kg`, `oz`, `g`. */
  unit: string;
  /** The printed per-unit rate, in integer cents ("1.99/lb" ⇒ 199). */
  rate_cents: number;
}

/** The best match the cascade found for an item line, when it found one. */
export interface ReceiptMatch {
  ingredient_id: string;
  confidence: number;
  /**
   * `auto` above the cascade's auto threshold, `suggest` below it. Store
   * abbreviations make `suggest` the common answer here.
   */
  kind: "auto" | "suggest";
  /**
   * True where this is the household's own past answer for these printed words
   * (`_shared/receipt_memory.ts`). It overrides the cascade and arrives `auto`
   * at `confidence: 1`. The review says so; correcting it becomes the newest
   * answer.
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
  /** The line verbatim: item name and price as printed. */
  printed_text: string;
  /**
   * The words that name the thing, figures off: what the cascade was asked
   * about and what an unmatched card is titled with. Empty when the model split
   * nothing out; the app then falls back to `printed_text`.
   */
  name_printed: string;
  /** The printed figure for this line, in cents. A `fee` may be negative. */
  cents: number;
  /**
   * How many the line rang up, from the sub-row under it (`Qty 4 $2.39 ea`,
   * `8 @ $2.99`). At least 1. `cents` already includes them all; a price
   * divides by the count.
   */
  count: number;
  /**
   * The per-one figure printed beside the count, in cents; null where none was
   * printed. Nothing is derived from it: a line whose `count × each_cents`
   * disagrees with `cents` keeps `cents` and arrives `low_confidence`.
   */
  each_cents: number | null;
  /**
   * The deduction printed directly under this item, kept beside `cents` rather
   * than subtracted into it (0044). Non-negative.
   */
  discount_cents: number;
  kind: ReceiptLineKind;
  /** The printed weight and rate, on a by-weight line; null on every other. */
  weight: ReceiptWeight | null;
  /** The cascade's best answer; null when nothing was close. */
  match: ReceiptMatch | null;
  /** At most three, for "Did you mean". */
  suggestions: ReceiptSuggestion[];
  /** The extraction's own doubt about this line: cut off, faint, half a seam. */
  low_confidence: boolean;
  /** Which photo it came from; the first one, for a line inside a seam. */
  photo: number;
}

/** One seam: where photo `from` was joined to photo `to`, and by how much. */
export interface ReceiptSeam {
  from: number;
  to: number;
  /** Identical consecutive lines shared by the end of `from` and start of `to`. */
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
  /** The header as printed, e.g. "TRADER JOE'S #135". */
  store_printed: string | null;
  /** The date and time as printed, e.g. "09/13/26 05:42 PM". */
  purchased_at_printed: string | null;
  /**
   * The same moment as ISO-8601 local wall time, no zone, parsed best-effort;
   * null when the paper's date could not be read.
   */
  purchased_at: string | null;
  printed: ReceiptPrintedTotals;
  /**
   * The reconcile figure, summed server-side:
   * `sum(item.cents − item.discount_cents) + sum(not_food.cents) + sum(fee.cents)`.
   * Tax is out. A disagreement with the printed subtotal is a flag in the
   * review, never a refusal.
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
  /** The unit as printed ("lb", "LB", "kg"). The server canonicalises it. */
  unit_printed: string;
  /** The per-unit rate as printed ("1.99", "$1.99"). */
  rate_printed: string;
}

/** One line the model read off the joined transcription. */
export interface ExtractedLine {
  /** The whole line verbatim, money included. */
  printed_text: string;
  /**
   * The words that name the thing: the same characters with money, rate and
   * weight taken off. The match cascade runs over this.
   */
  name_printed: string;
  /** The line's own money figure, as printed ("3.49", "$3.49", "−0.55"). */
  amount_printed: string;
  /**
   * The count from the sub-row under this item (`Qty 4`, `8 @ $2.99`); 1 when
   * none was printed. A by-weight sub-row is a weight, never this.
   */
  count: number;
  /** The per-one figure printed on that sub-row; null when there is none. */
  each_printed: string | null;
  /** A deduction printed directly under this item, as printed; else null. */
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
 * The two model-facing calls, behind one seam so the function is testable
 * offline and replayable. `transcribe` returns one string per photo; the join
 * is deterministic code (`receipt_join.ts`), never the model's.
 */
export interface ReceiptAdapter {
  name: string;
  /** The pinned model id this adapter sends (absent for the fakes). */
  readonly model?: string;
  /** Told whenever the model produced more output; drives `heartbeat` frames. */
  onProgress?: () => void;
  /** Vision: photos in, one faithful transcription per photo out. */
  transcribe(images: Uint8Array[]): Promise<string[]>;
  /** Structure: the joined transcription in, the printed facts out. */
  structure(transcript: string): Promise<ReceiptExtraction>;
}
