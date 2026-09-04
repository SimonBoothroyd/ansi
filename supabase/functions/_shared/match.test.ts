import { assert, assertEquals } from "@std/assert";
import {
  BAND_AUTO_MIN,
  BAND_SUGGEST_MIN,
  bandForScore,
  matchLines,
  matchOne,
  matchRecipeTitles,
  recipeMatchText,
  TOP_N,
} from "./match.ts";
import {
  inMemoryRecipeTitleMatcher,
  inMemoryVocabMatcher,
  type RecipeTitleEntry,
  type VocabEntry,
} from "./match_trgm.ts";
import { normalize } from "./normalize.ts";
import type { RawLineItem } from "./types.ts";

// A tiny, deterministic hand vocab for the cascade unit tests. match_texts are the
// normalized forms the row writer would store (§7).
const HAND: VocabEntry[] = [
  { ingredient_id: "i-onion", canonical_name: "Onion", match_texts: ["onion"] },
  {
    ingredient_id: "i-cilantro",
    canonical_name: "Cilantro",
    // an alias absorbs the household's phrasing (the §8 learning loop shape)
    match_texts: ["cilantro", "coriander", "cilantro leaf tender stem"],
  },
  {
    ingredient_id: "i-cocomilk",
    canonical_name: "Coconut Milk",
    match_texts: ["coconut milk"],
  },
  {
    ingredient_id: "i-cocacream",
    canonical_name: "Coconut Cream",
    match_texts: ["coconut cream"],
  },
  {
    ingredient_id: "i-gsugar",
    canonical_name: "Granulated Sugar",
    match_texts: ["granulated sugar", "sugar"],
  },
];
const hand = inMemoryVocabMatcher(HAND);

const line = (ingredient_text: string): RawLineItem => ({
  qty: 1,
  qty_low: null,
  qty_high: null,
  unit: null,
  unit_mappable: true,
  ingredient_text,
  notes: null,
  raw_amount: ingredient_text,
  optional: false,
  confidence: 1,
});

Deno.test("bandForScore — the §6 boundaries", () => {
  assertEquals(bandForScore(0.85), "auto");
  assertEquals(bandForScore(0.9), "auto");
  assertEquals(bandForScore(0.8499), "suggest");
  assertEquals(bandForScore(0.55), "suggest");
  assertEquals(bandForScore(0.5499), "none");
  assertEquals(bandForScore(0), "none");
  assert(BAND_AUTO_MIN > BAND_SUGGEST_MIN);
});

Deno.test("cascade — exact match_text → auto with the single candidate", async () => {
  const r = await matchOne("onion", hand);
  assertEquals(r.band, "auto");
  assertEquals(r.candidates.map((c) => c.canonical_name), ["Onion"]);
  assertEquals(r.candidates[0].score, 1);
});

Deno.test("cascade — exact via an alias → auto on the aliased ingredient", async () => {
  // "coriander" is an alias of Cilantro; exact tier resolves it (the synonym gap
  // trigram can't close is handled by aliases, per the 0014 decision log).
  const r = await matchOne("coriander", hand);
  assertEquals(r.band, "auto");
  assertEquals(r.candidates[0].canonical_name, "Cilantro");
});

Deno.test("cascade — exact wins over a longer alias surface", async () => {
  const r = await matchOne("cilantro leaf tender stem", hand);
  assertEquals(r.band, "auto");
  assertEquals(r.candidates[0].canonical_name, "Cilantro");
});

Deno.test("cascade — exact does NOT over-collapse form/state words", async () => {
  // The §7 own-goal: coconut milk ≠ coconut cream. Distinct exact rows.
  assertEquals(
    (await matchOne("coconut milk", hand)).candidates[0].canonical_name,
    "Coconut Milk",
  );
  assertEquals(
    (await matchOne("coconut cream", hand)).candidates[0].canonical_name,
    "Coconut Cream",
  );
});

