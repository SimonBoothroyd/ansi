// `share-recipe`: a recipe's public, read-only page, by the token in its link
// (exec plan 0051). Public — the gateway checks no JWT — so this function is
// the whole boundary: it answers GET and HEAD on two paths, and reads nothing
// but one share's rows by token.
//
//   …/share-recipe/r/<token>   the page, rendered on the server so its
//                              JSON-LD and link preview are in the HTML
//   …/share-recipe/r/share.js  the bundle that renders it, which the page
//                              loads for its servings stepper and timers
//
// The renderer is the app's own Dart compiled to JS (`share_page.js`, built
// by `scripts/share_bundle.sh`), so a number on the page is the number in the
// app. `live.ts` wires Postgres and the bundle; this file is the pure spine.

import { loadSharePayload, type SqlExecutor } from "./payload.ts";

export type RenderPage = (
  payloadJson: string,
  url: string,
  bundleUrl: string,
) => string;

export interface ShareDeps {
  /** The payload's JSON text for a token, or null when nothing is live. */
  loadPayload: (token: string) => Promise<string | null>;
  render: RenderPage;
  /** The bundle's source, served at `r/share.js`. */
  bundle: string;
  /** A short hash of [bundle], so a page names the bundle it was built by. */
  bundleVersion: string;
  /**
   * The origin links are minted under (`https://getansi.app`); the page's
   * canonical URL is built from it. Null takes the request's own origin.
   */
  shareBase: string | null;
}

/** How long a page may be cached: a revoke or an edit shows within this. */
export const PAGE_MAX_AGE_S = 60;

const BUNDLE_PATH = "share.js";

const PAGE_HEADERS: Record<string, string> = {
  "content-type": "text/html; charset=utf-8",
  "cache-control": `public, max-age=${PAGE_MAX_AGE_S}`,
  "x-robots-tag": "noindex",
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
  // Only the page's own bundle runs. The JSON-LD and the embedded payload are
  // data blocks, which no script policy executes.
  "content-security-policy": [
    "default-src 'none'",
    "script-src 'self'",
    "style-src 'unsafe-inline' https://fonts.googleapis.com",
    "font-src https://fonts.gstatic.com",
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'",
  ].join("; "),
};

const NOT_FOUND_HTML = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex"><title>Nothing here</title>
<style>body{margin:0;font:16px/1.55 system-ui,sans-serif;background:#fbfaf6;color:#18211c}
main{max-width:640px;margin:0 auto;padding:40px 16px}
@media (prefers-color-scheme:dark){body{background:#141a16;color:#e8ece8}}</style>
</head><body><main><h1>Nothing here</h1>
<p>This recipe is no longer shared, or the link was never one. Ask whoever
sent it for a fresh link.</p></main></body></html>`;

const FAILED_HTML = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex"><title>Something went wrong</title>
</head><body><main><h1>Something went wrong</h1>
<p>The recipe could not be shown just now. Try again in a minute.</p>
</main></body></html>`;

/** The handler, over [deps]. */
export function makeHandler(
  deps: ShareDeps,
): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method !== "GET" && req.method !== "HEAD") {
      return new Response(null, {
        status: 405,
        headers: { allow: "GET, HEAD" },
      });
    }
    const url = new URL(req.url);
    // The function sees its own name in the path; only the tail is ours.
    const match = url.pathname.match(/\/r\/([^/]+)$/);
    if (!match) return page(req, 404, NOT_FOUND_HTML);
    const last = match[1];

    if (last === BUNDLE_PATH) {
      const current = url.searchParams.get("v") === deps.bundleVersion;
      return respond(req, 200, deps.bundle, {
        "content-type": "text/javascript; charset=utf-8",
        "x-content-type-options": "nosniff",
        // Named by its hash, a bundle can be kept forever; asked for by an
        // old or missing hash, it is the current one, briefly.
        "cache-control": current
          ? "public, max-age=31536000, immutable"
          : `public, max-age=${PAGE_MAX_AGE_S}`,
      });
    }

    let payload: string | null;
    try {
      payload = await deps.loadPayload(last);
    } catch (e) {
      console.error(
        `share-recipe: loading the payload failed: ${
          e instanceof Error ? e.stack ?? e.message : String(e)
        }`,
      );
      return page(req, 500, FAILED_HTML, "no-store");
    }
    if (payload === null) return page(req, 404, NOT_FOUND_HTML);

    const base = (deps.shareBase ?? url.origin).replace(/\/$/, "");
    let html: string;
    try {
      html = deps.render(
        payload,
        `${base}/r/${last}`,
        `/r/${BUNDLE_PATH}?v=${deps.bundleVersion}`,
      );
    } catch (e) {
      console.error(
        `share-recipe: rendering failed: ${
          e instanceof Error ? e.stack ?? e.message : String(e)
        }`,
      );
      return page(req, 500, FAILED_HTML, "no-store");
    }
    return page(req, 200, html);
  };
}

function page(
  req: Request,
  status: number,
  html: string,
  cache?: string,
): Response {
  return respond(req, status, html, {
    ...PAGE_HEADERS,
    ...(cache ? { "cache-control": cache } : {}),
  });
}

function respond(
  req: Request,
  status: number,
  body: string,
  headers: Record<string, string>,
): Response {
  return new Response(req.method === "HEAD" ? null : body, { status, headers });
}

/** [loadSharePayload] over [exec], as the handler takes it. */
export function payloadLoader(
  exec: SqlExecutor,
): (token: string) => Promise<string | null> {
  return (token) => loadSharePayload(exec, token);
}

if (import.meta.main) {
  // Not a top-level await: `live.ts` imports back from this module, so awaiting
  // here would deadlock module evaluation.
  import("./live.ts").then((m) => m.serveShare());
}
