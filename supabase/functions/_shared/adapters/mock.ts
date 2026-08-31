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
  ProviderCallSink,
  RawBlob,
  TokenUsage,
  UnitHints,
} from "../types.ts";
import { coerceExtractionResult, validateExtractionResult } from "./schema.ts";
import { emitCall } from "./usage.ts";

export type SanitizeResolver = (
  blob: RawBlob,
  hints: UnitHints,
) => ExtractionResult;

export type TranscribeResolver = (images: Uint8Array[]) => RawBlob;

/** The mock's stand-in model id — never a real, billable one. */
export const MOCK_MODEL = "mock-1";

/**
 * Deterministic fake usage: a ~4-chars-per-token estimate over the input text
 * and the emitted JSON, plus a fixed cache-read share to keep the cache column
 * exercised. It is a FIXTURE, not a tokenizer — its only contract is that the
 * same (blob, result) pair always yields the same numbers, so the cost
 * columns, the persistence format and `--rescore` are all testable for free.
 */
export function mockUsage(
  inputText: string,
  result: ExtractionResult,
): TokenUsage {
  const est = (s: string) => Math.ceil(s.length / 4);
  const input = est(inputText);
  const output = est(JSON.stringify(result));
  // A tenth of the input is modelled as a prompt-cache hit so the cache-read
  // price column is never silently untested.
  const cacheRead = Math.floor(input / 10);
  return {
    input_tokens: input - cacheRead,
    output_tokens: output,
    cache_read_tokens: cacheRead,
    cache_write_tokens: 0,
    reasoning_tokens: 0,
    total_tokens: input + output,
  };
}

export interface MockAdapterOptions {
  name?: string;
  /** Produces the ① output for a blob. Required — the eval supplies the gold. */
  sanitizeWith: SanitizeResolver;
  /** Optional vision tier. Omit to model a jsonld-style, transcribe-less adapter. */
  transcribeWith?: TranscribeResolver;
  /** Route the result through coercion + structural validation (default true). */
  validate?: boolean;
  /** Stand-in model id reported on `onCall` (default `MOCK_MODEL`). */
  model?: string;
  /** Override the deterministic usage fixture (default {@link mockUsage}). */
  usageWith?: (blob: RawBlob, result: ExtractionResult) => TokenUsage;
}

export class MockAdapter implements ExtractAdapter {
  readonly name: string;
  readonly model: string;
  readonly #sanitize: SanitizeResolver;
  readonly #transcribe?: TranscribeResolver;
  readonly #validate: boolean;
  readonly #usage: (blob: RawBlob, result: ExtractionResult) => TokenUsage;
  /** Optional benchmark observer — the same seam the real adapters expose. */
  onCall?: ProviderCallSink;

  constructor(opts: MockAdapterOptions) {
    this.name = opts.name ?? "mock";
    this.model = opts.model ?? MOCK_MODEL;
    this.#sanitize = opts.sanitizeWith;
    this.#transcribe = opts.transcribeWith;
    this.#validate = opts.validate ?? true;
    this.#usage = opts.usageWith ??
      ((blob, result) => mockUsage(blob.text ?? "", result));
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
    const out = this.#validate ? validateExtractionResult(coerced) : coerced;
    // The mock's "raw response" IS the ExtractionResult, so a persisted mock run
    // round-trips through the very same decode-and-rescore path a paid run does.
    emitCall(this.onCall, {
      provider: this.name,
      model: this.model,
      op: "sanitize",
      usage: this.#usage(blob, out),
      latency_ms: 0, // deterministic: a wall-clock here would defeat the fixture
      raw: out,
    });
    return Promise.resolve(out);
  }
}

/** VERBATIM mock "response" → `ExtractionResult` (it is already the result). */
export function decodeMockSanitize(res: unknown): ExtractionResult {
  return validateExtractionResult(coerceExtractionResult(res));
}

/** A mock whose sanitize always returns `result` (the gold-oracle case). */
export function fixedMock(
  result: ExtractionResult,
  name = "mock-oracle",
): MockAdapter {
  return new MockAdapter({ name, sanitizeWith: () => result });
}
