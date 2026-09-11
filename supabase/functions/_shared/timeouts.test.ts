// The server half of the import's timeout ladder, checked as arithmetic rather
// than as prose. The ladder itself is written out where the client timeout
// lives (`app/lib/features/import/data/remote_import_repository.dart`).
//
// Why this is worth a test: the numbers live in four files that nobody edits
// together, and the failure they guard against is silent. Raise one model
// deadline "a bit" and the longest SILENCE the function can produce walks past
// the platform's cut-off, at which point every long import dies as a gateway
// 504 with the model call already paid for.
//
// What the platform's idle timeout measures changed twice. The stage stream
// (§4.7) made it bound the longest GAP between events rather than the whole
// call. HEARTBEATS then shrank that gap again: while a model call streams, the
// function says so every `HEARTBEAT_INTERVAL_MS`, so a model budget is no
// longer a silence at all. That is what lets the budgets below be sized by what
// the model needs (`evals/runs/`) instead of by what the platform tolerates —
// and it is why the photo path may now cost MORE than the idle timeout.

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
import { HEARTBEAT_INTERVAL_MS } from "../import-recipe/index.ts";
import {
  FETCH_TIMEOUT_MS,
  FETCH_TOTAL_TIMEOUT_MS,
  MAX_REDIRECTS,
} from "./jsonld.ts";

/**
 * Supabase's request idle timeout: a function that has sent nothing by then is
 * cut off with a gateway 504, whatever it is still doing. It bounds one GAP,
 * not the call — the call is bounded by the wall-clock limit below.
 * https://supabase.com/docs/guides/functions/limits
 */
const PLATFORM_IDLE_TIMEOUT_MS = 150_000;

/**
 * Supabase's wall-clock limit for one invocation, from the same page. With the
 * stream and its heartbeats this — not the idle timeout — is the platform
 * ceiling the pipeline's total has to fit inside. It is not ours to raise.
 */
const PLATFORM_WALL_CLOCK_MS = 400_000;

/** Headroom for the parts nobody budgets: matching, JSON, cold start. */
const OVERHEAD_MS = 15_000;

/**
 * `edgeInvokeTimeout` and `edgeSilenceTimeout` in
 * `app/lib/features/import/data/remote_import_repository.dart` — the client's
 * two rungs. Mirrored here (there is no way to import a Dart constant) so
 * raising a server budget past one fails on this side too.
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
  // The cap has to actually BIND, or it is decorative: without it a chain of
  // slow redirects costs one hop's budget times the number of hops.
  assert(FETCH_TOTAL_TIMEOUT_MS < FETCH_TIMEOUT_MS * (MAX_REDIRECTS + 1));
});

Deno.test("one attempt cannot eat a whole provider deadline", () => {
  // `postJson`'s pair — the benchmark-only providers still use it.
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
 * A model call that IS producing. The heartbeat is throttled, so the worst gap
 * is a delta landing just under one interval after the last frame — too soon to
 * beat — and then nothing, until the idle timer ends the attempt.
 */
const STREAMING_MODEL_SILENCE_MS = HEARTBEAT_INTERVAL_MS +
  DEFAULT_IDLE_TIMEOUT_MS;

/**
 * A model call that never starts producing — the honest worst case, and the
 * widest gap in the whole pipeline. Before the first delta there is nothing to
 * heartbeat ABOUT, so a run of attempts that each go silent is ONE gap: every
 * idle window, plus the sleeps between them. Raising the idle timer is what
 * would break this first, which is exactly the coupling worth a test.
 */
const STALLED_MODEL_SILENCE_MS = DEFAULT_IDLE_TIMEOUT_MS * MAX_ATTEMPTS +
  MODEL_BACKOFF_MS;

/** The longest the stream can go quiet — the widest of the three. */
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
  // …and the APP gives up on a gap before the platform does, so a person gets
  // a sentence rather than a gateway error.
  assert(
    LONGEST_SILENCE_MS + OVERHEAD_MS < CLIENT_SILENCE_MS,
    `the longest gap between events is ${LONGEST_SILENCE_MS}ms, which with ` +
      `${OVERHEAD_MS}ms of slack outlasts the app's ${CLIENT_SILENCE_MS}ms ` +
      `silence rung — the app would give up on a server that is still trying`,
  );
  assert(CLIENT_SILENCE_MS < PLATFORM_IDLE_TIMEOUT_MS);
  // The widest gap is a model call that never produced, not one that is slow:
  // heartbeats cover the second case, and nothing can cover the first.
  assert(STALLED_MODEL_SILENCE_MS > STREAMING_MODEL_SILENCE_MS);
});

Deno.test("the photo path outlives the idle timeout — which is exactly what heartbeats buy", () => {
  // THE rung. Before the heartbeats, both model calls had to fit inside
  // PLATFORM_IDLE_TIMEOUT_MS together, and that arithmetic is what held
  // sanitize to 60s while the corpus said it could legitimately need ~54s on a
  // bad day. If this assertion ever fails the budgets have shrunk back under
  // the old ceiling, and the reason for the heartbeats has been lost.
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

Deno.test("the link path — intake plus one model call — is the lighter door", () => {
  assert(
    LINK_WORST_CASE_MS < PHOTO_WORST_CASE_MS,
    `the link path (${LINK_WORST_CASE_MS}ms) is supposed to be cheaper than ` +
      `the photo path (${PHOTO_WORST_CASE_MS}ms)`,
  );
});
