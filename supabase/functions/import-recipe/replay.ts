// Replays a saved extraction response from `evals/runs/` instead of calling
// the model, so everything downstream runs locally against a real Postgres
// with no key. See supabase/AGENTS.md § "Driving import locally without a key".
//
// Local only, held by three locks:
//   1. it is off unless `IMPORT_EXTRACT_FIXTURE` names a file, which no deploy
//      script or `supabase secrets` row sets (docs/cloud-setup.md §3b);
//   2. it refuses to load when `ANTHROPIC_API_KEY` is set;
//   3. the saved responses live under `evals/`, which is not deployed.

import type {
  ExtractAdapter,
  ExtractionResult,
  RawBlob,
} from "../_shared/types.ts";
import { decodeClaudeSanitize } from "../_shared/adapters/claude.ts";
import { MockAdapter } from "../_shared/adapters/mock.ts";

/** The env var that names a saved response to replay. Unset ⇒ the provider. */
export const REPLAY_FIXTURE_ENV = "IMPORT_EXTRACT_FIXTURE";

/** The fields this reads out of an `evals/runs/**` case file (`SavedCase`). */
interface SavedCase {
  provider?: string;
  op?: string;
  raw?: unknown;
  input?: { text?: string };
}

/**
 * An {@link ExtractAdapter} that answers from `saved`, a case file written by
 * the eval runner. `sanitize` replays the verbatim response through the real
 * Claude decoder; `transcribe` hands back the run's source text, so the photo
 * path runs end to end without reading the image bytes.
 */
export function replayAdapter(saved: unknown, label: string): ExtractAdapter {
  const c = saved as SavedCase;
  if (!c || typeof c !== "object" || c.raw === undefined) {
    throw new Error(`${label} is not an eval run case file (no "raw" field)`);
  }
  if (!(c.provider ?? "").startsWith("claude")) {
    throw new Error(
      `${label} was recorded from "${c.provider}" — replay decodes Claude ` +
        `responses, which is what production sends`,
    );
  }
  // Decoded once, at wiring time, so a malformed fixture fails loudly.
  const result: ExtractionResult = decodeClaudeSanitize(c.raw);
  const text = c.input?.text ?? null;

  return new MockAdapter({
    name: "replay",
    model: `replay:${label}`,
    sanitizeWith: () => result,
    transcribeWith: (): RawBlob => ({
      source: "transcription",
      url: null,
      jsonld: null,
      text,
    }),
  });
}

/**
 * The replay adapter named by {@link REPLAY_FIXTURE_ENV}, or `null` when the
 * switch is off. Throws when the switch is on beside a real key, or when the
 * file cannot be replayed.
 */
export function replayAdapterFromEnv(): ExtractAdapter | null {
  const path = Deno.env.get(REPLAY_FIXTURE_ENV);
  if (!path || path.trim() === "") return null;
  if ((Deno.env.get("ANTHROPIC_API_KEY") ?? "").trim() !== "") {
    throw new Error(
      `${REPLAY_FIXTURE_ENV} is set in an environment that has ` +
        `ANTHROPIC_API_KEY — refusing to serve a saved recipe where the real ` +
        `extractor is available`,
    );
  }
  return replayAdapter(JSON.parse(Deno.readTextFileSync(path)), path);
}
