// Replaying a SAVED reading instead of calling the model — the keyless way to
// drive the whole served function locally.
//
// The pipeline's paid, non-deterministic half is the two model calls.
// Everything after them — the join, the money and date readers, the match
// cascade, the assembly, the HTTP edges — is deterministic, and that is the
// half the app lane and the owner need to run the review against a real
// Postgres. A replay fixture holds what the model said, verbatim, and this
// adapter answers from it: no key, no provider call, the same decoders.
//
//   make functions-up            # or serve this module directly (below)
//   RECEIPT_EXTRACT_FIXTURE=…/testdata/tj_strip.json
//
// LOCAL ONLY, held by locks rather than by a warning:
//
//   1. it is off unless `RECEIPT_EXTRACT_FIXTURE` names a file, and that name
//      appears in no deploy script and no `supabase secrets` row (the deployed
//      function's secrets are `ANTHROPIC_API_KEY` and
//      `IMPORT_ALLOWED_HOUSEHOLDS`, both set by hand);
//   2. it REFUSES to load when `ANTHROPIC_API_KEY` is set — and a deployed
//      function always has that key, or it could not extract at all — so the
//      environment that can really read a receipt never serves a canned one.
//
// The fixture format is deliberately the same idea as `evals/runs/**`: the
// provider's VERBATIM response, decoded here by the same decoder the live call
// uses, so a malformed fixture fails loudly at wiring rather than surfacing as
// an empty receipt.

import type {
  ReceiptAdapter,
  ReceiptExtraction,
} from "../_shared/receipt_types.ts";
import { decodeClaudeReceiptStructure } from "../_shared/adapters/claude_receipt.ts";

/** The env var that names a saved reading to replay. Unset ⇒ the real provider. */
export const REPLAY_FIXTURE_ENV = "RECEIPT_EXTRACT_FIXTURE";

/** The shape this reads out of a fixture file. */
interface SavedReceipt {
  provider?: string;
  /** One transcription per photo, in order — what `transcribe` hands back. */
  photos?: unknown;
  /** The structuring call's verbatim provider response. */
  raw?: unknown;
}

/**
 * A {@link ReceiptAdapter} that answers from `saved`.
 *
 * `transcribe` hands back the fixture's per-photo transcriptions without
 * looking at the image bytes, so the REAL join runs over them — which is the
 * point: a replay exercises the seam-finding, not a pre-joined strip.
 * `structure` replays the saved response through the live decoder.
 */
export function replayReceiptAdapter(
  saved: unknown,
  label: string,
): ReceiptAdapter {
  const c = saved as SavedReceipt;
  if (!c || typeof c !== "object" || c.raw === undefined) {
    throw new Error(
      `${label} is not a receipt replay fixture (no "raw" field)`,
    );
  }
  if (!(c.provider ?? "").startsWith("claude")) {
    throw new Error(
      `${label} was recorded from "${c.provider}" — replay decodes Claude ` +
        `responses, which is what production sends`,
    );
  }
  if (
    !Array.isArray(c.photos) || c.photos.length === 0 ||
    c.photos.some((p) => typeof p !== "string")
  ) {
    throw new Error(
      `${label} has no "photos" — a replay needs one transcription per photo, ` +
        `so the join is exercised rather than skipped`,
    );
  }
  const photos = c.photos as string[];
  // Decoded ONCE, at wiring time: a malformed fixture must fail the request
  // loudly rather than surface as an empty receipt.
  const extraction: ReceiptExtraction = decodeClaudeReceiptStructure(c.raw);

  return {
    name: "replay",
    model: `replay:${label}`,
    transcribe: (): Promise<string[]> => Promise.resolve([...photos]),
    structure: (): Promise<ReceiptExtraction> => Promise.resolve(extraction),
  };
}

/**
 * The replay adapter named by {@link REPLAY_FIXTURE_ENV}, or `null` when the
 * switch is off (the ordinary case, production included). Throws when the
 * switch is on in an environment that holds a real key, or when the file it
 * names cannot be replayed.
 */
export function replayReceiptAdapterFromEnv(): ReceiptAdapter | null {
  const path = Deno.env.get(REPLAY_FIXTURE_ENV);
  if (!path || path.trim() === "") return null;
  if ((Deno.env.get("ANTHROPIC_API_KEY") ?? "").trim() !== "") {
    throw new Error(
      `${REPLAY_FIXTURE_ENV} is set in an environment that has ` +
        `ANTHROPIC_API_KEY — refusing to serve a saved receipt where the real ` +
        `reader is available`,
    );
  }
  return replayReceiptAdapter(JSON.parse(Deno.readTextFileSync(path)), path);
}
