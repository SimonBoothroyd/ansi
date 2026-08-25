// Household-vocabulary seed miner (roadmap step 1; scoped in the import doc §7).
//
// Deterministic, offline-in-spirit tool: fetch recipe URLs, read their
// schema.org/Recipe JSON-LD, split ingredient lines into {qty, unit, text},
// normalize each to match_text with the SHARED normalizer (so the seed and the
// live cascade agree), then dedup into candidate vocabulary. No LLM — JSON-LD is
// structured, so the extraction model never runs here (import doc §4.1).
//
// Inputs:  recipe_urls.txt (one URL per line; # comments ignored).
// Outputs: out/vocab_candidates.csv   deduped review table → curate into seed.sql
//          out/gold_labels.jsonl      every raw_line → {qty, unit, match_text}
//          out/needs_fallback.txt     URLs with missing/malformed JSON-LD
//          out/parse_failures.jsonl   lines the parser couldn't split, + reason
//          out/ambiguous_pairs.txt    near-duplicate match_text to eyeball
// Plus a coverage report to stdout.
//
// Run:  deno task mine   (from supabase/seed/scripts)
//
// The raw → canonical trail is the gold set: raw strings are never discarded.

import { normalize } from "../../functions/_shared/normalize.ts";

// --- Types -------------------------------------------------------------------

interface GoldLabel {
  url: string;
  raw: string;
  qty: number | null;
  qty_high: number | null; // set when the line gave a range (2–3)
  unit: string | null; // a units.dart id, or null when none/unknown
  ingredient_text: string;
  match_text: string;
  flags: string[]; // range | no_qty | parenthetical | to_taste
}

interface ParseFailure {
  url: string;
  raw: string;
  reason: string;
}

interface Candidate {
  match_text: string;
  canonical_name: string; // best-guess surface form; the human finalizes
  category: string; // best-guess; may be ""
  default_unit: string; // modal unit id in the group; may be ""
  aliases: string[]; // distinct raw surface forms
  source_urls: string[];
  count: number;
}

// --- Ingredient-line parsing -------------------------------------------------

/** Unicode vulgar fractions → ascii, so "1½" becomes "1 1/2". */
const UNICODE_FRACTIONS: Record<string, string> = {
  "¼": "1/4",
  "½": "1/2",
  "¾": "3/4",
  "⅓": "1/3",
  "⅔": "2/3",
  "⅕": "1/5",
  "⅖": "2/5",
  "⅗": "3/5",
  "⅘": "4/5",
  "⅙": "1/6",
  "⅚": "5/6",
  "⅐": "1/7",
  "⅛": "1/8",
  "⅜": "3/8",
  "⅝": "5/8",
  "⅞": "7/8",
  "⅑": "1/9",
  "⅒": "1/10",
};

/**
 * Measure/unit words → a units.dart id (or a count/imprecise id). Unknown words
 * are simply not consumed as units — match_text is salvaged by normalize()
 * either way, so this only needs to be good enough for qty/unit + default_unit.
 */
const UNIT_LEXICON: Record<string, string> = {
  g: "g",
  gram: "g",
  grams: "g",
  gr: "g",
  kg: "kg",
  kilogram: "kg",
  kilograms: "kg",
  kilo: "kg",
  mg: "mg",
  oz: "oz",
  ounce: "oz",
  ounces: "oz",
  lb: "lb",
  lbs: "lb",
  pound: "lb",
  pounds: "lb",
  ml: "ml",
  milliliter: "ml",
  milliliters: "ml",
  millilitre: "ml",
  millilitres: "ml",
  l: "l",
  liter: "l",
  liters: "l",
  litre: "l",
  litres: "l",
  tsp: "tsp",
  teaspoon: "tsp",
  teaspoons: "tsp",
  tbsp: "tbsp",
  tbs: "tbsp",
  tablespoon: "tbsp",
  tablespoons: "tbsp",
  cup: "cup",
  cups: "cup",
  clove: "piece",
  cloves: "piece",
  can: "piece",
  cans: "piece",
  jar: "piece",
  jars: "piece",
  slice: "piece",
  slices: "piece",
  stick: "piece",
  sticks: "piece",
  sprig: "piece",
  sprigs: "piece",
  head: "piece",
  bunch: "piece",
  package: "piece",
  packet: "piece",
  pinch: "pinch",
  dash: "dash",
};

/** Words that only ever describe amount to taste → imprecise. */
const TO_TASTE = /\b(to taste|to serve|for garnish|as needed)\b/i;

const NUM = String.raw`(?:\d+\s+\d+/\d+|\d+/\d+|\d*\.?\d+)`;
const QTY_RE = new RegExp(`^(${NUM})(?:\\s*-\\s*(${NUM}))?`);

