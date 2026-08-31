// Live provider comparison for the extraction benchmark (charter 0018 "compare
// step"). Runs the real Gemini-Flash / GPT-5-Mini / Claude-Haiku adapters across
// the stages and paths a key + inputs allow, and prints a scorecard per
// (provider × stage × path). This is the driver Simon runs once keys land; it is
// deliberately SEPARATE from score_extraction.ts's keyless mock self-test.
//
//   Stages   D1 transcribe (photo → text)   [needs vision key + local images]
//            D2 sanitize on gold text        [needs a sanitize key; runs keyless-
//                                             adjacent on the reconstructed gold]
//            D3 e2e (photo → transcribe → sanitize) [needs vision + local images]
//   Paths    photo      — the 12 gitignored images (datasets/extraction/images)
//            page_text  — reconstructed gold text (always available)
//            jsonld     — the 36 recipe_urls.txt pages via lane A's jsonld
//                         (SEAM: wire `blobFromUrl` to lane A when it lands)
//
// Each provider whose key is unset is skipped with a note — never a crash. Run:
//   deno run --allow-read --allow-write --allow-env --allow-net --allow-run=git \
//     runner/run_extraction_live.ts --label=my-run
//   # optional: --providers=claude-haiku,gpt-5-mini  --stage=D2  --no-persist
//
// PERSISTENCE: unless `--no-persist` is passed, every provider's VERBATIM
// response is written to `evals/runs/<yyyy-mm-dd>-<label>/<provider>/<case>.json`
// along with usage, latency and the exact input. Those files are COMMITTED —
// they are what the run cost — and `score_extraction.ts --rescore <dir>` scores
// them again for free, so a scorer or gold fix never buys a second run.

import type {
  ExtractAdapter,
  RawBlob,
} from "../../supabase/functions/_shared/types.ts";
import {
  buildProvider,
  MissingKeyError,
  PROVIDER_NAMES,
  type ProviderName,
} from "../../supabase/functions/_shared/adapters/mod.ts";
import { fetchRawBlob } from "../../supabase/functions/_shared/jsonld.ts";
import {
  type GoldCase,
  type GoldRecipe,
  goldToBlob,
  loadGold,
} from "./fixtures.ts";
import {
  type BenchmarkReport,
  printCost,
  runBenchmark,
  type Stage,
  summarize,
} from "./score_extraction.ts";
import {
  buildManifest,
  gitRev,
  runDir,
  toSavedCase,
  writeCase,
  writeManifest,
} from "./run_store.ts";

const IMAGES_DIR = new URL("../datasets/extraction/images/", import.meta.url);
const RECIPE_URLS = new URL(
  "../../supabase/seed/scripts/recipe_urls.txt",
  import.meta.url,
);

/** Reads the local (gitignored) photos for a gold case, or null when absent. */
async function loadImages(gold: GoldRecipe): Promise<Uint8Array[] | null> {
  const imgs: Uint8Array[] = [];
  for (const name of gold.source_images) {
    try {
      imgs.push(
        await Deno.readFile(new URL(encodeURIComponent(name), IMAGES_DIR)),
      );
    } catch {
      return null; // any missing page → skip this case for photo stages
    }
  }
  return imgs.length > 0 ? imgs : null;
}

/**
 * The jsonld / page_text web path: URL → `RawBlob`, straight through lane A's
 * `_shared/jsonld.ts` (`fetchRawBlob` = `fetch` + `buildRawBlob`). Lane A owns
 * the implementation; the eval only calls it, so the harness and production
 * intake read a page the same way.
 *
 * `fetchRawBlob` is total: a non-OK response or a network error yields a text
 * blob rather than throwing, and `buildRawBlob` picks `source: "jsonld"` when
 * the page publishes a schema.org/Recipe block and `"page_text"` otherwise —
 * which is exactly the `jsonld` vs `page_text` path split this runner reports.
 */
export function blobFromUrl(url: string): Promise<RawBlob> {
  return fetchRawBlob(url);
}

/** Reads the 36-URL web corpus (`#` comments and blanks ignored). */
export async function loadRecipeUrls(): Promise<string[]> {
  const text = await Deno.readTextFile(RECIPE_URLS);
  return text
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l !== "" && !l.startsWith("#"));
}

interface Args {
  providers: ProviderName[];
  stages: Stage[];
  label: string;
  persist: boolean;
}

function parseArgs(): Args {
  let providers = [...PROVIDER_NAMES];
  let stages: Stage[] = ["D2", "D1", "D3"];
  let label = "compare";
  let persist = true;
  for (const arg of Deno.args) {
    if (arg.startsWith("--providers=")) {
      providers = arg.slice("--providers=".length).split(",") as ProviderName[];
    } else if (arg.startsWith("--stage=")) {
      stages = arg.slice("--stage=".length).split(",") as Stage[];
    } else if (arg.startsWith("--label=")) {
      label = arg.slice("--label=".length);
    } else if (arg === "--no-persist") {
      persist = false;
    }
  }
  return { providers, stages, label, persist };
}

