// The benchmark's price list: $/Mtok per PINNED model, checked in and DATED.
//
// Why checked in rather than fetched: a benchmark run is a dated artifact. If
// the numbers were fetched at score time, re-scoring a run from six weeks ago
// would silently re-price it at today's rates and the two runs would stop being
// comparable. Every row therefore carries the URL it came from and the date it
// was read, and a persisted run records the rows it was priced with.
//
// Adding a model: pin its exact id in the adapter, add a row here with a source
// URL and a `retrieved` date, and that is the whole change — nothing else keys
// off the model string. A model with no row costs `null`, which the report
// prints as "n/a", never as free.
//
// KEYLESS and network-free.

import type { TokenUsage } from "../../supabase/functions/_shared/types.ts";

export interface PriceRow {
  /** The exact pinned model id — the key the adapter actually sends. */
  model: string;
  /** Human label for the report column. */
  label: string;
  usd_per_mtok_input: number;
  usd_per_mtok_output: number;
  /** Cache-READ (hit) rate, or null where the provider does not price one. */
  usd_per_mtok_cache_read: number | null;
  /** Cache-WRITE rate, or null where writes are not separately billed. */
  usd_per_mtok_cache_write: number | null;
  /** Where the numbers came from. */
  source: string;
  /** yyyy-mm-dd the source was read. */
  retrieved: string;
  note?: string;
}

/**
 * Every model the benchmark can currently run, keyed by the exact model id.
 *
 * All four rows were read on 2026-08-31 from the vendors' own pricing pages.
 * The two Gemini Flash tiers and Claude Haiku are listed even though only one
 * of each is pinned, so an owner-confirmed swap needs no second pricing pass.
 */
export const PRICING: Record<string, PriceRow> = {
  "claude-haiku-4-5": {
    model: "claude-haiku-4-5",
    label: "Claude Haiku 4.5",
    usd_per_mtok_input: 1.0,
    usd_per_mtok_output: 5.0,
    usd_per_mtok_cache_read: 0.1,
    usd_per_mtok_cache_write: 1.25,
    source: "https://platform.claude.com/docs/en/about-claude/pricing",
    retrieved: "2026-08-31",
    note:
      "cache_write is the 5-minute rate (1.25x base input); the adapter marks " +
      "one ephemeral breakpoint on the sanitize system prompt.",
  },
  "gpt-5.6-luna": {
    model: "gpt-5.6-luna",
    label: "GPT-5.6 Luna",
    usd_per_mtok_input: 0.2,
    usd_per_mtok_output: 1.2,
    usd_per_mtok_cache_read: 0.02,
    usd_per_mtok_cache_write: null, // OpenAI caching is automatic, writes unbilled
    source: "https://developers.openai.com/api/docs/pricing",
    retrieved: "2026-08-31",
    note: "short-context standard tier (the recipe corpus is far below any " +
      "long-context threshold).",
  },
  "gemini-3.5-flash": {
    model: "gemini-3.5-flash",
    label: "Gemini 3.5 Flash",
    usd_per_mtok_input: 1.5,
    usd_per_mtok_output: 9.0,
    usd_per_mtok_cache_read: 0.15,
    usd_per_mtok_cache_write: null, // explicit caching is a separate endpoint
    source: "https://ai.google.dev/gemini-api/docs/pricing",
    retrieved: "2026-08-31",
    note: "output price includes thinking tokens, which is why the usage " +
      "parser folds thoughtsTokenCount into output_tokens. Context-cache " +
      "storage ($1/Mtok/hour) is NOT modelled — this adapter creates no cache.",
  },
  // --- priced but not pinned: candidates for the owner's confirmation --------
  "gemini-3.7-flash": {
    model: "gemini-3.7-flash",
    label: "Gemini 3.7 Flash",
    usd_per_mtok_input: 0.75,
    usd_per_mtok_output: 3.75,
    usd_per_mtok_cache_read: 0.075,
    usd_per_mtok_cache_write: null,
    source: "https://ai.google.dev/gemini-api/docs/pricing",
    retrieved: "2026-08-31",
    note:
      "NEWER than the pinned 3.5 Flash and currently CHEAPER: promotional rate " +
      "through 2026-12-31, then $1.50 / $7.50. Not pinned — the owner asked " +
      "for 3.5 by name.",
  },
  "gemini-3.5-flash-lite": {
    model: "gemini-3.5-flash-lite",
    label: "Gemini 3.5 Flash Lite",
    usd_per_mtok_input: 0.3,
    usd_per_mtok_output: 2.5,
    usd_per_mtok_cache_read: 0.03,
    usd_per_mtok_cache_write: null,
    source: "https://ai.google.dev/gemini-api/docs/pricing",
    retrieved: "2026-08-31",
    note: "the cheaper half of the 3.5 Flash pair, if the flash-tier framing " +
      "should mean the lite variant.",
  },
  "gpt-5.4-mini": {
    model: "gpt-5.4-mini",
    label: "GPT-5.4 Mini",
    usd_per_mtok_input: 0.75,
    usd_per_mtok_output: 4.5,
    usd_per_mtok_cache_read: 0.075,
    usd_per_mtok_cache_write: null,
    source: "https://developers.openai.com/api/docs/pricing",
    retrieved: "2026-08-31",
    note: "the id this repo was pinned to before 2026-08-31 — kept so an " +
      "old run can still be re-priced.",
  },
  // The mock is free by construction; a row keeps the keyless run's cost
  // columns exercised end-to-end instead of falling through to "n/a".
  "mock-1": {
    model: "mock-1",
    label: "Mock (free)",
    usd_per_mtok_input: 0,
    usd_per_mtok_output: 0,
    usd_per_mtok_cache_read: 0,
    usd_per_mtok_cache_write: 0,
    source: "n/a — keyless reference adapter, no provider call is made",
    retrieved: "2026-08-31",
  },
};

