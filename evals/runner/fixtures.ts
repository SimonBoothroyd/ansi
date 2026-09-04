// Extraction-eval fixtures: the gold loader, the unit-hint set, and the
// deterministic gold → source-text renderer that lets us score the sanitize
// stage (D2) keyless.
//
// The 12 photos are gitignored (copyright + EXIF), so the committed oracle is
// the structured gold under datasets/extraction/gold/. To score ① text→structure
// without a live vision call, we render each gold back into a faithful "as
// printed" recipe text (`goldToSourceText`) and feed THAT to an adapter. That is
// a fair D2 input — the amounts/steps are all present in the text; the test is
// whether the model re-structures them correctly, never-invent included.

import type {
  ExtractionResult,
  RawBlob,
  StepToken,
  TimeField,
  UnitHints,
} from "../../supabase/functions/_shared/types.ts";
import { deriveUnitHints } from "../../supabase/functions/_shared/unit_hints.ts";

// The unit hints handed to `sanitize` — the SAME set production sends. This
// file used to hold its own copy "so the two never need to import each other",
// and the copy drifted: it offered the model splash/drizzle/glug as imprecise
// units and withheld the size words big/tiny, so every benchmark number was
// measured on a prompt that does not ship. `deriveUnitHints()` is pure and
// dependency-free; importing it costs one line and removes the whole class of
// error.
export const UNIT_HINTS: UnitHints = deriveUnitHints();

export interface GoldRecipe extends ExtractionResult {
  source_images: string[];
  _review: string[];
}

export interface GoldCase {
  /** File stem, e.g. "dense-bean-salad". */
  id: string;
  gold: GoldRecipe;
}

const GOLD_DIR = new URL("../datasets/extraction/gold/", import.meta.url);

/** Loads every gold/<recipe>.json (skips the _SCHEMA / _INDEX markdown). */
export async function loadGold(): Promise<GoldCase[]> {
  const cases: GoldCase[] = [];
  for await (const entry of Deno.readDir(GOLD_DIR)) {
    if (!entry.isFile || !entry.name.endsWith(".json")) continue;
    const text = await Deno.readTextFile(new URL(entry.name, GOLD_DIR));
    const gold = JSON.parse(text) as GoldRecipe;
    cases.push({ id: entry.name.replace(/\.json$/, ""), gold });
  }
  cases.sort((a, b) => a.id.localeCompare(b.id));
  return cases;
}

// --- printed-amount rendering ------------------------------------------------

/**
 * Unit id → the word a cookbook actually prints. Used ONLY for the handful of
 * gold lines that carry no `raw_amount` (the printed phrase is the preferred
 * source); rendering the normalized id itself would hand the model the answer
 * ("1 piece cucumber" is not English, and it leaks our unit vocabulary).
 * `piece` maps to the empty string on purpose — a counted produce line prints
 * as a bare number ("1 red bell pepper").
 */
const PRINTED_UNIT: Record<string, [singular: string, plural: string]> = {
  g: ["g", "g"],
  kg: ["kg", "kg"],
  mg: ["mg", "mg"],
  oz: ["oz", "oz"],
  lb: ["lb", "lb"],
  ml: ["ml", "ml"],
  l: ["l", "l"],
  tsp: ["teaspoon", "teaspoons"],
  tbsp: ["tablespoon", "tablespoons"],
  fl_oz: ["fl oz", "fl oz"],
  cup: ["cup", "cups"],
  pt: ["pint", "pints"],
  qt: ["quart", "quarts"],
  piece: ["", ""],
  clove: ["clove", "cloves"],
  head: ["head", "heads"],
  sprig: ["sprig", "sprigs"],
  loaf: ["loaf", "loaves"],
  block: ["block", "blocks"],
  slice: ["slice", "slices"],
  can: ["can", "cans"],
  bunch: ["bunch", "bunches"],
  stalk: ["stalk", "stalks"],
  handful: ["handful", "handfuls"],
  pinch: ["pinch", "pinches"],
  dash: ["dash", "dashes"],
};

function unitWord(unit: string | null, qty: number | null): string {
  if (!unit) return "";
  const pair = PRINTED_UNIT[unit];
  if (!pair) return unit; // an unmapped word is already the printed word
  return (qty !== null && qty > 1 ? pair[1] : pair[0]);
}

function numText(n: number): string {
  return Number.isInteger(n) ? String(n) : String(n);
}

/**
 * The printed amount phrase for a line. Prefers the verbatim `raw_amount`; only
 * when that is absent does it reconstruct printed-style prose from qty/unit —
 * and it returns "" (the caller omits the amount entirely) rather than emit a
 * normalized token like "1 piece", which would leak the structured answer into
 * the D2 input.
 */
export function printedAmount(li: {
  qty: number | null;
  qty_low: number | null;
  qty_high: number | null;
  unit: string | null;
  raw_amount: string | null;
}): string {
  const raw = (li.raw_amount ?? "").trim();
  if (raw !== "") return raw;
  const word = (q: number | null) => unitWord(li.unit, q);
  if (li.qty_low !== null && li.qty_high !== null) {
    const w = word(li.qty_high);
    return `${numText(li.qty_low)} to ${numText(li.qty_high)}${
      w ? " " + w : ""
    }`;
  }
  if (li.qty !== null) {
    const w = word(li.qty);
    return `${numText(li.qty)}${w ? " " + w : ""}`;
  }
  // No number printed. A bare imprecise/measure word is still page text ("a
  // pinch"); a bare canonical unit id is not, so drop it.
  const w = word(null);
  return w && !["g", "kg", "mg", "oz", "lb", "ml", "l"].includes(li.unit ?? "")
    ? w
    : "";
}

