// Production wiring for `import-receipt`, the twin of `import-recipe/live.ts`:
// `ClaudeReceiptAdapter` over the same pinned model; a household-scoped
// `sqlVocabMatcher` and `sqlReceiptMemory` over Postgres (`SUPABASE_DB_URL`,
// service role), where the household comes only from the verified token; auth
// (`auth.ts`); and a permissive CORS preflight.
//
// There is no recipe-title tier, and nothing writes: the only SQL is three
// SELECTs (`no_alias.test.ts`). The app writes the receipt at Save.

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
// compatible with a transaction-mode pooler. `max` is small on purpose: one
// receipt needs at most two connections, because each tier is one batched
// query.
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
  // Off in every deployed environment; see `replay.ts`.
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
    // A missing ANTHROPIC_API_KEY or SUPABASE_DB_URL is a server misconfig → a
    // 500. The detail goes to the function log, never to the caller.
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
