// Edge function: import-receipt, the orchestration spine for a photographed
// till receipt.
//
//   photos → ① transcribe (vision) → join by position → ② structure →
//   ⑥ match the item lines → ReceiptPayload
//
// It shares `import-recipe`'s auth, model pin, streaming transport, stage
// events and failure shapes. The join (`receipt_join.ts`) and the match are
// deterministic code; the model never sees the vocabulary (ADR-0004). No alias
// is written (`no_alias.test.ts`); matches are recalled per printed name from
// the household's saved receipt lines (`_shared/receipt_memory.ts`).
// Collaborators are injected (`ReceiptDeps`).

import type { MatchedLine, RawLineItem } from "../_shared/types.ts";
import type {
  ReceiptAdapter,
  ReceiptExtraction,
  ReceiptPayload,
} from "../_shared/receipt_types.ts";
import type {
  RecallMatchesFn,
  ReceiptMemory,
} from "../_shared/receipt_memory.ts";
import { joinPhotoTranscripts } from "../_shared/receipt_join.ts";
import {
  assembleReceipt,
  itemMatchInputs,
} from "../_shared/receipt_assemble.ts";
import { ImportError } from "../_shared/errors.ts";
import { failureFor as sharedFailureFor } from "../_shared/failures.ts";
import {
  HEARTBEAT_INTERVAL_MS,
  jsonResponse,
  parseImages,
  SSE_HEADERS,
  sseFrame,
} from "../_shared/http_edge.ts";

export { ImportError };
export { MAX_IMAGE_BYTES, MAX_IMAGES } from "../_shared/http_edge.ts";

/** Match cascade seam: the household-scoped matcher, pre-bound in `live.ts`. */
export type MatchLinesFn = (lines: RawLineItem[]) => Promise<MatchedLine[]>;

/** The injected collaborators. Real ones wired in `live.ts`; fakes in tests. */
export interface ReceiptDeps {
  adapter: ReceiptAdapter;
  matchLines: MatchLinesFn;
  /**
   * What this household has already said about these printed names
   * (`_shared/receipt_memory.ts`), pre-bound to the household.
   */
  recallMatches: RecallMatchesFn;
}

/** Request to the pipeline: the photos of one receipt, in order, top to bottom. */
export interface ReceiptRequest {
  images: Uint8Array[];
}

// --- The stages the caller is told about -------------------------------------
//
// The ids are the contract; the wording is the app's.

export type ReceiptStageId = "received" | "read" | "written" | "matched";

/** Always these four, in this order. A receipt has one door and no link tier. */
export const RECEIPT_STAGES: ReceiptStageId[] = [
  "received",
  "read",
  "written",
  "matched",
];

/** Told each stage's id and the milliseconds since the request reached us. */
export type StageSink = (stage: ReceiptStageId, elapsedMs: number) => void;

/** Told, mid-stage, that the model is still producing. Same clock as a stage. */
export type BeatSink = (elapsedMs: number) => void;

export { HEARTBEAT_INTERVAL_MS };

/**
 * Runs transcribe → join → structure → match and assembles the
 * {@link ReceiptPayload}. Pure orchestration over the injected `deps`.
 *
 * `onStage` is told as each stage completes, with the time elapsed since
 * `startedAt`. `onBeat` is told, at most every {@link HEARTBEAT_INTERVAL_MS},
 * that the model has produced output since the last frame. Neither changes
 * what is produced.
 */
export async function importReceipt(
  req: ReceiptRequest,
  deps: ReceiptDeps,
  onStage: StageSink = () => {},
  startedAt: number = Date.now(),
  onBeat: BeatSink = () => {},
): Promise<ReceiptPayload> {
  // Now, not `startedAt`: the caller has just sent `received`, and `startedAt`
  // is when the upload began.
  let lastFrameAt = Date.now();
  const done = (stage: ReceiptStageId) => {
    lastFrameAt = Date.now();
    onStage(stage, lastFrameAt - startedAt);
  };
  const previousProgress = deps.adapter.onProgress;
  deps.adapter.onProgress = () => {
    const now = Date.now();
    if (now - lastFrameAt < HEARTBEAT_INTERVAL_MS) return;
    lastFrameAt = now;
    onBeat(now - startedAt);
  };
  try {
    const segments = await deps.adapter.transcribe(req.images);
    done("read");

    const transcript = joinPhotoTranscripts(segments);
    if (segments.length !== req.images.length) {
      // Said first: a missing photo explains the seam notes below it.
      transcript.notes.unshift(
        `We read ${segments.length} of the ${req.images.length} photos — a ` +
          `stretch of the receipt may be missing.`,
      );
    }
    if (transcript.lines.length === 0) {
      throw new ImportError(
        "we could not read anything on those photos — try again with the " +
          "receipt flat and the light on it",
      );
    }

    const extraction = await deps.adapter.structure(transcript.text);
    done("written");

    // ⑥ over the item lines only: a tax line has no ingredient (migration
    // 0044).
    const inputs = itemMatchInputs(extraction);
    const matched = await deps.matchLines(inputs);
    if (matched.length !== inputs.length) {
      throw new ImportError(
        `matcher returned ${matched.length} lines for ${inputs.length} inputs`,
      );
    }
    done("matched");
    return assembleReceipt(
      extraction,
      transcript,
      matched,
      await recall(extraction, deps),
    );
  } finally {
    deps.adapter.onProgress = previousProgress;
  }
}

