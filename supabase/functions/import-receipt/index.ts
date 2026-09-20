// Edge function: import-receipt — the deterministic orchestration spine for a
// photographed till receipt.
//
//   photos → ① transcribe (vision) → join by position → ② structure →
//   ⑥ match the item lines → ReceiptPayload
//
// It is `import-recipe`'s shape, deliberately: the same auth and household
// allowlist, the same Haiku pin, the same streaming transport and budgets, the
// same SSE stage events with the server's own elapsed clock, the same four
// failure shapes. What differs is the document. A receipt is smaller, flatter
// and more regular than a cookbook page — and it has one thing a recipe does
// not, which is a printed subtotal it can be checked against.
//
// Two model calls and nothing between them that thinks:
//
//   * **the join is ours.** `transcribe` returns one transcription per photo;
//     `receipt_join.ts` finds the seam by position and a unit test says what
//     that means. A model asked to splice the photos would have to decide
//     whether a repeated line is an overlap or a second banana, and it would be
//     believed.
//   * **the match is ours.** The model never sees the vocabulary and never
//     matches (ADR-0004). The existing cascade runs afterwards over each item
//     line's printed words, and because those words are a store's
//     abbreviations it says `suggest` far more often than it does on a recipe
//     line. That is the honest answer, and the review is built for it.
//
// **The vocabulary learns nothing here.** No alias is written, and there is no
// code path from this function to one — a receipt's words are one store's
// abbreviations, and putting them in the household's own language would
// surface them in every recipe import, picker and search (ADR-0004).
// `no_alias.test.ts` holds that structurally.
//
// What DOES carry between shops is the household's own answers, and neither of
// them is a word the vocabulary knows:
//
//   * the **pack**, on the ingredient row, written by the app at Save;
//   * the **match**, recalled per printed name off this household's own saved
//     receipt lines (`_shared/receipt_memory.ts`) — a SELECT, latest answer
//     wins, so correcting the receipt corrects the memory.
//
// The spine takes its collaborators injected (`ReceiptDeps`), so the whole
// pipeline is offline-testable with fakes and replayable with a saved answer.

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

/** Match cascade seam — the household-scoped matcher, pre-bound at integration. */
export type MatchLinesFn = (lines: RawLineItem[]) => Promise<MatchedLine[]>;

/** The injected collaborators. Real ones wired in `live.ts`; fakes in tests. */
export interface ReceiptDeps {
  adapter: ReceiptAdapter;
  matchLines: MatchLinesFn;
  /**
   * What this household has already said about these printed names
   * (`_shared/receipt_memory.ts`) — a SELECT over its own saved receipt lines,
   * pre-bound to the household exactly as `matchLines` is.
   */
  recallMatches: RecallMatchesFn;
}

/** Request to the pipeline: the photos of one receipt, in order, top to bottom. */
export interface ReceiptRequest {
  images: Uint8Array[];
}

// --- The stages the caller is told about -------------------------------------
//
// The ids are the contract; the WORDING is the app's, because copy belongs
// where the screen is. The board names them: "Photos received", "Photos read",
// "Writing the receipt out…", "Lines matched" — the recipe reader's four rows,
// the third renamed for what it writes.

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
 * {@link ReceiptPayload}. Pure orchestration over the injected `deps`;
 * deterministic given deterministic collaborators.
 *
 * `onStage` is told as each stage completes, with the elapsed time measured
 * from `startedAt` — the caller's clock, so the numbers on the screen and the
 * numbers in the log are the same numbers. `onBeat` is told, at most every
 * {@link HEARTBEAT_INTERVAL_MS}, that the model has produced output since the
 * last frame went out. Neither changes what is produced.
 */
export async function importReceipt(
  req: ReceiptRequest,
  deps: ReceiptDeps,
  onStage: StageSink = () => {},
  startedAt: number = Date.now(),
  onBeat: BeatSink = () => {},
): Promise<ReceiptPayload> {
  // NOW, not `startedAt`: the caller has just sent `received`, and `startedAt`
  // is however long ago the upload began.
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
      // Said FIRST, before the seams' own notes: if a photo went missing
      // between the camera and the transcription, everything below is a
      // consequence of that and not a separate problem.
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

    // ⑥ — the deterministic cascade, over the ITEM lines only. A tax line has
    // no ingredient to be about (migration 0044's own fence), and asking about
    // one would spend a query to be told so.
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
 * folded alike. A recall that fails is logged and the receipt goes on with
 * the cascade alone: it improves the match, the import never depends on it.
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
 * (⇒ 400). TOTAL: every rejection path returns an error string rather than
 * throwing, because this runs BEFORE the handler's try/catch and a throw here
 * would escape as an unhandled 500.
 *
 * Photos only. There is no link door for a receipt — a till receipt is a piece
 * of paper — and a body carrying a `url` is told so rather than ignored, so a
 * client that sent one learns why nothing happened.
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
 * carry it if the answer had not already started streaming. The three shapes
 * are `_shared/failures.ts`'s, so both import doors fail alike; only the
 * subject is this door's.
 */
export function failureFor(e: unknown): { status: number; error: string } {
  return sharedFailureFor(e, { fn: "import-receipt", subject: "receipt" });
}

// --- The answer is a STREAM --------------------------------------------------
//
// Same wire as `import-recipe` (spec §4.7), frame for frame, because the app
// reads both with one reader:
//
//   `plan`      `{stages}`            — once, first: what this import will walk
//   `stage`     `{stage, elapsed_ms}` — one per stage as it completes
//   `heartbeat` `{elapsed_ms}`        — mid-stage: the model is producing
//   `result` the `ReceiptPayload`     — last, on success
//   `error`     `{error}`             — last, instead, on failure
//
// And the same consequence: the STATUS is committed before the work runs, so a
// failure after the first byte arrives as an `error` event carrying the
// sentence `failureFor` gives it, not as a 4xx/5xx. Everything knowable BEFORE
// the pipeline starts — the method, a malformed body, an unusable request — is
// still a plain JSON status, because nothing has been promised yet.

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
        // The body is in hand and usable: that IS the first stage, and its
        // elapsed covers reading however many megabytes of photo off the wire.
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

/** Builds the HTTP handler over injected `deps` (real ones supplied by `live.ts`). */
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

// Production wiring — the real `ClaudeReceiptAdapter`, the household-scoped
// Postgres matcher, auth and CORS — lives in `live.ts`, loaded ONLY when this
// module runs as the served entry point, so the pure orchestration above (and
// its tests) never pull in the Postgres driver or the provider path.
if (import.meta.main) {
  // NOT a top-level await: `live.ts` imports back from this module, so awaiting
  // the dynamic import here deadlocks module evaluation.
  import("./live.ts").then((m) => m.serveImport());
}
