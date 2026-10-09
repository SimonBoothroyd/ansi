// The share page's handler: its two paths, its refusals and its headers,
// rendering through the real compiled bundle from the app's payload fixture.

import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import { makeHandler, PAGE_MAX_AGE_S, type ShareDeps } from "./index.ts";
import { bundledRenderer, SHARE_BUNDLE, shortHash } from "./bundle.ts";

const FIXTURE = await Deno.readTextFile(
  new URL(
    "../../../app/test/features/share/testdata/share_payload.json",
    import.meta.url,
  ),
);
const TOKEN = "Tok3n_Tok3n-Tok3n_Tok3";
const BASE = "https://example.test/functions/v1/share-recipe";

function handler(over: Partial<ShareDeps> = {}) {
  const asked: string[] = [];
  const handle = makeHandler({
    loadPayload: (token) => {
      asked.push(token);
      return Promise.resolve(token === TOKEN ? FIXTURE : null);
    },
    render: bundledRenderer(),
    bundle: SHARE_BUNDLE,
    bundleVersion: "abc123",
    shareBase: "https://getansi.app",
    ...over,
  });
  return { handle, asked };
}

Deno.test("a live token renders the recipe, server-side", async () => {
  const { handle } = handler();
  const res = await handle(new Request(`${BASE}/r/${TOKEN}`));
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type"), "text/html; charset=utf-8");
  assertEquals(
    res.headers.get("cache-control"),
    `public, max-age=${PAGE_MAX_AGE_S}`,
  );
  assertEquals(res.headers.get("x-robots-tag"), "noindex");
  assertStringIncludes(
    res.headers.get("content-security-policy") ?? "",
    "script-src 'self'",
  );
  const html = await res.text();
  assertStringIncludes(html, "<title>Miso Noodles &lt;spicy&gt;</title>");
  assertStringIncludes(html, '<script type="application/ld+json">');
  assertStringIncludes(html, '<span class="amt">2 blob (30 g)</span>');
  // The canonical link is the share host's, not the function's.
  assertStringIncludes(
    html,
    `<link rel="canonical" href="https://getansi.app/r/${TOKEN}">`,
  );
  assertStringIncludes(html, '<script src="/r/share.js?v=abc123" defer>');
});

Deno.test("with no share host set, links are minted under the request's own origin", async () => {
  const { handle } = handler({ shareBase: null });
  const html = await (await handle(new Request(`${BASE}/r/${TOKEN}`))).text();
  assertStringIncludes(
    html,
    `<link rel="canonical" href="https://example.test/r/${TOKEN}">`,
  );
});

Deno.test("an unknown or revoked token is a 404 page, never an error", async () => {
  const { handle, asked } = handler();
  const res = await handle(new Request(`${BASE}/r/AAAAAAAAAAAAAAAAAAAAAA`));
  assertEquals(res.status, 404);
  assertEquals(res.headers.get("x-robots-tag"), "noindex");
  assertStringIncludes(await res.text(), "no longer shared");
  assertEquals(asked, ["AAAAAAAAAAAAAAAAAAAAAA"]);
});

Deno.test("a path that is not ours is a 404", async () => {
  const { handle } = handler();
  for (const path of ["", "/", "/r/", `/x/${TOKEN}`, `/r/${TOKEN}/more`]) {
    const res = await handle(new Request(`${BASE}${path}`));
    assertEquals(res.status, 404, path);
    await res.body?.cancel();
  }
});

Deno.test("only GET and HEAD are answered", async () => {
  const { handle } = handler();
  const post = await handle(
    new Request(`${BASE}/r/${TOKEN}`, { method: "POST", body: "x" }),
  );
  assertEquals(post.status, 405);
  assertEquals(post.headers.get("allow"), "GET, HEAD");

  const head = await handle(
    new Request(`${BASE}/r/${TOKEN}`, { method: "HEAD" }),
  );
  assertEquals(head.status, 200);
  assertEquals(await head.text(), "");
});

Deno.test("the bundle is served beside the page, cached by its hash", async () => {
  const { handle, asked } = handler();
  const current = await handle(new Request(`${BASE}/r/share.js?v=abc123`));
  assertEquals(current.status, 200);
  assertEquals(
    current.headers.get("content-type"),
    "text/javascript; charset=utf-8",
  );
  assertStringIncludes(current.headers.get("cache-control") ?? "", "immutable");
  assertEquals(await current.text(), SHARE_BUNDLE);

  const stale = await handle(new Request(`${BASE}/r/share.js?v=old`));
  assertEquals(
    stale.headers.get("cache-control"),
    `public, max-age=${PAGE_MAX_AGE_S}`,
  );
  await stale.body?.cancel();
  // Serving the bundle reads no share.
  assertEquals(asked, []);
});

Deno.test("a database that fails is a 500 page, uncached, with no detail", async () => {
  const { handle } = handler({
    loadPayload: () => Promise.reject(new Error("connection refused 10.0.0.1")),
  });
  const original = console.error;
  console.error = () => {};
  try {
    const res = await handle(new Request(`${BASE}/r/${TOKEN}`));
    assertEquals(res.status, 500);
    assertEquals(res.headers.get("cache-control"), "no-store");
    const html = await res.text();
    assert(!html.includes("10.0.0.1"));
  } finally {
    console.error = original;
  }
});

Deno.test("the bundle's version is a stable short hash of its source", async () => {
  const one = await shortHash(SHARE_BUNDLE);
  assertEquals(one, await shortHash(SHARE_BUNDLE));
  assertEquals(one.length, 12);
  assert(/^[0-9a-f]+$/.test(one));
});
