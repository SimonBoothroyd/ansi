// Production wiring for `share-recipe`: a Postgres pool on `SUPABASE_DB_URL`
// (service role, read by token alone — `payload.ts`), the compiled renderer
// (`bundle.ts`), and the share host the links are minted under
// (`SHARE_BASE_URL`, optional).

import postgres from "postgres";
import { bundledRenderer, SHARE_BUNDLE, shortHash } from "./bundle.ts";
import { makeHandler, payloadLoader } from "./index.ts";
import type { SqlExecutor } from "./payload.ts";

let pool: ReturnType<typeof postgres> | null = null;

function executor(): SqlExecutor {
  if (!pool) {
    const url = Deno.env.get("SUPABASE_DB_URL");
    if (!url || url.trim() === "") {
      throw new Error("SUPABASE_DB_URL is not set");
    }
    // One read per page; `prepare: false` for a transaction-mode pooler.
    pool = postgres(url, { prepare: false, max: 2 });
  }
  const sql = pool;
  return <T = Record<string, unknown>>(text: string, params: unknown[]) =>
    sql.unsafe(text, params as never[]) as unknown as Promise<T[]>;
}

/** Starts the edge server. Called only from `index.ts`'s `import.meta.main`. */
export async function serveShare(): Promise<void> {
  const handler = makeHandler({
    loadPayload: (token) => payloadLoader(executor())(token),
    render: bundledRenderer(),
    bundle: SHARE_BUNDLE,
    bundleVersion: await shortHash(SHARE_BUNDLE),
    shareBase: Deno.env.get("SHARE_BASE_URL")?.trim() || null,
  });
  Deno.serve(handler);
}
