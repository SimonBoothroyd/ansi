// The HTTP edges both import functions sit behind: the photo intake's cost
// caps, the SSE frame shape, and the one wording a failure is given.
//
// It was `import-recipe/index.ts`'s alone until `import-receipt` arrived. A
// second copy of "how big may a photo be", "what does an SSE frame look like"
// and "what does a person see when the model ran long" is three chances for
// the two doors to answer differently for no reason a person could discover —
// so they answer from here, and each function supplies only the words that are
// genuinely its own.
//
// Nothing in this module knows what a recipe or a receipt is.

// --- Per-call cost caps ------------------------------------------------------
//
// Every image is billed to a vision model, so the request body is bounded HERE,
// before a byte of it reaches a provider. These are deliberately generous (a
// long recipe spans a few pages, a tall receipt goes in two or three shots, and
// `resizeForUpload` shrinks big photos) — they exist to stop an accidental or
// hostile 200-image / 100 MB call, not to second-guess a real import.

/** Most photos one call may carry. */
export const MAX_IMAGES = 8;
/** Most DECODED bytes one photo may carry (the app already downscales). */
export const MAX_IMAGE_BYTES = 3 * 1024 * 1024;
// base64 inflates by 4/3; reject on the encoded length first so an oversized
// payload is never materialised as bytes just to be measured.
const MAX_IMAGE_B64_CHARS = Math.ceil(MAX_IMAGE_BYTES / 3) * 4 + 8;

/** Decodes a base64 string to bytes (no @std dep — keeps the fns lean). */
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
 * TOTAL: every rejection path — malformed base64 included — RETURNS rather than
 * throws, because this runs before a handler's try/catch and a throw here would
 * escape as an unhandled 500.
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
  // Long-lived responses die to proxy buffering more often than to anything
  // else; this is the header that turns it off where it is honoured.
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
 * Longest the stream may go quiet WHILE A MODEL CALL IS STREAMING. The model
 * calls are the long stages, and before this they were also silent ones: the
 * gap between two stage events was a whole model deadline, which is what forced
 * those deadlines to fit inside the platform's idle cut-off.
 *
 * A heartbeat is not a clock tick — it is only sent because the model produced
 * output since the last frame we sent, so it means "still working", not "still
 * connected". That keeps the client's silence rung honest: silence still means
 * something is wrong, it just no longer means "the model is being slow".
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
 * Copies a response through, stamping the CORS headers onto it. The body is
 * passed as a STREAM, never read: the success answer is `text/event-stream` and
 * buffering it here would hold every stage event back until the work was
 * already over — which is the whole thing the stream exists to avoid.
 */
export function withCors(res: Response): Response {
  const headers = new Headers(res.headers);
  for (const [k, v] of Object.entries(CORS_HEADERS)) headers.set(k, v);
  return new Response(res.body, { status: res.status, headers });
}
