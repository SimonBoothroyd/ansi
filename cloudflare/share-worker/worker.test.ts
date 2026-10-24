// The share Worker against a fake origin — including one that behaves the way
// Supabase's gateway does with HTML on its shared domain.

import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import { type Env, makeWorker } from "./worker.ts";
import {
  PRIVACY_MD,
  PRIVACY_PAGE,
  renderInline,
  renderMarkdown,
} from "./privacy.ts";

const ENV: Env = {
  SHARE_ORIGIN: "https://ref.supabase.co/functions/v1/share-recipe/",
};
const TOKEN = "Tok3n_Tok3n-Tok3n_Tok3";

type Call = { url: string; init: RequestInit };

function worker(answer: (url: string) => Response | Promise<Response>) {
  const calls: Call[] = [];
  const handle = makeWorker((url, init) => {
    calls.push({ url, init });
    return Promise.resolve(answer(url));
  });
  return { handle, calls };
}

/** What the gateway is documented to do: HTML served as plain, sandboxed. */
function gatewayRewrite(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: {
      "content-type": "text/plain;charset=UTF-8",
      "content-security-policy": "default-src 'none'; sandbox",
      "cache-control": "public, max-age=60",
      "set-cookie": "x=1",
    },
  });
}

Deno.test("a page is forwarded and served as the HTML it is", async () => {
  const { handle, calls } = worker(() =>
    gatewayRewrite("<!doctype html><title>Miso</title>")
  );
  const res = await handle(
    new Request(`https://getansi.app/r/${TOKEN}?utm=x`, {
      headers: { cookie: "session=secret", authorization: "Bearer y" },
    }),
    ENV,
  );
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type"), "text/html; charset=utf-8");
  // The function's own policy, not the gateway's sandbox.
  assertStringIncludes(
    res.headers.get("content-security-policy") ?? "",
    "script-src 'self'",
  );
  assertEquals(res.headers.get("x-robots-tag"), "noindex");
  assertEquals(res.headers.get("cache-control"), "public, max-age=60");
  assertEquals(res.headers.get("set-cookie"), null);
  assertEquals(await res.text(), "<!doctype html><title>Miso</title>");

  // One call, to the function, with the page's query dropped and nothing of
  // the visitor's passed on.
  assertEquals(calls.length, 1);
  assertEquals(
    calls[0].url,
    `https://ref.supabase.co/functions/v1/share-recipe/r/${TOKEN}`,
  );
  const sent = new Headers(calls[0].init.headers);
  assertEquals(sent.get("cookie"), null);
  assertEquals(sent.get("authorization"), null);
});

Deno.test("the bundle is forwarded with its version, as JavaScript", async () => {
  const { handle, calls } = worker(() =>
    new Response("(function(){})()", {
      headers: { "cache-control": "public, max-age=31536000, immutable" },
    })
  );
  const res = await handle(
    new Request("https://getansi.app/r/share.js?v=ff298e6d16db"),
    ENV,
  );
  assertEquals(res.status, 200);
  assertEquals(
    res.headers.get("content-type"),
    "text/javascript; charset=utf-8",
  );
  assertEquals(
    res.headers.get("cache-control"),
    "public, max-age=31536000, immutable",
  );
  assertEquals(res.headers.get("content-security-policy"), null);
  assertEquals(
    calls[0].url,
    "https://ref.supabase.co/functions/v1/share-recipe/r/share.js?v=ff298e6d16db",
  );
  await res.body?.cancel();
});

Deno.test("the function's 404 page passes through as a 404", async () => {
  const { handle } = worker(() => gatewayRewrite("<p>Nothing here</p>", 404));
  const res = await handle(new Request(`https://getansi.app/r/${TOKEN}`), ENV);
  assertEquals(res.status, 404);
  assertEquals(res.headers.get("content-type"), "text/html; charset=utf-8");
  await res.body?.cancel();
});

Deno.test("anything but a token or the bundle never reaches the origin", async () => {
  const { handle, calls } = worker(() => new Response("origin"));
  for (
    const path of [
      "/",
      "/r/",
      "/r/short",
      `/r/${TOKEN}/x`,
      `/x/${TOKEN}`,
      "/r/share.js.map",
      "/r/..%2Fadmin",
      `/r/${TOKEN}x`,
    ]
  ) {
    const res = await handle(new Request(`https://getansi.app${path}`), ENV);
    assertEquals(res.status, 404, path);
    assertEquals(res.headers.get("x-robots-tag"), "noindex", path);
    await res.body?.cancel();
  }
  assertEquals(calls, []);
});

