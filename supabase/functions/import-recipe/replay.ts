// Replaying a SAVED extraction response instead of calling the model — the
// keyless way to drive the whole served function locally.
//
// The pipeline's one paid, non-deterministic stage is the LLM. Everything
// downstream of it — normalize, the match cascade, the payload assembly, the
// HTTP edges — is deterministic, and that is the half a change to matching
// needs to be exercised against a real Postgres. `evals/runs/` already holds
// what the model said, verbatim, for every case in the extraction corpus
// (`run_store.ts`), decoded by the same decoder the live call used. Pointing
// this adapter at one of those files runs the function end to end over the real
// vocabulary with no API key and no provider call.
//
// LOCAL ONLY, and held that way by three locks rather than by a warning:
//
//   1. it is off unless `IMPORT_EXTRACT_FIXTURE` names a file, and that name
//      appears in no deploy script and no `supabase secrets` row (the deployed
//      function's secrets are `ANTHROPIC_API_KEY` and
//      `IMPORT_ALLOWED_HOUSEHOLDS`, both set by hand — docs/cloud-setup.md §3b);
//   2. it REFUSES to load when `ANTHROPIC_API_KEY` is set, so the environment
//      that can really extract never serves a canned recipe;
//   3. the saved responses live under `evals/`, which is not part of the
//      deployed function, so there is nothing there for it to read.
//
// See supabase/AGENTS.md § "Driving import locally without a key".

import type {
  ExtractAdapter,
  ExtractionResult,
  RawBlob,
} from "../_shared/types.ts";
import { decodeClaudeSanitize } from "../_shared/adapters/claude.ts";
import { MockAdapter } from "../_shared/adapters/mock.ts";

/** The env var that names a saved response to replay. Unset ⇒ the real provider. */
export const REPLAY_FIXTURE_ENV = "IMPORT_EXTRACT_FIXTURE";

/** The fields this reads out of an `evals/runs/**` case file (`SavedCase`). */
interface SavedCase {
  provider?: string;
  op?: string;
  raw?: unknown;
  input?: { text?: string };
}

/**
 * An {@link ExtractAdapter} that answers from `saved` — a case file written by
 * the eval runner. `sanitize` replays the model's verbatim response through the
 * real Claude decoder; `transcribe` hands back the source text the run was made
 * from, so the PHOTO path (two model calls) runs end to end from image bytes
 * that are never looked at.
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
  // Decoded ONCE, at wiring time: a malformed fixture must fail the request
  // loudly rather than surface as an empty recipe.
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
 * switch is off (the ordinary case, production included). Throws when the
 * switch is on in an environment that holds a real key, or when the file it
 * names cannot be replayed.
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
