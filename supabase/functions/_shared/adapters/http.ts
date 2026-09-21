// Shared helpers for the provider adapters. Raw `fetch`, no provider SDKs; each
// adapter owns its provider's request/response shape.

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
 * Attempts, and the total budget they share. These belong to `postJson`, the
 * benchmark-only path (Gemini, GPT). Production goes through `streamJson`,
 * whose per-op budgets live in `claude.ts`. The whole timeout ladder is
 * written out in
 * `app/lib/features/import/data/remote_import_repository.dart`.
 */
export const MAX_ATTEMPTS = 3;
/** Total budget for one logical provider call, across attempts and sleeps. */
export const DEFAULT_DEADLINE_MS = 60_000;
/** Per-attempt wall clock, so one hung socket cannot eat the whole deadline. */
export const DEFAULT_ATTEMPT_TIMEOUT_MS = 45_000;
/** Longest we honour a `Retry-After`. Providers do send `600`. */
export const MAX_RETRY_AFTER_MS = 10_000;

/**
 * A `Retry-After` header as a delay in ms, or null when absent or unusable
 * (the HTTP-date form included). Clamped to {@link MAX_RETRY_AFTER_MS}.
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
 * network/abort errors) with exponential backoff, all within one total
 * deadline.
 *
 * Throws `ProviderHttpError` on a non-transient status, on a 2xx whose body is
 * not JSON, or once retries are exhausted; `ProviderTimeoutError` when the
 * deadline runs out first.
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
      // Network error or timeout abort: transient.
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
        // A 200 that is not JSON is a provider/proxy fault; same typed error.
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

// --- Streaming one provider call ---------------------------------------------
//
// `streamJson` replaces `postJson` for the calls a user waits on:
//
//   * an idle timer instead of a per-attempt wall clock: arriving bytes prove
//     the provider is working, so what is bounded is silence.
//   * no retry once the answer has started: the aborted attempt was already
//     generated and billed.
//   * no retry is started into a budget too small to finish in.
//
// The assembled value has the non-streaming response's shape.

/** No progress on the wire for this long and the attempt is abandoned. */
export const DEFAULT_IDLE_TIMEOUT_MS = 20_000;
/**
 * Shortest window a retry may be started into; below it the attempt would be
 * aborted mid-generation after billing a full response. It does not gate the
 * first attempt.
 */
export const DEFAULT_MIN_ATTEMPT_MS = 30_000;

/** Folds a provider's stream frames into one response object. */
export interface StreamAssembler {
  /**
   * Folds one frame in. Returns true when the frame carried generated output.
   * Throws to fail the attempt (a provider error frame).
   */
  push(event: string, data: unknown): boolean;
  /** The assembled response, or null when the stream stopped mid-message. */
  finish(): unknown | null;
}

export interface StreamJsonOpts {
  url: string;
  headers: Record<string, string>;
  /** Request body. `stream: true` is added here. */
  body: Record<string, unknown>;
  provider: string;
  /** Builds a fresh assembler per attempt. */
  assembler: () => StreamAssembler;
  /** Total budget across every attempt and every backoff sleep. */
  deadlineMs?: number;
  /** Silence that ends an attempt. See {@link DEFAULT_IDLE_TIMEOUT_MS}. */
  idleTimeoutMs?: number;
  /** Smallest budget worth retrying into. See {@link DEFAULT_MIN_ATTEMPT_MS}. */
  minAttemptMs?: number;
  /** Backoff base; a test seam so retry paths don't cost seconds. */
  baseBackoffMs?: number;
  /** Fetch seam — the global `fetch` in prod, a stub in tests. */
  fetchImpl?: typeof fetch;
  /** Told whenever the provider produced output. Its failures are swallowed. */
  onDelta?: () => void;
}

/** One `event:`/`data:` frame off an SSE body. */
interface SseFrame {
  event: string;
  data: string;
}

/** Parses one frame's lines; `data:` lines are joined with newlines. */
function parseSseFrame(frame: string): SseFrame | null {
  let event = "message";
  const data: string[] = [];
  for (const raw of frame.split("\n")) {
    const line = raw.endsWith("\r") ? raw.slice(0, -1) : raw;
    if (line === "" || line.startsWith(":")) continue;
    if (line.startsWith("event:")) event = line.slice(6).trim();
    else if (line.startsWith("data:")) data.push(line.slice(5).trimStart());
  }
  return data.length === 0 ? null : { event, data: data.join("\n") };
}

/** Yields SSE frames off a response body as they arrive. */
async function* sseFrames(
  body: ReadableStream<Uint8Array>,
): AsyncGenerator<SseFrame> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      let cut = buffer.indexOf("\n\n");
      while (cut !== -1) {
        const frame = parseSseFrame(buffer.slice(0, cut));
        buffer = buffer.slice(cut + 2);
        if (frame) yield frame;
        cut = buffer.indexOf("\n\n");
      }
    }
  } finally {
    // An abort would otherwise leave the body locked for the next attempt.
    reader.cancel().catch(() => {});
  }
}

/** Calls an observer without ever letting its failure reach the caller. */
function notify(fn: (() => void) | undefined): void {
  if (!fn) return;
  try {
    fn();
  } catch (e) {
    console.error(
      `stream observer threw (ignored): ${
        e instanceof Error ? e.message : String(e)
      }`,
    );
  }
}