Deno.test("only GET and HEAD are answered", async () => {
  const { handle, calls } = worker(() => new Response("origin"));
  const post = await handle(
    new Request(`https://getansi.app/r/${TOKEN}`, {
      method: "POST",
      body: "x",
    }),
    ENV,
  );
  assertEquals(post.status, 405);
  assertEquals(post.headers.get("allow"), "GET, HEAD");
  assertEquals(calls, []);

  const { handle: h2 } = worker(() => new Response("page"));
  const head = await h2(
    new Request(`https://getansi.app/r/${TOKEN}`, { method: "HEAD" }),
    ENV,
  );
  assertEquals(head.status, 200);
  assertEquals(await head.text(), "");
});

Deno.test("an origin that fails or redirects is not passed on", async () => {
  const down = worker(() => {
    throw new Error("connection reset");
  });
  const a = await down.handle(
    new Request(`https://getansi.app/r/${TOKEN}`),
    ENV,
  );
  assertEquals(a.status, 502);
  assertEquals(a.headers.get("cache-control"), "no-store");
  await a.body?.cancel();

  const broken = worker(() =>
    new Response("stack trace here", { status: 500 })
  );
  const b = await broken.handle(
    new Request(`https://getansi.app/r/${TOKEN}`),
    ENV,
  );
  assertEquals(b.status, 502);
  assert(!(await b.text()).includes("stack trace"));

  const moved = worker(() =>
    new Response(null, {
      status: 302,
      headers: { location: "https://elsewhere.example" },
    })
  );
  const c = await moved.handle(
    new Request(`https://getansi.app/r/${TOKEN}`),
    ENV,
  );
  assertEquals(c.status, 404);
  assertEquals(c.headers.get("location"), null);
  await c.body?.cancel();
});

// ---- The privacy policy ---------------------------------------------------

const POLICY_FILE = new URL("../../PRIVACY.md", import.meta.url);

/** What a reader sees: tags dropped, entities read, whitespace collapsed. */
function visibleText(html: string): string {
  return html
    .replace(/<style>[\s\S]*?<\/style>/g, " ")
    .replace(/<[^>]+>/g, "")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ");
}

Deno.test("the privacy policy is served as an indexable page of its own", async () => {
  const { handle, calls } = worker(() => new Response("origin"));
  for (const path of ["/privacy", "/privacy?from=health-connect"]) {
    const res = await handle(new Request(`https://getansi.app${path}`), ENV);
    assertEquals(res.status, 200, path);
    assertEquals(res.headers.get("content-type"), "text/html; charset=utf-8");
    assertEquals(
      res.headers.get("content-security-policy"),
      "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; " +
        "form-action 'none'; frame-ancestors 'none'",
    );
    assertEquals(res.headers.get("cache-control"), "public, max-age=300");
    assertEquals(res.headers.get("x-content-type-options"), "nosniff");
    assertEquals(res.headers.get("referrer-policy"), "no-referrer");
    assertStringIncludes(
      res.headers.get("strict-transport-security") ?? "",
      "max-age=",
    );
    // Findable: a privacy policy is not hidden from search.
    assertEquals(res.headers.get("x-robots-tag"), null);
    const html = await res.text();
    assert(!html.includes("noindex"));
    assert(html.startsWith("<!doctype html>"));
    assertStringIncludes(html, '<html lang="en">');
    assertStringIncludes(html, "<title>Ansi — privacy policy</title>");
    assertStringIncludes(html, 'name="viewport"');
    assertStringIncludes(html, "color-scheme: light dark");
    assert(!/<script|<link|<img|src=/i.test(html), "no external anything");
  }
  assertEquals(calls, []);
});

Deno.test("HEAD on the policy answers its headers and no body", async () => {
  const { handle } = worker(() => new Response("origin"));
  const res = await handle(
    new Request("https://getansi.app/privacy", { method: "HEAD" }),
    ENV,
  );
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type"), "text/html; charset=utf-8");
  assertEquals(res.headers.get("cache-control"), "public, max-age=300");
  assertEquals(await res.text(), "");
});

