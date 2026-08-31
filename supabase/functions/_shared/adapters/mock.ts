// The mock / reference adapter — a keyless ExtractAdapter so the whole harness
// (adapters seam, prompts wiring, scorers, ledger, calibration) builds and
// self-tests with NO provider API key (charter 0018 boundary).
//
// It carries no intelligence of its own: it returns whatever `sanitizeWith`
// resolves for a blob (the eval harness feeds it the gold, optionally perturbed,
// to exercise the scorer's perfect path AND its dangerous-failure ledger). This
// keeps the ExtractAdapter interface honest — a real provider is a drop-in
// replacement — while making green, keyless CI possible.

import type {
  ExtractAdapter,
  ExtractionResult,
  RawBlob,
  UnitHints,
} from "../types.ts";
import { coerceExtractionResult, validateExtractionResult } from "./schema.ts";

export type SanitizeResolver = (
  blob: RawBlob,
  hints: UnitHints,
) => ExtractionResult;

export type TranscribeResolver = (images: Uint8Array[]) => RawBlob;

export interface MockAdapterOptions {
  name?: string;
  /** Produces the ① output for a blob. Required — the eval supplies the gold. */
  sanitizeWith: SanitizeResolver;
  /** Optional vision tier. Omit to model a jsonld-style, transcribe-less adapter. */
  transcribeWith?: TranscribeResolver;
  /** Route the result through coercion + structural validation (default true). */
  validate?: boolean;
}

export class MockAdapter implements ExtractAdapter {
  readonly name: string;
  readonly #sanitize: SanitizeResolver;
  readonly #transcribe?: TranscribeResolver;
  readonly #validate: boolean;

  constructor(opts: MockAdapterOptions) {
    this.name = opts.name ?? "mock";
    this.#sanitize = opts.sanitizeWith;
    this.#transcribe = opts.transcribeWith;
    this.#validate = opts.validate ?? true;
    // `transcribe` is an optional interface member; only expose it when a
    // resolver was given, so a mock can faithfully model a no-vision adapter.
    if (this.#transcribe) {
      this.transcribe = (images: Uint8Array[]) => {
        return Promise.resolve(this.#transcribe!(images));
      };
    }
  }

  transcribe?: (images: Uint8Array[]) => Promise<RawBlob>;

  sanitize(blob: RawBlob, hints: UnitHints): Promise<ExtractionResult> {
    const raw = this.#sanitize(blob, hints);
    // Round-trip through coercion so the mock exercises the same path a real
    // provider's JSON does (catches schema drift between the two).
    const coerced = coerceExtractionResult(raw as unknown);
    return Promise.resolve(
      this.#validate ? validateExtractionResult(coerced) : coerced,
    );
  }
}

/** A mock whose sanitize always returns `result` (the gold-oracle case). */
export function fixedMock(
  result: ExtractionResult,
  name = "mock-oracle",
): MockAdapter {
  return new MockAdapter({ name, sanitizeWith: () => result });
}
