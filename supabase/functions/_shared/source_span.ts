// Where a reconciliation line sits in the page's own text (0047).
//
// The wide review draws the fetched page beside the lines and lights the
// selected line inside it. That needs a character range per line, and nothing
// upstream carries one: extraction is ingredient-blind prose-in / JSON-out, and
// asking the model for offsets would be a prompt, schema and gold-set change
// for a drawing affordance.
//
// So the span is **located, never guessed** — the same posture as everything
// else in the pipeline. A line's own verbatim printed words are looked for in
// the exact string the payload is about to carry, and a span is emitted only
// where they can be pointed at unambiguously. Anything else omits the field,
// and the app draws the plain page. A lit range that is off by a line is worse
// than no lit range: it tells a reader the page said something it did not.

import type { RawLineItem, SourceSpan } from "./types.ts";

/**
 * How far past the printed amount the identity may sit and still be counted as
 * the same line. The page's text is whitespace-collapsed, so a printed line is
 * a run of characters rather than something delimited — this is what keeps
 * "400 g" and a "chopped tomatoes" two paragraphs later from being welded into
 * one span.
 */
const IDENTITY_GAP = 80;

/** The one unambiguous occurrence of [needle] in [text], or null. */
function soleOccurrence(
  text: string,
  needle: string,
): { start: number; end: number } | null {
  const trimmed = needle.trim();
  // A one- or two-character needle ("1", "g") occurs everywhere; it can only
  // ever be ambiguous, and asking is wasted work.
  if (trimmed.length < 3) return null;
  const hay = text.toLowerCase();
  const pin = trimmed.toLowerCase();
  const first = hay.indexOf(pin);
  if (first < 0) return null;
  if (hay.indexOf(pin, first + 1) >= 0) return null;
  return { start: first, end: first + pin.length };
}

/**
 * Where [raw] was printed inside [text], or null when it cannot be said.
 *
 * Two exact substring reads, no fuzz: the line's verbatim `raw_amount` and its
 * `ingredient_text`. Whichever can be pointed at uniquely gives the span, and
 * when both can — with the identity following the amount closely — the span
 * runs from the amount's start to the identity's end, which is the printed
 * line as a reader sees it.
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
    // The two are far apart, so at most one of them is this line. The identity
    // is the half that names the thing, so it is the half worth lighting.
    return { start: identity.start, end: identity.end };
  }
  return amount ?? identity;
}
