// The server half of the import's timeout ladder, checked as arithmetic. The
// ladder is written out in
// `app/lib/features/import/data/remote_import_repository.dart`.
//
// The numbers live in four files nobody edits together, and the failure is
// silent: raise one budget and the longest silence the function can produce
// passes the platform's cut-off, so long imports die as gateway 504s after the
// model call is paid for. The platform's idle timeout bounds one gap between
// events, and heartbeats keep a streaming model call from being a gap, so
// model budgets are sized from `evals/runs/` and the photo path may cost more
// than the idle timeout.

import { assert } from "@std/assert";
import {
  DEFAULT_ATTEMPT_TIMEOUT_MS,
  DEFAULT_DEADLINE_MS,
  DEFAULT_IDLE_TIMEOUT_MS,
  DEFAULT_MIN_ATTEMPT_MS,
  MAX_ATTEMPTS,
} from "./adapters/http.ts";
import {
  SANITIZE_DEADLINE_MS,
  TRANSCRIBE_DEADLINE_MS,
} from "./adapters/claude.ts";
import { LABEL_DEADLINE_MS } from "./adapters/claude_label.ts";
import { HEARTBEAT_INTERVAL_MS } from "../import-recipe/index.ts";
import {
  FETCH_TIMEOUT_MS,
  FETCH_TOTAL_TIMEOUT_MS,
  MAX_REDIRECTS,
} from "./jsonld.ts";

/**
 * Supabase's request idle timeout: a function silent for this long gets a
 * gateway 504. It bounds one gap, not the call.
 * https://supabase.com/docs/guides/functions/limits
 */
const PLATFORM_IDLE_TIMEOUT_MS = 150_000;

/**
 * Supabase's wall-clock limit for one invocation: the ceiling the pipeline's
 * total has to fit inside.
 */
const PLATFORM_WALL_CLOCK_MS = 400_000;

/** Headroom for the parts nobody budgets: matching, JSON, cold start. */
const OVERHEAD_MS = 15_000;

/**
 * `edgeInvokeTimeout` and `edgeSilenceTimeout` in
 * `app/lib/features/import/data/remote_import_repository.dart`, mirrored by
 * hand so raising a server budget past one fails here too.
 */
const CLIENT_TOTAL_DEADLINE_MS = 240_000;
const CLIENT_SILENCE_MS = 90_000;

/** What the photo door costs at its worst: two model calls, back to back. */
const PHOTO_WORST_CASE_MS = TRANSCRIBE_DEADLINE_MS + SANITIZE_DEADLINE_MS +
  OVERHEAD_MS;
/** And the link door: intake, then one model call. */
const LINK_WORST_CASE_MS = FETCH_TOTAL_TIMEOUT_MS + SANITIZE_DEADLINE_MS +
  OVERHEAD_MS;

Deno.test("intake is capped as a whole, not just per hop", () => {
  assert(FETCH_TOTAL_TIMEOUT_MS >= FETCH_TIMEOUT_MS);
  // The cap has to bind: without it a chain of slow redirects costs one hop's
  // budget per hop.
  assert(FETCH_TOTAL_TIMEOUT_MS < FETCH_TIMEOUT_MS * (MAX_REDIRECTS + 1));
});

Deno.test("one attempt cannot eat a whole provider deadline", () => {
  // `postJson`'s pair, used by the benchmark-only providers.
  assert(DEFAULT_ATTEMPT_TIMEOUT_MS < DEFAULT_DEADLINE_MS);
});

Deno.test("the streaming budgets leave room for the attempt they allow", () => {
  // A budget under the minimum useful attempt would refuse to dial out at all;
  // an idle timer above it would end an attempt that had time to finish.
  assert(DEFAULT_IDLE_TIMEOUT_MS < DEFAULT_MIN_ATTEMPT_MS);
  assert(DEFAULT_MIN_ATTEMPT_MS < TRANSCRIBE_DEADLINE_MS);
  assert(DEFAULT_MIN_ATTEMPT_MS < SANITIZE_DEADLINE_MS);
  // Sanitize writes the whole recipe out; transcribe only reads the page.
  assert(TRANSCRIBE_DEADLINE_MS < SANITIZE_DEADLINE_MS);
});

/**
 * The two backoff sleeps between three stalled attempts, at the 1s base
 * `streamJson` uses: under 1.5s then under 2.5s, jitter included.
 */
const MODEL_BACKOFF_MS = 4_000;

/**
 * A model call that is producing. The worst gap is a delta landing just under
 * one interval after the last frame, then nothing until the idle timer fires.
 */
