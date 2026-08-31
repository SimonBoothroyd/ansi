// Small shared helpers for the provider adapters. Raw `fetch` (no per-provider
// SDK) keeps the three adapters uniform, dependency-free, and fully reasonable
// in-repo — the same reason the codebase favours boring, legible dependencies
// (AGENTS.md). Each adapter owns its provider's request/response shape; this
// file only holds what all three share.

/** Reads an API key from env, throwing a clear error when it is absent. */
export function requireKey(envVar: string, providerLabel: string): string {
  const key = Deno.env.get(envVar);
  if (!key || key.trim() === "") {
    throw new MissingKeyError(envVar, providerLabel);
  }
  return key;
}

export class MissingKeyError extends Error {
  constructor(readonly envVar: string, readonly provider: string) {
    super(
      `${provider} adapter needs ${envVar} — set it to run live (keyless runs ` +
        `use the mock adapter).`,
    );
    this.name = "MissingKeyError";
  }
}

export class ProviderHttpError extends Error {
  constructor(
    readonly provider: string,
    readonly status: number,
    readonly body: string,
  ) {
    super(`${provider} HTTP ${status}: ${body.slice(0, 500)}`);
    this.name = "ProviderHttpError";
  }
}

export interface PostJsonOpts {
  url: string;
  headers: Record<string, string>;
  body: unknown;
  provider: string;
  /** Per-attempt wall clock. Also clamped by whatever the deadline has left. */
  timeoutMs?: number;
  /** TOTAL budget across every attempt and every backoff sleep. */
  deadlineMs?: number;
  /** Backoff base; a test seam so retry paths don't cost seconds. */
  baseBackoffMs?: number;
  /** Fetch seam — the global `fetch` in prod, a stub in tests. */
  fetchImpl?: typeof fetch;
}

/** Transient HTTP statuses worth retrying (overload, rate limit, gateway). */
const TRANSIENT_STATUSES = new Set([408, 429, 500, 502, 503, 504]);
/**
 * Attempts, and the TOTAL budget they share. The caller is a user staring at a
 * spinner inside an edge function with its own wall-clock limit, so the ceiling
 * that matters is the total, not the per-attempt one: five attempts each
 * allowed 120s could hang for ten minutes.
 */
const MAX_ATTEMPTS = 3;
const DEFAULT_DEADLINE_MS = 60_000;
const DEFAULT_ATTEMPT_TIMEOUT_MS = 45_000;
/** Longest we honour a `Retry-After`. Providers do send `600`. */
export const MAX_RETRY_AFTER_MS = 10_000;

/**
 * A `Retry-After` header as a delay in ms, or null when it is absent/unusable
 * (an HTTP-date form included — we fall back to backoff rather than parse it).
 * CLAMPED: an honest `Retry-After: 600` is a request to sleep ten minutes inside
 * a request handler, which is not a thing we can do to a waiting user.
 */
export function retryAfterDelayMs(header: string | null): number | null {
  const seconds = Number(header);
  if (!Number.isFinite(seconds) || seconds <= 0) return null;
  return Math.min(seconds * 1000, MAX_RETRY_AFTER_MS);
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Thrown when the shared deadline runs out before a usable response. */
export class ProviderTimeoutError extends Error {
  constructor(readonly provider: string, readonly deadlineMs: number) {
    super(`${provider} did not answer within ${deadlineMs}ms`);
    this.name = "ProviderTimeoutError";
  }
}

/**
 * POST JSON, return parsed JSON. Retries transient failures (429/503/5xx and
 * network/abort errors) with exponential backoff — providers like Gemini Flash
 * 503 "high demand" intermittently — but every attempt and every sleep draws on
 * ONE total deadline, so the worst case is bounded.
 *
 * Throws `ProviderHttpError` on a non-transient status, on a 2xx whose body is
 * not JSON (a proxy's HTML error page reaches us as a 200), or once retries are
 * exhausted; `ProviderTimeoutError` when the deadline runs out first.
 */
export async function postJson(opts: PostJsonOpts): Promise<unknown> {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const budget = opts.deadlineMs ?? DEFAULT_DEADLINE_MS;
  const base = opts.baseBackoffMs ?? 1000;
  const deadline = Date.now() + budget;
  const backoffMs = (attempt: number) =>
    Math.min(16_000, base * 2 ** (attempt - 1)) + Math.random() * (base / 2);
  /** Sleeps `ms`, or gives up if that would blow the deadline. */
  const sleepWithin = async (ms: number): Promise<boolean> => {
    const left = deadline - Date.now();
    if (left <= 0 || ms >= left) return false;
    await sleep(ms);
    return true;
  };

  let lastError: unknown = null;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    const left = deadline - Date.now();
    if (left <= 0) break;
    const controller = new AbortController();
    const timer = setTimeout(
      () => controller.abort(),
      Math.min(opts.timeoutMs ?? DEFAULT_ATTEMPT_TIMEOUT_MS, left),
    );
    let res: Response;
    let text: string;
    try {
      res = await fetchImpl(opts.url, {
        method: "POST",
        headers: { "content-type": "application/json", ...opts.headers },
        body: JSON.stringify(opts.body),
        signal: controller.signal,
      });
      text = await res.text();
    } catch (e) {
      // Network / timeout-abort — transient; retry while the budget allows.
      clearTimeout(timer);
      lastError = e;
      if (attempt >= MAX_ATTEMPTS) throw e;
      if (!await sleepWithin(backoffMs(attempt))) break;
      continue;
    }
    clearTimeout(timer);

    if (res.ok) {
      try {
        return JSON.parse(text);
      } catch {
        // A 200 that isn't JSON is a provider/proxy fault, not a parse bug of
        // ours — map it onto the same typed contract as any other bad response
        // so callers have one thing to catch.
        throw new ProviderHttpError(
          opts.provider,
          res.status,
          `non-JSON body: ${text.slice(0, 200)}`,
        );
      }
    }

    if (TRANSIENT_STATUSES.has(res.status) && attempt < MAX_ATTEMPTS) {
      lastError = new ProviderHttpError(opts.provider, res.status, text);
      const honoured = retryAfterDelayMs(res.headers.get("retry-after")) ??
        backoffMs(attempt);
      if (!await sleepWithin(honoured)) break;
      continue;
    }
    throw new ProviderHttpError(opts.provider, res.status, text);
  }
  if (lastError) throw lastError;
  throw new ProviderTimeoutError(opts.provider, budget);
}

