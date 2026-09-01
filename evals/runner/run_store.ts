// Persisted benchmark runs — the paid artifact.
//
// A live provider compare costs real money, and until now its output was a
// scorecard printed to a terminal. Any scorer fix, any gold correction, any new
// metric meant paying for the whole run again. So a live run now writes the
// provider's VERBATIM response for every case to
//
//   evals/runs/<yyyy-mm-dd>-<label>/<provider>/<case>.json
//   evals/runs/<yyyy-mm-dd>-<label>/manifest.json
//
// and those files are COMMITTED (`evals/reports/` stays gitignored — that is
// derived output; this is not). `--rescore <run-dir>` then replays each saved
// response through the SAME decoder the live call used and scores it with
// today's scorer, at zero cost and with no key.
//
// What a case file carries, and why each field is load-bearing:
//   raw        the response exactly as parsed off the wire — the thing that was
//              paid for. Everything else is derivable from it plus this repo.
//   model      the PINNED id actually sent, so a run made before a re-pin can
//              still be read and priced correctly.
//   usage      normalized token counts (see `_shared/adapters/usage.ts`).
//   input      the exact rendered input text AND its sha256, so a rescore can
//              prove the gold that produced this run still renders identically.
//   git_rev    (manifest) the runner revision, so a scorer change is auditable.
//
// KEYLESS and network-free. Writing needs --allow-write; reading --allow-read.

import type {
  ExtractionResult,
  ProviderCall,
  TokenUsage,
} from "../../supabase/functions/_shared/types.ts";
import {
  decodeMockSanitize,
  MOCK_MODEL,
  RESPONSE_DECODERS,
} from "../../supabase/functions/_shared/adapters/mod.ts";
import type { ProviderName } from "../../supabase/functions/_shared/adapters/mod.ts";
import { type PriceRow, priceRow } from "./pricing.ts";

// These tags are WRITTEN into every new run and never checked on read (loadRun
// casts, it does not validate), which is why the 2026-09-01 Mise → Ansi rename
// could move them without touching the runs already committed under `runs/`.
// Those older artifacts still say `mise.eval.*` and stay fully re-scoreable.
export const CASE_SCHEMA = "ansi.eval.extraction-response/1";
export const MANIFEST_SCHEMA = "ansi.eval.extraction-run/1";

/** Where committed run artifacts live (NOT `reports/`, which is gitignored). */
export const RUNS_DIR = new URL("../runs/", import.meta.url);

export interface SavedInput {
  /** The exact text handed to `sanitize` — a rescore must see what the run saw. */
  text: string;
  sha256: string;
}

export interface SavedCase {
  schema: typeof CASE_SCHEMA;
  case_id: string;
  provider: string;
  model: string;
  stage: string;
  path: string;
  op: "transcribe" | "sanitize";
  captured_at: string;
  latency_ms: number;
  usage: TokenUsage | null;
  input: SavedInput;
  /** The provider's response body, verbatim. */
  raw: unknown;
  /**
   * The adapter's error message when the call or decode failed. The case is
   * still written: a run that only saves its successes cannot be re-scored
   * honestly, since the failures are exactly what the json-valid rate measures.
   */
  error: string | null;
}

export interface ManifestProvider {
  provider: string;
  model: string;
  /** The pricing row this run was costed with, snapshotted (rates move). */
  price: PriceRow | null;
}

export interface RunManifest {
  schema: typeof MANIFEST_SCHEMA;
  label: string;
  created_at: string;
  /** Runner git revision, or "unknown" when it could not be read. */
  git_rev: string;
  stage: string;
  path: string;
  providers: ManifestProvider[];
  case_ids: string[];
  note: string;
}

