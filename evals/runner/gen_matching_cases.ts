// Builds the matching calibration set (datasets/matching/cases.jsonl) from the
// mined gold lines + the curated household vocabulary. The label for each raw
// line is the ingredient(s) the ARBITER assigned it — the oracle — recovered by
// resolving the line's match_text against the vocab's ingredient + alias keys.
// The future server-side cascade (step 8) is graded against these labels.
//
// Bands (§6):
//   auto    — the line resolves to exactly one ingredient (exact match_text).
//   suggest — a choice ("A or B") or a compound ("sea salt and black pepper")
//             that covers several ingredients; the human picks at reconciliation.
//   none    — nothing in the vocab covers it (a genuine stub/skip, e.g. "ice").
//
// Regenerate after re-mining or editing the vocab:
//   deno run --allow-read --allow-write evals/runner/gen_matching_cases.ts

import { normalize } from "../../supabase/functions/_shared/normalize.ts";

const root = new URL("../../", import.meta.url); // repo root
const read = (p: string) => Deno.readTextFileSync(new URL(p, root).pathname);
const jsonl = (s: string) =>
  s.split("\n").map((l) => l.trim()).filter(Boolean).map((l) => JSON.parse(l));

// --- vocabulary index: match_text -> canonical_name -------------------------
interface Vocab {
  canonical_name: string;
  aliases?: string[];
}
const byMatch = new Map<string, string>();
const vocab: Vocab[] = jsonl(read("supabase/seed/vocab.jsonl"));
for (const v of vocab) {
  for (const s of [v.canonical_name, ...(v.aliases ?? [])]) {
    const m = normalize(s);
    if (m && !byMatch.has(m)) byMatch.set(m, v.canonical_name);
  }
}
const vocabTokens = vocab.map((v) => ({
  name: v.canonical_name,
  tokens: new Set(normalize(v.canonical_name).split(" ").filter(Boolean)),
}));

/** Ingredients whose whole name is contained in these tokens (compound cover). */
function subsetCandidates(mt: string): string[] {
  const toks = new Set(mt.split(" ").filter(Boolean));
  const hits = vocabTokens
    .filter((v) =>
      v.tokens.size >= 1 && [...v.tokens].every((t) => toks.has(t))
    )
    .filter((v) => v.tokens.size < toks.size) // proper subset — a partial cover
    .map((v) => v.name);
  return [...new Set(hits)];
}

// --- group gold lines by raw, then label ------------------------------------
interface Gold {
  raw: string;
  match_text: string;
}

/**
 * The raw → match_text ground truth.
 *
 * Preferred source is the miner's `out/gold_labels.jsonl`. That file is
 * GITIGNORED (regenerable, and producing it re-fetches 36 live recipe pages),
 * so when it is absent we recover the very same pairs from the committed
 * `cases.jsonl` — `expect_normalized` is exactly `match_texts.join(" | ")`, so
 * the round-trip is lossless. Either way the LABELS (which vocab entry each
 * match_text resolves to) are recomputed from the CURRENT `vocab.jsonl`, which
 * is the whole point of regenerating: the committed set drifted when the vocab
 * was re-curated (`Cashew` → `Cashews`, the new `Canned X` rows) and ~9% of the
 * cascade's apparent misses were stale labels, not defects (ledger 0019).
 */
function loadGoldPairs(): Gold[] {
  try {
    return (jsonl(
      read("supabase/seed/scripts/out/gold_labels.jsonl"),
    ) as Gold[])
      .map((g) => ({ raw: g.raw, match_text: g.match_text }));
  } catch {
    // Fall back to the previous generation's own raw → normalized pairs.
    const prev = jsonl(read("evals/datasets/matching/cases.jsonl")) as {
      raw: string;
      expect_normalized: string;
    }[];
    console.log(
      "  note: supabase/seed/scripts/out/gold_labels.jsonl is absent " +
        "(gitignored miner output) — recovering raw → match_text from the " +
        "committed cases.jsonl and re-labelling against the current vocab.",
    );
    return prev.flatMap((c) =>
      c.expect_normalized.split(" | ").filter(Boolean).map((match_text) => ({
        raw: c.raw,
        match_text,
      }))
    );
  }
}

const groups = new Map<string, Set<string>>();
for (const g of loadGoldPairs()) {
  if (!g.match_text) continue;
  (groups.get(g.raw) ?? groups.set(g.raw, new Set()).get(g.raw)!).add(
    g.match_text,
  );
}

interface Case {
  raw: string;
  expect_normalized: string;
  expect_band: "auto" | "suggest" | "none";
  expect_match?: string;
  expect_candidates?: string[];
}
const cases: Case[] = [];
for (const [raw, mtSet] of groups) {
  const mts = [...mtSet];
  const resolved = [
    ...new Set(mts.map((m) => byMatch.get(m)).filter(Boolean)),
  ] as string[];
  const norm = mts.join(" | ");

  if (mts.length > 1) {
    // A choice line ("A or B") split into components.
    if (resolved.length >= 2) {
      cases.push({
        raw,
        expect_normalized: norm,
        expect_band: "suggest",
        expect_candidates: resolved,
      });
    } else if (resolved.length === 1) {
      cases.push({
        raw,
        expect_normalized: norm,
        expect_band: "auto",
        expect_match: resolved[0],
      });
    } else {
      cases.push({ raw, expect_normalized: norm, expect_band: "none" });
    }
    continue;
  }

  const mt = mts[0];
  const one = byMatch.get(mt);
  if (one) {
    cases.push({
      raw,
      expect_normalized: mt,
      expect_band: "auto",
      expect_match: one,
    });
  } else {
    const cover = subsetCandidates(mt); // compound / partial
    if (cover.length >= 1) {
      cases.push({
        raw,
        expect_normalized: mt,
        expect_band: "suggest",
        expect_candidates: cover,
      });
    } else {
      cases.push({ raw, expect_normalized: mt, expect_band: "none" });
    }
  }
}

cases.sort((a, b) => a.raw.localeCompare(b.raw));
const outPath =
  new URL("../datasets/matching/cases.jsonl", import.meta.url).pathname;
Deno.writeTextFileSync(
  outPath,
  cases.map((c) => JSON.stringify(c)).join("\n") + "\n",
);

const byBand = (b: string) => cases.filter((c) => c.expect_band === b).length;
console.log(
  `wrote ${cases.length} matching cases → ${outPath}\n` +
    `  auto ${byBand("auto")} · suggest ${byBand("suggest")} · none ${
      byBand("none")
    }`,
);
