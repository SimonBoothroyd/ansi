import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "@std/assert";
import {
  buildRawBlob,
  extractRecipeObjects,
  type FetchFn,
  fetchRawBlob,
  htmlToText,
  isPrivateIpv4,
  isPrivateIpv6,
  MAX_BODY_BYTES,
  MAX_REDIRECTS,
  MAX_TEXT_CHARS,
} from "./jsonld.ts";
import { ImportError } from "./errors.ts";
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

// --- fetchRawBlob: the hardened network front ---------------------------------
// Both I/O seams are injected, so none of this touches the network or DNS.

const HTML = { "content-type": "text/html; charset=utf-8" };
/** A resolver that says every hostname is one public address. */
const publicDns = (_h: string) => Promise.resolve(["93.184.216.34"]);
const html = (body: string, init: ResponseInit = {}) =>
  new Response(body, { headers: HTML, ...init });

function stubFetch(
  responses: Response[] | ((url: string) => Response),
): { fetchImpl: FetchFn; urls: string[] } {
  const urls: string[] = [];
  let i = 0;
  const fetchImpl: FetchFn = (url) => {
    urls.push(url);
    const res = Array.isArray(responses) ? responses[i++] : responses(url);
    return Promise.resolve(res);
  };
  return { fetchImpl, urls };
}

const importErrorFrom = async (p: Promise<unknown>): Promise<ImportError> => {
  const e = await assertRejects(() => p, ImportError);
  return e as ImportError;
};

Deno.test("fetchRawBlob — injectable fetch + DNS, offline", async () => {
  const { fetchImpl, urls } = stubFetch(() => html(PLAIN_RECIPE));
  const blob = await fetchRawBlob("https://example.test/curry", {
    fetchImpl,
    resolve: publicDns,
  });
  assertEquals(blob.source, "jsonld");
  assertEquals(blob.jsonld?.["name"], "Weeknight Chicken Curry");
  assertEquals(urls, ["https://example.test/curry"]);
});

Deno.test("fetchRawBlob — a network error is a 422, not an empty blob", async () => {
  // The old behaviour swallowed this into `text: ""` and billed the LLM for it.
  const boom: FetchFn = () => Promise.reject(new Error("offline"));
  const e = await importErrorFrom(
    fetchRawBlob("https://example.test/down", {
      fetchImpl: boom,
      resolve: publicDns,
    }),
  );
  assertStringIncludes(e.message, "could not reach that site");
});

Deno.test("fetchRawBlob — a blocking 403 says so instead of returning nothing", async () => {
  const { fetchImpl } = stubFetch(() =>
    html("<html>Are you a robot?</html>", { status: 403 })
  );
  const e = await importErrorFrom(
    fetchRawBlob("https://example.test/x", { fetchImpl, resolve: publicDns }),
  );
  assertStringIncludes(e.message, "blocked the fetch");
  assertStringIncludes(e.message, "403");
});

Deno.test("fetchRawBlob — a 404 is a readable failure too", async () => {
  const { fetchImpl } = stubFetch(() => html("nope", { status: 404 }));
  const e = await importErrorFrom(
    fetchRawBlob("https://example.test/x", { fetchImpl, resolve: publicDns }),
  );
  assertStringIncludes(e.message, "404");
});

Deno.test("fetchRawBlob — requires https", async () => {
  const { fetchImpl, urls } = stubFetch(() => html(PLAIN_RECIPE));
  for (const url of ["http://example.test/x", "file:///etc/passwd"]) {
    const e = await importErrorFrom(
      fetchRawBlob(url, { fetchImpl, resolve: publicDns }),
    );
    assertStringIncludes(e.message, "https://");
  }
  assertEquals(urls, []); // never dialled
});

Deno.test("fetchRawBlob — rejects a garbage address before any I/O", async () => {
  const { fetchImpl, urls } = stubFetch(() => html(PLAIN_RECIPE));
  await assertRejects(
    () => fetchRawBlob("not a url", { fetchImpl, resolve: publicDns }),
    ImportError,
    "web address",
  );
  assertEquals(urls, []);
});

Deno.test("fetchRawBlob — refuses private, loopback and metadata targets", async () => {
  const { fetchImpl, urls } = stubFetch(() => html(PLAIN_RECIPE));
  const blocked = [
    "https://127.0.0.1/x",
    "https://localhost/x",
    "https://10.0.0.5/x",
    "https://192.168.1.1/x",
    "https://172.16.9.9/x",
    "https://169.254.169.254/latest/meta-data/", // the cloud metadata endpoint
    "https://metadata.google.internal/x",
    "https://[::1]/x",
    "https://[fd00::1]/x",
    "https://kubernetes.default.local/x",
  ];
  for (const url of blocked) {
    await assertRejects(
      () => fetchRawBlob(url, { fetchImpl, resolve: publicDns }),
      ImportError,
      "not a public web page",
      `expected ${url} to be refused`,
    );
  }
  assertEquals(urls, []); // not one of them was dialled
});

Deno.test("fetchRawBlob — refuses a public NAME that resolves privately", async () => {
  // DNS rebinding: the hostname is fine, the address it points at is not.
  const { fetchImpl, urls } = stubFetch(() => html(PLAIN_RECIPE));
  const rebind = (_h: string) => Promise.resolve(["169.254.169.254"]);
  await assertRejects(
    () => fetchRawBlob("https://evil.test/x", { fetchImpl, resolve: rebind }),
    ImportError,
    "not a public web page",
  );
  assertEquals(urls, []);
});

