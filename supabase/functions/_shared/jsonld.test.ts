import { assertEquals } from "@std/assert";
import {
  buildRawBlob,
  extractRecipeObjects,
  fetchRawBlob,
  htmlToText,
} from "./jsonld.ts";
// Parity anchor: the seed miner's proven block scanner (a separate deno project,
// imported by relative path). Both must agree on which Recipe a page publishes.
import { extractIngredientLines } from "../../seed/scripts/mine_recipes.ts";

// --- Fixtures (inline HTML — deterministic, offline; no saved files) ----------

const PLAIN_RECIPE = `<!doctype html><html><head>
  <title>Weeknight Chicken Curry</title>
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"Recipe",
   "name":"Weeknight Chicken Curry",
   "recipeYield":"4 servings",
   "recipeIngredient":["900 g chicken thighs, boneless","1 can coconut milk","2 onions"]}
  </script></head><body><h1>Curry</h1></body></html>`;

// A Recipe nested in an @graph, with @type as an array — the common CMS shape.
const GRAPH_RECIPE = `<html><head>
  <script type=application/ld+json>
  {"@graph":[
    {"@type":"WebPage","name":"page"},
    {"@type":["Recipe","NewsArticle"],"name":"Dense Bean Salad",
     "recipeIngredient":["2.5 x 400 g cans mixed beans","1 red bell pepper"]}
  ]}
  </script></head><body>body</body></html>`;

// No JSON-LD at all — the needs_fallback → page_text path.
const NO_JSONLD = `<html><head><title>Just a page</title>
  <style>.x{color:red}</style></head>
  <body><h1>Grandma&#39;s Soup</h1>
  <p>Simmer onions &amp; garlic for 20 minutes.</p>
  <script>console.log("ignore me")</script></body></html>`;

// Only a malformed JSON-LD block — must fall back to page_text, never throw.
const MALFORMED_JSONLD = `<html><head>
  <script type="application/ld+json">{ not valid json </script>
  </head><body><p>Fallback body text.</p></body></html>`;

Deno.test("extractRecipeObjects — plain Recipe and @graph array-typed", () => {
  const plain = extractRecipeObjects(PLAIN_RECIPE);
  assertEquals(plain.length, 1);
  assertEquals(plain[0]["name"], "Weeknight Chicken Curry");

  const graph = extractRecipeObjects(GRAPH_RECIPE);
  assertEquals(graph.length, 1);
  assertEquals(graph[0]["name"], "Dense Bean Salad");
});

Deno.test("extractRecipeObjects — malformed block yields no recipe, no throw", () => {
  assertEquals(extractRecipeObjects(MALFORMED_JSONLD), []);
  assertEquals(extractRecipeObjects(NO_JSONLD), []);
});

Deno.test("buildRawBlob — Recipe JSON-LD → source jsonld", () => {
  const blob = buildRawBlob(PLAIN_RECIPE, "https://example.test/curry");
  assertEquals(blob.source, "jsonld");
  assertEquals(blob.url, "https://example.test/curry");
  assertEquals(blob.text, null);
  assertEquals(blob.jsonld?.["name"], "Weeknight Chicken Curry");
  assertEquals(
    (blob.jsonld?.["recipeIngredient"] as string[]).length,
    3,
  );
});

Deno.test("buildRawBlob — no JSON-LD → source page_text (needs_fallback)", () => {
  const blob = buildRawBlob(NO_JSONLD, "https://example.test/soup");
  assertEquals(blob.source, "page_text");
  assertEquals(blob.jsonld, null);
  // Script/style bodies are dropped; entities decoded; whitespace collapsed.
  assertEquals(blob.text?.includes("Grandma's Soup"), true);
  assertEquals(blob.text?.includes("onions & garlic"), true);
  assertEquals(blob.text?.includes("console.log"), false);
  assertEquals(blob.text?.includes("color:red"), false);
});

Deno.test("buildRawBlob — malformed JSON-LD falls back to page_text", () => {
  const blob = buildRawBlob(MALFORMED_JSONLD, null);
  assertEquals(blob.source, "page_text");
  assertEquals(blob.text?.includes("Fallback body text."), true);
});

Deno.test("htmlToText — decodes numeric + hex entities", () => {
  assertEquals(htmlToText("<p>caf&#233; &#x26; co</p>"), "café & co");
});

Deno.test("fetchRawBlob — injectable fetch, offline", async () => {
  const stub = (_url: string) => Promise.resolve(new Response(PLAIN_RECIPE));
  const blob = await fetchRawBlob("https://example.test/curry", stub);
  assertEquals(blob.source, "jsonld");
  assertEquals(blob.jsonld?.["name"], "Weeknight Chicken Curry");
});

Deno.test("fetchRawBlob — network error falls back to empty page_text", async () => {
  const boom = (_url: string) => Promise.reject(new Error("offline"));
  const blob = await fetchRawBlob("https://example.test/down", boom);
  assertEquals(blob.source, "page_text");
  assertEquals(blob.text, "");
});

Deno.test("PARITY — recipe scan matches mine_recipes.ts on a shared fixture", () => {
  // Same block scan, different projection: the seed miner pulls recipeIngredient
  // lines; this module keeps the whole object. On a shared fixture the ingredient
  // lines the two derive must be identical.
  for (const html of [PLAIN_RECIPE, GRAPH_RECIPE]) {
    const mine = extractIngredientLines(html); // seed miner
    const ours = extractRecipeObjects(html)
      .flatMap((r) => (r["recipeIngredient"] as string[]) ?? []);
    assertEquals(mine.found, true);
    assertEquals(ours, mine.lines);
  }
});
