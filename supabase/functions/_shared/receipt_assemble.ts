// Assembly: what the model printed + where the photos joined + what the cascade
// matched ⇒ the `ReceiptPayload` the app receives.
//
// PURE. No I/O, no clock, no model. Everything here is arithmetic over strings
// somebody else read, which is what makes the reconcile figure — the one number
// the review hangs its join card on — a thing with tests rather than a thing
// that looked right on one receipt.
//
// Two rules run through it:
//
//   * **Never invent a figure.** A price that cannot be read does not become a
//     plausible number. The contract has nowhere to put "unreadable" on a
//     line's `cents`, so such a line lands at 0 with `low_confidence` set and a
//     note naming it — the three signals a review needs to stop and ask. What
//     it never does is quietly contribute a figure to a sum.
//   * **The server states both numbers and stops.** `lines_sum_cents` and
//     `printed.subtotal_cents` are returned side by side; nothing here decides
//     which is right, and nothing here refuses a receipt for their disagreeing.
//     The paper's total is the paper's, and the review draws the flag.

import type { MatchedLine, RawLineItem } from "./types.ts";
import type {
  ExtractedLine,
  ReceiptExtraction,
  ReceiptLineOut,
  ReceiptPayload,
  ReceiptSuggestion,
  ReceiptWeight,
} from "./receipt_types.ts";
import type { JoinedTranscript } from "./receipt_join.ts";
import { joinKey } from "./receipt_join.ts";
import {
  canonicalWeightUnit,
  parseCents,
  parseDiscountCents,
  parseReceiptDate,
} from "./receipt_parse.ts";
import { MAX_RECEIPT_NOTES } from "./adapters/receipt_schema.ts";

/** At most this many "did you mean" candidates ride on a line (the cascade's own TOP_N). */
export const MAX_SUGGESTIONS = 3;

/**
 * The match cascade's input for each ITEM line, in printed order — one
 * `RawLineItem` per item, built from the printed words alone.
 *
 * Only `ingredient_text` does any work: the cascade normalizes it (§7) and
 * compares it against the household's vocabulary. Everything else on the shape
 * is a recipe line's business and is filled with the empty answer, because a
 * receipt line has no quantity in the recipe sense — what it has is money, and
 * money never reaches the matcher.
 *
 * The text handed over is `name_printed`, the line with its figures taken off.
 * Matching `TJ ORG BANANAS 3.49` would compare a price against a vocabulary.
 */
export function itemMatchInputs(extraction: ReceiptExtraction): RawLineItem[] {
  return extraction.lines
    .filter((l) => l.kind === "item")
    .map((l) => ({
      qty: null,
      qty_low: null,
      qty_high: null,
      unit: null,
      unit_mappable: false,
      // The name if the model split one out, else the whole printed line —
      // a line is never sent to the cascade as nothing.
      ingredient_text: l.name_printed.trim() !== ""
        ? l.name_printed
        : l.printed_text,
      notes: null,
      raw_amount: l.amount_printed,
      optional: false,
      confidence: l.low_confidence ? 0.3 : 0.9,
    }));
}

/** The cascade's candidates as the review draws them. */
function suggestionsOf(m: MatchedLine | undefined): ReceiptSuggestion[] {
  if (!m) return [];
  return m.candidates.slice(0, MAX_SUGGESTIONS).map((c) => ({
    ingredient_id: c.ingredient_id,
    name: c.canonical_name,
    confidence: c.score,
  }));
}

/**
 * The line's best answer. `auto` only where the cascade said `auto` — i.e. only
 * above its own auto threshold, which is calibrated on recipe lines and which a
 * store's abbreviations clear far less often. Everything it bands as `suggest`
 * comes back as a suggestion, and `none` comes back as nothing at all.
 */
function matchOf(m: MatchedLine | undefined): ReceiptLineOut["match"] {
  if (!m || m.band === "none" || m.candidates.length === 0) return null;
  const best = m.candidates[0];
  return {
    ingredient_id: best.ingredient_id,
    confidence: best.score,
    kind: m.band === "auto" ? "auto" : "suggest",
  };
}

/**
 * Which photo a printed line came from.
 *
 * A forward-only cursor over the joined strip, so the same printed line
 * appearing twice on one receipt is attributed to its OWN occurrence rather
 * than to the first one — the same reason the join itself is positional. A line
 * inside a seam belongs to the photo that contributed it, which is the earlier
 * one (`receipt_join.ts` keeps the earlier photo's copy).
 */
class PhotoCursor {
  #at = 0;
  readonly #keys: string[];
  constructor(private readonly transcript: JoinedTranscript) {
    this.#keys = transcript.lines.map(joinKey);
  }

