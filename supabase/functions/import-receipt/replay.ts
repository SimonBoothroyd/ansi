// Replays a saved reading instead of calling the model, so everything after
// the two model calls runs locally against a real Postgres with no key.
//
//   make functions-up            # or serve this module directly (below)
//   RECEIPT_EXTRACT_FIXTURE=…/testdata/tj_strip.json
//
// Local only, held by two locks:
//   1. it is off unless `RECEIPT_EXTRACT_FIXTURE` names a file, which no deploy
//      script or `supabase secrets` row sets;
//   2. it refuses to load when `ANTHROPIC_API_KEY` is set.

import type {
  ReceiptAdapter,
  ReceiptExtraction,
} from "../_shared/receipt_types.ts";
import { decodeClaudeReceiptStructure } from "../_shared/adapters/claude_receipt.ts";

/** The env var that names a saved reading to replay. Unset ⇒ the provider. */
export const REPLAY_FIXTURE_ENV = "RECEIPT_EXTRACT_FIXTURE";

/** The shape this reads out of a fixture file. */
interface SavedReceipt {
  provider?: string;
  /** One transcription per photo, in order. */
  photos?: unknown;
  /** The structuring call's verbatim provider response. */
  raw?: unknown;
}

/**
 * A {@link ReceiptAdapter} that answers from `saved`. `transcribe` hands back
 * the fixture's per-photo transcriptions, so the real join runs over them.
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
  // Decoded once, at wiring time, so a malformed fixture fails loudly.
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
 * switch is off. Throws when the switch is on beside a real key, or when the
 * file cannot be replayed.
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