/** Lowercased alphanumeric word list — the double-print guard's comparison basis. */
function wordSet(s: string): Set<string> {
  return new Set(
    s.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean),
  );
}

/** Crude suffix stem, enough to see "juice" and "juiced" as the same word. */
export function stem(w: string): string {
  return w.replace(/(ing|ed|es|s|d)$/u, "").replace(/e$/u, "");
}

function stemSet(s: string): Set<string> {
  return new Set([...wordSet(s)].map(stem));
}

function timeToText(t: TimeField): string | null {
  if (t === null) return null;
  const fmt = (s: number) => `${Math.round(s / 60)} minutes`;
  if (typeof t === "number") return fmt(t);
  if (t.low_seconds === t.high_seconds) return fmt(t.low_seconds);
  return `${Math.round(t.low_seconds / 60)} to ${
    Math.round(t.high_seconds / 60)
  } minutes`;
}

function tokenToText(tok: StepToken): string {
  switch (tok.t) {
    case "text":
      return tok.s;
    case "ref":
      return tok.label;
    case "timer": {
      if (tok.low_seconds === tok.high_seconds) {
        return `${Math.round(tok.low_seconds / 60)} minutes`;
      }
      return `${Math.round(tok.low_seconds / 60)} to ${
        Math.round(tok.high_seconds / 60)
      } minutes`;
    }
  }
}

/**
 * Renders ONE ingredient line back into the phrase a page would print:
 * `<amount> <identity>[ (optional)][, <notes>]`.
 *
 * Three things this deliberately does:
 * - **Emits `notes`.** The cook-prep half of the line ("destemmed and roughly
 *   chopped", "juiced", "for garnish") is ~a third of the gold's line content.
 *   Leaving it out meant the model was never shown the text it is graded on
 *   splitting out, so `notes` could not be scored at all.
 * - **No double-print.** When the printed amount already contains the identity
 *   ("Juice of 1 lemon" + identity "lemon"), the identity is not appended again
 *   — the old renderer emitted "Juice of 1 lemon lemon".
 * - **No normalized-token leak.** A line with no `raw_amount` reconstructs
 *   printed prose via {@link printedAmount}, never "1 piece".
 */
export function goldLineToText(li: {
  qty: number | null;
  qty_low: number | null;
  qty_high: number | null;
  unit: string | null;
  ingredient_text: string;
  notes: string | null;
  raw_amount: string | null;
  optional: boolean;
}): string {
  const amount = printedAmount(li);
  const ident = li.ingredient_text.trim();
  // Identity already spelled out inside the printed amount ⇒ don't repeat it.
  const amountWords = wordSet(amount);
  const identWords = [...wordSet(ident)];
  const swallowed = identWords.length > 0 &&
    identWords.every((w) => amountWords.has(w));
  const head = swallowed ? amount : `${amount ? amount + " " : ""}${ident}`;
  const opt = li.optional ? " (optional)" : "";
  // Emit each notes fragment, minus any the printed head already says (a page
  // that prints "Juice of 1 lemon" does not then print ", juiced").
  const headStems = stemSet(head);
  const kept = (li.notes ?? "")
    .split(/\s*;\s*/u)
    .map((f) => f.trim())
    .filter((f) => f !== "")
    .filter((f) => ![...stemSet(f)].every((w) => headStems.has(w)));
  const notes = kept.length > 0 ? `, ${kept.join("; ")}` : "";
  return `${head}${opt}${notes}`.trim();
}

/**
 * Renders a gold recipe back into a faithful plain-text page — the D2 input.
 * Uses `raw_amount` (verbatim printed amount) so the model must re-derive the
 * structured qty/unit itself, exactly as it would from a real page.
 */
export function goldToSourceText(gold: GoldRecipe): string {
  const lines: string[] = [gold.title, ""];
  if (gold.servings_raw) lines.push(gold.servings_raw);
  if (gold.yield_raw) lines.push(gold.yield_raw);
  const total = timeToText(gold.total_time_seconds);
  if (total) lines.push(`TOTAL TIME: ${total}`);
  const cook = timeToText(gold.cook_time_seconds);
  if (cook) lines.push(`COOK TIME: ${cook}`);
  lines.push("", "INGREDIENTS");
  for (const group of gold.groups) {
    if (group.name) lines.push("", group.name);
    for (const li of group.line_items) lines.push(goldLineToText(li));
  }
  lines.push("", "METHOD");
  gold.steps.forEach((step, i) => {
    const prose = step.tokens.map(tokenToText).join("");
    lines.push(`${i + 1}. ${prose}`);
  });
  if (gold.truncated) lines.push("", "[PAGE CONTINUES — method truncated]");
  return lines.join("\n");
}

/** The D2 RawBlob for a gold case (reconstructed page text). */
export function goldToBlob(gold: GoldRecipe): RawBlob {
  return {
    source: "page_text",
    url: null,
    jsonld: null,
    text: goldToSourceText(gold),
  };
}
