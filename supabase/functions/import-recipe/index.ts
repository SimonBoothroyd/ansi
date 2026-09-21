// Edge function: import-recipe, the deterministic orchestration spine (§3, §4).
//
//   intake → RawBlob → ① sanitize (adapter) → §7 normalize → ⑥ match →
//   ReconciliationPayload
//
// The collaborators are injected (`ImportDeps`), so the pipeline is
// offline-testable with fakes. The orchestrator moves data and never fills a
// value in: warnings, confidence, ranges and tokenized steps pass through
// untouched, and step refs stay by flattened `line_index` (§4.6).

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
import { locateSourceSpan } from "../_shared/source_span.ts";
import { ImportError } from "../_shared/errors.ts";
import { failureFor as sharedFailureFor } from "../_shared/failures.ts";
import {
  HEARTBEAT_INTERVAL_MS,
  jsonResponse,
  parseImages,
  SSE_HEADERS,
  sseFrame,
} from "../_shared/http_edge.ts";

// The class lives in `_shared/errors.ts` so intake and the adapters can throw
// it without importing this module.
export { ImportError };

/**
 * Match cascade seam: a matcher pre-bound to the household-scoped
 * `VocabMatcher`, so the orchestrator stays decoupled from the DB.
 */
export type MatchLinesFn = (lines: RawLineItem[]) => Promise<MatchedLine[]>;

/** The injected collaborators: real ones from `live.ts`, fakes in tests. */
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

// --- The stages the caller is told about (§4.7) -------------------------------
//
// The ids are the contract; the wording is the app's.

/** One completed step of the pipeline, as named on the wire. */
export type ImportStageId =
  | "received"
  | "fetched"
  | "transcribed"
  | "sanitised"
  | "matched";

/** From a link: the page is fetched, then read, then matched. */
export const URL_STAGES: ImportStageId[] = [
  "received",
  "fetched",
  "sanitised",
  "matched",
];

/** From photos: the pages are transcribed first, so there are two model calls. */
export const PHOTO_STAGES: ImportStageId[] = [
  "received",
  "transcribed",
  "sanitised",
  "matched",
];

/** The stage list a request will walk. */
export function stagesFor(req: ImportRequest): ImportStageId[] {
  return req.images && req.images.length > 0 ? PHOTO_STAGES : URL_STAGES;
}

/** Told each stage's id and the milliseconds since the request reached us. */
export type StageSink = (stage: ImportStageId, elapsedMs: number) => void;

/** Told, mid-stage, that the model is still producing. Same clock as a stage. */
export type BeatSink = (elapsedMs: number) => void;

/** Longest the stream may go quiet mid-call; shared with import-receipt. */
export { HEARTBEAT_INTERVAL_MS } from "../_shared/http_edge.ts";

/**
 * Runs intake → ① → ⑥ and assembles the {@link ReconciliationPayload}. Pure
 * orchestration over the injected `deps`.
 *
 * `onStage` is told as each stage completes, with the time elapsed since
 * `startedAt`. `onBeat` is told, at most every {@link HEARTBEAT_INTERVAL_MS},
 * that the model has produced output since the last frame; a stage event
 * counts as a frame. Neither changes what is produced.
 */