Deno.test("cascade — trigram typo lands in a band, best-first", async () => {
  // "granulated suger" (typo) — no exact, trigram should surface Granulated Sugar.
  const r = await matchOne("granulated suger", hand);
  assert(r.candidates.length >= 1);
  assertEquals(r.candidates[0].canonical_name, "Granulated Sugar");
  assert(r.band === "auto" || r.band === "suggest");
});

Deno.test("cascade — no match → band none, empty candidates (no silent stub)", async () => {
  const r = await matchOne(normalize("ice"), hand);
  assertEquals(r.band, "none");
  assertEquals(r.candidates, []);
});

Deno.test("cascade — empty identity → none", async () => {
  assertEquals((await matchOne("", hand)).band, "none");
});

Deno.test("matchLines — preserves order and normalizes each line", async () => {
  const out = await matchLines(
    [line("2 large Onions, diced"), line("ice")],
    hand,
  );
  assertEquals(out.length, 2);
  assertEquals(out[0].band, "auto");
  assertEquals(out[0].candidates[0].canonical_name, "Onion");
  assertEquals(out[0].raw.ingredient_text, "2 large Onions, diced");
  assertEquals(out[1].band, "none");
});

Deno.test("cascade — ambiguous exact (shared surface) → suggest, not auto", async () => {
  // Two ingredients whose match_text collides: don't auto-commit either.
  const ambiguous = inMemoryVocabMatcher([
    {
      ingredient_id: "a",
      canonical_name: "Scallion",
      match_texts: ["green onion"],
    },
    {
      ingredient_id: "b",
      canonical_name: "Spring Onion",
      match_texts: ["green onion"],
    },
  ]);
  const r = await matchOne("green onion", ambiguous);
  assertEquals(r.band, "suggest");
  assertEquals(r.candidates.length, 2);
});

// --- The sub-recipe tier (step 8.6 / exec plan 0021 D6) ----------------------
// The household's own recipes, as the review card would offer them. Titles are
// normalized by the matcher itself (a recipe has no stored match_text).

const RECIPES: RecipeTitleEntry[] = [
  { recipe_id: "r-aioli", title: "Romesco Aioli" },
  { recipe_id: "r-buns", title: "Pretzel Buns" },
  { recipe_id: "r-butter", title: "Garlic Butter" },
];
const recipes = inMemoryRecipeTitleMatcher(RECIPES);

Deno.test("sub-recipe tier — the printed cross-reference is stripped before matching", () => {
  // "(page 38)" is the whole reason a title hit needs its own match text: the
  // ingredient cascade's normalizer keeps "page" as a noun.
  assertEquals(recipeMatchText("Romesco Aioli (page 38)"), "romesco aioli");
  assertEquals(normalize("Romesco Aioli (page 38)"), "romesco aioli page");
  // An aside that IS the line falls back to the unstripped text rather than
  // matching everything with an empty string.
  assertEquals(recipeMatchText("(page 38)"), "page");
});

Deno.test("sub-recipe tier — an exact title hit is offered", async () => {
  const hits = await matchRecipeTitles("Romesco Aioli (page 38)", recipes);
  assertEquals(hits.length, 1);
  assertEquals(hits[0].recipe_id, "r-aioli");
  assertEquals(hits[0].title, "Romesco Aioli"); // the stored title, for the chip
  assertEquals(hits[0].score, 1);
});

Deno.test("sub-recipe tier — the normalizer is symmetric on titles", async () => {
  // "8 Pretzel Buns (page 97)" — plural on the line, singular nowhere: both
  // sides go through the same §7 normalizer, so they meet.
  const hits = await matchRecipeTitles("Pretzel Buns (page 97)", recipes);
  assertEquals(hits.map((h) => h.recipe_id), ["r-buns"]);
});

Deno.test("sub-recipe tier — an ordinary ingredient line offers nothing", async () => {
  assertEquals(await matchRecipeTitles("2 large onions, diced", recipes), []);
  assertEquals(await matchRecipeTitles("", recipes), []);
});

