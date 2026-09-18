// What a person is told when an import pipeline throws, and the status that
// would carry it if the answer had not already started streaming.
//
// Shared by both import functions so the two doors fail in the same shapes.
// Only the SUBJECT differs — "this recipe", "this receipt" — because a person
// who waited two minutes needs to know which thing ran long, and a sentence
// that named neither would be worse than either.
//
// Logging the un-showable detail is part of it: the caller gets the sentence,
// the function log gets the stack.

import { ImportError, isTimeoutFailure } from "./errors.ts";

export interface FailureVoice {
  /** The function's own name, for the log line ("import-recipe"). */
  fn: string;
  /** What the person was importing, as the sentence names it ("recipe", "receipt"). */
  subject: string;
}

/**
 * Three server-side shapes, and they are the same three for both doors:
 *
 *   422 — an {@link ImportError}: something about the request or the paper the
 *         person can act on, in the words whoever raised it chose.
 *   504 — running out of time. Not an unexpected failure and not the recipe's
 *         or the receipt's fault: say so, and say that retrying costs nothing.
 *   500 — anything else. The detail can carry provider URLs, prompt fragments
 *         or a driver's connection string, so it is logged and never returned.
 *
 * The fourth shape a client sees — a stream that went quiet, or ended without a
 * result — is not raised here: it has no server to raise it, and the reader
 * owns it (`remote_import_repository.dart`).
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
