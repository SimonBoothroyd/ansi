// The share Worker against a fake origin — including one that behaves the way
// Supabase's gateway does with HTML on its shared domain.

import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@^1";
import { type Env, makeWorker } from "./worker.ts";

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
