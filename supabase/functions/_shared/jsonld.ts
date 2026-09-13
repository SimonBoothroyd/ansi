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
// `fetchRawBlob(url)` is the network wrapper — and the pipeline's only
// attacker-reachable outbound request, so it carries the SSRF guards, the size
// and time budgets, and the fail-loud contract (see its doc comment). Both I/O
// seams (fetch, DNS) are injectable so the whole module stays offline-testable.

import type { RawBlob } from "./types.ts";
import { ImportError } from "./errors.ts";

// --- Budgets -----------------------------------------------------------------
// This module is the ONLY place an attacker-influenced string (a URL the user
// pasted, a page someone else's server returned) enters the pipeline, and every
// byte past here is billed to a model. Bound all of it.

/**
 * Wall-clock budget for one hop.
 *
 * Intake is the FIRST rung of the import's timeout ladder (the whole ladder is
 * written out where the client timeout lives,
 * `app/lib/features/import/data/remote_import_repository.dart`). A slow or
 * hostile site must not be able to spend the budget the model call still needs.
 */
export const FETCH_TIMEOUT_MS = 10_000;
/**
 * Budget for the WHOLE intake, redirects included. Without it a chain of
 * {@link MAX_REDIRECTS} slow hops costs `FETCH_TIMEOUT_MS × (MAX_REDIRECTS+1)`
 * — four times the number the ladder is counting on. Each hop gets whatever is
 * smaller: its own budget, or what is left of this one.
 */
export const FETCH_TOTAL_TIMEOUT_MS = 25_000;
/** Redirect hops we will follow; each destination is re-validated. */
export const MAX_REDIRECTS = 3;
/** Stop reading a response body past this. */
export const MAX_BODY_BYTES = 2_000_000;
/** Chars of page text that may reach the prompt. */
export const MAX_TEXT_CHARS = 120_000;
/**
 * Chars of page text that may reach the APP, on {@link RawBlob.page_text} and
 * from there the payload's `source_text` (0047).
 *
 * Far under {@link MAX_TEXT_CHARS}: the prompt's copy is billed once and read
 * by a model, while this one crosses the wire on every import and is read by a
 * person in a 380 px column. 20k characters is a long recipe page's visible
 * text with room to spare, and it bounds the SSE `result` frame — which is one
 * line of JSON — to something a phone can hold.
 */
export const SOURCE_TEXT_MAX_CHARS = 20_000;

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
  // The page as a PERSON reads it (0047), on both branches and bounded
  // separately: a JSON-LD page is still a page, and the review's source column
  // has to be able to show it. It is never an input to sanitize — `text` and
  // `jsonld` are, and neither moves here.
  const visible = htmlToText(html);
  const pageText = visible.slice(0, SOURCE_TEXT_MAX_CHARS);
  if (recipes.length > 0) {
    return {
      source: "jsonld",
      url,
      jsonld: recipes[0],
      text: null,
      page_text: pageText,
    };
  }
  // Bounded before it leaves this module: `text` goes straight into the ①
  // prompt, and a 5 MB page of comments would be billed in full.
  return {
    source: "page_text",
    url,
    jsonld: null,
    text: visible.slice(0, MAX_TEXT_CHARS),
    page_text: pageText,
  };
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

// --- Target validation (SSRF) ------------------------------------------------
// The URL comes from the client, and this function runs inside the Supabase
// network with a service-role DB connection and a cloud metadata endpoint one
// hop away. Every hop is validated: scheme, hostname shape, and the ADDRESSES
// the hostname actually resolves to (a public name can point at 127.0.0.1 or
// 169.254.169.254 — DNS rebinding).

/** Hostnames that never leave the machine/VPC, whatever DNS says. */
const BLOCKED_SUFFIXES = [".localhost", ".local", ".internal", ".home.arpa"];

function isBlockedHostname(host: string): boolean {
  const h = host.toLowerCase().replace(/\.$/, "");
  if (h === "" || h === "localhost") return true;
  return BLOCKED_SUFFIXES.some((s) => h.endsWith(s));
}

