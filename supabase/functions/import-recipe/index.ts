// Edge function: import-recipe — the deterministic orchestration spine (§3, §4).
//
//   intake → RawBlob → ① sanitize (adapter) → §7 normalize → ⑥ match →
//   ReconciliationPayload
//
// This file owns the wiring; the two model-facing stages are consumed THROUGH
// their frozen interfaces and injected (`ImportDeps`), so the whole pipeline is
// offline-testable with fakes:
//   - `adapter` — the `ExtractAdapter`. `transcribe` is the vision tier
//     (images → RawBlob); `sanitize` is ①. Always an LLM in prod.
//   - `matchLines` — the deterministic, server-side match cascade. It owns the
//     §7 `normalize` call (normalize.ts's header: match.ts calls it), so the
//     orchestrator delegates matching rather than re-normalizing.
//   - `fetchBlob` — URL → RawBlob intake (`jsonld.ts`).
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

// Re-exported for the stages that raise it and everything that catches it — the
// class itself lives in `_shared/errors.ts` so intake and the adapters can throw
// it without importing this module (see that file's header).
export { ImportError };

/**
 * Match cascade seam. The orchestrator depends on a PRE-BOUND matcher
 * function — the cascade's real `matchLines(lines, matcher)` takes a second
 * `VocabMatcher` (the household-scoped Postgres seam), which is constructed
 * per-request at integration (0019) and closed over here. That keeps the
 * orchestrator decoupled from the DB, and tests inject a plain fake.
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

// --- The stages the caller is told about (§4.7) -------------------------------
//
// The server has always run these in order; what changed is that it now SAYS so
// as each one lands, instead of leaving the phone to guess from a clock. The
// ids are the contract — the wording is the app's, because copy belongs where
// the screen is.

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

/** From photos: the pages are transcribed FIRST, so there are two model calls. */
export const PHOTO_STAGES: ImportStageId[] = [
  "received",
  "transcribed",
  "sanitised",
  "matched",
];

/** The stage list a request will walk, decided the moment the body is parsed. */
export function stagesFor(req: ImportRequest): ImportStageId[] {
  return req.images && req.images.length > 0 ? PHOTO_STAGES : URL_STAGES;
}

/** Told each stage's id and the milliseconds since the request reached us. */
export type StageSink = (stage: ImportStageId, elapsedMs: number) => void;

/** Told, mid-stage, that the model is still producing. Same clock as a stage. */
export type BeatSink = (elapsedMs: number) => void;

/**
 * Longest the stream may go quiet while a model call is streaming — shared
 * with `import-receipt` and re-exported here, where the timeout ladder's test
 * and the spec's table have always found it.
 */
export { HEARTBEAT_INTERVAL_MS } from "../_shared/http_edge.ts";

/**
 * Runs intake → ① → ⑥ and assembles the {@link ReconciliationPayload}. Pure
 * orchestration over the injected `deps`; deterministic given deterministic
 * collaborators.
 *
 * `onStage` is told as each stage completes, with the elapsed time measured
 * from `startedAt` — the caller's clock, so the numbers on the screen and the
 * numbers in the log are the same numbers. It never changes what is produced.
 *
 * `onBeat` is told, at most every {@link HEARTBEAT_INTERVAL_MS}, that the model
 * has produced output since the last frame went out. The throttle lives here
 * rather than at the HTTP edge because the thing being throttled is "how long
 * since we last said anything", and a stage event counts as saying something.
 */
