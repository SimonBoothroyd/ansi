// The server half of the import's timeout ladder, checked as arithmetic rather
// than as prose. The ladder itself is written out where the client timeout
// lives (`app/lib/features/import/data/remote_import_repository.dart`).
//
// Why this is worth a test: the numbers live in three files that nobody edits
// together, and the failure they guard against is silent. Raise one model
// deadline "a bit" and the photo path — which spends TWO of them back to back —
// walks past the platform's cut-off, at which point every long import dies as a
// gateway 504 with the model call already paid for.

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

Deno.test("intake is capped as a whole, not just per hop", () => {
  assert(FETCH_TOTAL_TIMEOUT_MS >= FETCH_TIMEOUT_MS);
  // The cap has to actually BIND, or it is decorative: without it a chain of
  // slow redirects costs one hop's budget times the number of hops.
  assert(FETCH_TOTAL_TIMEOUT_MS < FETCH_TIMEOUT_MS * (MAX_REDIRECTS + 1));
});

Deno.test("one attempt cannot eat a whole provider deadline", () => {
  assert(DEFAULT_ATTEMPT_TIMEOUT_MS < DEFAULT_DEADLINE_MS);
});

Deno.test("the photo path — two model calls — fits inside the platform cut-off", () => {
  const photos = DEFAULT_DEADLINE_MS * 2 + OVERHEAD_MS;
  assert(
    photos < PLATFORM_IDLE_TIMEOUT_MS,
    `photo import worst case ${photos}ms exceeds the platform's ` +
      `${PLATFORM_IDLE_TIMEOUT_MS}ms idle timeout`,
  );
});

Deno.test("the link path — intake plus one model call — fits too", () => {
  const link = FETCH_TOTAL_TIMEOUT_MS + DEFAULT_DEADLINE_MS + OVERHEAD_MS;
  assert(
    link < PLATFORM_IDLE_TIMEOUT_MS,
    `link import worst case ${link}ms exceeds the platform's ` +
      `${PLATFORM_IDLE_TIMEOUT_MS}ms idle timeout`,
  );
});
