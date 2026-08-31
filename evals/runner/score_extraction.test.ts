// Keyless self-test for the extraction scorer (charter 0018: "the runner scores
// at least D2 on the gold with the mock adapter (keyless)"). Proves two things
// with no provider key: the scorer's PERFECT path (oracle → 100%, empty ledger),
// and that it DISCRIMINATES (a degraded output loses points and lights the
// never-invent ledger). If either drifts, the scorer is miscalibrated.

import { assert, assertAlmostEquals, assertEquals } from "@std/assert";
import {
  fixedMock,
  MockAdapter,
} from "../../supabase/functions/_shared/adapters/mock.ts";
import { goldLineToText, loadGold, printedAmount } from "./fixtures.ts";
import {
  alignLines,
  calibrate,
  degrade,
  ledgerTotal,
  notesAgree,
  numEq,
  runBenchmark,
  scoreExtraction,
  summarize,
  unitMatch,
  unitVerdict,
} from "./score_extraction.ts";
import { flattenLines } from "../../supabase/functions/_shared/adapters/schema.ts";
import type {
  ExtractionResult,
  RawLineItem,
} from "../../supabase/functions/_shared/types.ts";

/** A line item with every field defaulted — tests override only what they mean. */
function line(over: Partial<RawLineItem> = {}): RawLineItem {
  return {
    qty: null,
    qty_low: null,
    qty_high: null,
    unit: null,
    unit_mappable: false,
    ingredient_text: "thing",
    notes: null,
    raw_amount: "",
    optional: false,
    confidence: 0.9,
    ...over,
  };
}

/** A one-group, no-steps recipe around `lines`. */
function recipe(lines: RawLineItem[]): ExtractionResult {
  return {
    title: "t",
    servings_base: null,
    servings_raw: null,
    yield_raw: null,
    total_time_seconds: null,
    cook_time_seconds: null,
    truncated: false,
    image_quality: "ok",
    parse_warnings: [],
    groups: [{ name: null, line_items: lines }],
    steps: [],
  };
}

Deno.test("oracle mock scores the gold perfectly, empty ledger", async () => {
  const cases = await loadGold();
  assert(
    cases.length >= 11,
    `expected the 11+ gold recipes, got ${cases.length}`,
  );
  const scores = [];
  for (const c of cases) {
    const report = await runBenchmark({
      provider: "oracle",
      adapter: fixedMock(c.gold),
      cases: [c],
      stage: "D2",
      path: "page_text",
    });
    scores.push(...report.scores);
  }
  const s = summarize("oracle", scores);
  assertEquals(s.json_valid_rate, 1);
  assertEquals(s.line_f1, 1);
  assertEquals(s.qty_acc, 1);
  assertEquals(s.unit_acc, 1);
  assertEquals(s.normalize_agree, 1);
  assertEquals(s.servings_acc, 1);
  assertEquals(s.total_time_acc, 1);
  assertEquals(s.step_ref_f1, 1);
  assertEquals(s.timer_f1, 1);
  assertEquals(
    s.ledger_total,
    0,
    "a faithful extraction must trip no ledger row",
  );
  assertEquals(s.ledger.omitted_lines, 0);
});

Deno.test("degraded mock loses points and lights the ledger", async () => {
  const cases = await loadGold();
  const scores = [];
  for (const c of cases) {
    const report = await runBenchmark({
      provider: "degraded",
      adapter: new MockAdapter({
        name: "degraded",
        sanitizeWith: () => degrade(c.gold),
      }),
      cases: [c],
      stage: "D2",
      path: "page_text",
    });
    scores.push(...report.scores);
  }
  const s = summarize("degraded", scores);
  // The corruption invents a line, drops a line, collapses ranges, forces units.
  assert(s.ledger.invented_lines > 0, "should catch invented lines");
  assert(s.ledger.omitted_lines > 0, "should catch dropped lines");
  assert(s.ledger.collapsed_range > 0, "should catch force-fit ranges");
  assert(s.ledger.forced_unit > 0, "should catch force-fit units");
  assert(ledgerTotal(s.ledger) > 0, "dangerous-failure total must be positive");
  assert(s.line_f1 < 1, "line F1 must drop below the oracle");
  assert(s.unit_acc < 1, "unit accuracy must drop below the oracle");
});

Deno.test("alignLines pairs by ingredient identity, flags extras/omissions", () => {
  const gold = [
    { ingredient_text: "chicken thighs, boneless" },
    { ingredient_text: "red onion, finely diced" },
    { ingredient_text: "cannellini beans, drained" },
    // deno-lint-ignore no-explicit-any
  ] as any;
  const got = [
    { ingredient_text: "boneless chicken thighs" }, // matches 0
    { ingredient_text: "red onion diced" }, // matches 1
    { ingredient_text: "monosodium glutamate" }, // extra
    // deno-lint-ignore no-explicit-any
  ] as any;
  const a = alignLines(gold, got);
  assertEquals(a.pairs.length, 2);
  assertEquals(a.extraGot, [2]);
  assertEquals(a.missedGold, [2]);
});

