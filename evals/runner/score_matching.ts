// Scores the MATCHING dimension (§6 / evals/AGENTS.md): raw ingredient line →
// confidence band + candidates, run through the REAL server-side cascade.
//
// This used to print "engine not implemented yet (roadmap step 8) — not scored".
// The cascade shipped, so the calibration set is now actually scored:
//
//   supabase/functions/_shared/match.ts       the cascade (exact → trigram → none)
//   supabase/functions/_shared/match_trgm.ts  the offline pg_trgm-compatible matcher
//
// The matcher is built in-memory from `supabase/seed/vocab.jsonl` — the same
// curated household vocabulary that generated the expectations, so this measures
// the CASCADE, not vocab coverage. `match_trgm.ts` mirrors Postgres `similarity()`
// closely enough for band calibration (the production path uses `match_db.ts`).
//
// It is a CALIBRATION TOOL, not a merge gate (evals/AGENTS.md): it reports the
// bands' precision/recall against the current BAND_AUTO_MIN / BAND_SUGGEST_MIN
// thresholds and never fails the run. Read the numbers, then move the thresholds.
//
// Run: deno run --allow-read runner/score_matching.ts   (part of runner/run.sh)

import {
  BAND_AUTO_MIN,
  BAND_SUGGEST_MIN,
  matchOne,
  TOP_N,
} from "../../supabase/functions/_shared/match.ts";
import { inMemoryVocabMatcher } from "../../supabase/functions/_shared/match_trgm.ts";
import type { VocabEntry } from "../../supabase/functions/_shared/match_trgm.ts";
import { normalize } from "../../supabase/functions/_shared/normalize.ts";
import type { MatchBand } from "../../supabase/functions/_shared/types.ts";

const BANDS: MatchBand[] = ["auto", "suggest", "none"];

interface Case {
  raw: string;
  expect_normalized: string;
  expect_band: MatchBand;
  expect_match?: string;
  expect_candidates?: string[];
}

interface VocabRow {
  canonical_name: string;
  aliases?: string[];
}

function jsonl<T>(text: string): T[] {
  return text.split("\n").map((l) => l.trim()).filter(Boolean).map((l) =>
    JSON.parse(l) as T
  );
}

/**
 * Builds the offline matcher from the seed vocab. `ingredient_id` is the
 * canonical name — the eval has no database, and the name is unique in
 * `vocab.jsonl`, so it is a stable stand-in for the row's uuid.
 */
function buildMatcher(rows: VocabRow[]) {
  const entries: VocabEntry[] = rows.map((v) => ({
    ingredient_id: v.canonical_name,
    canonical_name: v.canonical_name,
    match_texts: [
      ...new Set(
        [v.canonical_name, ...(v.aliases ?? [])]
          .map(normalize)
          .filter(Boolean),
      ),
    ],
  }));
  return inMemoryVocabMatcher(entries);
}

function pct(x: number): string {
  return (x * 100).toFixed(1).padStart(5) + "%";
}

/**
 * The cascade's real input. `matchLines` takes ① sanitize's `ingredient_text`
 * (the cleaned identity), NOT the printed line — parentheticals, prep clauses
 * and pack sizes are ①'s to strip. `expect_normalized` is exactly that cleaned
 * identity (the miner's `normalize(ingredient_text)`), so it is the faithful
 * stand-in; a choice line's components (`"a | b"`) are re-joined, because ①
 * emits "dried currants or raisins" as ONE identity and it is the cascade's job
 * to fail it into `suggest`.
 */
function cascadeInput(c: Case): string {
  return normalize(c.expect_normalized.split(" | ").join(" "));
}

interface Lane {
  label: string;
  note: string;
  input: (c: Case) => string;
}

interface LaneResult {
  confusion: Map<string, number>;
  autoTop: number;
  autoTopOf: number;
  wrongAuto: number;
  suggestHit: number;
  suggestOf: number;
  examples: string[];
}

