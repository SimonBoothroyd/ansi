// Edge function: read-label, the third model door and the smallest.
//
//   one photo → ① read (vision) → LabelReading
//
// It shares `import-receipt`'s auth and allowlist, model pin, photo caps,
// transport and failure shapes. What it does NOT share is the stream: one
// image and one call finish well inside the platform's idle timeout, so the
// answer is a plain JSON body with no stages and no heartbeat.
//
// **It writes nothing and reads nothing.** There is no database seam at all
// (`no_write.test.ts`): what the reading becomes is the ingredient form's
// business, and nothing is saved until the person presses Save.

import type { LabelAdapter, LabelReading } from "../_shared/label_types.ts";
import { ImportError } from "../_shared/errors.ts";
import { failureFor as sharedFailureFor } from "../_shared/failures.ts";
import { jsonResponse, parseImages } from "../_shared/http_edge.ts";

export { ImportError };
export { MAX_IMAGE_BYTES } from "../_shared/http_edge.ts";

/** The injected collaborator. The real one is wired in `live.ts`. */
export interface LabelDeps {
  adapter: LabelAdapter;
}

/** Request to the door: the one photo of the label. */
export interface LabelRequest {
  image: Uint8Array;
}

/** Reads the label. Pure orchestration over the injected `deps`. */
export function readLabel(
  req: LabelRequest,
  deps: LabelDeps,
): Promise<LabelReading> {
  return deps.adapter.read(req.image);
}

// --- HTTP boundary -----------------------------------------------------------

/**
 * Parses a decoded JSON body into a {@link LabelRequest}, or an error message
 * (⇒ 400). Total: it never throws, because it runs before the handler's
 * try/catch.
 *
 * ONE image. A label is one panel; asking for several would mean asking which
 * of the readings to believe, and the form has one set of fields.
 */
export function parseRequestBody(
  body: unknown,
): { request: LabelRequest } | { error: string } {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { error: "body must be a JSON object" };
  }
  const b = body as Record<string, unknown>;
  if (!Array.isArray(b.images)) {
    return { error: "body must include `images`" };
  }
  if (b.images.length > 1) {
    return { error: "a label is read from one photo" };
  }
  const parsed = parseImages(b.images);
  if ("error" in parsed) return parsed;
  return { request: { image: parsed.images[0] } };
}

/**
 * What a person is told when the read throws, and the status that carries it.
 * The shapes are `_shared/failures.ts`'s, shared with both import doors.
 */
export function failureFor(e: unknown): { status: number; error: string } {
  return sharedFailureFor(e, { fn: "read-label", subject: "label" });
}

/** Builds the HTTP handler over injected `deps`. */
export function makeHandler(
  deps: LabelDeps,
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
      return jsonResponse(200, await readLabel(parsed.request, deps));
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
  import("./live.ts").then((m) => m.serveReadLabel());
}
