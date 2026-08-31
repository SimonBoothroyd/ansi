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
