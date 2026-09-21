// Provider JSON → the frozen `ReceiptExtraction`, beside the recipe coercion in
// `schema.ts` and for the same reasons: a structured-output dialect can still
// hand back a number where a string was asked for, a missing key, or a `kind`
// nobody modelled, and every one of those must land as a known shape rather
// than as an exception three modules downstream.
//
// The rule this file holds to is the recipe pipeline's: coercion only ever
// REMOVES or NORMALISES. It caps a string, it reads a number written as a
// string, it drops a line that has nothing in it. It never fills a figure in —
// an amount that cannot be read stays unreadable and becomes a note.

import type {
  ExtractedLine,
  ExtractedWeight,
  ReceiptExtraction,
  ReceiptLineKind,
} from "../receipt_types.ts";
import { ExtractionParseError } from "./schema.ts";
import { repairedName } from "../receipt_parse.ts";

/**
 * Length caps, in the shape `schema.ts` uses. A receipt's strings are short —
 * a till line is under 50 characters — so these are several times the longest
 * real value and exist only to bound a provider having a bad day.
 */
export const RECEIPT_CAPS = {
  store: 200,
  purchased_at: 80,
  printed_text: 300,
  name_printed: 300,
  amount_printed: 40,
  unit_printed: 20,
  note: 500,
} as const;

/** Most notes kept. A per-line note storm is bounded, exactly as warnings are. */
export const MAX_RECEIPT_NOTES = 100;

/** Most lines one receipt may carry. A long TJ's strip is ~40; this is a fence. */
export const MAX_RECEIPT_LINES = 400;

/**
 * Most of one thing a line may say was bought. A till prints two digits here;
 * a three-digit count is a misread rate or a run-together figure, and it reads
 * as one — with the line flagged, because the count is now a divisor.
 */
export const MAX_LINE_COUNT = 99;

const KINDS = new Set<string>(["item", "not_food", "tax", "fee"]);

function cap(s: string, max: number): string {
  return s.length <= max ? s : s.slice(0, max);
}

function asRecord(v: unknown): Record<string, unknown> {
  if (v === null || typeof v !== "object" || Array.isArray(v)) {
    throw new ExtractionParseError("expected an object", v);
  }
  return v as Record<string, unknown>;
}

function strOrNull(v: unknown, max: number): string | null {
  if (v === null || v === undefined) return null;
  const s = cap(String(v), max).trim();
  return s === "" ? null : s;
}

function str(v: unknown, max: number): string {
  return strOrNull(v, max) ?? "";
}

function numOrNull(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string" && v.trim() !== "" && Number.isFinite(Number(v))) {
    return Number(v);
  }
  return null;
}

/**
 * A `kind` we do not model reads as `item`, because "food" is the default a
 * receipt line is, and the review can move a line either way in one tap. It is
 * the one coercion here that chooses, and it chooses the reversible answer.
 */
function coerceKind(v: unknown): ReceiptLineKind {
  const s = typeof v === "string" ? v.trim().toLowerCase() : "";
  return KINDS.has(s) ? s as ReceiptLineKind : "item";
}

/**
 * The count the sub-row said, or 1 — with `coerced` true where a value was
 * thrown away.
 *
 * A count is a DIVISOR now, so an unusable one must not ride through quietly:
 * a fraction, a zero, a negative and an absurd figure all read as one thing
 * bought, and the line is flagged so the review checks it against the paper.
 * An absent count is not a coercion — most lines print none.
 */
function coerceCount(v: unknown): { count: number; coerced: boolean } {
  if (v === null || v === undefined) return { count: 1, coerced: false };
  const n = numOrNull(v);
  if (n === null || !Number.isInteger(n) || n < 1 || n > MAX_LINE_COUNT) {
    return { count: 1, coerced: true };
  }
  return { count: n, coerced: false };
}

function coerceWeight(v: unknown): ExtractedWeight | null {
  if (v === null || v === undefined || typeof v !== "object") return null;
  const w = v as Record<string, unknown>;
  const amount = numOrNull(w.amount);
  const unit = strOrNull(w.unit_printed, RECEIPT_CAPS.unit_printed);
  const rate = strOrNull(w.rate_printed, RECEIPT_CAPS.amount_printed);
  // All three or none: a weight with no rate prices nothing, and a rate with no
  // weight is a number with no dimension. Either way the line is still a line —
  // it simply is not a by-weight one.
  if (amount === null || amount <= 0 || unit === null || rate === null) {
    return null;
  }
  return { amount, unit_printed: unit, rate_printed: rate };
}

function coerceLine(v: unknown): ExtractedLine | null {
  if (v === null || typeof v !== "object" || Array.isArray(v)) return null;
  const l = v as Record<string, unknown>;
  const printed_text = str(l.printed_text, RECEIPT_CAPS.printed_text);
  const amount_printed = str(l.amount_printed, RECEIPT_CAPS.amount_printed);
  // A line with neither words nor a figure is not a line. Dropping it is a
  // removal, which is the only thing coercion is allowed to do.
  if (printed_text === "" && amount_printed === "") return null;
  const { count, coerced } = coerceCount(l.count);
  return {
    printed_text,
    // A name the model cut short is restored from the line it came off.
    name_printed: cap(
      repairedName(
        str(l.name_printed, RECEIPT_CAPS.name_printed),
        printed_text,
      ),
      RECEIPT_CAPS.name_printed,
    ),
    amount_printed,
    count,
    each_printed: strOrNull(l.each_printed, RECEIPT_CAPS.amount_printed),
    discount_printed: strOrNull(
      l.discount_printed,
      RECEIPT_CAPS.amount_printed,
    ),
    kind: coerceKind(l.kind),
    weight: coerceWeight(l.weight),
    low_confidence: l.low_confidence === true || coerced,
  };
}

function coerceNotes(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  return v
    .map((n) => strOrNull(n, RECEIPT_CAPS.note))
    .filter((n): n is string => n !== null)
    .slice(0, MAX_RECEIPT_NOTES);
}

/** Provider JSON → `ReceiptExtraction`. Throws only when the top level is not an object. */
export function coerceReceiptExtraction(raw: unknown): ReceiptExtraction {
  const r = asRecord(raw);
  const lines = Array.isArray(r.lines)
    ? r.lines
      .map(coerceLine)
      .filter((l): l is ExtractedLine => l !== null)
      .slice(0, MAX_RECEIPT_LINES)
    : [];
  return {
    store_printed: strOrNull(r.store_printed, RECEIPT_CAPS.store),
    purchased_at_printed: strOrNull(
      r.purchased_at_printed,
      RECEIPT_CAPS.purchased_at,
    ),
    subtotal_printed: strOrNull(
      r.subtotal_printed,
      RECEIPT_CAPS.amount_printed,
    ),
    tax_printed: strOrNull(r.tax_printed, RECEIPT_CAPS.amount_printed),
    total_printed: strOrNull(r.total_printed, RECEIPT_CAPS.amount_printed),
    lines,
    notes: coerceNotes(r.notes),
  };
}

/**
 * The one structural check worth failing on: a receipt with no lines at all.
 * Everything else a receipt can be missing — a subtotal, a store, a date — is a
 * real state of real paper and rides through as null. No lines means the model
 * did not read a receipt, and showing an empty review over that would make the
 * person look for what they were sure they photographed.
 */
export function validateReceiptExtraction(
  r: ReceiptExtraction,
): ReceiptExtraction {
  if (r.lines.length === 0) {
    throw new ExtractionParseError("the receipt has no lines", r);
  }
  return r;
}
