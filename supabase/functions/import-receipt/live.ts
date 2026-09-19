// Production wiring for `import-receipt`.
//
// `index.ts` is the pure, deps-injected orchestration spine; this module binds
// it to real infrastructure and owns the HTTP edges the spine deliberately does
// not. It is `import-recipe/live.ts`'s twin, and where a line is identical it
// is identical on purpose:
//   - the provider — `ClaudeReceiptAdapter`, over the SAME pin (`claude-haiku-4-5`,
//     imported from `_shared/adapters/claude.ts`), keyed by ANTHROPIC_API_KEY.
//   - the match cascade's DB seam — a household-scoped `sqlVocabMatcher`
//     (match_db.ts) over Postgres (`SUPABASE_DB_URL`, service role). The
//     parameterized pg_trgm SQL is scoped to the caller's household in
//     `WHERE household_id = $1`, so a service-role connection is safe: the
//     household never comes from the body, only from the verified token.
//   - the match memory's DB seam — `sqlReceiptMemory` (receipt_memory.ts) over
//     the same pool and the same fence, one batched SELECT over this
//     household's own saved receipt lines.
//   - auth — `auth.ts`, over the shared gate: the `household_id` claim plus the
//     deploy-time allowlist.
//   - CORS — a permissive preflight so a browser client can call it too.
//
// **No recipe-title tier.** `import-recipe` also offers a sub-recipe link per
// line (8.6); a receipt line is a thing that was bought, never a recipe, so
// that matcher is not wired here and the query is not spent.
//
// **Nothing writes.** The only SQL this function issues is the cascade's two
// SELECTs and the memory's one. There is no alias write, no stub write, no
// receipt write — the app writes the `receipt` and its lines through PowerSync
// at Save, from the review (plan 0049). `no_alias.test.ts` holds that
// structurally, by spying on every statement the function issues.

import postgres from "postgres";
import type { ReceiptAdapter } from "../_shared/receipt_types.ts";
import { ClaudeReceiptAdapter } from "../_shared/adapters/claude_receipt.ts";
import { matchLines as matchCascade } from "../_shared/match.ts";
import { type SqlExecutor, sqlVocabMatcher } from "../_shared/match_db.ts";
import { sqlReceiptMemory } from "../_shared/receipt_memory.ts";
import { CORS_HEADERS, jsonResponse, withCors } from "../_shared/http_edge.ts";
import { readCaller } from "./auth.ts";
import { replayReceiptAdapterFromEnv } from "./replay.ts";
import { makeHandler, type ReceiptDeps } from "./index.ts";

// --- Postgres seam -----------------------------------------------------------
//
// One connection pool per cold start, lazily opened. `prepare: false` keeps it
// compatible with a transaction-mode pooler and is harmless on a direct
// connection. `max` is small ON PURPOSE and is a statement about the cascade:
// one receipt asks for at most two connections, because each tier is a single
// batched query rather than one per line.
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

function buildDeps(householdId: string): ReceiptDeps {
  // Off in every deployed environment — see `replay.ts` for the locks that keep
  // it that way.
  const adapter: ReceiptAdapter = replayReceiptAdapterFromEnv() ??
    new ClaudeReceiptAdapter();
  const exec = executor();
  const matcher = sqlVocabMatcher(exec, householdId);
  return {
    adapter,
    matchLines: (lines) => matchCascade(lines, matcher),
    recallMatches: sqlReceiptMemory(exec, householdId),
  };
}

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  const caller = readCaller(req);
  if ("error" in caller) {
    return withCors(jsonResponse(caller.status, { error: caller.error }));
  }

  let deps: ReceiptDeps;
  try {
    deps = buildDeps(caller.householdId);
  } catch (e) {
    // A missing ANTHROPIC_API_KEY or SUPABASE_DB_URL is a server misconfig, not
    // a client error → a 500. The detail names env vars and provider internals,
    // so it goes to the function log, never to the caller.
    console.error(
      `import-receipt: dependency wiring failed: ${
        e instanceof Error ? e.stack ?? e.message : String(e)
      }`,
    );
    return withCors(
      jsonResponse(500, { error: "receipt import is not configured" }),
    );
  }
  return withCors(await makeHandler(deps)(req));
}

/** Starts the edge server. Called only from `index.ts`'s `import.meta.main`. */
export function serveImport(): void {
  Deno.serve(handle);
}
