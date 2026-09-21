// The HTTP edges both import functions share: the photo intake's cost caps,
// the SSE frame shape, and the wording a failure is given. Nothing here knows
// what a recipe or a receipt is.

// --- Per-call cost caps ------------------------------------------------------
//
// Every image is billed to a vision model, so the request body is bounded
// here, before it reaches a provider. Generous: they exist to stop an
// accidental or hostile 200-image / 100 MB call.

/** Most photos one call may carry. */
export const MAX_IMAGES = 8;
/** Most decoded bytes one photo may carry (the app already downscales). */
export const MAX_IMAGE_BYTES = 3 * 1024 * 1024;
// base64 inflates by 4/3; reject on the encoded length first, before decoding.
const MAX_IMAGE_B64_CHARS = Math.ceil(MAX_IMAGE_BYTES / 3) * 4 + 8;

/** Decodes a base64 string to bytes (no @std dep). */
function decodeBase64(b64: string): Uint8Array {
  const bin = atob(b64); // throws on non-base64 input — callers must catch
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function oversizeMessage(index: number, bytes: number): string {
  const mb = (n: number) => (n / (1024 * 1024)).toFixed(1);
  return `image ${index + 1} is ${mb(bytes)}MB — the limit is ${
    mb(MAX_IMAGE_BYTES)
  }MB per image`;
}

/**
 * A JSON body's `images` array → decoded bytes, or an error message (⇒ 400).
 * Total: it never throws, because it runs before a handler's try/catch.
 */
export function parseImages(
  raw: unknown[],
): { images: Uint8Array[] } | { error: string } {
  if (raw.length === 0) return { error: "`images` must not be empty" };
  if (raw.length > MAX_IMAGES) {
    return {
      error:
        `too many images: ${raw.length} (at most ${MAX_IMAGES} per import)`,
    };
  }
  const images: Uint8Array[] = [];
  for (let i = 0; i < raw.length; i++) {
    const s = raw[i];
    if (typeof s !== "string") {
      return { error: "`images` must be an array of base64 strings" };
    }
    if (s.length > MAX_IMAGE_B64_CHARS) {
      return { error: oversizeMessage(i, (s.length / 4) * 3) };
    }
    let bytes: Uint8Array;
    try {
      bytes = decodeBase64(s);
    } catch {
      return { error: `image ${i + 1} is not valid base64` };
    }
    if (bytes.length > MAX_IMAGE_BYTES) {
      return { error: oversizeMessage(i, bytes.length) };
    }
    images.push(bytes);
  }
  return { images };
}

// --- The stream --------------------------------------------------------------

export const SSE_HEADERS: Record<string, string> = {
  "content-type": "text/event-stream",
  "cache-control": "no-cache",
  // Turns off proxy buffering, which kills long-lived responses.
  "x-accel-buffering": "no",
};

/** One SSE frame. Data is single-line JSON, so no multi-line `data:` folding. */
export function sseFrame(event: string, data: unknown): string {
  return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
}

export function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

/**
 * Longest the stream may go quiet while a model call is streaming. A heartbeat
 * is sent only because the model produced output since the last frame, so it
 * means "still working", and client-side silence still means a fault.
 */
export const HEARTBEAT_INTERVAL_MS = 10_000;

// --- CORS --------------------------------------------------------------------

export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/**
 * Copies a response through with the CORS headers. The body is passed as a
 * stream, never read: buffering `text/event-stream` would hold every stage
 * event back until the work was over.
 */
export function withCors(res: Response): Response {
  const headers = new Headers(res.headers);
  for (const [k, v] of Object.entries(CORS_HEADERS)) headers.set(k, v);
  return new Response(res.body, { status: res.status, headers });
}
