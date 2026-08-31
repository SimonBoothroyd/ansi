// Edge function: import-recipe — the deterministic orchestration spine (§3, §4).
//
//   intake → RawBlob → ① sanitize (adapter) → §7 normalize → ⑥ match →
//   ReconciliationPayload
//
// This lane (A) owns the wiring; the two model-facing stages are consumed
// THROUGH their frozen interfaces and injected (`ImportDeps`), so the whole
// pipeline is offline-testable with fakes:
//   - `adapter` — the `ExtractAdapter` (lane D). `transcribe` is the vision tier
//     (images → RawBlob); `sanitize` is ①. Always an LLM in prod.
//   - `matchLines` — the deterministic, server-side match cascade (lane B). It
//     owns the §7 `normalize` call (normalize.ts's header: match.ts calls it),
//     so the orchestrator delegates matching rather than re-normalizing.
//   - `fetchBlob` — URL → RawBlob intake (lane A's own jsonld.ts).
//
// Never-invent (0014 INVARIANT): the orchestrator moves data, it never fills a
// value in. `parse_warnings`, `confidence`, ranges, `image_quality`, and the
// tokenized steps pass through from the `ExtractionResult` UNTOUCHED; step refs
// stay by flattened `line_index` (the app remaps them to line_item_ids on
// commit, §4.6). The human resolves bands and ranges at reconciliation.

import type {
  ExtractAdapter,
  ExtractionResult,
  MatchedLine,
  RawBlob,
  RawLineItem,
  ReconciliationPayload,
  ReconGroup,
  ReconLine,
} from "../_shared/types.ts";
import { deriveUnitHints } from "../_shared/unit_hints.ts";

/**
 * Match cascade seam (lane B). The orchestrator depends on a PRE-BOUND matcher
 * function — lane B's real `matchLines(lines, matcher)` takes a second
 * `VocabMatcher` (the household-scoped Postgres seam), which is constructed
 * per-request at integration (0019) and closed over here. That keeps lane A
 * decoupled from the DB, and tests inject a plain fake.
 */
export type MatchLinesFn = (lines: RawLineItem[]) => Promise<MatchedLine[]>;

/** The injected collaborators. Real ones wired at integration (0019); fakes in tests. */
export interface ImportDeps {
  adapter: ExtractAdapter;
  matchLines: MatchLinesFn;
  fetchBlob: (url: string) => Promise<RawBlob>;
}

/** Request to the pipeline: exactly one of `url` (page) or `images` (photos). */
export interface ImportRequest {
  url?: string;
  images?: Uint8Array[];
}

/** A client-visible pipeline error → surfaced as 4xx, never a 500. */
export class ImportError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ImportError";
  }
}

/**
 * Runs intake → ① → ⑥ and assembles the {@link ReconciliationPayload}. Pure
 * orchestration over the injected `deps`; deterministic given deterministic
 * collaborators.
 */
export async function importRecipe(
  req: ImportRequest,
  deps: ImportDeps,
): Promise<ReconciliationPayload> {
  const blob = await intake(req, deps);
  const hints = deriveUnitHints();
  const extraction = await deps.adapter.sanitize(blob, hints);
  const flat = flattenLines(extraction.groups);
  const matched = await deps.matchLines(flat);
  if (matched.length !== flat.length) {
    throw new ImportError(
      `matcher returned ${matched.length} lines for ${flat.length} inputs`,
    );
  }
  return assemble(extraction, matched);
}

/** Intake: URL → RawBlob via jsonld.ts, or images → RawBlob via the vision tier. */
async function intake(req: ImportRequest, deps: ImportDeps): Promise<RawBlob> {
  const hasUrl = typeof req.url === "string" && req.url.length > 0;
  const hasImages = Array.isArray(req.images) && req.images.length > 0;
  if (hasUrl && hasImages) {
    throw new ImportError("provide either `url` or `images`, not both");
  }
  if (hasUrl) return await deps.fetchBlob(req.url!);
  if (hasImages) {
    if (!deps.adapter.transcribe) {
      throw new ImportError(
        `adapter "${deps.adapter.name}" cannot transcribe images`,
      );
    }
    return await deps.adapter.transcribe(req.images!);
  }
  throw new ImportError("request must include a `url` or `images`");
}