export function priceRow(model: string): PriceRow | null {
  return PRICING[model] ?? null;
}

/** What one call (or a set of them) cost, split by what drove the spend. */
export interface Cost {
  usd_input: number;
  usd_output: number;
  usd_cache_read: number;
  usd_cache_write: number;
  usd_total: number;
  /**
   * True when at least one priced field was `null` in the usage, i.e. the
   * provider did not report it. The total is then a LOWER BOUND, and the report
   * says so rather than quietly presenting it as exact.
   */
  partial: boolean;
}

export function zeroCost(): Cost {
  return {
    usd_input: 0,
    usd_output: 0,
    usd_cache_read: 0,
    usd_cache_write: 0,
    usd_total: 0,
    partial: false,
  };
}

const PER_MTOK = 1_000_000;

/**
 * Cost of one call's usage at a model's rates. `null` when the model has no
 * priced row — an unpriced model must read "n/a", never "$0.00".
 *
 * `usage` is already normalized by `_shared/adapters/usage.ts`: `input_tokens`
 * excludes cache reads and writes for EVERY provider, so this is a plain
 * four-term sum with no per-provider special cases. A token count the provider
 * did not report contributes 0 and flips `partial`.
 */
export function costOf(model: string, usage: TokenUsage | null): Cost | null {
  const row = priceRow(model);
  if (!row) return null;
  if (!usage) return { ...zeroCost(), partial: true };
  let partial = false;
  const term = (tokens: number | null, rate: number | null): number => {
    if (tokens === null || tokens === 0) {
      if (tokens === null) partial = true;
      return 0;
    }
    if (rate === null) {
      // The provider reported tokens for a category it does not separately
      // price (e.g. OpenAI cache writes). Not partial — genuinely unbilled.
      return 0;
    }
    return (tokens / PER_MTOK) * rate;
  };
  const usd_input = term(usage.input_tokens, row.usd_per_mtok_input);
  const usd_output = term(usage.output_tokens, row.usd_per_mtok_output);
  const usd_cache_read = term(
    usage.cache_read_tokens,
    row.usd_per_mtok_cache_read,
  );
  const usd_cache_write = term(
    usage.cache_write_tokens,
    row.usd_per_mtok_cache_write,
  );
  return {
    usd_input,
    usd_output,
    usd_cache_read,
    usd_cache_write,
    usd_total: usd_input + usd_output + usd_cache_read + usd_cache_write,
    partial,
  };
}

export function addCost(a: Cost, b: Cost): Cost {
  return {
    usd_input: a.usd_input + b.usd_input,
    usd_output: a.usd_output + b.usd_output,
    usd_cache_read: a.usd_cache_read + b.usd_cache_read,
    usd_cache_write: a.usd_cache_write + b.usd_cache_write,
    usd_total: a.usd_total + b.usd_total,
    partial: a.partial || b.partial,
  };
}

export function addUsage(a: TokenUsage, b: TokenUsage | null): TokenUsage {
  if (!b) return a;
  // null + n = n; null + null stays null, so "nobody reported this" survives
  // the aggregation instead of becoming a misleading 0.
  const plus = (x: number | null, y: number | null): number | null =>
    x === null && y === null ? null : (x ?? 0) + (y ?? 0);
  return {
    input_tokens: plus(a.input_tokens, b.input_tokens),
    output_tokens: plus(a.output_tokens, b.output_tokens),
    cache_read_tokens: plus(a.cache_read_tokens, b.cache_read_tokens),
    cache_write_tokens: plus(a.cache_write_tokens, b.cache_write_tokens),
    reasoning_tokens: plus(a.reasoning_tokens, b.reasoning_tokens),
    total_tokens: plus(a.total_tokens, b.total_tokens),
  };
}

/** `$0.001234` at four significant-ish decimals — cents are too coarse here. */
export function usd(x: number): string {
  if (!Number.isFinite(x)) return "—";
  if (x === 0) return "$0";
  if (x < 0.01) return `$${x.toFixed(6)}`;
  if (x < 1) return `$${x.toFixed(4)}`;
  return `$${x.toFixed(2)}`;
}