/** True for any IPv4 literal outside the globally-routable space. */
export function isPrivateIpv4(ip: string): boolean {
  const parts = ip.split(".");
  if (parts.length !== 4) return false;
  const n = parts.map((p) => (/^\d{1,3}$/.test(p) ? Number(p) : NaN));
  if (n.some((v) => !Number.isInteger(v) || v < 0 || v > 255)) return false;
  const [a, b] = n;
  return (
    a === 0 || // 0.0.0.0/8 "this network"
    a === 10 || // private
    a === 127 || // loopback
    (a === 100 && b >= 64 && b <= 127) || // CGNAT 100.64/10
    (a === 169 && b === 254) || // link-local — incl. 169.254.169.254 metadata
    (a === 172 && b >= 16 && b <= 31) || // private
    (a === 192 && b === 0) || // 192.0.0/24 + 192.0.2/24
    (a === 192 && b === 168) || // private
    (a === 198 && (b === 18 || b === 19)) || // benchmarking
    a >= 224 // multicast + reserved
  );
}

/** True for any IPv6 literal outside the globally-routable space. */
export function isPrivateIpv6(ip: string): boolean {
  const h = ip.toLowerCase().replace(/^\[|\]$/g, "").split("%")[0];
  if (h === "::1" || h === "::" || h === "") return true;
  // IPv4-mapped / -compatible (::ffff:127.0.0.1) — judge the embedded address.
  const v4 = h.match(/(\d{1,3}(?:\.\d{1,3}){3})$/);
  if (v4 && h.includes(":")) return isPrivateIpv4(v4[1]);
  if (/^f[cd]/.test(h)) return true; // fc00::/7 unique-local
  if (/^fe[89ab]/.test(h)) return true; // fe80::/10 link-local
  if (/^ff/.test(h)) return true; // multicast
  return false;
}

function isPrivateAddress(ip: string): boolean {
  return ip.includes(":") ? isPrivateIpv6(ip) : isPrivateIpv4(ip);
}

/** Hostname → resolved IP literals. Injectable so tests never touch DNS. */
export type ResolveFn = (hostname: string) => Promise<string[]>;

/**
 * The production resolver. Asks for both families and tolerates one being
 * absent; a hostname that resolves to NOTHING (including because the runtime
 * denied us `--allow-net`) yields `[]`, and the caller fails CLOSED on that.
 */
const resolveDns: ResolveFn = async (hostname) => {
  const out: string[] = [];
  for (const type of ["A", "AAAA"] as const) {
    try {
      out.push(...await Deno.resolveDns(hostname, type));
    } catch {
      // No record of this family (or no permission) — the other may still answer.
    }
  }
  return out;
};

/**
 * Validates one hop. Throws {@link ImportError} (⇒ 422 with a human message) for
 * anything we will not fetch: a non-https scheme, a name that is structurally
 * internal, a literal private address, or a name resolving to one.
 */
async function assertFetchableTarget(
  target: URL,
  resolve: ResolveFn,
): Promise<void> {
  if (target.protocol !== "https:") {
    throw new ImportError("recipe URLs must start with https://");
  }
  const host = target.hostname;
  if (isBlockedHostname(host)) {
    throw new ImportError("that address is not a public web page");
  }
  const literal = host.startsWith("[") || /^[\d.]+$/.test(host) ||
    host.includes(":");
  if (literal) {
    if (isPrivateAddress(host)) {
      throw new ImportError("that address is not a public web page");
    }
    return;
  }
  const addresses = await resolve(host);
  if (addresses.length === 0) {
    throw new ImportError(`could not resolve ${host}`);
  }
  if (addresses.some(isPrivateAddress)) {
    throw new ImportError("that address is not a public web page");
  }
}