function asciifyFractions(s: string): string {
  let out = "";
  for (const ch of s) {
    const frac = UNICODE_FRACTIONS[ch];
    if (!frac) {
      out += ch;
      continue;
    }
    if (out.length && /\d/.test(out[out.length - 1])) out += " ";
    out += frac;
  }
  return out;
}

function parseNumber(tok: string): number | null {
  const mixed = tok.match(/^(\d+)\s+(\d+)\/(\d+)$/);
  if (mixed) return +mixed[1] + +mixed[2] / +mixed[3];
  const frac = tok.match(/^(\d+)\/(\d+)$/);
  if (frac) return +frac[1] / +frac[2];
  if (/^\d*\.?\d+$/.test(tok)) return parseFloat(tok);
  return null;
}

/** Splits one raw ingredient line into structured fields (see {@link GoldLabel}). */
export function parseIngredientLine(raw: string): {
  qty: number | null;
  qty_high: number | null;
  unit: string | null;
  ingredient_text: string;
  flags: string[];
} {
  const flags: string[] = [];
  let text = asciifyFractions(raw).replace(/[–—]/g, "-").trim();

  if (/\([^)]*\)/.test(text)) {
    flags.push("parenthetical");
    text = text.replace(/\([^)]*\)/g, " ").replace(/\s+/g, " ").trim();
  }

  let unit: string | null = null;
  if (TO_TASTE.test(text)) {
    flags.push("to_taste");
    unit = "to_taste";
    text = text.replace(TO_TASTE, "").replace(/[,\s]+$/, "").trim();
  }

  const qtyMatch = text.match(QTY_RE);
  let qty: number | null = null;
  let qtyHigh: number | null = null;
  if (qtyMatch) {
    qty = parseNumber(qtyMatch[1]);
    qtyHigh = qtyMatch[2] ? parseNumber(qtyMatch[2]) : null;
    if (qtyHigh !== null) flags.push("range");
    text = text.slice(qtyMatch[0].length).trim();
  } else {
    flags.push("no_qty");
  }

  // A leading measure word becomes the unit (unless "to taste" already set one).
  const wordMatch = text.match(/^([a-zA-Z]+)\.?\b/);
  if (wordMatch) {
    const id = UNIT_LEXICON[wordMatch[1].toLowerCase()];
    if (id) {
      if (unit === null) unit = id;
      text = text.slice(wordMatch[0].length).replace(/^\s*of\b/i, "").trim();
    }
  }

  return { qty, qty_high: qtyHigh, unit, ingredient_text: text.trim(), flags };
}

// --- JSON-LD extraction ------------------------------------------------------