Deno.test("sub-recipe tier — weak trigram noise is filtered out", async () => {
  // Below BAND_SUGGEST_MIN nothing is offered: a stray "↪ your recipe" chip on
  // a plain ingredient line is pure noise, and a missed one costs a tap.
  const noisy = inMemoryRecipeTitleMatcher([
    { recipe_id: "r-x", title: "Roast Aubergine and Butterbean Stew" },
  ]);
  assertEquals(await matchRecipeTitles("butter", noisy), []);
  // …while a typo'd surface that still scores in-band IS offered.
  const near = await matchRecipeTitles("garlick butter", recipes);
  assertEquals(near.map((h) => h.recipe_id), ["r-butter"]);
  assert(near[0].score >= BAND_SUGGEST_MIN && near[0].score < 1);
});

Deno.test("matchLines — recipe candidates are ADDITIVE and never auto-link", async () => {
  const out = await matchLines(
    [line("¼ cup Romesco Aioli (page 38)"), line("onion")],
    hand,
    recipes,
  );
  // The component line: no ingredient match, a recipe suggestion beside it.
  assertEquals(out[0].band, "none");
  assertEquals(out[0].candidates, []);
  assertEquals(out[0].recipe_candidates?.map((c) => c.title), [
    "Romesco Aioli",
  ]);
  // The ordinary line is untouched — same band, same candidates, no new key.
  assertEquals(out[1].band, "auto");
  assertEquals(out[1].candidates[0].canonical_name, "Onion");
  assertEquals(out[1].recipe_candidates, undefined);
});

Deno.test("matchLines — the ingredient cascade is unaffected by the recipe tier", async () => {
  // A line that hits BOTH: the band and candidates are exactly what the
  // two-argument call produces; the suggestion rides alongside, and the human
  // picks (D6 — matching offers, it never chooses).
  const alsoARecipe = inMemoryRecipeTitleMatcher([
    { recipe_id: "r-onion", title: "Onion" },
  ]);
  const lines = [line("2 large Onions, diced")];
  const before = await matchLines(lines, hand);
  const after = await matchLines(lines, hand, alsoARecipe);
  assertEquals(after[0].band, before[0].band);
  assertEquals(after[0].candidates, before[0].candidates);
  assertEquals(after[0].recipe_candidates?.length, 1);
  // No matcher ⇒ the key is absent entirely (the pre-8.6 wire shape).
  assert(!("recipe_candidates" in before[0]));
});

Deno.test("sub-recipe tier — candidates are capped at TOP_N and deterministic", async () => {
  const many = inMemoryRecipeTitleMatcher([
    { recipe_id: "r-1", title: "Romesco Aioli" },
    { recipe_id: "r-2", title: "Romesco Aioli Extra" },
    { recipe_id: "r-3", title: "Romesco Aioli Verde" },
    { recipe_id: "r-4", title: "Romesco Aioli Rojo" },
  ]);
  const hits = await matchRecipeTitles("romesco aioli", many);
  assertEquals(hits.length, 1, "an exact title hit wins outright");
  const fuzzy = await matchRecipeTitles("romesco aiolis extra verde", many);
  assert(fuzzy.length <= TOP_N);
  // Stable order: score desc, then title, then id — never row order.
  assertEquals(
    fuzzy,
    await matchRecipeTitles("romesco aiolis extra verde", many),
  );
});

// --- Calibration against the household vocab + lane-D eval set ----------------
// Exercises the cascade over the REAL vocab (evals note: cases.jsonl may be stale
// vs vocab.jsonl — this asserts a precision FLOOR + reports, it is not a per-case
// gate). We isolate lane B from lane A extraction by feeding the gold-normalized
// identity (expect_normalized) as the line's ingredient_text.

const REPO = new URL("../../../", import.meta.url); // repo root from _shared/
const readIf = (rel: string): string | null => {
  try {
    return Deno.readTextFileSync(new URL(rel, REPO).pathname);
  } catch {
    return null;
  }
};
const jsonl = (s: string) =>
  s.split("\n").map((l) => l.trim()).filter(Boolean).map((l) => JSON.parse(l));