/**
 * What the household has already said about these printed names, item and
 * folded alike. A failed recall is logged and the import goes on without it.
 */
async function recall(
  extraction: ReceiptExtraction,
  deps: ReceiptDeps,
): Promise<ReceiptMemory> {
  const names = extraction.lines
    .filter((l) => l.kind === "item" || l.kind === "not_food")
    .map((l) => l.name_printed);
  try {
    return await deps.recallMatches(names);
  } catch (e) {
    console.error("import-receipt: could not recall past answers", e);
    return new Map();
  }
}

// --- HTTP boundary -----------------------------------------------------------

/**
 * Parses a decoded JSON body into a {@link ReceiptRequest}, or an error message
 * (⇒ 400). Total: it never throws, because it runs before the handler's
 * try/catch. Photos only; a body carrying a `url` is told so.
 */
export function parseRequestBody(
  body: unknown,
): { request: ReceiptRequest } | { error: string } {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { error: "body must be a JSON object" };
  }
  const b = body as Record<string, unknown>;
  if (typeof b.url === "string" && b.url.trim() !== "") {
    return { error: "a receipt is read from photos, not from a `url`" };
  }
  if (!Array.isArray(b.images)) {
    return { error: "body must include `images`" };
  }
  const parsed = parseImages(b.images);
  if ("error" in parsed) return parsed;
  return { request: { images: parsed.images } };
}

/**
 * What a person is told when the pipeline throws, and the status that would
 * carry it had the answer not started streaming. The shapes are
 * `_shared/failures.ts`'s, shared with import-recipe.
 */
export function failureFor(e: unknown): { status: number; error: string } {
  return sharedFailureFor(e, { fn: "import-receipt", subject: "receipt" });
}

// --- The answer is a stream --------------------------------------------------
//
// The same wire as `import-recipe` (spec §4.7); the app reads both with one
// reader:
//
//   `plan`      `{stages}`            — once, first: what this import will walk
//   `stage`     `{stage, elapsed_ms}` — one per stage as it completes
//   `heartbeat` `{elapsed_ms}`        — mid-stage: the model is producing
//   `result` the `ReceiptPayload`     — last, on success
//   `error`     `{error}`             — last, instead, on failure
//
// The status is committed before the work runs, so a failure after the first
// byte arrives as an `error` event; anything known before the pipeline starts
// is still a plain JSON status.

function streamReceipt(
  request: ReceiptRequest,
  deps: ReceiptDeps,
  startedAt: number,
): Response {
  const encoder = new TextEncoder();
  const body = new ReadableStream<Uint8Array>({
    async start(controller) {
      const send = (event: string, data: unknown) =>
        controller.enqueue(encoder.encode(sseFrame(event, data)));
      try {
        send("plan", { stages: RECEIPT_STAGES });
        // A usable body in hand is the first stage; its elapsed covers the
        // upload.
        send("stage", {
          stage: "received",
          elapsed_ms: Date.now() - startedAt,
        });
        const payload = await importReceipt(
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
  deps: ReceiptDeps,
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
    return streamReceipt(parsed.request, deps, startedAt);
  };
}

// Production wiring lives in `live.ts`, loaded only when this module is the
// served entry point, so the orchestration and its tests never pull in the
// Postgres driver.
if (import.meta.main) {
  // Not a top-level await: `live.ts` imports back from this module, so awaiting
  // here would deadlock module evaluation.
  import("./live.ts").then((m) => m.serveImport());
}
