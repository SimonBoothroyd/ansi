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

// The unit hints, mirrored from app/lib/core/units/units.dart (the single
// source of the unit system). This is the eval's own copy of the hint set —
// lane A owns the server-side `unit_hints.ts`; the adapter takes hints as a
// parameter, so the two never need to import each other.
export const UNIT_HINTS: UnitHints = {
  units: [
    "g",
    "kg",
    "mg",
    "oz",
    "lb",
    "ml",
    "l",
    "tsp",
    "tbsp",
    "fl_oz",
    "cup",
    "piece",
  ],
  imprecise: [
    "pinch",
    "dash",
    "to_taste",
    "handful",
    "splash",
    "drizzle",
    "glug",
  ],
  size_words: ["large", "medium", "small"],
  measures: [
    "clove",
    "head",
    "sprig",
    "loaf",
    "block",
    "slice",
    "can",
    "bunch",
    "stalk",
  ],
};

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
    for (const li of group.line_items) {
      const amount = li.raw_amount && li.raw_amount.trim() !== ""
        ? li.raw_amount
        : [li.qty ?? "", li.unit ?? ""].join(" ").trim();
      const opt = li.optional ? " (optional)" : "";
      lines.push(
        `${amount ? amount + " " : ""}${li.ingredient_text}${opt}`.trim(),
      );
    }
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
