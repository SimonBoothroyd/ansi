// Production wiring for `read-label`: a `ClaudeLabelAdapter` over the same
// pinned model the two import doors use, the shared household gate
// (`auth.ts`), and a permissive CORS preflight.
//
// There is no Postgres seam here, and that is the point — this door reads an
// image and hands the figures back. It never opens a connection, so there is
// no pool, no database url to read, and nothing for a write to be introduced
// into. `no_write.test.ts` refuses a statement verb, the driver or that url's
// name in any file this door owns, which is why none of them appears above.

import { ClaudeLabelAdapter } from "../_shared/adapters/claude_label.ts";
import { CORS_HEADERS, jsonResponse, withCors } from "../_shared/http_edge.ts";
import { readCaller } from "./auth.ts";
import { type LabelDeps, makeHandler } from "./index.ts";

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  const caller = readCaller(req);
  if ("error" in caller) {
    return withCors(jsonResponse(caller.status, { error: caller.error }));
  }

  let deps: LabelDeps;
  try {
    deps = { adapter: new ClaudeLabelAdapter() };
  } catch (e) {
    // A missing ANTHROPIC_API_KEY is a server misconfig → a 500. The detail
    // goes to the function log, never to the caller.
    console.error(
      `read-label: dependency wiring failed: ${
        e instanceof Error ? e.stack ?? e.message : String(e)
      }`,
    );
    return withCors(
      jsonResponse(500, { error: "reading a label is not configured" }),
    );
  }
  return withCors(await makeHandler(deps)(req));
}

/** Starts the edge server. Called only from `index.ts`'s `import.meta.main`. */
export function serveReadLabel(): void {
  Deno.serve(handle);
}
