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
//   deno run --allow-read --allow-env --allow-net runner/run_extraction_live.ts
//   # optional: --providers=claude-haiku,gpt-5-mini  --stage=D2

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
import {
  type GoldCase,
  type GoldRecipe,
  goldToBlob,
  loadGold,
} from "./fixtures.ts";
import {
  type BenchmarkReport,
  runBenchmark,
  type Stage,
  summarize,
} from "./score_extraction.ts";

const IMAGES_DIR = new URL("../datasets/extraction/images/", import.meta.url);

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
 * SEAM: the jsonld / page_text web path needs lane A's `_shared/jsonld.ts` to
 * turn a URL into a RawBlob. Until it lands, this throws — the web corpus rows
 * are wired but gated. (Lane A owns jsonld; lane D must not implement it.)
 */
export function blobFromUrl(_url: string): Promise<RawBlob> {
  throw new Error(
    "web path needs lane A's _shared/jsonld.ts (not yet available); " +
      "wire blobFromUrl to it at integration.",
  );
}

interface Args {
  providers: ProviderName[];
  stages: Stage[];
}

function parseArgs(): Args {
  let providers = [...PROVIDER_NAMES];
  let stages: Stage[] = ["D2", "D1", "D3"];
  for (const arg of Deno.args) {
    if (arg.startsWith("--providers=")) {
      providers = arg.slice("--providers=".length).split(",") as ProviderName[];
    } else if (arg.startsWith("--stage=")) {
      stages = arg.slice("--stage=".length).split(",") as Stage[];
    }
  }
  return { providers, stages };
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
  const { providers, stages } = parseArgs();
  const cases = await loadGold();
  console.log(
    `live extraction compare · ${cases.length} gold recipes · ` +
      `providers=${providers.join(",")} · stages=${stages.join(",")}`,
  );

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
    if (stages.includes("D2")) {
      printReport(await runD2PageText(name, adapter, cases));
    }
    for (const stage of stages) {
      if (stage === "D2") continue;
      const report = await runPhotoStage(name, adapter, cases, stage);
      if (report) printReport(report);
      else {console.log(
          `\n## ${name} · ${stage} · photo — SKIPPED (no local images or no vision).`,
        );}
    }
  }
  console.log(
    "\nWeb corpus (jsonld / 36 recipe_urls.txt) is wired but gated on lane A's " +
      "jsonld.ts — see blobFromUrl().",
  );
}

if (import.meta.main) {
  await main();
}
