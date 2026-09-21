// Provider JSON → the frozen `ReceiptExtraction`, the receipt twin of the
// coercion in `schema.ts`: a wrong type, a missing key or an unmodelled `kind`
// lands as a known shape, not as an exception downstream.
//
// Coercion only removes or normalises. It never fills a figure in: an amount
// that cannot be read stays unreadable and becomes a note.

import type {
  ExtractedLine,
  ExtractedWeight,
  ReceiptExtraction,
  ReceiptLineKind,
} from "../receipt_types.ts";
import { ExtractionParseError } from "./schema.ts";

/** Length caps, several times the longest real value (a till line is < 50). */
export const RECEIPT_CAPS = {
  store: 200,
  purchased_at: 80,
  printed_text: 300,
  name_printed: 300,
  amount_printed: 40,
  unit_printed: 20,
  note: 500,
} as const;

/** Most notes kept. */
export const MAX_RECEIPT_NOTES = 100;

/** Most lines one receipt may carry. A long strip is ~40. */
export const MAX_RECEIPT_LINES = 400;

/**
 * Most of one thing a line may say was bought. A three-digit count is a
 * misread; it reads as one and the line is flagged, because the count is a
 * divisor.
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

/** An unmodelled `kind` reads as `item`; the review can move it in one tap. */
function coerceKind(v: unknown): ReceiptLineKind {
  const s = typeof v === "string" ? v.trim().toLowerCase() : "";
  return KINDS.has(s) ? s as ReceiptLineKind : "item";
}

/**
 * The count the sub-row said, or 1, with `coerced` true where a value was
 * thrown away. The count is a divisor, so a fraction, zero, negative or absurd
 * figure reads as one and flags the line. An absent count is not a coercion.
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
  // All three or none: a weight with no rate, or a rate with no weight, makes
  // the line an ordinary one.
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
  // A line with neither words nor a figure is dropped.
  if (printed_text === "" && amount_printed === "") return null;
  const { count, coerced } = coerceCount(l.count);
  return {
    printed_text,
    name_printed: str(l.name_printed, RECEIPT_CAPS.name_printed),
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

/** Provider JSON → `ReceiptExtraction`. Throws only on a non-object top level. */
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
 * The one structural check worth failing on: a receipt with no lines, which
 * means the model did not read a receipt. A missing subtotal, store or date is
 * real paper and rides through as null.
 */
export function validateReceiptExtraction(
  r: ReceiptExtraction,
): ReceiptExtraction {
  if (r.lines.length === 0) {
    throw new ExtractionParseError("the receipt has no lines", r);
  }
  return r;
}
