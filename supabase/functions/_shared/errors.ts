// The one client-visible pipeline error, shared by every stage. It lives here
// so intake (`jsonld.ts`) and the adapters can raise it without importing the
// orchestrator. `index.ts` re-exports it; the HTTP boundary maps it to a 422.

/** A client-visible pipeline error → surfaced as 4xx, never a 500. */
export class ImportError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ImportError";
  }
}

/**
 * True for failures that mean "we ran out of time": `ProviderTimeoutError`, an
 * `AbortError`, and `AbortSignal.timeout`'s `TimeoutError`. Matched by name,
 * because the abort a `fetch` raises is a `DOMException`, not one of our
 * classes. Lets a timeout be reported as one rather than as a 500.
 */
export function isTimeoutFailure(e: unknown): boolean {
  if (!(e instanceof Error)) return false;
  return e.name === "ProviderTimeoutError" || e.name === "TimeoutError" ||
    e.name === "AbortError";
}
