// Production wiring for `import-recipe`. `index.ts` is the pure spine; this
// module supplies `ClaudeHaikuAdapter` (ANTHROPIC_API_KEY); a household-scoped
// `sqlVocabMatcher` over Postgres (`SUPABASE_DB_URL`, service role), where the
// household comes only from the verified token; auth (`auth.ts`: no bearer
// token → 401, no household or one outside `IMPORT_ALLOWED_HOUSEHOLDS` → 403);
// and a permissive CORS preflight.

import postgres from "postgres";
import type { ExtractAdapter } from "../_shared/types.ts";
import { ClaudeHaikuAdapter } from "../_shared/adapters/claude.ts";
import { fetchRawBlob } from "../_shared/jsonld.ts";
import { matchLines as matchCascade } from "../_shared/match.ts";
import {
  type SqlExecutor,
  sqlRecipeTitleMatcher,
  sqlVocabMatcher,
} from "../_shared/match_db.ts";
import { readCaller } from "./auth.ts";
import { replayAdapterFromEnv } from "./replay.ts";
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

/**
 * Copies a spine response through with the CORS headers. The body is passed
 * as a stream, never read: buffering `text/event-stream` would hold every
 * stage event back until the import was over.
 */
function withCors(res: Response): Response {
  const headers = new Headers(res.headers);
  for (const [k, v] of Object.entries(CORS_HEADERS)) headers.set(k, v);
  return new Response(res.body, { status: res.status, headers });
}

// --- Postgres seam -----------------------------------------------------------

// One connection pool per cold start, lazily opened. `prepare: false` keeps it
// compatible with a transaction-mode pooler (pgbouncer rejects prepared
// statements).
//
// `max` is small on purpose: one import needs at most two connections at once,
// because each tier is a single batched query (match_db.ts). A per-line
// fan-out would have to raise this.
const POOL_MAX = 4;

let pool: ReturnType<typeof postgres> | null = null;

function executor(): SqlExecutor {
  if (!pool) {
    const url = Deno.env.get("SUPABASE_DB_URL");
    if (!url || url.trim() === "") {
      throw new Error("SUPABASE_DB_URL is not set");
    }
    pool = postgres(url, { prepare: false, max: POOL_MAX });
  }
  const sql = pool;
  return <T = Record<string, unknown>>(text: string, params: unknown[]) =>
    sql.unsafe(text, params as unknown[]) as unknown as Promise<T[]>;
}

// --- Per-request deps --------------------------------------------------------

function buildDeps(householdId: string): ImportDeps {
  // Off in every deployed environment; see `replay.ts`. It drives the
  // deterministic half of the pipeline against a real Postgres with no API key.
  const adapter: ExtractAdapter = replayAdapterFromEnv() ??
    new ClaudeHaikuAdapter();
  const exec = executor();
  const matcher = sqlVocabMatcher(exec, householdId);
  // The household's live recipe titles, so a printed cross-reference can be
  // offered as a component link at review. Never auto-linked.
  const recipes = sqlRecipeTitleMatcher(exec, householdId);
  return {
    adapter,
    matchLines: (lines) => matchCascade(lines, matcher, recipes),
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
    // A missing ANTHROPIC_API_KEY or SUPABASE_DB_URL is a server misconfig → a
    // 500. The detail goes to the function log, never to the caller.
    console.error(
      `import-recipe: dependency wiring failed: ${
        e instanceof Error ? e.stack ?? e.message : String(e)
      }`,
    );
    return jsonResponse(500, { error: "import pipeline is not configured" });
  }
  return withCors(await makeHandler(deps)(req));
}

/** Starts the edge server. Called only from `index.ts`'s `import.meta.main`. */
export function serveImport(): void {
  Deno.serve(handle);
}
