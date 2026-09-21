// Where a reconciliation line sits in the page's own text, for the wide
// review's source column.
//
// The span is located, never guessed: a line's verbatim printed words are
// searched for in the exact string the payload carries, and a span is emitted
// only for an unambiguous hit. Otherwise the field is omitted.

import type { RawLineItem, SourceSpan } from "./types.ts";

/**
 * How far past the printed amount the identity may sit and still count as the
 * same line. The page text is whitespace-collapsed, so nothing else delimits
 * a line.
 */
const IDENTITY_GAP = 80;

/** The one unambiguous occurrence of [needle] in [text], or null. */
function soleOccurrence(
  text: string,
  needle: string,
): { start: number; end: number } | null {
  const trimmed = needle.trim();
  // A one- or two-character needle ("1", "g") can only be ambiguous.
  if (trimmed.length < 3) return null;
  const hay = text.toLowerCase();
  const pin = trimmed.toLowerCase();
  const first = hay.indexOf(pin);
  if (first < 0) return null;
  if (hay.indexOf(pin, first + 1) >= 0) return null;
  return { start: first, end: first + pin.length };
}

/**
 * Where [raw] was printed inside [text], or null.
 *
 * Two exact substring reads: the line's `raw_amount` and its
 * `ingredient_text`. Whichever is unique gives the span; when both are and the
 * identity closely follows the amount, the span runs from the amount's start
 * to the identity's end.
 */
export function locateSourceSpan(
  text: string,
  raw: RawLineItem,
): SourceSpan | null {
  const amount = soleOccurrence(text, raw.raw_amount ?? "");
  const identity = soleOccurrence(text, raw.ingredient_text ?? "");
  if (amount && identity) {
    const gap = identity.start - amount.end;
    if (gap >= 0 && gap <= IDENTITY_GAP) {
      return { start: amount.start, end: identity.end };
    }
    // Far apart, so at most one is this line; light the identity.
    return { start: identity.start, end: identity.end };
  }
  return amount ?? identity;
}