/** Pulls ingredient lines from every schema.org/Recipe in an HTML document. */
export function extractIngredientLines(
  html: string,
): { found: boolean; lines: string[] } {
  // The type value may be quoted or bare (HTML5 allows unquoted attributes, and
  // some sites/minifiers emit `type=application/ld+json`).
  const blocks = [
    ...html.matchAll(
      /<script[^>]*type=["']?application\/ld\+json["']?[^>]*>([\s\S]*?)<\/script>/gi,
    ),
  ];
  const recipes: Record<string, unknown>[] = [];
  for (const b of blocks) {
    let data: unknown;
    try {
      data = JSON.parse(b[1].trim());
    } catch {
      continue; // malformed block; a later block may still parse
    }
    collectRecipes(data, recipes);
  }
  if (recipes.length === 0) return { found: false, lines: [] };

  const lines: string[] = [];
  for (const r of recipes) {
    const ing = r["recipeIngredient"] ?? r["ingredients"];
    if (Array.isArray(ing)) {
      for (const item of ing) if (typeof item === "string") lines.push(item);
    }
  }
  return { found: true, lines };
}

function collectRecipes(node: unknown, out: Record<string, unknown>[]): void {
  if (Array.isArray(node)) {
    for (const n of node) collectRecipes(n, out);
    return;
  }
  if (!node || typeof node !== "object") return;
  const obj = node as Record<string, unknown>;
  if (Array.isArray(obj["@graph"])) collectRecipes(obj["@graph"], out);
  const t = obj["@type"];
  const isRecipe = t === "Recipe" ||
    (Array.isArray(t) && t.includes("Recipe"));
  if (isRecipe) out.push(obj);
}

// --- Aggregation -------------------------------------------------------------

const CATEGORY_HINTS: [RegExp, string][] = [
  [/\boil\b|\bbutter\b|\bghee\b/, "fats & oils"],
  [/\bflour\b|\bsugar\b|\byeast\b|\bbaking (powder|soda)\b/, "baking"],
  [
    /\bsalt\b|\bpepper\b|\bspice\b|\bcumin\b|\bpaprika\b|\bcinnamon\b/,
    "spices & seasoning",
  ],
  [/\bchicken\b|\bbeef\b|\bpork\b|\blamb\b|\bmince\b/, "meat"],
  [/\bmilk\b|\bcream\b|\bcheese\b|\byogurt\b|\byoghurt\b/, "dairy"],
  [
    /\bonion\b|\bgarlic\b|\btomato\b|\bpepper\b|\bcarrot\b|\bginger\b/,
    "produce",
  ],
  [/\brice\b|\bpasta\b|\bnoodle\b|\bbread\b|\boat\b/, "grains"],
  [/\bstock\b|\bbroth\b|\bsauce\b|\bvinegar\b/, "pantry"],
];

function guessCategory(matchText: string): string {
  for (const [re, cat] of CATEGORY_HINTS) if (re.test(matchText)) return cat;
  return "";
}

function mode(values: string[]): string {
  const counts = new Map<string, number>();
  for (const v of values) counts.set(v, (counts.get(v) ?? 0) + 1);
  let best = "";
  let bestN = 0;
  for (const [v, n] of counts) if (n > bestN) [best, bestN] = [v, n];
  return best;
}

/** Groups gold labels by match_text into candidate vocabulary rows. */
export function aggregate(labels: GoldLabel[]): Candidate[] {
  const groups = new Map<string, GoldLabel[]>();
  for (const l of labels) {
    if (!l.match_text) continue;
    (groups.get(l.match_text) ??
      groups.set(l.match_text, []).get(l.match_text)!)
      .push(l);
  }

  const candidates: Candidate[] = [];
  for (const [match_text, ls] of groups) {
    const surfaces = ls
      .map((l) =>
        l.ingredient_text.replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, "")
      )
      .filter(Boolean);
    const units = ls.map((l) => l.unit).filter((u): u is string => !!u);
    candidates.push({
      match_text,
      // Propose the normalized form title-cased — a clean starting point the
      // human edits. The raw surface forms are preserved as aliases.
      canonical_name: titleCase(match_text),
      category: guessCategory(match_text),
      default_unit: mode(units),
      aliases: [...new Set(surfaces)],
      source_urls: [...new Set(ls.map((l) => l.url))],
      count: ls.length,
    });
  }
  candidates.sort((a, b) => b.count - a.count);
  return candidates;
}

function titleCase(s: string): string {
  // Capitalize the first letter of each word. Unicode-aware so "jalapeño"
  // becomes "Jalapeño", not "JalapeñO" (a \b\w boundary falls after "ñ").
  return s.replace(/(^|\s)(\p{L})/gu, (_m, pre, ch) => pre + ch.toUpperCase());
}

/**
 * Flags candidate pairs to eyeball — never auto-merged (spec step 5). A pair is
 * flagged when it looks like the same thing written two ways, OR the "own-goal"
 * case (near-identical text, different ingredient). Signals:
 *   - small edit distance (yogurt/yoghurt, plurals);
 *   - a shared RARE token — "coconut" links coconut milk/cream, but "oil" and
 *     "salt" are hubs in nearly every candidate, so a token in many candidates
 *     is not a signal (unfiltered, that left ~800 useless pairs);
 *   - two or more shared content tokens (black pepper vs cracked black pepper).
 * State words never count as a shared token, so it won't fire on every "fresh".
 */
export function ambiguousPairs(candidates: Candidate[]): [string, string][] {
  const STOP = new Set([
    "fresh",
    "ground",
    "dried",
    "dry",
    "frozen",
    "canned",
    "whole",
    "raw",
    "and",
    "of",
    "chopped",
    "sliced",
  ]);
  const tokens = (s: string) => [
    ...new Set(s.split(/\s+/).filter((t) => t && !STOP.has(t))),
  ];

  const keys = candidates.map((c) => c.match_text);
  const toks = keys.map(tokens);

  // Document frequency: how many candidates each token appears in.
  const df = new Map<string, number>();
  for (const ts of toks) for (const t of ts) df.set(t, (df.get(t) ?? 0) + 1);
  const RARE = 3; // a token in ≤3 candidates discriminates; more = a hub

  const pairs: [string, string][] = [];
  for (let i = 0; i < keys.length; i++) {
    for (let j = i + 1; j < keys.length; j++) {
      const shared = toks[i].filter((t) => toks[j].includes(t));
      const rareShare = shared.some((t) => (df.get(t) ?? 0) <= RARE);
      if (
        rareShare || shared.length >= 2 || editDistance(keys[i], keys[j]) <= 1
      ) {
        pairs.push([keys[i], keys[j]]);
      }
    }
  }
  return pairs;
}