Deno.test("calibration ECE is 0 for a perfectly-calibrated set", () => {
  // Perfectly calibrated: confident-and-right at the top of its bin, and
  // not-confident-and-wrong at the bottom of its bin ⇒ ECE 0.
  const cal = calibrate([
    { confidence: 1, correct: true, kind: "aligned" },
    { confidence: 1, correct: true, kind: "aligned" },
    { confidence: 0, correct: false, kind: "aligned" },
    { confidence: 0, correct: false, kind: "aligned" },
  ]);
  assertAlmostEquals(cal.ece, 0, 1e-9);
});

Deno.test("a single gold case round-trips flatten + score", async () => {
  const cases = await loadGold();
  const c = cases[0];
  const score = scoreExtraction(c.id, c.gold, c.gold, true);
  assertEquals(score.line.f1, 1);
  assertEquals(score.aligned, flattenLines(c.gold).length);
});

// --- the honesty fixes -------------------------------------------------------

Deno.test("numEq: fraction rounding passes, a real transcription error fails", () => {
  // ⅓ printed as 0.33 in the gold vs a model's 0.3333 — the same number.
  assert(numEq(0.33, 1 / 3), "⅓ rounding must pass");
  assert(numEq(2 / 3, 0.67), "⅔ rounding must pass");
  assert(numEq(0.125, 0.13), "⅛ rounding must pass");
  // The old 2%-relative rule passed both of these. They are wrong answers.
  assert(!numEq(400, 395), "400 g vs 395 g must fail");
  assert(!numEq(1800, 1770), "30 min vs 29.5 min must fail");
  assert(!numEq(1, 1.5), "1 vs 1½ must fail");
  assert(numEq(null, null));
  assert(!numEq(null, 1));
});

Deno.test("unit equivalence: piece↔measure-noun is a near-miss, not a failure", () => {
  const g = (u: string, m = true) => line({ unit: u, unit_mappable: m });
  assertEquals(unitVerdict(g("clove"), g("clove")), "exact");
  assertEquals(unitVerdict(g("clove"), g("cloves")), "exact"); // plural folded
  assertEquals(unitVerdict(g("can"), g("tin")), "exact"); // tin → can
  // The tracked mappable-equivalence fix: the generic count unit vs a specific
  // count-measure noun, both mappable.
  assertEquals(unitVerdict(g("clove"), g("piece")), "family");
  assertEquals(unitVerdict(g("sprig"), g("piece")), "family");
  assert(unitMatch(g("sprig"), g("piece")));
  // Two DIFFERENT specific nouns is a real error, not a family near-miss.
  assertEquals(unitVerdict(g("clove"), g("can")), "mismatch");
  // A different family is a real error.
  assertEquals(unitVerdict(g("tsp"), g("tbsp")), "mismatch");
  // A forced mapping is never a near-miss — it is a ledger event.
  assertEquals(unitVerdict(g("block", false), g("block", true)), "mismatch");
});

Deno.test("notes_agree: order-insensitive, but a dropped qualifier fails", () => {
  const n = (s: string | null) => line({ notes: s });
  assert(notesAgree(n(null), n(null)), "both empty ⇒ agree");
  assert(notesAgree(n(null), n("")), "empty vs blank ⇒ agree");
  assert(!notesAgree(n("chopped"), n(null)), "one empty ⇒ disagree");
  assert(
    notesAgree(n("chopped, for garnish"), n("for garnish, chopped")),
    "word order must not matter",
  );
  assert(
    notesAgree(n("drained and rinsed"), n("drained, rinsed")),
    "punctuation and stopwords must not matter",
  );
  assert(
    !notesAgree(n("finely diced"), n("diced")),
    "a dropped qualifier is a disagreement",
  );
});

Deno.test("omissions count against the GOLD denominator, not just aligned pairs", () => {
  const gold = recipe([
    line({ qty: 1, unit: "tsp", unit_mappable: true, ingredient_text: "salt" }),
    line({
      qty: 2,
      unit: "tsp",
      unit_mappable: true,
      ingredient_text: "sugar",
    }),
    line({
      qty: 3,
      unit: "tsp",
      unit_mappable: true,
      ingredient_text: "flour",
    }),
    line({
      qty: 4,
      unit: "tsp",
      unit_mappable: true,
      ingredient_text: "cocoa",
    }),
  ]);
  // Emits ONE line, perfectly. Aligned-only scoring would call that 100%.
  const got = recipe([
    line({ qty: 1, unit: "tsp", unit_mappable: true, ingredient_text: "salt" }),
  ]);
  const s = scoreExtraction("t", gold as never, got, true);
  assertEquals(s.qty_acc_aligned, 1, "aligned-only reading is still 100%");
  assertEquals(s.qty_acc, 0.25, "headline is over the 4 GOLD lines");
  assertEquals(s.unit_acc, 0.25);
  assertEquals(s.notes_agree, 0.25);
  assertEquals(s.ledger.omitted_lines, 3);
  // …and the three omissions became calibration samples.
  assertEquals(s.calibration.length, 4);
  assertEquals(s.calibration.filter((c) => c.kind === "omitted").length, 3);
});