/**
 * POST a streaming provider call and return the assembled response. Retries
 * transient failures only while nothing has been generated, and only into a
 * budget an attempt could finish in.
 *
 * Throws `ProviderHttpError` on a non-transient status, a provider error
 * frame, or a stream that ends mid-message; `ProviderTimeoutError` when the
 * budget is gone; and the abort itself when an attempt runs silent or
 * overruns. `isTimeoutFailure` reads the last two as a timeout.
 */
export async function streamJson(opts: StreamJsonOpts): Promise<unknown> {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const budget = opts.deadlineMs ?? DEFAULT_DEADLINE_MS;
  const idleMs = opts.idleTimeoutMs ?? DEFAULT_IDLE_TIMEOUT_MS;
  const minAttempt = opts.minAttemptMs ?? DEFAULT_MIN_ATTEMPT_MS;
  const base = opts.baseBackoffMs ?? 1000;
  const deadline = Date.now() + budget;
  const backoffMs = (attempt: number) =>
    Math.min(16_000, base * 2 ** (attempt - 1)) + Math.random() * (base / 2);
  const sleepWithin = async (ms: number): Promise<boolean> => {
    const left = deadline - Date.now();
    if (left <= 0 || ms >= left) return false;
    await sleep(ms);
    return true;
  };

  let lastError: unknown = null;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    const left = deadline - Date.now();
    // Out of time, or too little left for a retry to finish in. The minimum
    // gates retries only: the first attempt always dials.
    if (left <= 0 || (attempt > 1 && left < minAttempt)) {
      throw new ProviderTimeoutError(opts.provider, budget);
    }
    const controller = new AbortController();
    const wall = setTimeout(() => controller.abort(), left);
    let idle = setTimeout(() => controller.abort(), idleMs);
    /** A frame arrived: the provider is alive, so restart the silence clock. */
    const alive = () => {
      clearTimeout(idle);
      idle = setTimeout(() => controller.abort(), idleMs);
    };
    const assembler = opts.assembler();
    let produced = false;
    try {
      const res = await fetchImpl(opts.url, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "accept": "text/event-stream",
          ...opts.headers,
        },
        body: JSON.stringify({ ...opts.body, stream: true }),
        signal: controller.signal,
      });
      if (!res.ok) {
        const text = await res.text();
        if (TRANSIENT_STATUSES.has(res.status) && attempt < MAX_ATTEMPTS) {
          lastError = new ProviderHttpError(opts.provider, res.status, text);
          const honoured = retryAfterDelayMs(res.headers.get("retry-after")) ??
            backoffMs(attempt);
          if (!await sleepWithin(honoured)) break;
          continue;
        }
        throw new ProviderHttpError(opts.provider, res.status, text);
      }
      if (!res.body) {
        throw new ProviderHttpError(
          opts.provider,
          res.status,
          "a 200 with no body to stream",
        );
      }
      for await (const frame of sseFrames(res.body)) {
        alive();
        let data: unknown;
        try {
          data = JSON.parse(frame.data);
        } catch {
          continue; // a frame we cannot read is noise, not an answer
        }
        if (assembler.push(frame.event, data)) {
          produced = true;
          notify(opts.onDelta);
        }
      }
      const message = assembler.finish();
      if (message === null) {
        throw new ProviderHttpError(
          opts.provider,
          502,
          "the stream ended before the message did",
        );
      }
      return message;
    } catch (e) {
      lastError = e;
      // Past the first delta the answer was generated and billed; do not
      // retry.
      if (produced) throw e;
      if (e instanceof ProviderHttpError && !TRANSIENT_STATUSES.has(e.status)) {
        throw e;
      }
      if (attempt >= MAX_ATTEMPTS) throw e;
      if (!await sleepWithin(backoffMs(attempt))) break;
      continue;
    } finally {
      clearTimeout(wall);
      clearTimeout(idle);
    }
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
 * Pulls the first JSON object out of a text blob, recovering from a stray
 * markdown fence or leading prose.
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

/** Media type for a recipe photo. */
export const IMAGE_MEDIA_TYPE = "image/jpeg";

/** Longest-edge target (px) for uploaded photos (spec §4.3). */
export const UPLOAD_MAX_EDGE = 1568;

/**
 * Reads a JPEG's pixel dimensions from its SOF header without decoding.
 * Returns null for anything it cannot read this cheaply.
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
    // SOF0-3, SOF5-7, SOF9-11, SOF13-15: every frame header carries the size.
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
 * Downscales a photo before it goes to a vision model: longest edge ≈
 * `UPLOAD_MAX_EDGE`px, JPEG quality ~85. Pure WASM (imagescript), safe on Deno
 * Deploy. An image whose SOF header is already in budget skips the decode.
 * Any decode/encode failure logs and returns the original bytes.
 */
export async function resizeForUpload(bytes: Uint8Array): Promise<Uint8Array> {
  const header = jpegDimensions(bytes);
  if (header && Math.max(header.width, header.height) <= UPLOAD_MAX_EDGE) {
    return bytes;
  }
  try {
    // Imported lazily: imagescript fetches and instantiates a WASM module at
    // import time, which every importer of this file would otherwise pay.
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