/** Base64-encode image bytes for a data payload. */
export function toBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

/**
 * Pulls the first JSON object out of a text blob. Providers in structured-output
 * mode return clean JSON, but a stray markdown fence or leading prose is a
 * common real-world wobble — recover from it rather than fail the whole case.
 */
export function extractJson(text: string): string {
  const trimmed = text.trim();
  const fence = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) return fence[1].trim();
  const start = trimmed.indexOf("{");
  const end = trimmed.lastIndexOf("}");
  if (start !== -1 && end !== -1 && end > start) {
    return trimmed.slice(start, end + 1);
  }
  return trimmed;
}

/** Media type for a recipe photo — the corpus is JPEG. */
export const IMAGE_MEDIA_TYPE = "image/jpeg";

/**
 * Longest-edge target (px) for uploaded photos (spec §4.3). The Pixel corpus is
 * ~4080×3064; the vision models gain nothing from that resolution and it costs
 * 3–5 MB of base64 per image, so we downscale before upload.
 */
export const UPLOAD_MAX_EDGE = 1568;

/**
 * Reads a JPEG's pixel dimensions from its SOF header — bytes only, no decode.
 * Returns null for anything that is not a JPEG we can read this cheaply (the
 * caller then falls back to a real decode).
 */
export function jpegDimensions(
  bytes: Uint8Array,
): { width: number; height: number } | null {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
  let i = 2;
  while (i + 3 < bytes.length) {
    if (bytes[i] !== 0xff) return null; // not on a marker boundary — give up
    const marker = bytes[i + 1];
    if (marker === 0xff) { // fill byte
      i++;
      continue;
    }
    if (
      marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)
    ) {
      i += 2; // standalone marker, no payload
      continue;
    }
    if (marker === 0xda || marker === 0xd9) return null; // scan/end: no SOF found
    const length = (bytes[i + 2] << 8) | bytes[i + 3];
    if (length < 2 || i + 2 + length > bytes.length) return null;
    // SOF0-3, SOF5-7, SOF9-11, SOF13-15 — every frame header carries the size.
    const isSof = marker >= 0xc0 && marker <= 0xcf &&
      marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;
    if (isSof) {
      if (length < 7) return null;
      const height = (bytes[i + 5] << 8) | bytes[i + 6];
      const width = (bytes[i + 7] << 8) | bytes[i + 8];
      return width > 0 && height > 0 ? { width, height } : null;
    }
    i += 2 + length;
  }
  return null;
}

/**
 * Downscale a recipe photo before it goes to a vision model: decode the JPEG,
 * scale so the longest edge is ≈ `UPLOAD_MAX_EDGE`px (skip if already ≤ that),
 * re-encode JPEG at quality ~85, return the bytes. Still `image/jpeg`.
 *
 * Pure/WASM (imagescript) — no subprocess, so it is safe on Deno Deploy where
 * the edge function runs. The WASM decode is the expensive part, so an image
 * whose SOF header already reports an in-budget size skips it entirely (the
 * app downscales before upload, making that the common case). GRACEFUL: any
 * decode/encode failure logs and returns the ORIGINAL bytes rather than
 * throwing, so one odd image can never crash a transcribe call.
 */
export async function resizeForUpload(bytes: Uint8Array): Promise<Uint8Array> {
  const header = jpegDimensions(bytes);
  if (header && Math.max(header.width, header.height) <= UPLOAD_MAX_EDGE) {
    return bytes;
  }
  try {
    // Imported LAZILY: imagescript instantiates a WASM module at import time by
    // fetching it over the network, which would make merely importing this file
    // (any adapter, any test) require net access and pay that cost on every
    // cold start — including URL imports, which never decode an image.
    const { Image } = await import("imagescript");
    const img = await Image.decode(bytes);
    const longest = Math.max(img.width, img.height);
    if (longest <= UPLOAD_MAX_EDGE) return bytes;
    const scale = UPLOAD_MAX_EDGE / longest;
    const resized = img.resize(
      Math.max(1, Math.round(img.width * scale)),
      Math.max(1, Math.round(img.height * scale)),
    );
    return await resized.encodeJPEG(85);
  } catch (err) {
    console.error(
      `resizeForUpload: falling back to original bytes (${bytes.length}B): ${
        err instanceof Error ? err.message : String(err)
      }`,
    );
    return bytes;
  }
}
