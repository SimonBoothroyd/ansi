// Keyless self-test for the extraction scorer (charter 0018: "the runner scores
// at least D2 on the gold with the mock adapter (keyless)"). Proves two things
// with no provider key: the scorer's PERFECT path (oracle → 100%, empty ledger),
// and that it DISCRIMINATES (a degraded output loses points and lights the
// never-invent ledger). If either drifts, the scorer is miscalibrated.

import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@^1";
import {
  fixedMock,
  MockAdapter,
} from "../../supabase/functions/_shared/adapters/mock.ts";
import { loadGold } from "./fixtures.ts";
import {
  alignLines,
  calibrate,
  degrade,
  ledgerTotal,
  runBenchmark,
  scoreExtraction,
  summarize,
} from "./score_extraction.ts";
import { flattenLines } from "../../supabase/functions/_shared/adapters/schema.ts";

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
    { confidence: 1, correct: true },
    { confidence: 1, correct: true },
    { confidence: 0, correct: false },
    { confidence: 0, correct: false },
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