Deno.test("fetchRawBlob — fails closed when a name resolves to nothing", async () => {
  const { fetchImpl } = stubFetch(() => html(PLAIN_RECIPE));
  await assertRejects(
    () =>
      fetchRawBlob("https://nowhere.test/x", {
        fetchImpl,
        resolve: () => Promise.resolve([]),
      }),
    ImportError,
    "could not resolve",
  );
});

Deno.test("fetchRawBlob — follows a redirect, re-validating each hop", async () => {
  const { fetchImpl, urls } = stubFetch([
    new Response(null, {
      status: 301,
      headers: { location: "https://example.test/final" },
    }),
    html(PLAIN_RECIPE),
  ]);
  const blob = await fetchRawBlob("https://example.test/start", {
    fetchImpl,
    resolve: publicDns,
  });
  assertEquals(blob.source, "jsonld");
  assertEquals(urls, [
    "https://example.test/start",
    "https://example.test/final",
  ]);
});

Deno.test("fetchRawBlob — a redirect INTO the private range is refused", async () => {
  const { fetchImpl, urls } = stubFetch([
    new Response(null, {
      status: 302,
      headers: { location: "https://169.254.169.254/latest/meta-data/" },
    }),
    html(PLAIN_RECIPE),
  ]);
  await assertRejects(
    () =>
      fetchRawBlob("https://example.test/start", {
        fetchImpl,
        resolve: publicDns,
      }),
    ImportError,
    "not a public web page",
  );
  assertEquals(urls, ["https://example.test/start"]); // stopped at the hop
});

Deno.test("fetchRawBlob — bounded redirect budget", async () => {
  let n = 0;
  const { fetchImpl } = stubFetch(() =>
    new Response(null, {
      status: 302,
      headers: { location: `https://example.test/hop${++n}` },
    })
  );
  await assertRejects(
    () =>
      fetchRawBlob("https://example.test/start", {
        fetchImpl,
        resolve: publicDns,
      }),
    ImportError,
    "redirected too many times",
  );
  assertEquals(n, MAX_REDIRECTS + 1);
});

Deno.test("fetchRawBlob — rejects non-HTML content types", async () => {
  for (const type of ["application/pdf", "image/jpeg", "application/json"]) {
    const { fetchImpl } = stubFetch(() =>
      new Response("x", { headers: { "content-type": type } })
    );
    const e = await importErrorFrom(
      fetchRawBlob("https://example.test/x", { fetchImpl, resolve: publicDns }),
    );
    assertStringIncludes(e.message, "not a web page");
  }
});

Deno.test("fetchRawBlob — an empty 200 is a failure, not an empty blob", async () => {
  const { fetchImpl } = stubFetch(() => html("   "));
  await assertRejects(
    () =>
      fetchRawBlob("https://example.test/x", { fetchImpl, resolve: publicDns }),
    ImportError,
    "came back empty",
  );
});

Deno.test("fetchRawBlob — stops reading past the body cap", async () => {
  // A page that keeps streaming: we must not buffer it all.
  const chunk = new TextEncoder().encode("<p>" + "x".repeat(50_000) + "</p>");
  let served = 0;
  const body = new ReadableStream<Uint8Array>({
    pull(controller) {
      served += chunk.length;
      if (served > MAX_BODY_BYTES * 4) return controller.close();
      controller.enqueue(chunk);
    },
  });
  const { fetchImpl } = stubFetch(() => new Response(body, { headers: HTML }));
  const blob = await fetchRawBlob("https://example.test/huge", {
    fetchImpl,
    resolve: publicDns,
  });
  assertEquals(blob.source, "page_text");
  // Bounded by the cap plus the chunk in flight (streams pull ahead by one).
  assert(served <= MAX_BODY_BYTES + 2 * chunk.length, `read ${served} bytes`);
  // …and what survives is capped again before it can reach a prompt.
  assert((blob.text?.length ?? 0) <= MAX_TEXT_CHARS);
});

Deno.test("buildRawBlob — page text is capped for the prompt", () => {
  const huge = `<html><body><p>${"word ".repeat(60_000)}</p></body></html>`;
  const blob = buildRawBlob(huge, null);
  assertEquals(blob.text?.length, MAX_TEXT_CHARS);
});

Deno.test("private-address classification — the ranges that matter", () => {
  for (
    const ip of [
      "0.0.0.0",
      "10.1.2.3",
      "127.0.0.1",
      "100.64.0.1",
      "169.254.169.254",
      "172.16.0.1",
      "172.31.255.255",
      "192.168.0.1",
      "192.0.2.1",
      "198.18.0.1",
      "224.0.0.1",
    ]
  ) assert(isPrivateIpv4(ip), `${ip} should be private`);
  for (const ip of ["8.8.8.8", "93.184.216.34", "172.32.0.1", "171.16.0.1"]) {
    assert(!isPrivateIpv4(ip), `${ip} should be public`);
  }
  for (const ip of ["::1", "::", "fd00::1", "fe80::1", "::ffff:127.0.0.1"]) {
    assert(isPrivateIpv6(ip), `${ip} should be private`);
  }
  assert(!isPrivateIpv6("2606:4700:4700::1111"));
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
