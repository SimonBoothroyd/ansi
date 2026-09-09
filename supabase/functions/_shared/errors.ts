// The one client-visible pipeline error, shared by every stage.
//
// It lives here (not in `import-recipe/index.ts`) so the stages BELOW the
// orchestrator — intake (`jsonld.ts`), the provider adapters — can raise a
// human-readable failure without importing the orchestrator and creating a
// cycle. `index.ts` re-exports it, so `e instanceof ImportError` is the same
// class everywhere and the HTTP boundary keeps mapping it to a 422.

/** A client-visible pipeline error → surfaced as 4xx, never a 500. */
export class ImportError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ImportError";
  }
}

/**
 * True for the failures that mean "we ran out of time waiting", whoever raised
 * them: the provider plumbing's own deadline (`ProviderTimeoutError`), an
 * aborted attempt (`AbortError`), and `AbortSignal.timeout`'s `TimeoutError`.
 *
 * Matched by NAME, not by class, for two reasons: the orchestrator can classify
 * a failure without importing the adapter plumbing, and the abort a `fetch`
 * raises is a `DOMException` that is not one of our classes at all.
 *
 * It exists so a timeout stops arriving as the opaque "import failed" 500. A
 * person who waited two minutes needs to know it was the reading that ran long
 * — not that their recipe was rejected — and that nothing was written.
 */
export function isTimeoutFailure(e: unknown): boolean {
  if (!(e instanceof Error)) return false;
  return e.name === "ProviderTimeoutError" || e.name === "TimeoutError" ||
    e.name === "AbortError";
}