Deno.test("invented lines enter calibration as confident-and-wrong", () => {
  const gold = recipe([
    line({ qty: 1, unit: "tsp", unit_mappable: true, ingredient_text: "salt" }),
  ]);
  const got = recipe([
    line({ qty: 1, unit: "tsp", unit_mappable: true, ingredient_text: "salt" }),
    line({
      qty: 1,
      unit: "tsp",
      unit_mappable: true,
      ingredient_text: "monosodium glutamate",
      confidence: 0.95,
    }),
  ]);
  const s = scoreExtraction("t", gold as never, got, true);
  const invented = s.calibration.filter((c) => c.kind === "invented");
  assertEquals(invented.length, 1);
  assertEquals(invented[0].confidence, 0.95);
  assertEquals(invented[0].correct, false);
  const cal = calibrate(s.calibration);
  assertEquals(cal.n_invented, 1);
  assert(cal.ece > 0, "a confident hallucination must cost calibration");
});

Deno.test("empty-vs-empty timers/step-refs are n/a, not a free 100%", () => {
  const bare = recipe([
    line({ qty: 1, unit: "tsp", unit_mappable: true, ingredient_text: "salt" }),
  ]);
  const s = scoreExtraction("t", bare as never, bare, true);
  assertEquals(s.timer_applicable, false);
  assertEquals(s.step_ref_applicable, false);
  // Excluded from the macro ⇒ coverage 0, and the metric does not report 100%.
  const summary = summarize("x", [s]);
  assertEquals(summary.timer_coverage, 0);
  assertEquals(summary.step_ref_coverage, 0);
  assertEquals(summary.timer_f1, 0, "no free 1.0 from an empty-vs-empty case");
});

Deno.test("summarize reports a line-weighted aggregate beside the macro", async () => {
  const cases = await loadGold();
  const scores = cases.map((c) => scoreExtraction(c.id, c.gold, c.gold, true));
  const s = summarize("oracle", scores);
  assertEquals(s.weighted.qty, 1);
  assertEquals(s.weighted.notes, 1);
  assertEquals(s.aligned_only.qty, 1);
  assertEquals(
    s.gold_lines,
    scores.reduce((a, x) => a + x.counts.gold_lines, 0),
  );
  assert(s.gold_lines > 100, "the gold set should be ~200 lines");
});

// --- the D2 input renderer ---------------------------------------------------

Deno.test("goldLineToText emits notes, never double-prints, never leaks tokens", () => {
  assertEquals(
    goldLineToText(
      line({
        qty: 80,
        unit: "g",
        unit_mappable: true,
        ingredient_text: "kale",
        notes: "destemmed and roughly chopped",
        raw_amount: "80g",
      }),
    ),
    "80g kale, destemmed and roughly chopped",
  );
  // "Juice of 1 lemon lemon" was the old output.
  assertEquals(
    goldLineToText(
      line({
        qty: 1,
        unit: "piece",
        unit_mappable: true,
        ingredient_text: "lemon",
        notes: "juiced",
        raw_amount: "Juice of 1 lemon",
      }),
    ),
    "Juice of 1 lemon",
  );
  // No raw_amount ⇒ printed prose, not the normalized "1 piece".
  assertEquals(
    goldLineToText(
      line({
        qty: 1,
        unit: "piece",
        unit_mappable: true,
        ingredient_text: "red bell pepper",
      }),
    ),
    "1 red bell pepper",
  );
  assertEquals(
    goldLineToText(
      line({
        qty: 2,
        unit: "tsp",
        unit_mappable: true,
        ingredient_text: "salt",
      }),
    ),
    "2 teaspoons salt",
  );
  // A line with no amount at all renders as bare identity.
  assertEquals(
    goldLineToText(line({ ingredient_text: "Sea salt" })),
    "Sea salt",
  );
  assertEquals(printedAmount(line({ ingredient_text: "Sea salt" })), "");
});

Deno.test("the rendered D2 input never contains a normalized unit id", async () => {
  const cases = await loadGold();
  for (const c of cases) {
    for (const g of c.gold.groups) {
      for (const li of g.line_items) {
        const text = goldLineToText(li);
        assert(
          !/\b\d+\s+piece\b/u.test(text),
          `${c.id}: leaked a normalized "N piece" token → ${text}`,
        );
      }
    }
  }
});
