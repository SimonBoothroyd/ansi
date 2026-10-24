// The share host's Worker: `getansi.app/r/*` → the `share-recipe` edge
// function (exec plan 0051), and `getansi.app/privacy`, the privacy policy.
//
// Supabase serves no browser-renderable HTML on its shared `*.supabase.co`
// domain without its paid Custom Domain add-on, so the function's page cannot
// be opened there directly. This Worker stands on the share host in front of
// it, forwards the two paths the function answers, and sets the response
// headers itself — the type the page really is, and the function's own
// security policy — rather than passing on whatever the gateway rewrote.
//
// It holds no logic about recipes. Everything it refuses, the function would
// refuse too; refusing here first just keeps junk off the origin.
//
// The privacy policy is the one page it answers itself: `PRIVACY.md`, bundled
// at deploy (`privacy.ts`). Health Connect's permission screen opens that
// address, and the Play listing names the same one.

import { PRIVACY_PAGE } from "./privacy.ts";

/** What the Worker is configured with (`wrangler.toml`, `--var`). */
export interface Env {
  /** The function's base URL: `https://<ref>.supabase.co/functions/v1/share-recipe`. */
  SHARE_ORIGIN: string;
}

/** A share token as `share_recipe()` mints it, or the bundle's path. */
const PATH = /^\/r\/([A-Za-z0-9_-]{22}|share\.js)$/;

/** How long a page may be cached: the function's own figure. */
const PAGE_MAX_AGE_S = 60;

const PAGE_POLICY = [
  "default-src 'none'",
  "script-src 'self'",
  "style-src 'unsafe-inline' https://fonts.googleapis.com",
  "font-src https://fonts.gstatic.com",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'",
].join("; ");

/** The policy's address, and how long a copy of it may be kept. */
const PRIVACY_PATH = "/privacy";
const PRIVACY_MAX_AGE_S = 300;

/** The policy is static text: inline styles, nothing else. */
const PRIVACY_POLICY = [
  "default-src 'none'",
  "style-src 'unsafe-inline'",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'",
].join("; ");

const COMMON: Record<string, string> = {
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
  "strict-transport-security": "max-age=31536000; includeSubDomains",
};

const NOT_FOUND = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex"><title>Nothing here</title>
</head><body><p>Nothing here.</p></body></html>`;

/** The Worker's handler over [fetchOrigin], the network seam tests replace. */
export function makeWorker(
  fetchOrigin: (input: string, init: RequestInit) => Promise<Response>,
): (req: Request, env: Env) => Promise<Response> {
  return async (req, env) => {
    if (req.method !== "GET" && req.method !== "HEAD") {
      return new Response(null, {
        status: 405,
        headers: { ...COMMON, allow: "GET, HEAD" },
      });
    }
    const url = new URL(req.url);
    if (url.pathname === PRIVACY_PATH) return privacy(req);
    // One address for the policy: the trailing slash is sent to it.
    if (url.pathname === `${PRIVACY_PATH}/`) {
      return new Response(null, {
        status: 301,
        headers: {
          ...COMMON,
          location: PRIVACY_PATH,
          "cache-control": `public, max-age=${PRIVACY_MAX_AGE_S}`,
        },
      });
    }
    const match = url.pathname.match(PATH);
    if (!match) return notFound(req);
    const tail = match[1];
    const isBundle = tail === "share.js";

    const origin = env.SHARE_ORIGIN.replace(/\/$/, "");
    // The bundle's version rides on its query; a page's query means nothing.
    const target = `${origin}/r/${tail}${isBundle ? url.search : ""}`;
    let upstream: Response;
    try {
      // Only what the function needs: no cookies, no client headers.
      upstream = await fetchOrigin(target, {
        method: req.method,
        headers: { accept: isBundle ? "text/javascript" : "text/html" },
        redirect: "manual",
      });
    } catch {
      return failed(req);
    }
    if (upstream.status >= 500) {
      await upstream.body?.cancel();
      return failed(req);
    }

    const headers = new Headers(COMMON);
    headers.set(
      "cache-control",
      upstream.headers.get("cache-control") ??
        `public, max-age=${PAGE_MAX_AGE_S}`,
    );
    if (isBundle) {
      headers.set("content-type", "text/javascript; charset=utf-8");
    } else {
      headers.set("content-type", "text/html; charset=utf-8");
      headers.set("content-security-policy", PAGE_POLICY);
      headers.set("x-robots-tag", "noindex");
    }
    const status = upstream.status === 200 || upstream.status === 404
      ? upstream.status
      : 404;
    return new Response(req.method === "HEAD" ? null : upstream.body, {
      status,
      headers,
    });
  };
}

/** The policy, indexable: it should be findable. */
function privacy(req: Request): Response {
  return new Response(req.method === "HEAD" ? null : PRIVACY_PAGE, {
    status: 200,
    headers: {
      ...COMMON,
      "content-type": "text/html; charset=utf-8",
      "content-security-policy": PRIVACY_POLICY,
      "cache-control": `public, max-age=${PRIVACY_MAX_AGE_S}`,
    },
  });
}

function notFound(req: Request): Response {
  return new Response(req.method === "HEAD" ? null : NOT_FOUND, {
    status: 404,
    headers: {
      ...COMMON,
      "content-type": "text/html; charset=utf-8",
      "cache-control": `public, max-age=${PAGE_MAX_AGE_S}`,
      "x-robots-tag": "noindex",
    },
  });
}

function failed(req: Request): Response {
  return new Response(
    req.method === "HEAD"
      ? null
      : "<!doctype html><title>Something went wrong</title>" +
        "<p>The recipe could not be shown just now. Try again in a minute.</p>",
    {
      status: 502,
      headers: {
        ...COMMON,
        "content-type": "text/html; charset=utf-8",
        "cache-control": "no-store",
        "x-robots-tag": "noindex",
      },
    },
  );
}

const handle = makeWorker((input, init) => fetch(input, init));

export default {
  fetch: (req: Request, env: Env): Promise<Response> => handle(req, env),
};