/**
 * Flattens `groups[].line_items[]` into a single ordered list. This order IS the
 * `line_index` space that `steps[].tokens[].refs` point into (§4.6), so it must
 * be preserved end to end — group 0's lines, then group 1's, and so on.
 */
function flattenLines(groups: { line_items: RawLineItem[] }[]): RawLineItem[] {
  return groups.flatMap((g) => g.line_items);
}

/** Re-groups the flat `MatchedLine[]` back onto the original group shape. */
function assemble(
  extraction: ExtractionResult,
  matched: MatchedLine[],
): ReconciliationPayload {
  const groups: ReconGroup[] = [];
  let cursor = 0;
  for (const g of extraction.groups) {
    const lines: ReconLine[] = g.line_items.map(() => {
      const m = matched[cursor++];
      return { raw: m.raw, band: m.band, candidates: m.candidates };
    });
    groups.push({ name: g.name, lines });
  }
  return {
    title: extraction.title,
    servings_base: extraction.servings_base,
    servings_raw: extraction.servings_raw,
    yield_raw: extraction.yield_raw,
    total_time_seconds: extraction.total_time_seconds,
    cook_time_seconds: extraction.cook_time_seconds,
    truncated: extraction.truncated,
    image_quality: extraction.image_quality,
    parse_warnings: extraction.parse_warnings,
    groups,
    steps: extraction.steps, // refs stay by line_index — untouched
  };
}

// --- HTTP boundary -----------------------------------------------------------

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

/** Decodes a base64 string to bytes (no @std dep — keeps the fn lean). */
function decodeBase64(b64: string): Uint8Array {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

/** Parses a decoded JSON body into an {@link ImportRequest}, or an error message. */
export function parseRequestBody(
  body: unknown,
): { request: ImportRequest } | { error: string } {
  if (!body || typeof body !== "object") {
    return { error: "body must be a JSON object" };
  }
  const b = body as Record<string, unknown>;
  if (typeof b.url === "string") return { request: { url: b.url } };
  if (Array.isArray(b.images)) {
    if (!b.images.every((i) => typeof i === "string")) {
      return { error: "`images` must be an array of base64 strings" };
    }
    return { request: { images: (b.images as string[]).map(decodeBase64) } };
  }
  return { error: "body must include a `url` or `images`" };
}

/** Builds the HTTP handler over injected `deps` (real ones supplied at integration). */
export function makeHandler(
  deps: ImportDeps,
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
      const payload = await importRecipe(parsed.request, deps);
      return jsonResponse(200, payload);
    } catch (e) {
      if (e instanceof ImportError) {
        return jsonResponse(422, { error: e.message });
      }
      return jsonResponse(500, {
        error: "import failed",
        detail: e instanceof Error ? e.message : String(e),
      });
    }
  };
}

// Production wiring — the real ClaudeHaikuAdapter, the household-scoped Postgres
// `sqlVocabMatcher`, auth (the `household_id` JWT claim), and CORS — lives in
// `live.ts` (plan 0019). It is loaded ONLY when this module runs as the served
// entry point, so the pure orchestration above (and its tests) never pull in the
// Postgres driver or the provider SDK path. `deno check index.ts` still follows
// this literal import and type-checks the live wiring.
if (import.meta.main) {
  // NOT a top-level await: `live.ts` imports back from this module, so awaiting
  // the dynamic import here deadlocks module evaluation (the cycle can't resolve
  // while this module is still evaluating). Defer with `.then` so this module
  // finishes evaluating first; `live.ts` then loads against the completed module
  // and registers `Deno.serve`.
  import("./live.ts").then((m) => m.serveImport());
}
