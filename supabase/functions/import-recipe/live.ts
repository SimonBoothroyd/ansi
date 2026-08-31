// Production wiring for `import-recipe` (plan 0019 — the integration tail).
//
// `index.ts` is the pure, deps-injected orchestration spine; this module binds
// it to real infrastructure and owns the HTTP edges the spine deliberately does
// not:
//   - the extraction provider — `ClaudeHaikuAdapter` (`claude-haiku-4-5`), keyed
//     by ANTHROPIC_API_KEY. Missing key → a clear 500.
//   - the match cascade's DB seam — a household-scoped `sqlVocabMatcher`
//     (match_db.ts) over Postgres (`SUPABASE_DB_URL`, service role). The parameterized
//     pg_trgm SQL is scoped to the caller's household in `WHERE household_id = $1`,
//     so a service-role connection is safe: the household never comes from the
//     body, only from the verified token.
//   - auth — the `household_id` claim the `add_household_claim` hook (migration
//     0007) injects into the caller's JWT. No bearer token → 401; a token with no
//     household (not onboarded) → 403.
//   - CORS — a permissive preflight so a browser client can call it too (the iOS
//     app uses native HTTP, where CORS is moot).
//
// It reuses `makeHandler(deps)` unchanged: per request we build the household-
// scoped `deps` from the token, then hand the request to the spine.

import postgres from "postgres";
import type { ExtractAdapter } from "../_shared/types.ts";
import { ClaudeHaikuAdapter } from "../_shared/adapters/claude.ts";
import { fetchRawBlob } from "../_shared/jsonld.ts";
import { matchLines as matchCascade } from "../_shared/match.ts";
import { type SqlExecutor, sqlVocabMatcher } from "../_shared/match_db.ts";
import { type ImportDeps, makeHandler } from "./index.ts";

// --- CORS --------------------------------------------------------------------

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...CORS_HEADERS },
  });
}

/** Copies a spine response through, stamping the CORS headers onto it. */
async function withCors(res: Response): Promise<Response> {
  const headers = new Headers(res.headers);
  for (const [k, v] of Object.entries(CORS_HEADERS)) headers.set(k, v);
  return new Response(await res.text(), { status: res.status, headers });
}

// --- Auth: household_id from the verified JWT --------------------------------

interface Caller {
  userId: string;
  householdId: string;
}

/** base64url JSON segment → object (UTF-8 safe; tolerant of missing padding). */
function decodeSegment(seg: string): Record<string, unknown> | null {
  try {
    const b64 = seg.replace(/-/g, "+").replace(/_/g, "/").padEnd(
      Math.ceil(seg.length / 4) * 4,
      "=",
    );
    const bin = atob(b64);
    const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return null;
  }
}

/**
 * Reads the caller from the request's bearer token. The Supabase edge gateway
 * verifies the JWT signature before the function runs (config `verify_jwt =
 * true`), so here we only decode the already-verified claims — the
 * `household_id` the `add_household_claim` hook stamped, plus `sub`.
 */
function readCaller(req: Request): Caller | { error: string; status: number } {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (!token) return { error: "missing bearer token", status: 401 };
  const parts = token.split(".");
  const claims = parts.length === 3 ? decodeSegment(parts[1]) : null;
  if (!claims) return { error: "malformed bearer token", status: 401 };
  const householdId = typeof claims.household_id === "string"
    ? claims.household_id
    : "";
  if (!householdId) {
    return {
      error: "no household on this account — finish onboarding first",
      status: 403,
    };
  }
  return { userId: String(claims.sub ?? ""), householdId };
}

// --- Postgres seam -----------------------------------------------------------

// One connection pool per cold start, lazily opened. `prepare: false` keeps it
// compatible with a transaction-mode pooler (Supabase's `SUPABASE_DB_URL` may be
// pgbouncer, which rejects prepared statements) and is harmless on a direct
// connection.
let pool: ReturnType<typeof postgres> | null = null;

function executor(): SqlExecutor {
  if (!pool) {
    const url = Deno.env.get("SUPABASE_DB_URL");
    if (!url || url.trim() === "") {
      throw new Error("SUPABASE_DB_URL is not set");
    }
    pool = postgres(url, { prepare: false });
  }
  const sql = pool;
  return <T = Record<string, unknown>>(text: string, params: unknown[]) =>
    sql.unsafe(text, params as unknown[]) as unknown as Promise<T[]>;
}

// --- Per-request deps --------------------------------------------------------

function buildDeps(householdId: string): ImportDeps {
  const adapter: ExtractAdapter = new ClaudeHaikuAdapter();
  const matcher = sqlVocabMatcher(executor(), householdId);
  return {
    adapter,
    matchLines: (lines) => matchCascade(lines, matcher),
    fetchBlob: fetchRawBlob,
  };
}

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  const caller = readCaller(req);
  if ("error" in caller) {
    return jsonResponse(caller.status, { error: caller.error });
  }

  let deps: ImportDeps;
  try {
    deps = buildDeps(caller.householdId);
  } catch (e) {
    // A missing ANTHROPIC_API_KEY or SUPABASE_DB_URL is a server misconfig, not
    // a client error — surface it plainly as a 500.
    return jsonResponse(500, {
      error: "import pipeline is not configured",
      detail: e instanceof Error ? e.message : String(e),
    });
  }
  return await withCors(await makeHandler(deps)(req));
}

/** Starts the edge server. Called only from `index.ts`'s `import.meta.main`. */
export function serveImport(): void {
  Deno.serve(handle);
}