export async function importRecipe(
  req: ImportRequest,
  deps: ImportDeps,
  onStage: StageSink = () => {},
  startedAt: number = Date.now(),
  onBeat: BeatSink = () => {},
): Promise<ReconciliationPayload> {
  // Now, not `startedAt`: the caller has just sent `received`, and on the photo
  // door `startedAt` is when the upload began.
  let lastFrameAt = Date.now();
  const done = (stage: ImportStageId) => {
    lastFrameAt = Date.now();
    onStage(stage, lastFrameAt - startedAt);
  };
  // Saved and restored: the eval runner hangs its own observers on a shared
  // adapter.
  const previousProgress = deps.adapter.onProgress;
  deps.adapter.onProgress = () => {
    const now = Date.now();
    if (now - lastFrameAt < HEARTBEAT_INTERVAL_MS) return;
    lastFrameAt = now;
    onBeat(now - startedAt);
  };
  try {
    const blob = await intake(req, deps);
    done(req.images && req.images.length > 0 ? "transcribed" : "fetched");
    const hints = deriveUnitHints();
    const extraction = await deps.adapter.sanitize(blob, hints);
    done("sanitised");
    const flat = flattenLines(extraction.groups);
    const matched = await deps.matchLines(flat);
    if (matched.length !== flat.length) {
      throw new ImportError(
        `matcher returned ${matched.length} lines for ${flat.length} inputs`,
      );
    }
    done("matched");
    return assemble(extraction, matched, blob);
  } finally {
    deps.adapter.onProgress = previousProgress;
  }
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
 * Flattens `groups[].line_items[]` into one ordered list. This order is the
 * `line_index` space that `steps[].tokens[].refs` point into (§4.6).
 */
function flattenLines(groups: { line_items: RawLineItem[] }[]): RawLineItem[] {
  return groups.flatMap((g) => g.line_items);
}

/** Re-groups the flat `MatchedLine[]` back onto the original group shape. */
function assemble(
  extraction: ExtractionResult,
  matched: MatchedLine[],
  blob: RawBlob,
): ReconciliationPayload {
  // The page as a person reads it. A photo import's blob has no `page_text`,
  // so the field is omitted there.
  const sourceText = blob.page_text;
  const groups: ReconGroup[] = [];
  let cursor = 0;
  for (const g of extraction.groups) {
    const lines: ReconLine[] = g.line_items.map(() => {
      const m = matched[cursor++];
      const line: ReconLine = {
        raw: m.raw,
        band: m.band,
        candidates: m.candidates,
      };
      // The sub-recipe suggestion rides along only when there is one; the
      // golden fixture pins the key's absence otherwise.
      if (m.recipe_candidates && m.recipe_candidates.length > 0) {
        line.recipe_candidates = m.recipe_candidates;
      }
      // A span rides along only where the line's printed words can be located
      // in that text unambiguously (`_shared/source_span.ts`).
      if (sourceText) {
        const span = locateSourceSpan(sourceText, m.raw);
        if (span) line.source_span = span;
      }
      return line;
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
    // Omitted rather than null when there is none.
    ...(sourceText ? { source_text: sourceText } : {}),
  };
}

// --- HTTP boundary -----------------------------------------------------------

// --- Per-call cost caps ------------------------------------------------------
// Shared with `import-receipt` (`_shared/http_edge.ts`); re-exported because
// this module's tests and the app's contract read them from here.
export { MAX_IMAGE_BYTES, MAX_IMAGES } from "../_shared/http_edge.ts";

/**
 * Parses a decoded JSON body into an {@link ImportRequest}, or an error message
 * (⇒ 400). Total: it never throws, because it runs before the handler's
 * try/catch.
 */
export function parseRequestBody(
  body: unknown,
): { request: ImportRequest } | { error: string } {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { error: "body must be a JSON object" };
  }
  const b = body as Record<string, unknown>;
  const hasUrl = typeof b.url === "string" && b.url.trim() !== "";
  const hasImages = Array.isArray(b.images);
  // `url` would otherwise win silently.
  if (hasUrl && hasImages) {
    return { error: "provide either `url` or `images`, not both" };
  }
  if (hasUrl) return { request: { url: (b.url as string).trim() } };
  if (hasImages) {
    const parsed = parseImages(b.images as unknown[]);
    if ("error" in parsed) return parsed;
    return { request: { images: parsed.images } };
  }
  return { error: "body must include a `url` or `images`" };
}

// --- Failures: one wording, wherever it is delivered -------------------------

/**
 * What a person is told when the pipeline throws, and the status that would
 * carry it had the answer not started streaming. The detail goes to the log.
 */
export function failureFor(e: unknown): { status: number; error: string } {
  return sharedFailureFor(e, { fn: "import-recipe", subject: "recipe" });
}

// --- The answer is a stream (§4.7) -------------------------------------------
//
// The response is `text/event-stream`, one event per stage as it lands.
//
//   * The status is committed before the work runs, so a failure after the
//     first byte arrives as an `error` event. Anything known before the
//     pipeline starts (method, malformed body) is still a plain JSON status.
//   * The platform's idle timeout bounds the longest silence, and `heartbeat`
//     frames keep that to the heartbeat interval, so model budgets are not
//     pinned to the platform's cut-off. The client's ladder is written out in
//     `remote_import_repository.dart`.

/**
 * Runs the pipeline and narrates it as Server-Sent Events:
 *
 *   `plan`      `{stages}`               — once, first: what this import will walk
 *   `stage`     `{stage, elapsed_ms}`    — one per stage as it completes
 *   `heartbeat` `{elapsed_ms}`           — mid-stage: the model is producing
 *   `result` the `ReconciliationPayload` — last, on success
 *   `error`     `{error}`                — last, instead, on failure
 *
 * `heartbeat` is additive; a client that does not know it ignores it.
 */
function streamImport(
  request: ImportRequest,
  deps: ImportDeps,
  startedAt: number,
): Response {
  const encoder = new TextEncoder();
  const body = new ReadableStream<Uint8Array>({
    async start(controller) {
      const send = (event: string, data: unknown) =>
        controller.enqueue(encoder.encode(sseFrame(event, data)));
      try {
        send("plan", { stages: stagesFor(request) });
        // A usable body in hand is the first stage; its elapsed covers the
        // upload.
        send("stage", {
          stage: "received",
          elapsed_ms: Date.now() - startedAt,
        });
        const payload = await importRecipe(
          request,
          deps,
          (stage, elapsed_ms) => send("stage", { stage, elapsed_ms }),
          startedAt,
          (elapsed_ms) => send("heartbeat", { elapsed_ms }),
        );
        send("result", payload);
      } catch (e) {
        send("error", { error: failureFor(e).error });
      } finally {
        controller.close();
      }
    },
  });
  return new Response(body, { status: 200, headers: SSE_HEADERS });
}

/** Builds the HTTP handler over injected `deps`. */
export function makeHandler(
  deps: ImportDeps,
): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    const startedAt = Date.now();
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
    return streamImport(parsed.request, deps, startedAt);
  };
}

// Production wiring lives in `live.ts`, loaded only when this module is the
// served entry point, so the orchestration and its tests never pull in the
// Postgres driver. `deno check index.ts` still type-checks it.
if (import.meta.main) {
  // Not a top-level await: `live.ts` imports back from this module, so awaiting
  // here would deadlock module evaluation.
  import("./live.ts").then((m) => m.serveImport());
}
