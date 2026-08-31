// Small shared helpers for the provider adapters. Raw `fetch` (no per-provider
// SDK) keeps the three adapters uniform, dependency-free, and fully reasonable
// in-repo — the same reason the codebase favours boring, legible dependencies
// (AGENTS.md). Each adapter owns its provider's request/response shape; this
// file only holds what all three share.

import { Image } from "imagescript";

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
  timeoutMs?: number;
}

/** Transient HTTP statuses worth retrying (overload, rate limit, gateway). */
const TRANSIENT_STATUSES = new Set([408, 429, 500, 502, 503, 504]);
const MAX_ATTEMPTS = 5;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const backoffMs = (attempt: number) =>
  Math.min(16_000, 1000 * 2 ** (attempt - 1)) + Math.random() * 500;

/**
 * POST JSON, return parsed JSON. Retries transient failures (429/503/5xx and
 * network/abort errors) with exponential backoff — providers like Gemini Flash
 * 503 "high demand" intermittently. Throws a typed ProviderHttpError only on a
 * non-transient status or once retries are exhausted.
 */
export async function postJson(opts: PostJsonOpts): Promise<unknown> {
  for (let attempt = 1;; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(
      () => controller.abort(),
      opts.timeoutMs ?? 120_000,
    );
    let res: Response;
    let text: string;
    try {
      res = await fetch(opts.url, {
        method: "POST",
        headers: { "content-type": "application/json", ...opts.headers },
        body: JSON.stringify(opts.body),
        signal: controller.signal,
      });
      text = await res.text();
    } catch (e) {
      // Network / timeout-abort — transient; retry until exhausted.
      clearTimeout(timer);
      if (attempt >= MAX_ATTEMPTS) throw e;
      await sleep(backoffMs(attempt));
      continue;
    }
    clearTimeout(timer);
    if (res.ok) return JSON.parse(text);
    if (TRANSIENT_STATUSES.has(res.status) && attempt < MAX_ATTEMPTS) {
      const retryAfter = Number(res.headers.get("retry-after"));
      await sleep(
        Number.isFinite(retryAfter) && retryAfter > 0
          ? retryAfter * 1000
          : backoffMs(attempt),
      );
      continue;
    }
    throw new ProviderHttpError(opts.provider, res.status, text);
  }
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
 * Downscale a recipe photo before it goes to a vision model: decode the JPEG,
 * scale so the longest edge is ≈ `UPLOAD_MAX_EDGE`px (skip if already ≤ that),
 * re-encode JPEG at quality ~85, return the bytes. Still `image/jpeg`.
 *
 * Pure/WASM (imagescript) — no subprocess, so it is safe on Deno Deploy where
 * the edge function runs. GRACEFUL: any decode/encode failure logs and returns
 * the ORIGINAL bytes rather than throwing, so one odd image can never crash a
 * transcribe call.
 */
export async function resizeForUpload(bytes: Uint8Array): Promise<Uint8Array> {
  try {
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