export async function importRecipe(
  req: ImportRequest,
  deps: ImportDeps,
  onStage: StageSink = () => {},
  startedAt: number = Date.now(),
  onBeat: BeatSink = () => {},
): Promise<ReconciliationPayload> {
  // NOW, not `startedAt`: the caller has just sent `received`, and on the photo
  // door `startedAt` is however long ago the upload began.
  let lastFrameAt = Date.now();
  const done = (stage: ImportStageId) => {
    lastFrameAt = Date.now();
    onStage(stage, lastFrameAt - startedAt);
  };
  // Saved and restored: the adapter is built per request in production, but the
  // eval runner hangs its own observers on a shared one.
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
  blob: RawBlob,
): ReconciliationPayload {
  // 0047: the page as a person reads it, when intake had one. A photo import's
  // blob carries no `page_text` — its pages are files the phone already holds
  // — so this is undefined there and the field is omitted, exactly as
  // `recipe_candidates` is when empty.
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
      // 8.6 / D6: the sub-recipe suggestion rides along ONLY when there is
      // one. No matcher wired, or no hit ⇒ the key is absent and the payload
      // is byte-identical to the pre-8.6 contract (the golden fixture pins
      // exactly that).
      if (m.recipe_candidates && m.recipe_candidates.length > 0) {
        line.recipe_candidates = m.recipe_candidates;
      }
      // 0047, same rule: a span rides along only where the line's own printed
      // words can be pointed at in that text unambiguously. Located, never
      // guessed — see `_shared/source_span.ts`.
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
    // Omitted rather than null when there is none, so a payload from a photo
    // import is byte-identical to the one this function used to build.
    ...(sourceText ? { source_text: sourceText } : {}),
  };
}

// --- HTTP boundary -----------------------------------------------------------

// --- Per-call cost caps ------------------------------------------------------
// The caps, the base64 decoding and their wordings are shared with
// `import-receipt` (`_shared/http_edge.ts`): every image is billed to a vision
// model whichever door it came through, so there is one answer to "how big may
// a photo be" and one sentence when it is too big. Re-exported here because
// this module's own tests — and the app's contract — have always read them
// from it.
export { MAX_IMAGE_BYTES, MAX_IMAGES } from "../_shared/http_edge.ts";

/**
 * Parses a decoded JSON body into an {@link ImportRequest}, or an error message
 * (⇒ 400). TOTAL: every rejection path — malformed base64 included — returns an
 * error string rather than throwing, because this runs BEFORE the handler's
 * try/catch and a throw here would escape as an unhandled 500.
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
  // Checked here, not just in `intake`: with `url` winning silently, a client
  // sending both never learned it was ambiguous.
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
 * carry it if the answer had not already started streaming. Logging the
 * un-showable detail is part of it: the caller gets the sentence, the function
 * log gets the stack.
 */
export function failureFor(e: unknown): { status: number; error: string } {
  return sharedFailureFor(e, { fn: "import-recipe", subject: "recipe" });
}

// --- The answer is a STREAM (§4.7) -------------------------------------------
//
// A photo import is two model calls and takes a minute or more, and a single
// non-streaming POST could say nothing at all until it was over — so the screen
// had to guess the server's progress off a clock. It does not have to any more:
// the response is `text/event-stream`, and each stage is an event as it lands.
//
// Two consequences worth stating, because both are load-bearing:
//
//   * the STATUS is committed before the work runs. A failure after the first
//     byte therefore arrives as an `error` event carrying the sentence
//     `failureFor` gives it, not as a 4xx/5xx. Everything that is known BEFORE
//     the pipeline starts — the method, a malformed body, an unusable request —
//     is still a plain JSON status, because nothing has been promised yet.
//   * the platform's idle timeout bounds only the longest SILENCE inside the
//     call, rather than the call itself — and with `heartbeat` frames the
//     longest silence inside a model call is the heartbeat interval, not the
//     model's budget. That is what unpins the model budgets from the platform's
//     cut-off: they are now sized by what the model actually needs. The
//     client's ladder rests on it; it is written out in
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
 * `heartbeat` is ADDITIVE and carries nothing to show. A client that predates
 * it ignores an event it does not know, which is the property that let it be
 * added at all — see the reader in `remote_import_repository.dart`.
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
        // The body is in hand and usable: that IS the first stage, and its
        // elapsed covers reading however many megabytes of photo off the wire.
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

/** Builds the HTTP handler over injected `deps` (real ones supplied at integration). */
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
