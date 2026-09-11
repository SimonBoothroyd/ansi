// The server half of the import's timeout ladder, checked as arithmetic rather
// than as prose. The ladder itself is written out where the client timeout
// lives (`app/lib/features/import/data/remote_import_repository.dart`).
//
// Why this is worth a test: the numbers live in three files that nobody edits
// together, and the failure they guard against is silent. Raise one model
// deadline "a bit" and the longest SILENCE the function can produce walks past
// the platform's cut-off, at which point every long import dies as a gateway
// 504 with the model call already paid for.
//
// What the platform's idle timeout measures changed with the stage stream
// (§4.7): the function answers `text/event-stream` and emits an event as each
// stage lands, so the clock that matters is no longer the whole call — it is
// the longest GAP between two events. Both are checked below, because the whole
// call still has to fit inside the platform's wall-clock ceiling.

import { assert } from "@std/assert";
import {
  DEFAULT_ATTEMPT_TIMEOUT_MS,
  DEFAULT_DEADLINE_MS,
} from "./adapters/http.ts";
import {
  FETCH_TIMEOUT_MS,
  FETCH_TOTAL_TIMEOUT_MS,
  MAX_REDIRECTS,
} from "./jsonld.ts";

/**
 * Supabase's request idle timeout: a function that has sent nothing by then is
 * cut off with a gateway 504, whatever it is still doing. This is the ceiling
 * every budget below has to fit inside — it is not ours to raise.
 * https://supabase.com/docs/guides/functions/limits
 */
const PLATFORM_IDLE_TIMEOUT_MS = 150_000;

/** Headroom for the parts nobody budgets: matching, JSON, cold start. */
const OVERHEAD_MS = 15_000;

/**
 * `edgeInvokeTimeout` in
 * `app/lib/features/import/data/remote_import_repository.dart` — the client's
 * ceiling on the whole call. Mirrored here (there is no way to import a Dart
 * constant) so raising a server budget past it fails on this side too.
 */
const CLIENT_TOTAL_DEADLINE_MS = 180_000;

Deno.test("intake is capped as a whole, not just per hop", () => {
  assert(FETCH_TOTAL_TIMEOUT_MS >= FETCH_TIMEOUT_MS);
  // The cap has to actually BIND, or it is decorative: without it a chain of
  // slow redirects costs one hop's budget times the number of hops.
  assert(FETCH_TOTAL_TIMEOUT_MS < FETCH_TIMEOUT_MS * (MAX_REDIRECTS + 1));
});

Deno.test("one attempt cannot eat a whole provider deadline", () => {
  assert(DEFAULT_ATTEMPT_TIMEOUT_MS < DEFAULT_DEADLINE_MS);
});

/**
 * The longest the stage stream can go quiet. Every stage boundary emits an
 * event, so the gaps are: request → `received` (negligible), `received` →
 * `fetched`/`transcribed` (intake, or one model call), → `sanitised` (one model
 * call), → `matched` (two batched queries). The model deadline is the widest.
 */
const LONGEST_SILENCE_MS = Math.max(
  DEFAULT_DEADLINE_MS,
  FETCH_TOTAL_TIMEOUT_MS,
);

Deno.test("the stream is never quiet for as long as the platform's idle timeout", () => {
  // THE rung the stage stream buys. Before it, a photo import sent nothing at
  // all for its whole duration and the two model calls had to fit inside this
  // number together; now only ONE of them has to.
  assert(
    LONGEST_SILENCE_MS + OVERHEAD_MS < PLATFORM_IDLE_TIMEOUT_MS,
    `the longest gap between events is ${LONGEST_SILENCE_MS}ms, which with ` +
      `${OVERHEAD_MS}ms of slack does not fit inside the platform's ` +
      `${PLATFORM_IDLE_TIMEOUT_MS}ms idle timeout`,
  );
});

Deno.test("the photo path — two model calls — is the worst case the client must outlast", () => {
  // Not a platform check any more: the stream keeps the connection alive
  // through both calls. It is the number the CLIENT's total deadline is sized
  // against (`edgeInvokeTimeout`), so it is worth keeping honest here.
  const photos = DEFAULT_DEADLINE_MS * 2 + OVERHEAD_MS;
  assert(photos > DEFAULT_DEADLINE_MS, "two calls cost more than one");
  assert(
    photos < CLIENT_TOTAL_DEADLINE_MS,
    `photo import worst case ${photos}ms has outgrown the client's ` +
      `${CLIENT_TOTAL_DEADLINE_MS}ms total deadline`,
  );
});

Deno.test("the link path — intake plus one model call — is the lighter door", () => {
  const link = FETCH_TOTAL_TIMEOUT_MS + DEFAULT_DEADLINE_MS + OVERHEAD_MS;
  const photos = DEFAULT_DEADLINE_MS * 2 + OVERHEAD_MS;
  assert(
    link < photos,
    `the link path (${link}ms) is supposed to be cheaper than the photo ` +
      `path (${photos}ms)`,
  );
});
