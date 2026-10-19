// Edge function: ask, the assistant's relay (plan 0053).
//
//   the conversation so far → one model call → the assistant's next blocks
//
// The app holds the conversation and runs every tool against its own
// database, with the Dart that scales a recipe; this door adds the prompt and
// the tool list, spends the model call, and hands the blocks back. It shares
// `read-label`'s gate, allowlist and failure shapes.
//
// **It reads and writes nothing.** No database seam at all
// (`no_write.test.ts`). The household's rows reach the model only as the tool
// results the app chose to send.

import type { AskAdapter, AskMessage, AskReply } from "../_shared/ask_types.ts";
import { ImportError } from "../_shared/errors.ts";
import { failureFor as sharedFailureFor } from "../_shared/failures.ts";
import { jsonResponse } from "../_shared/http_edge.ts";

export { ImportError };

/** The injected collaborator. The real one is wired in `live.ts`. */
export interface AskDeps {
  adapter: AskAdapter;
}

/** Request to the door: the whole conversation, ending on the member. */
export interface AskRequest {
  messages: AskMessage[];
}

/**
 * The most turns one request may carry. The app clears a thread after 30
 * idle minutes and trims long ones (`ask_thread.dart`), so a real kitchen
 * conversation stays far below this; the cap bounds what one call can spend.
 */
export const MAX_MESSAGES = 120;

/** The most bytes the conversation may weigh, as JSON. */
export const MAX_BODY_BYTES = 256 * 1024;

/** The block types each side may send. */
const USER_BLOCKS = new Set(["text", "tool_result"]);
const ASSISTANT_BLOCKS = new Set([
  "text",
  "tool_use",
  "thinking",
  "redacted_thinking",
]);

/** Answers the conversation. Pure orchestration over the injected `deps`. */
export function ask(req: AskRequest, deps: AskDeps): Promise<AskReply> {
  return deps.adapter.turn(req.messages);
}

// --- HTTP boundary -----------------------------------------------------------

/** Why one message is unusable, or null when it is fine. */
function messageError(m: unknown, i: number): string | null {
  if (!m || typeof m !== "object" || Array.isArray(m)) {
    return `message ${i} must be an object`;
  }
  const msg = m as Record<string, unknown>;
  const expected = i % 2 === 0 ? "user" : "assistant";
  if (msg.role !== expected) {
    return `message ${i} must be from the ${expected}: turns alternate, ` +
      "starting with the member";
  }
  const content = msg.content;
  if (typeof content === "string") {
    return content.trim() === "" ? `message ${i} is empty` : null;
  }
  if (!Array.isArray(content) || content.length === 0) {
    return `message ${i} must carry text or blocks`;
  }
  const allowed = expected === "user" ? USER_BLOCKS : ASSISTANT_BLOCKS;
  for (const block of content) {
    const type = block && typeof block === "object"
      ? (block as Record<string, unknown>).type
      : undefined;
    if (typeof type !== "string" || !allowed.has(type)) {
      return `message ${i} carries a block the ${expected} cannot send`;
    }
  }
  return null;
}

/**
 * Parses a decoded JSON body into an {@link AskRequest}, or an error message
 * (⇒ 400). Total: it never throws, because it runs before the handler's
 * try/catch. Blocks pass through untouched past their `type` — a thinking
 * block is only valid as it was produced.
 */
export function parseRequestBody(
  body: unknown,
): { request: AskRequest } | { error: string } {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { error: "body must be a JSON object" };
  }
  const messages = (body as Record<string, unknown>).messages;
  if (!Array.isArray(messages) || messages.length === 0) {
    return { error: "body must include `messages`" };
  }
  if (messages.length > MAX_MESSAGES) {
    return { error: "this conversation is too long — start a new one" };
  }
  if (
    new TextEncoder().encode(JSON.stringify(messages)).length > MAX_BODY_BYTES
  ) {
    return { error: "this conversation is too long — start a new one" };
  }
  for (let i = 0; i < messages.length; i++) {
    const error = messageError(messages[i], i);
    if (error) return { error };
  }
  if (messages.length % 2 === 0) {
    return { error: "the conversation must end on the member's turn" };
  }
  return { request: { messages: messages as AskMessage[] } };
}

/**
 * What a member is told when the turn throws, and the status that carries
 * it. The shapes are `_shared/failures.ts`'s, shared with every model door.
 */
export function failureFor(e: unknown): { status: number; error: string } {
  const failure = sharedFailureFor(e, { fn: "ask", subject: "question" });
  // The shared 500 names an import; this door is not one.
  return failure.status === 500
    ? { status: 500, error: "Ansi could not answer that — try again" }
    : failure;
}

/** Builds the HTTP handler over injected `deps`. */
export function makeHandler(
  deps: AskDeps,
): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") {
      return jsonResponse(405, { error: "POST required" });
    }
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse(400, { error: "invalid JSON body" });
    }
    const parsed = parseRequestBody(body);
    if ("error" in parsed) return jsonResponse(400, { error: parsed.error });
    try {
      return jsonResponse(200, await ask(parsed.request, deps));
    } catch (e) {
      const failure = failureFor(e);
      return jsonResponse(failure.status, { error: failure.error });
    }
  };
}

// Production wiring lives in `live.ts`, loaded only when this module is the
// served entry point, so the orchestration and its tests never pull in an
// adapter that wants an API key.
if (import.meta.main) {
  // Not a top-level await: `live.ts` imports back from this module, so awaiting
  // here would deadlock module evaluation.
  import("./live.ts").then((m) => m.serveAsk());
}
