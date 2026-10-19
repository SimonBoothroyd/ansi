// Production wiring for `ask`: a `ClaudeAskAdapter` over the door's own pin,
// the shared household gate (`auth.ts`), and a permissive CORS preflight.
//
// There is no Postgres seam here, and that is the point — the household's rows
// reach this door only as tool results the app sent. `no_write.test.ts`
// refuses a statement verb, the driver or the connection string's name in any
// file this door owns.

import { ClaudeAskAdapter } from "../_shared/adapters/claude_ask.ts";
import { CORS_HEADERS, jsonResponse, withCors } from "../_shared/http_edge.ts";
import { readCaller } from "./auth.ts";
import { type AskDeps, makeHandler } from "./index.ts";

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  const caller = readCaller(req);
  if ("error" in caller) {
    return withCors(jsonResponse(caller.status, { error: caller.error }));
  }

  let deps: AskDeps;
  try {
    deps = { adapter: new ClaudeAskAdapter() };
  } catch (e) {
    // A missing ANTHROPIC_API_KEY is a server misconfig → a 500. The detail
    // goes to the function log, never to the caller.
    console.error(
      `ask: dependency wiring failed: ${
        e instanceof Error ? e.stack ?? e.message : String(e)
      }`,
    );
    return withCors(
      jsonResponse(500, { error: "asking Ansi is not configured" }),
    );
  }
  return withCors(await makeHandler(deps)(req));
}

/** Starts the edge server. Called only from `index.ts`'s `import.meta.main`. */
export function serveAsk(): void {
  Deno.serve(handle);
}