Deno.test("the policy has one address: a trailing slash is sent to it", async () => {
  const { handle, calls } = worker(() => new Response("origin"));
  for (const method of ["GET", "HEAD"]) {
    const res = await handle(
      new Request("https://getansi.app/privacy/", { method }),
      ENV,
    );
    assertEquals(res.status, 301, method);
    assertEquals(res.headers.get("location"), "/privacy");
    assertEquals(res.headers.get("x-content-type-options"), "nosniff");
    await res.body?.cancel();
  }
  for (
    const path of ["/privacy/x", "/PRIVACY", "/privacy.html", "/r/privacy"]
  ) {
    const res = await handle(new Request(`https://getansi.app${path}`), ENV);
    assertEquals(res.status, 404, path);
    await res.body?.cancel();
  }
  const post = await handle(
    new Request("https://getansi.app/privacy", { method: "POST", body: "x" }),
    ENV,
  );
  assertEquals(post.status, 405);
  assertEquals(calls, []);
});

Deno.test("the page is PRIVACY.md as it stands, every word of it", async () => {
  const md = await Deno.readTextFile(POLICY_FILE);
  // The bundled text is the file itself, not a copy of it.
  assertEquals(PRIVACY_MD, md);
  const { handle } = worker(() => new Response("origin"));
  const res = await handle(new Request("https://getansi.app/privacy"), ENV);
  const page = visibleText(await res.text());
  const blocks = md.split(/\n\s*\n/).flatMap((b) => b.split(/\n(?=- )/));
  assert(blocks.length > 10);
  for (const block of blocks) {
    const words = block
      .replace(/^#+\s+|^-\s+/, "")
      .replace(/\*\*|`/g, "")
      .replace(/\s+/g, " ")
      .trim();
    assertStringIncludes(page, words);
  }
});

Deno.test("no Markdown reaches the reader unrendered", () => {
  const page = visibleText(PRIVACY_PAGE);
  for (const marker of ["**", "`", "](", "# ", " - "]) {
    assert(!page.includes(marker), `"${marker}" left in the page`);
  }
});

Deno.test("the Worker holds no copy of the policy to fall behind", async () => {
  // PRIVACY.md is the one source: imported from the repository root, never
  // copied next to the Worker as Markdown, HTML or a generated module.
  const source = await Deno.readTextFile(
    new URL("./privacy.ts", import.meta.url),
  );
  assertStringIncludes(
    source,
    'import policy from "../../PRIVACY.md" with { type: "text" };',
  );
  for await (const entry of Deno.readDir(new URL("./", import.meta.url))) {
    assert(
      !/\.(md|html?)$/i.test(entry.name) || entry.name === "README.md",
      `${entry.name} beside the Worker`,
    );
  }
  for (const line of PRIVACY_MD.split("\n").filter((l) => l.length > 40)) {
    assert(!source.includes(line), "a line of the policy is pasted in");
  }
});

Deno.test("the renderer knows the policy's Markdown and escapes the rest", () => {
  const { title, body } = renderMarkdown(
    [
      "# Title <b>",
      "",
      "One line",
      "and its next, with **bold**, *italic*, _also_, `code` and",
      "[a link](https://example.com/?a=1&b=2).",
      "",
      "- **First:** item",
      "  carried on.",
      "- Second <script>alert(1)</script>",
      "",
      "## Then",
      "",
      "[bad](javascript:alert(1)) and share_recipe stays as it is.",
      "> not a quote | nor a table",
    ].join("\n"),
  );
  assertEquals(title, "Title <b>");
  assertEquals(
    body,
    [
      "<h1>Title &lt;b&gt;</h1>",
      "<p>One line and its next, with <strong>bold</strong>, <em>italic</em>, " +
      "<em>also</em>, <code>code</code> and " +
      '<a href="https://example.com/?a=1&amp;b=2">a link</a>.</p>',
      "<ul>",
      "<li><strong>First:</strong> item carried on.</li>",
      "<li>Second &lt;script&gt;alert(1)&lt;/script&gt;</li>",
      "</ul>",
      "<h2>Then</h2>",
      "<p>[bad](javascript:alert(1)) and share_recipe stays as it is. " +
      "&gt; not a quote | nor a table</p>",
    ].join("\n"),
  );
  assertEquals(renderInline(`"x" & 'y'`), "&quot;x&quot; &amp; &#39;y&#39;");
});