function printReport(r: BenchmarkReport): void {
  const s = summarize(r.provider, r.scores);
  console.log(
    `\n## ${r.provider} · ${r.stage} · ${r.path}  (n=${s.n})  ` +
      `line-F1=${(s.line_f1 * 100).toFixed(1)}% qty=${
        (s.qty_acc * 100).toFixed(1)
      }% ` +
      `unit=${(s.unit_acc * 100).toFixed(1)}% dangerous=${s.ledger_total} ` +
      `ECE=${s.calibration.ece.toFixed(3)}`,
  );
  printCost(r.cost);
}

/**
 * Writes one report's captured calls into the run directory. Called per report
 * rather than at the end so a run that dies halfway still leaves the responses
 * it already paid for on disk.
 */
async function persistReport(dir: URL, r: BenchmarkReport): Promise<void> {
  for (const c of r.calls) {
    await writeCase(
      dir,
      await toSavedCase({
        caseId: c.id,
        stage: r.stage,
        path: r.path,
        inputText: c.input_text,
        call: c.call,
        provider: r.provider,
        model: r.cost?.model ?? "unknown",
        error: c.error,
      }),
    );
  }
}

async function runD2PageText(
  provider: string,
  adapter: ExtractAdapter,
  cases: GoldCase[],
): Promise<BenchmarkReport> {
  return await runBenchmark({
    provider,
    adapter,
    cases,
    stage: "D2",
    path: "page_text",
    blobFor: goldToBlob,
  });
}

// D1/D3 (photo path) need a per-case transcription; we build the sanitize blob
// from the adapter's own transcribe output for D3, and score D1 indirectly via
// the never-invent ledger on the D3 result (there is no committed gold text to
// score a transcription against — see EXTRACTION.md).
async function runPhotoStage(
  provider: string,
  adapter: ExtractAdapter,
  cases: GoldCase[],
  stage: Stage,
): Promise<BenchmarkReport | null> {
  if (!adapter.transcribe) return null;
  const withImages: { case: GoldCase; blob: RawBlob }[] = [];
  for (const c of cases) {
    const imgs = await loadImages(c.gold);
    if (!imgs) continue;
    try {
      const blob = await adapter.transcribe(imgs);
      withImages.push({ case: c, blob });
    } catch (e) {
      // One provider's transient failure must not crash the whole run.
      console.error(
        `  ! ${provider}/${c.id}: ${e instanceof Error ? e.message : e}`,
      );
    }
  }
  if (withImages.length === 0) return null;
  const byId = new Map(withImages.map((w) => [w.case.id, w.blob]));
  return await runBenchmark({
    provider,
    adapter,
    cases: withImages.map((w) => w.case),
    stage,
    path: "photo",
    blobFor: (gold) => {
      const found = byId.get(
        cases.find((c) => c.gold === gold)?.id ?? "",
      );
      if (!found) throw new Error("missing transcription blob");
      return found;
    },
  });
}

async function main(): Promise<void> {
  const { providers, stages, label, persist } = parseArgs();
  const cases = await loadGold();
  const dir = runDir(label);
  console.log(
    `live extraction compare · ${cases.length} gold recipes · ` +
      `providers=${providers.join(",")} · stages=${stages.join(",")}`,
  );
  if (persist) console.log(`persisting raw responses → ${dir.pathname}`);
  else console.log(`--no-persist: raw responses will NOT be saved`);

  const ran: { provider: string; model: string }[] = [];
  for (const name of providers) {
    let adapter: ExtractAdapter;
    try {
      adapter = buildProvider(name);
    } catch (e) {
      if (e instanceof MissingKeyError) {
        console.log(`\n## ${name} — SKIPPED: ${e.message}`);
        continue;
      }
      throw e;
    }
    ran.push({ provider: name, model: adapter.model ?? "unknown" });
    if (stages.includes("D2")) {
      const report = await runD2PageText(name, adapter, cases);
      printReport(report);
      if (persist) await persistReport(dir, report);
    }
    for (const stage of stages) {
      if (stage === "D2") continue;
      const report = await runPhotoStage(name, adapter, cases, stage);
      if (report) {
        printReport(report);
        if (persist) await persistReport(dir, report);
      } else {console.log(
          `\n## ${name} · ${stage} · photo — SKIPPED (no local images or no vision).`,
        );}
    }
  }
  if (persist && ran.length > 0) {
    await writeManifest(
      dir,
      buildManifest({
        label,
        gitRev: await gitRev(),
        stage: stages.join(","),
        path: "page_text,photo",
        providers: ran,
        caseIds: cases.map((c) => c.id),
      }),
    );
    console.log(
      `\nwrote ${dir.pathname} — COMMIT it (it is the paid artifact), then ` +
        `rescore for free with:\n  deno run --allow-read ` +
        `runner/score_extraction.ts --rescore ${dir.pathname}`,
    );
  }
  const urls = await loadRecipeUrls();
  console.log(
    `\nWeb corpus: ${urls.length} recipe_urls.txt pages reachable through ` +
      `blobFromUrl() → _shared/jsonld.ts (fetchRawBlob). There is no structured ` +
      `gold for those pages, so they are an INPUT corpus for the ledger and the ` +
      `prose judge, not a scored oracle — the scored rows are the ${cases.length} gold recipes.`,
  );
}

if (import.meta.main) {
  await main();
}