async function main(): Promise<void> {
  const root = new URL("../../", import.meta.url);
  const vocab = jsonl<VocabRow>(
    await Deno.readTextFile(new URL("supabase/seed/vocab.jsonl", root)),
  );
  const cases = jsonl<Case>(
    await Deno.readTextFile(
      new URL("../datasets/matching/cases.jsonl", import.meta.url),
    ),
  );
  const matcher = buildMatcher(vocab);

  const key = (e: MatchBand, g: MatchBand) => `${e}>${g}`;
  const ratio = (n: number, d: number) => (d === 0 ? 0 : n / d);

  async function runLane(lane: Lane): Promise<LaneResult> {
    const r: LaneResult = {
      confusion: new Map(),
      autoTop: 0,
      autoTopOf: 0,
      wrongAuto: 0,
      suggestHit: 0,
      suggestOf: 0,
      examples: [],
    };
    for (const c of cases) {
      const { band, candidates } = await matchOne(lane.input(c), matcher);
      const k = key(c.expect_band, band);
      r.confusion.set(k, (r.confusion.get(k) ?? 0) + 1);

      const names = candidates.map((x) => x.canonical_name);
      if (c.expect_band === "auto" && band === "auto") {
        r.autoTopOf++;
        if (names[0] === c.expect_match) r.autoTop++;
        else if (r.examples.length < 10) {
          r.examples.push(
            `    auto→wrong ingredient  ${JSON.stringify(c.raw)}\n` +
              `        want ${c.expect_match}  got ${names[0] ?? "—"}`,
          );
        }
      }
      // The dangerous cell: the cascade auto-accepts what the oracle does not.
      if (band === "auto" && c.expect_band !== "auto") {
        r.wrongAuto++;
        if (r.examples.length < 10) {
          r.examples.push(
            `    DANGEROUS auto  ${JSON.stringify(c.raw)}\n` +
              `        oracle band ${c.expect_band}  got auto → ${
                names[0] ?? "—"
              }`,
          );
        }
      }
      if (c.expect_band === "suggest") {
        r.suggestOf++;
        const want = c.expect_candidates ?? [];
        if (want.some((w) => names.includes(w))) r.suggestHit++;
      }
    }
    return r;
  }

  function report(lane: Lane, r: LaneResult): void {
    const gotCount = (g: MatchBand) =>
      BANDS.reduce((a, e) => a + (r.confusion.get(key(e, g)) ?? 0), 0);
    const expCount = (e: MatchBand) =>
      BANDS.reduce((a, g) => a + (r.confusion.get(key(e, g)) ?? 0), 0);
    const hit = (b: MatchBand) => r.confusion.get(key(b, b)) ?? 0;
    const exact = BANDS.reduce((a, b) => a + hit(b), 0);

    console.log(`\n  ── ${lane.label}`);
    console.log(`     ${lane.note}`);
    console.log(
      `     band agreement  ${pct(ratio(exact, cases.length))} ` +
        `(${exact}/${cases.length})`,
    );
    for (const b of BANDS) {
      console.log(
        `     ${b.padEnd(8)} P ${pct(ratio(hit(b), gotCount(b)))}  ` +
          `R ${pct(ratio(hit(b), expCount(b)))}  ` +
          `(oracle ${expCount(b)}, cascade ${gotCount(b)})`,
      );
    }
    console.log(
      `     auto top-1 ingredient  ${pct(ratio(r.autoTop, r.autoTopOf))} ` +
        `(${r.autoTop}/${r.autoTopOf} lines both sides call auto)`,
    );
    console.log(
      `     suggest top-${TOP_N} covers a wanted candidate  ` +
        `${
          pct(ratio(r.suggestHit, r.suggestOf))
        } (${r.suggestHit}/${r.suggestOf})`,
    );
    console.log(
      `     DANGEROUS auto-accepts (cascade auto, oracle not): ${r.wrongAuto}`,
    );
    console.log("     confusion (oracle → cascade):");
    for (const e of BANDS) {
      const row = BANDS
        .map((g) => `${g}=${r.confusion.get(key(e, g)) ?? 0}`)
        .join("  ");
      console.log(`       ${e.padEnd(8)} ${row}`);
    }
    if (r.examples.length > 0) {
      console.log("     samples:");
      console.log(r.examples.join("\n"));
    }
  }

  console.log(
    `matching/band: ${cases.length} cases · vocab ${vocab.length} rows · ` +
      `cascade = exact → trigram(top-${TOP_N}) → none`,
  );
  console.log(
    `  thresholds: auto ≥ ${BAND_AUTO_MIN} · suggest ≥ ${BAND_SUGGEST_MIN} ` +
      `(these are what the numbers below calibrate)`,
  );

  const lanes: Lane[] = [
    {
      label: "identity lane (PRIMARY — the cascade's real contract)",
      note:
        "input = the sanitized identity, i.e. what ① hands matchLines. Isolates " +
        "the cascade from ①'s line-cleaning.",
      input: cascadeInput,
    },
    {
      label: "raw-line lane (FLOOR — diagnostic only)",
      note:
        "input = normalize(printed line). Conflates ① sanitize's job (stripping " +
        "parentheticals/prep/pack sizes) with the cascade's; expect it to be worse.",
      input: (c) => normalize(c.raw),
    },
  ];
  for (const lane of lanes) report(lane, await runLane(lane));

  console.log(
    "\n  (calibration, not a gate — evals/AGENTS.md: this reports drift, it never fails the run)",
  );
}

if (import.meta.main) {
  await main();
}