const STREAMING_MODEL_SILENCE_MS = HEARTBEAT_INTERVAL_MS +
  DEFAULT_IDLE_TIMEOUT_MS;

/**
 * A model call that never starts producing: the widest gap in the pipeline.
 * With nothing to heartbeat about, a run of silent attempts is one gap: every
 * idle window plus the sleeps between them.
 */
const STALLED_MODEL_SILENCE_MS = DEFAULT_IDLE_TIMEOUT_MS * MAX_ATTEMPTS +
  MODEL_BACKOFF_MS;

/** The longest the stream can go quiet. */
const LONGEST_SILENCE_MS = Math.max(
  FETCH_TOTAL_TIMEOUT_MS,
  STREAMING_MODEL_SILENCE_MS,
  STALLED_MODEL_SILENCE_MS,
);

Deno.test("the stream is never quiet for as long as the platform's idle timeout", () => {
  assert(
    LONGEST_SILENCE_MS + OVERHEAD_MS < PLATFORM_IDLE_TIMEOUT_MS,
    `the longest gap between events is ${LONGEST_SILENCE_MS}ms, which with ` +
      `${OVERHEAD_MS}ms of slack does not fit inside the platform's ` +
      `${PLATFORM_IDLE_TIMEOUT_MS}ms idle timeout`,
  );
  // The app gives up on a gap before the platform does, so a person gets a
  // sentence rather than a gateway error.
  assert(
    LONGEST_SILENCE_MS + OVERHEAD_MS < CLIENT_SILENCE_MS,
    `the longest gap between events is ${LONGEST_SILENCE_MS}ms, which with ` +
      `${OVERHEAD_MS}ms of slack outlasts the app's ${CLIENT_SILENCE_MS}ms ` +
      `silence rung — the app would give up on a server that is still trying`,
  );
  assert(CLIENT_SILENCE_MS < PLATFORM_IDLE_TIMEOUT_MS);
  // The widest gap is a call that never produced; heartbeats cover a slow one.
  assert(STALLED_MODEL_SILENCE_MS > STREAMING_MODEL_SILENCE_MS);
});

Deno.test("the photo path outlives the idle timeout — which is exactly what heartbeats buy", () => {
  // Heartbeats free the two model calls from fitting inside
  // PLATFORM_IDLE_TIMEOUT_MS together. If this fails, the budgets have shrunk
  // back under that ceiling.
  assert(
    PHOTO_WORST_CASE_MS > PLATFORM_IDLE_TIMEOUT_MS,
    `the photo path (${PHOTO_WORST_CASE_MS}ms) is back inside the platform's ` +
      `idle timeout — the model budgets are being sized by the wrong number`,
  );
  assert(
    PHOTO_WORST_CASE_MS < PLATFORM_WALL_CLOCK_MS,
    `photo import worst case ${PHOTO_WORST_CASE_MS}ms has outgrown the ` +
      `platform's ${PLATFORM_WALL_CLOCK_MS}ms wall-clock limit`,
  );
});

Deno.test("the client outlasts the worst case the pipeline can reach", () => {
  assert(
    PHOTO_WORST_CASE_MS < CLIENT_TOTAL_DEADLINE_MS,
    `photo import worst case ${PHOTO_WORST_CASE_MS}ms has outgrown the ` +
      `client's ${CLIENT_TOTAL_DEADLINE_MS}ms total deadline`,
  );
  // Or the total rung could never be the one that fires.
  assert(CLIENT_SILENCE_MS < CLIENT_TOTAL_DEADLINE_MS);
});

Deno.test("the label door buys no heartbeat, so its one call fits the idle timeout", () => {
  // `read-label` answers with a plain JSON body: no stages, no heartbeat, and
  // therefore nothing to keep the gateway from seeing one long silence. Its
  // whole worst case has to fit where the import doors' does not.
  const labelWorstCaseMs = LABEL_DEADLINE_MS + OVERHEAD_MS;
  assert(
    labelWorstCaseMs < PLATFORM_IDLE_TIMEOUT_MS,
    `reading a label worst case ${labelWorstCaseMs}ms does not fit inside ` +
      `the platform's ${PLATFORM_IDLE_TIMEOUT_MS}ms idle timeout — that door ` +
      `sends no heartbeat, so it has to`,
  );
});

Deno.test("the link path — intake plus one model call — is the lighter door", () => {
  assert(
    LINK_WORST_CASE_MS < PHOTO_WORST_CASE_MS,
    `the link path (${LINK_WORST_CASE_MS}ms) is supposed to be cheaper than ` +
      `the photo path (${PHOTO_WORST_CASE_MS}ms)`,
  );
});
