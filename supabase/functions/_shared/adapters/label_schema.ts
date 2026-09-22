// Provider JSON → the frozen `LabelReading`, the label twin of the coercion in
// `receipt_schema.ts`: a wrong type, a missing key or an unusable figure lands
// as a known shape rather than as an exception downstream.
//
// Coercion only removes or normalises. It never fills a figure in: a number
// that is not a usable number becomes null, and the form leaves that field
// alone.

import type {
  LabelMacros,
  LabelPer100,
  LabelReading,
  LabelServing,
} from "../label_types.ts";
import { ExtractionParseError } from "./schema.ts";

/** Length caps, several times the longest real value. */
export const LABEL_CAPS = {
  unit_printed: 40,
  text_printed: 200,
  note: 500,
} as const;

/** Most notes kept. A label that needed more was not read. */
export const MAX_LABEL_NOTES = 20;

/**
 * Largest figure a label can honestly print, for any of the five. Energy is
 * the tall one (900 kcal per 100 g is pure fat); anything past this is a
 * misread decimal point, so it reads as unreadable rather than as a number the
 * form would fill in.
 */
export const MAX_LABEL_FIGURE = 10_000;

function asRecord(v: unknown): Record<string, unknown> {
  if (v === null || typeof v !== "object" || Array.isArray(v)) {
    throw new ExtractionParseError("expected an object", v);
  }
  return v as Record<string, unknown>;
}

/** A printed figure, or null. Negative, absurd and unparseable all read null. */
function num(v: unknown): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = typeof v === "number" ? v : Number(String(v).trim());
  if (!Number.isFinite(n) || n < 0 || n > MAX_LABEL_FIGURE) return null;
  return n;
}

function strOrNull(v: unknown, max: number): string | null {
  if (v === null || v === undefined) return null;
  const s = String(v).slice(0, max).trim();
  return s === "" ? null : s;
}

function macros(v: unknown): LabelMacros {
  const r = v === null || v === undefined ? {} : asRecord(v);
  return {
    kcal: num(r.kcal),
    protein_g: num(r.protein_g),
    carbohydrate_g: num(r.carbohydrate_g),
    fat_g: num(r.fat_g),
    fibre_g: num(r.fibre_g),
  };
}

function serving(v: unknown): LabelServing {
  const r = v === null || v === undefined ? {} : asRecord(v);
  return {
    amount: num(r.amount),
    unit_printed: strOrNull(r.unit_printed, LABEL_CAPS.unit_printed),
    text_printed: strOrNull(r.text_printed, LABEL_CAPS.text_printed),
  };
}

/**
 * The per-100 column, or null. A basis that is neither `g` nor `ml` drops the
 * whole column: we would not know which 100 it was, and a guess would be
 * believed.
 */
function per100(v: unknown): LabelPer100 | null {
  if (v === null || v === undefined) return null;
  const r = asRecord(v);
  const basis = String(r.basis ?? "").trim().toLowerCase();
  if (basis !== "g" && basis !== "ml") return null;
  return { basis, ...macros(r) };
}

/** Provider JSON → a `LabelReading`, every field coerced. */
export function coerceLabelReading(raw: unknown): LabelReading {
  const r = asRecord(raw);
  const notes = Array.isArray(r.notes) ? r.notes : [];
  return {
    serving: serving(r.serving),
    per_serving: macros(r.per_serving),
    per_100: per100(r.per_100),
    notes: notes
      .map((n) => strOrNull(n, LABEL_CAPS.note))
      .filter((n): n is string => n !== null)
      .slice(0, MAX_LABEL_NOTES),
  };
}

/**
 * The one thing worth refusing: a reading with nothing in it. Every figure
 * null and no note means the call produced no reading at all, and filling a
 * form with that would be a silent no-op the person could not explain.
 */
export function validateLabelReading(reading: LabelReading): LabelReading {
  const figures = [
    reading.serving.amount,
    ...Object.values(reading.per_serving),
    ...(reading.per_100
      ? Object.values(reading.per_100).filter((v) => typeof v === "number")
      : []),
  ];
  if (figures.every((f) => f === null) && reading.notes.length === 0) {
    throw new ExtractionParseError("the label reading is empty", reading);
  }
  return reading;
}