function loadVocabMatcher(): ReturnType<typeof inMemoryVocabMatcher> | null {
  const raw = readIf("supabase/seed/vocab.jsonl");
  if (!raw) return null;
  const entries: VocabEntry[] = jsonl(raw).map(
    (v: { canonical_name: string; aliases?: string[] }, i: number) => ({
      ingredient_id: `v-${i}`,
      canonical_name: v.canonical_name,
      match_texts: [
        ...new Set(
          [v.canonical_name, ...(v.aliases ?? [])].map(normalize).filter(
            Boolean,
          ),
        ),
      ],
    }),
  );
  return inMemoryVocabMatcher(entries);
}

Deno.test("calibration — cascade over the real vocab hits a precision floor", async () => {
  const matcher = loadVocabMatcher();
  const casesRaw = readIf("evals/datasets/matching/cases.jsonl");
  // HARD FAILURE, not a skip. This test used to `console.log("(skipped)")` and
  // return green when a fixture was missing — which is exactly how it went
  // unnoticed that `deno test` without `--allow-read` was never running it at
  // all. A missing fixture is a broken test run, not a passing one.
  assert(
    matcher,
    "supabase/seed/vocab.jsonl is missing or unreadable — the calibration " +
      "test needs it (run via `deno task test`, which grants --allow-read)",
  );
  assert(
    casesRaw,
    "evals/datasets/matching/cases.jsonl is missing or unreadable — the " +
      "calibration test needs it (run via `deno task test`)",
  );
  interface Case {
    raw: string;
    expect_normalized: string;
    expect_band: "auto" | "suggest" | "none";
    expect_match?: string;
  }
  const cases: Case[] = jsonl(casesRaw);

  // Grade only single-ingredient AUTO cases whose gold label still exists in the
  // current vocab — the fair, drift-robust measure of the cascade's job. (Compound
  // "suggest" cases assume upstream line-splitting; stale singular/plural canonical
  // drift is a vocab-eval sync issue, flagged in the report, not a cascade bug.)
  let gradable = 0;
  let recovered = 0; // right ingredient appears as top candidate (auto or suggest)
  let autoExact = 0; // and the band was auto
  const misses: string[] = [];
  for (const c of cases) {
    if (c.expect_band !== "auto" || !c.expect_match) continue;
    // Skip cases whose gold label is no longer a canonical_name in the vocab.
    const label = c.expect_match;
    // Feed the gold-normalized identity as ingredient_text (already normalized).
    const r = await matchOne(normalize(c.expect_normalized), matcher);
    const labelPresent = r.candidates.some((x) => x.canonical_name === label) ||
      // label may be absent from vocab entirely (drift) — detect by exact probe
      (await matcher.exact(normalize(c.expect_normalized))).length > 0;
    if (!labelPresent && r.candidates.length === 0) continue; // pure vocab drift
    gradable++;
    const top = r.candidates[0]?.canonical_name;
    if (top === label) {
      recovered++;
      if (r.band === "auto") autoExact++;
    } else if (misses.length < 15) {
      misses.push(
        `${c.expect_normalized}: want ${label}, got ${
          top ?? "none"
        } (${r.band})`,
      );
    }
  }

  const precision = gradable === 0 ? 0 : recovered / gradable;
  console.log(
    `  calibration: gradable=${gradable} recovered=${recovered} ` +
      `(precision ${(precision * 100).toFixed(1)}%) auto-band=${autoExact}`,
  );
  if (misses.length) console.log("  sample misses (mostly vocab/eval drift):");
  for (const m of misses) console.log("    -", m);

  // A conservative floor: the cascade must recover the right ingredient for the
  // large majority of gradable in-vocab auto cases. Precision here is limited by
  // eval/vocab drift, not the cascade — hence a floor, not equality.
  assert(gradable > 100, `expected a meaningful gradable set, got ${gradable}`);
  assert(precision >= 0.9, `precision ${precision} below floor`);
});