/** sha256 hex of a string — the input fingerprint stored beside each response. */
export async function sha256Hex(s: string): Promise<string> {
  const bytes = new TextEncoder().encode(s);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * The runner's git revision, best-effort. Missing `--allow-run` is NOT an
 * error: the revision is provenance metadata, and a run that refuses to save
 * because it could not shell out to git would be strictly worse than one that
 * saves with `git_rev: "unknown"`.
 */
export async function gitRev(): Promise<string> {
  try {
    const out = await new Deno.Command("git", {
      args: ["rev-parse", "HEAD"],
      stdout: "piped",
      stderr: "null",
    }).output();
    if (!out.success) return "unknown";
    return new TextDecoder().decode(out.stdout).trim() || "unknown";
  } catch {
    return "unknown";
  }
}

/** `yyyy-mm-dd` in UTC — the run-directory date component. */
export function todayStamp(now = new Date()): string {
  return now.toISOString().slice(0, 10);
}

/** A filesystem-safe slug, so a `--label` can be typed freely. */
export function slug(s: string): string {
  const out = s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(
    /^-+|-+$/g,
    "",
  );
  return out === "" ? "run" : out;
}

/** `evals/runs/<yyyy-mm-dd>-<label>/`, under `base` (default `RUNS_DIR`). */
export function runDir(label: string, base: URL = RUNS_DIR, now?: Date): URL {
  return new URL(`${todayStamp(now)}-${slug(label)}/`, base);
}

function caseFile(dir: URL, provider: string, caseId: string): URL {
  return new URL(`${slug(provider)}/${slug(caseId)}.json`, dir);
}

export async function writeCase(dir: URL, rec: SavedCase): Promise<void> {
  const file = caseFile(dir, rec.provider, rec.case_id);
  await Deno.mkdir(new URL(".", file), { recursive: true });
  await Deno.writeTextFile(file, JSON.stringify(rec, null, 2) + "\n");
}

export async function writeManifest(
  dir: URL,
  manifest: RunManifest,
): Promise<void> {
  await Deno.mkdir(dir, { recursive: true });
  await Deno.writeTextFile(
    new URL("manifest.json", dir),
    JSON.stringify(manifest, null, 2) + "\n",
  );
}

/** Builds one saved-case record from a live `ProviderCall`. */
export async function toSavedCase(opts: {
  caseId: string;
  stage: string;
  path: string;
  inputText: string;
  call: ProviderCall | null;
  provider: string;
  model: string;
  error: string | null;
}): Promise<SavedCase> {
  return {
    schema: CASE_SCHEMA,
    case_id: opts.caseId,
    provider: opts.call?.provider ?? opts.provider,
    model: opts.call?.model ?? opts.model,
    stage: opts.stage,
    path: opts.path,
    op: opts.call?.op ?? "sanitize",
    captured_at: new Date().toISOString(),
    latency_ms: opts.call?.latency_ms ?? 0,
    usage: opts.call?.usage ?? null,
    input: {
      text: opts.inputText,
      sha256: await sha256Hex(opts.inputText),
    },
    // A failed call may still have no response at all (network error); `null`
    // is then the honest raw, and `error` explains it.
    raw: opts.call?.raw ?? null,
    error: opts.error,
  };
}

export function buildManifest(opts: {
  label: string;
  gitRev: string;
  stage: string;
  path: string;
  providers: { provider: string; model: string }[];
  caseIds: string[];
}): RunManifest {
  return {
    schema: MANIFEST_SCHEMA,
    label: opts.label,
    created_at: new Date().toISOString(),
    git_rev: opts.gitRev,
    stage: opts.stage,
    path: opts.path,
    providers: opts.providers.map((p) => ({
      provider: p.provider,
      model: p.model,
      price: priceRow(p.model),
    })),
    case_ids: opts.caseIds,
    note:
      "Raw provider responses from a PAID run. Committed on purpose: rescore " +
      "with `deno run --allow-read runner/score_extraction.ts --rescore <dir>`.",
  };
}

// --- reading back ------------------------------------------------------------

export interface LoadedRun {
  dir: URL;
  manifest: RunManifest | null;
  /** provider name → the cases saved for it, in directory order. */
  byProvider: Map<string, SavedCase[]>;
}

/** Reads a run directory: the manifest (optional) and every `<provider>/*.json`. */
export async function loadRun(dir: URL): Promise<LoadedRun> {
  let manifest: RunManifest | null = null;
  try {
    manifest = JSON.parse(
      await Deno.readTextFile(new URL("manifest.json", dir)),
    ) as RunManifest;
  } catch {
    // A manifest-less directory is still rescoreable — each case file is
    // self-describing. Provenance is lost, not the responses.
    manifest = null;
  }
  const byProvider = new Map<string, SavedCase[]>();
  for await (const entry of Deno.readDir(dir)) {
    if (!entry.isDirectory) continue;
    const providerDir = new URL(`${entry.name}/`, dir);
    const cases: SavedCase[] = [];
    for await (const f of Deno.readDir(providerDir)) {
      if (!f.isFile || !f.name.endsWith(".json")) continue;
      cases.push(
        JSON.parse(
          await Deno.readTextFile(new URL(f.name, providerDir)),
        ) as SavedCase,
      );
    }
    cases.sort((a, b) => a.case_id.localeCompare(b.case_id));
    if (cases.length > 0) byProvider.set(entry.name, cases);
  }
  return { dir, manifest, byProvider };
}

/**
 * Replays one saved response through the SAME decoder the live call used.
 *
 * Dispatch is by PROVIDER name, not model id, because the wire shape belongs to
 * the vendor: a re-pinned model still parses with its provider's decoder, so an
 * old run stays readable after the pin moves. An unknown provider is a hard
 * error rather than a silent zero — quietly scoring an undecodable run as a
 * total miss would look exactly like a model that failed every case.
 */
export function decodeSaved(rec: SavedCase): ExtractionResult {
  if (rec.model === MOCK_MODEL || rec.provider.startsWith("mock")) {
    return decodeMockSanitize(rec.raw);
  }
  const decode = RESPONSE_DECODERS[rec.provider as ProviderName];
  if (!decode) {
    throw new Error(
      `no response decoder for provider "${rec.provider}" (case ${rec.case_id}) ` +
        `— add one to RESPONSE_DECODERS in _shared/adapters/mod.ts`,
    );
  }
  return decode(rec.raw);
}
