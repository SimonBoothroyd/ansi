// Intake: URL → RawBlob (§3, §4.1). The deterministic, LLM-free front of the
// pipeline. Fetches a page, reads every schema.org/Recipe JSON-LD block, and
// hands the sanitize stage a `RawBlob` — the structured recipe object when the
// page publishes one, or the page's visible text as a fallback.
//
// PORTED from supabase/seed/scripts/mine_recipes.ts (`extractIngredientLines` /
// `collectRecipes`): the same block scan and @graph walk that the seed miner
// proved on the real recipe_urls.txt set. The difference is the output — the
// seed miner pulls `recipeIngredient` lines; here we keep the WHOLE Recipe
// object, because ① sanitize (an LLM, always — 0014 decision log) consumes the
// structured blob, not pre-parsed lines. A parity test pins the block scan to
// the miner's on a shared fixture.
//
// One forced LLM path (0014): JSON-LD is a cheaper *input* to the shared
// pipeline, never an LLM-free bypass. So this stage only ever produces a
// `RawBlob` — it does no ingredient parsing, no matching, no invention.
//
// Pure/deterministic given the HTML: `buildRawBlob(html, url)` has no I/O.
// `fetchRawBlob(url)` is the thin network wrapper (fetch is injectable so the
// whole module stays offline-testable).

import type { RawBlob } from "./types.ts";

/**
 * Scans an HTML document for every schema.org/Recipe JSON-LD block and returns
 * the raw Recipe objects, in document order. Malformed blocks are skipped (a
 * later block may still parse) — never throws. Ported from mine_recipes.ts.
 */
export function extractRecipeObjects(html: string): Record<string, unknown>[] {
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
  return recipes;
}

/** Recursively collects Recipe nodes, walking `@graph` and arrays (mine_recipes.ts). */
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

/**
 * Builds the intake {@link RawBlob} from a page's HTML. Deterministic — no I/O.
 *
 * - First schema.org/Recipe JSON-LD block found → `source: "jsonld"` carrying
 *   that Recipe object. (A page rarely has more than one true Recipe; when it
 *   does, the first in document order wins — the contract's `jsonld` holds a
 *   single object, and sanitize reads one recipe.)
 * - No usable JSON-LD → `source: "page_text"` carrying the page's visible text,
 *   the `needs_fallback` path ① still handles (0014: JSON-LD is an input, not a
 *   gate — a page without it is not an error, just the text tier).
 */
export function buildRawBlob(html: string, url: string | null): RawBlob {
  const recipes = extractRecipeObjects(html);
  if (recipes.length > 0) {
    return { source: "jsonld", url, jsonld: recipes[0], text: null };
  }
  return { source: "page_text", url, jsonld: null, text: htmlToText(html) };
}

/**
 * Strips an HTML document to its visible text: drops `<script>`/`<style>`
 * bodies, unwraps remaining tags, decodes the handful of entities that matter,
 * and collapses whitespace. Good enough to feed ① as the page_text fallback —
 * not a full DOM parse (the model tolerates noise; never-invent means we pass
 * text through, we don't reconstruct structure here).
 */
export function htmlToText(html: string): string {
  const stripped = html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ");
  return decodeEntities(stripped).replace(/\s+/g, " ").trim();
}

const NAMED_ENTITIES: Record<string, string> = {
  "&amp;": "&",
  "&lt;": "<",
  "&gt;": ">",
  "&quot;": '"',
  "&#39;": "'",
  "&apos;": "'",
  "&nbsp;": " ",
};

function decodeEntities(s: string): string {
  return s
    .replace(/&#(\d+);/g, (_m, code) => String.fromCodePoint(Number(code)))
    .replace(
      /&#x([0-9a-f]+);/gi,
      (_m, code) => String.fromCodePoint(parseInt(code, 16)),
    )
    .replace(
      /&[a-z]+;|&#39;/gi,
      (m) => NAMED_ENTITIES[m.toLowerCase()] ?? m,
    );
}

/** Fetch impl seam — the global `fetch` in prod, a stub in tests. */
export type FetchFn = (url: string) => Promise<Response>;

/**
 * Fetches a URL and builds its {@link RawBlob}. `fetchImpl` is injectable so the
 * module stays offline-testable; production passes the global `fetch`.
 *
 * A non-OK response or a network error falls back to a text blob with whatever
 * body arrived (empty on a hard failure) rather than throwing — the orchestrator
 * decides how to surface an unusable page; intake stays total.
 */
export async function fetchRawBlob(
  url: string,
  fetchImpl: FetchFn = fetch,
): Promise<RawBlob> {
  let html = "";
  try {
    const res = await fetchImpl(url);
    html = await res.text();
  } catch {
    html = "";
  }
  return buildRawBlob(html, url);
}