function editDistance(a: string, b: string): number {
  const dp = Array.from({ length: a.length + 1 }, (_, i) => i);
  for (let j = 1; j <= b.length; j++) {
    let prev = dp[0];
    dp[0] = j;
    for (let i = 1; i <= a.length; i++) {
      const tmp = dp[i];
      dp[i] = a[i - 1] === b[j - 1]
        ? prev
        : 1 + Math.min(prev, dp[i], dp[i - 1]);
      prev = tmp;
    }
  }
  return dp[a.length];
}

// --- Runner ------------------------------------------------------------------

function readUrls(path: string): string[] {
  return Deno.readTextFileSync(path)
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("#"));
}

function csvCell(s: string): string {
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

async function main(): Promise<void> {
  const scriptDir = new URL(".", import.meta.url).pathname;
  const urls = readUrls(scriptDir + "recipe_urls.txt");
  if (urls.length === 0) {
    console.error(
      "No URLs in recipe_urls.txt — paste some recipe links and re-run.",
    );
    Deno.exit(1);
  }

  const gold: GoldLabel[] = [];
  const failures: ParseFailure[] = [];
  const needsFallback: string[] = [];
  let jsonldHits = 0;

  for (const url of urls) {
    let html: string;
    try {
      const res = await fetch(url, {
        headers: {
          "user-agent": "mise-seed-miner/0.1 (+household vocab seed)",
        },
      });
      if (!res.ok) {
        needsFallback.push(`${url}\thttp ${res.status}`);
        continue;
      }
      html = await res.text();
    } catch (e) {
      needsFallback.push(`${url}\tfetch error: ${(e as Error).message}`);
      continue;
    }

    const { found, lines } = extractIngredientLines(html);
    if (!found) {
      needsFallback.push(`${url}\tno schema.org/Recipe JSON-LD`);
      continue;
    }
    jsonldHits++;

    for (const raw of lines) {
      const p = parseIngredientLine(raw);
      if (!p.ingredient_text) {
        failures.push({
          url,
          raw,
          reason: "empty ingredient_text after parse",
        });
        continue;
      }
      gold.push({ url, raw, ...p, match_text: normalize(p.ingredient_text) });
    }
    await new Promise((r) => setTimeout(r, 400)); // be a polite fetcher
  }

  const candidates = aggregate(gold);
  const pairs = ambiguousPairs(candidates);

  const outDir = scriptDir + "out";
  Deno.mkdirSync(outDir, { recursive: true });
  const w = (name: string, body: string) =>
    Deno.writeTextFileSync(`${outDir}/${name}`, body);

  w(
    "vocab_candidates.csv",
    "canonical_name,match_text,category,default_unit,aliases,source_urls,count\n" +
      candidates.map((c) =>
        [
          c.canonical_name,
          c.match_text,
          c.category,
          c.default_unit,
          c.aliases.join("; "),
          c.source_urls.join("; "),
          String(c.count),
        ].map(csvCell).join(",")
      ).join("\n") + "\n",
  );
  w("gold_labels.jsonl", gold.map((g) => JSON.stringify(g)).join("\n") + "\n");
  w("needs_fallback.txt", needsFallback.join("\n") + "\n");
  w(
    "parse_failures.jsonl",
    failures.map((f) => JSON.stringify(f)).join("\n") + "\n",
  );
  w("ambiguous_pairs.txt", pairs.map((p) => p.join("  ~  ")).join("\n") + "\n");

  const totalLines = gold.length + failures.length;
  const flagged = gold.filter((g) => g.flags.length).length + failures.length;
  console.log("── coverage ──────────────────────────────────────────────");
  console.log(`URLs processed:        ${urls.length}`);
  console.log(
    `JSON-LD hit rate:      ${jsonldHits}/${urls.length}` +
      ` (${needsFallback.length} → needs_fallback)`,
  );
  console.log(`Ingredient lines:      ${totalLines}`);
  console.log(`Unique candidates:     ${candidates.length}`);
  console.log(`Parse failures:        ${failures.length}`);
  console.log(
    `Lines flagged:         ${flagged}/${totalLines}` +
      ` (${totalLines ? ((flagged / totalLines) * 100).toFixed(1) : "0"}%)`,
  );
  console.log(`Ambiguous pairs:       ${pairs.length}`);
  console.log(`\nWrote 5 files to ${outDir}/`);
}

if (import.meta.main) await main();