  /** The photo `printedText` came from; the current position's when it cannot be found. */
  photoFor(printedText: string): number {
    const key = joinKey(printedText);
    if (key !== "") {
      for (let j = this.#at; j < this.#keys.length; j++) {
        const line = this.#keys[j];
        if (line === key || line.includes(key) || key.includes(line)) {
          this.#at = j + 1;
          return this.transcript.photoOfLine[j] ?? 0;
        }
      }
    }
    // Not located: the model reordered or merged something. The cursor's own
    // position is the honest best answer — it is where we were reading.
    const here = Math.min(this.#at, this.#keys.length - 1);
    return this.transcript.photoOfLine[here] ?? 0;
  }
}

/** The printed weight and rate, canonicalised — or null, with a note saying why. */
function weightOf(
  line: ExtractedLine,
  notes: string[],
): ReceiptWeight | null {
  if (!line.weight) return null;
  const unit = canonicalWeightUnit(line.weight.unit_printed);
  const rate_cents = parseCents(line.weight.rate_printed);
  if (unit === null || rate_cents === null) {
    notes.push(
      `We could not read the weight or the rate on "${line.printed_text}" — ` +
        `its price stands as printed.`,
    );
    return null;
  }
  return { amount: line.weight.amount, unit, rate_cents };
}

/**
 * The reconcile figure: what the lines come to, against what the paper said its
 * subtotal was.
 *
 *   `sum(item.cents − item.discount_cents) + sum(not_food.cents) + sum(fee.cents)`
 *
 * Tax is out, because a subtotal is the figure before it. A `fee` line's cents
 * may be negative — that is how a discount nobody could attach to an item still
 * lets the two numbers meet.
 */
export function linesSumCents(lines: ReceiptLineOut[]): number {
  return lines.reduce((sum, l) => {
    if (l.kind === "tax") return sum;
    if (l.kind === "item") return sum + l.cents - l.discount_cents;
    return sum + l.cents;
  }, 0);
}

/**
 * Builds the payload.
 *
 * `matched` is one entry per ITEM line, in the order {@link itemMatchInputs}
 * produced them — the caller is the orchestrator, which checks that length
 * before it gets here.
 */
export function assembleReceipt(
  extraction: ReceiptExtraction,
  transcript: JoinedTranscript,
  matched: MatchedLine[],
): ReceiptPayload {
  // The join's own notes lead: a seam that could not be found is the thing most
  // likely to be behind whatever else looks wrong below it.
  const notes: string[] = [...transcript.notes, ...extraction.notes];
  const cursor = new PhotoCursor(transcript);
  let itemIndex = 0;

  const lines: ReceiptLineOut[] = extraction.lines.map((line, index) => {
    const parsedCents = parseCents(line.amount_printed);
    let low_confidence = line.low_confidence;
    if (parsedCents === null) {
      notes.push(
        `We could not read the price on "${line.printed_text}" — it counts as ` +
          `nothing until you say what it was.`,
      );
      low_confidence = true;
    }
    let discount_cents = 0;
    if (line.discount_printed !== null) {
      const parsed = parseDiscountCents(line.discount_printed);
      if (parsed === null) {
        notes.push(
          `We could not read the discount under "${line.printed_text}" ` +
            `("${line.discount_printed}").`,
        );
        low_confidence = true;
      } else {
        discount_cents = parsed;
      }
    }
    const m = line.kind === "item" ? matched[itemIndex++] : undefined;
    return {
      index,
      printed_text: line.printed_text,
      cents: parsedCents ?? 0,
      discount_cents,
      kind: line.kind,
      weight: weightOf(line, notes),
      match: matchOf(m),
      suggestions: suggestionsOf(m),
      low_confidence,
      photo: cursor.photoFor(line.printed_text),
    };
  });

  const purchased_at_printed = extraction.purchased_at_printed;
  const purchased_at = parseReceiptDate(purchased_at_printed);
  if (purchased_at_printed !== null && purchased_at === null) {
    notes.push(
      `We could not read the date on this receipt ("${purchased_at_printed}") ` +
        `— say when the shop happened.`,
    );
  }

  return {
    store_printed: extraction.store_printed,
    purchased_at_printed,
    purchased_at,
    printed: {
      subtotal_cents: parseCents(extraction.subtotal_printed),
      tax_cents: parseCents(extraction.tax_printed),
      total_cents: parseCents(extraction.total_printed),
    },
    lines_sum_cents: linesSumCents(lines),
    lines,
    photos_joined: transcript.seams,
    notes: notes.slice(0, MAX_RECEIPT_NOTES),
  };
}
