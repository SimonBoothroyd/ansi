// Assembly: what the model printed + where the photos joined + what the cascade
// matched ⇒ the `ReceiptPayload` the app receives. Pure.
//
//   * Never invent a figure. A price that cannot be read lands at 0 with
//     `low_confidence` set and a note naming it.
//   * `lines_sum_cents` and `printed.subtotal_cents` are returned side by side;
//     nothing here decides which is right or refuses a receipt over them.

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
import type { ReceiptMemory, RememberedAnswer } from "./receipt_memory.ts";
import { recallKey } from "./receipt_memory.ts";
import {
  canonicalWeightUnit,
  parseCents,
  parseDiscountCents,
  parseReceiptDate,
} from "./receipt_parse.ts";
import { MAX_RECEIPT_NOTES } from "./adapters/receipt_schema.ts";

/** Most "did you mean" candidates on a line (the cascade's own TOP_N). */
export const MAX_SUGGESTIONS = 3;

/**
 * The match cascade's input for each item line, in printed order. Only
 * `ingredient_text` does any work; it is `name_printed`, the line with its
 * figures taken off. The other fields take the empty answer.
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
      // The name if the model split one out, else the whole printed line.
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
 * The line's best answer: `auto` only where the cascade said `auto`, a
 * suggestion for `suggest`, nothing for `none`.
 */
function matchOf(m: MatchedLine | undefined): ReceiptLineOut["match"] {
  if (!m || m.band === "none" || m.candidates.length === 0) return null;
  const best = m.candidates[0];
  return {
    ingredient_id: best.ingredient_id,
    confidence: best.score,
    kind: m.band === "auto" ? "auto" : "suggest",
    remembered: false,
  };
}

/**
 * What the household already said about this line's printed name, keyed on
 * `name_printed`, which is what a saved line stores.
 */
function recallFor(
  memory: ReceiptMemory,
  line: ExtractedLine,
): RememberedAnswer | undefined {
  const name = line.name_printed.trim();
  return name === "" ? undefined : memory.get(recallKey(name));
}

/**
 * The line's answer, with the household's own having the last word. A
 * remembered ingredient arrives `auto` at `confidence: 1`; a remembered fold
 * has no match.
 */
function matchFor(
  recalled: RememberedAnswer | undefined,
  m: MatchedLine | undefined,
): ReceiptLineOut["match"] {
  if (recalled === undefined) return matchOf(m);
  if (recalled.kind === "not_food") return null;
  return {
    ingredient_id: recalled.ingredient_id,
    confidence: 1,
    kind: "auto",
    remembered: true,
  };
}

/**
 * Which photo a printed line came from. A forward-only cursor over the joined
 * strip, so a line printed twice is attributed to its own occurrence. A line
 * inside a seam belongs to the earlier photo.
 */
class PhotoCursor {
  #at = 0;
  readonly #keys: string[];
  constructor(private readonly transcript: JoinedTranscript) {
    this.#keys = transcript.lines.map(joinKey);
  }

  /** The photo `printedText` came from; the current position's if not found. */
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
    // Not located (the model reordered or merged something): use the cursor's
    // own position.
    const here = Math.min(this.#at, this.#keys.length - 1);
    return this.transcript.photoOfLine[here] ?? 0;
  }
}

/** The printed weight and rate, canonicalised, or null with a note saying why. */
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
 * How many of the thing this line rang up. A by-weight line is one: its
 * sub-row (`Qty 0.73 lb @ $2.99/lb`) states a weight, and counting it too
 * would divide the price twice.
 */
function countOf(line: ExtractedLine, weight: ReceiptWeight | null): number {
  if (weight !== null) return 1;
  const n = line.count;
  return Number.isInteger(n) && n >= 1 ? n : 1;
}

/**
 * Whether `count × each` and the printed line total agree, within a penny per
 * thing (a till rounds each unit price). A line that disagrees keeps the
 * printed total and is flagged.
 */
function countAgrees(cents: number, count: number, each: number): boolean {
  return Math.abs(count * each - cents) <= count;
}

/**
 * The reconcile figure, compared against the paper's subtotal:
 *
 *   `sum(item.cents − item.discount_cents) + sum(not_food.cents) + sum(fee.cents)`
 *
 * Tax is out. A `fee` line's cents may be negative.
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
 * `matched` is one entry per item line, in the order {@link itemMatchInputs}
 * produced them; the orchestrator checks the length. `remembered` is what this
 * household has already said about these printed names, and it overrides the
 * cascade. Empty by default, and after a failed recall.
 */
export function assembleReceipt(
  extraction: ReceiptExtraction,
  transcript: JoinedTranscript,
  matched: MatchedLine[],
  remembered: ReceiptMemory = new Map(),
): ReceiptPayload {
  // The join's notes lead: a missed seam explains most of what follows.
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
    const weight = weightOf(line, notes);
    const count = countOf(line, weight);
    const each_cents = parseCents(line.each_printed);
    if (
      parsedCents !== null && each_cents !== null &&
      !countAgrees(parsedCents, count, each_cents)
    ) {
      notes.push(
        `"${line.printed_text}" rang up ${count} at ` +
          `${line.each_printed} each, which does not come to its printed ` +
          `total — the printed total stands; check the count.`,
      );
      low_confidence = true;
    }
    // `line.kind`, never the recalled one: this cursor must walk the same
    // item lines the cascade was given.
    const m = line.kind === "item" ? matched[itemIndex++] : undefined;
    // A remembered fold is as much an answer as a remembered match. Tax and
    // fee lines are never either.
    const recalled = line.kind === "item" || line.kind === "not_food"
      ? recallFor(remembered, line)
      : undefined;
    return {
      index,
      printed_text: line.printed_text,
      name_printed: line.name_printed.trim(),
      cents: parsedCents ?? 0,
      count,
      each_cents,
      discount_cents,
      // A folded line still counts toward what the trip cost.
      kind: recalled?.kind ?? line.kind,
      weight,
      match: matchFor(recalled, m),
      // The cascade's offers stand whatever is remembered, so the person can
      // change the answer.
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
