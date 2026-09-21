// What a person is told when an import pipeline throws, and the status that
// would carry it had the answer not started streaming. Shared by both import
// functions; only the subject ("this recipe", "this receipt") differs. The
// detail goes to the function log.

import { ImportError, isTimeoutFailure } from "./errors.ts";

export interface FailureVoice {
  /** The function's own name, for the log line ("import-recipe"). */
  fn: string;
  /** What the person was importing: "recipe" or "receipt". */
  subject: string;
}

/**
 * Three server-side shapes, the same for both doors:
 *
 *   422: an {@link ImportError}, something the person can act on, in the words
 *        whoever raised it chose.
 *   504: out of time. Says so, and that retrying costs nothing.
 *   500: anything else. The detail can carry provider URLs, prompt fragments
 *        or a connection string, so it is logged and never returned.
 *
 * A stream that went quiet or ended without a result is the reader's to
 * report (`remote_import_repository.dart`).
 */
export function failureFor(
  e: unknown,
  voice: FailureVoice,
): { status: number; error: string } {
  if (e instanceof ImportError) return { status: 422, error: e.message };
  if (isTimeoutFailure(e)) {
    console.error(
      `${voice.fn}: extraction timed out: ${
        e instanceof Error ? e.message : String(e)
      }`,
    );
    return {
      status: 504,
      error: `the model took too long to read this ${voice.subject} — ` +
        `nothing has been saved, so it is safe to try again`,
    };
  }
  console.error(
    `${voice.fn}: unhandled failure: ${
      e instanceof Error ? e.stack ?? e.message : String(e)
    }`,
  );
  return { status: 500, error: "import failed" };
}