/** Reads at most {@link MAX_BODY_BYTES}, then abandons the rest of the body. */
async function readCappedText(res: Response): Promise<string> {
  if (!res.body) return (await res.text()).slice(0, MAX_BODY_BYTES);
  const reader = res.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (total < MAX_BODY_BYTES) {
      const { done, value } = await reader.read();
      if (done) break;
      if (value) {
        chunks.push(value);
        total += value.length;
      }
    }
  } finally {
    // Past the cap we stop reading and drop the connection rather than buffer
    // a page someone is streaming at us forever.
    await reader.cancel().catch(() => {});
  }
  const buf = new Uint8Array(Math.min(total, MAX_BODY_BYTES));
  let off = 0;
  for (const c of chunks) {
    if (off >= buf.length) break;
    buf.set(c.subarray(0, buf.length - off), off);
    off += c.length;
  }
  return new TextDecoder("utf-8", { fatal: false }).decode(buf);
}

const HTML_TYPES = ["text/html", "application/xhtml+xml"];

/** Fetch impl seam — the global `fetch` in prod, a stub in tests. */
export type FetchFn = (url: string, init?: RequestInit) => Promise<Response>;

export interface FetchBlobOptions {
  fetchImpl?: FetchFn;
  resolve?: ResolveFn;
}

/**
 * Fetches a URL and builds its {@link RawBlob}. Both I/O seams are injectable so
 * the module stays offline-testable; production uses the global `fetch` and DNS.
 *
 * NOT total, deliberately. It used to swallow every failure into an empty
 * page_text blob on the theory that "the orchestrator decides how to surface an
 * unusable page" — the orchestrator does no such thing, so a 403 challenge page
 * or a DNS failure became an empty blob that was cheerfully sent to the LLM and
 * billed. Anything that leaves us without a page now throws {@link ImportError}
 * (⇒ 422 with a message the user can act on) BEFORE a provider is called.
 */
export async function fetchRawBlob(
  url: string,
  opts: FetchBlobOptions = {},
): Promise<RawBlob> {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const resolve = opts.resolve ?? resolveDns;

  let target: URL;
  try {
    target = new URL(url);
  } catch {
    throw new ImportError("that does not look like a web address");
  }

  const deadline = Date.now() + FETCH_TOTAL_TIMEOUT_MS;
  for (let hop = 0;; hop++) {
    await assertFetchableTarget(target, resolve);
    const left = deadline - Date.now();
    if (left <= 0) {
      throw new ImportError("could not reach that site (it timed out)");
    }
    let res: Response;
    try {
      res = await fetchImpl(target.toString(), {
        // Manual: a 30x is re-validated against the SSRF rules above before we
        // follow it, which `redirect: "follow"` would deny us.
        redirect: "manual",
        signal: AbortSignal.timeout(Math.min(FETCH_TIMEOUT_MS, left)),
        headers: { accept: "text/html,application/xhtml+xml" },
      });
    } catch (e) {
      throw new ImportError(
        `could not reach that site (${
          e instanceof Error && e.name === "TimeoutError"
            ? "it timed out"
            : "network error"
        })`,
      );
    }

    if (res.status >= 300 && res.status < 400) {
      const location = res.headers.get("location");
      await res.body?.cancel().catch(() => {});
      if (!location) {
        throw new ImportError("that site returned a broken redirect");
      }
      if (hop >= MAX_REDIRECTS) {
        throw new ImportError("that site redirected too many times");
      }
      try {
        target = new URL(location, target);
      } catch {
        throw new ImportError("that site returned a broken redirect");
      }
      continue;
    }

    if (!res.ok) {
      await res.body?.cancel().catch(() => {});
      throw new ImportError(
        res.status === 403 || res.status === 401 || res.status === 429
          ? `that site blocked the fetch (HTTP ${res.status}) — try the photo import instead`
          : `that page could not be read (HTTP ${res.status})`,
      );
    }

    const contentType = (res.headers.get("content-type") ?? "").toLowerCase();
    if (!HTML_TYPES.some((t) => contentType.includes(t))) {
      await res.body?.cancel().catch(() => {});
      throw new ImportError(
        `that link is not a web page (${contentType || "no content type"})`,
      );
    }

    const html = await readCappedText(res);
    if (html.trim() === "") throw new ImportError("that page came back empty");
    return buildRawBlob(html, target.toString());
  }
}
