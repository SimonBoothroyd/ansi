// Keyless self-test for the two things that make a PAID run cheap:
//   1. cost — normalized usage × a dated price row → $/import.
//   2. persistence + `--rescore` — a run's raw responses are saved and can be
//      re-scored later with zero API calls.
//
// Both are exercised end-to-end with the MockAdapter, so the machinery that
// costs money is proven by machinery that costs nothing. The round-trip below
// is the real assertion: a run written from a mock and read back must score
// IDENTICALLY to the live pass that produced it. If decode, persistence or the
// scorer drift apart, this fails instead of a $-denominated surprise later.

import { assert, assertAlmostEquals, assertEquals } from "@std/assert";
import {
  MOCK_MODEL,
  MockAdapter,
  mockUsage,
} from "../../supabase/functions/_shared/adapters/mock.ts";
import { type GoldRecipe, goldToBlob, loadGold } from "./fixtures.ts";
import {
  degrade,
  rescoreProvider,
  rescoreRun,
  runBenchmark,
  summarizeCost,
} from "./score_extraction.ts";
import {
  addUsage,
  costOf,
  priceRow,
  PRICING,
  usd,
  zeroCost,
} from "./pricing.ts";
import {
  buildManifest,
  decodeSaved,
  loadRun,
  runDir,
  sha256Hex,
  slug,
  toSavedCase,
  writeCase,
  writeManifest,
} from "./run_store.ts";
import { emptyUsage } from "../../supabase/functions/_shared/adapters/usage.ts";

// --- pricing -----------------------------------------------------------------

Deno.test("pricing — every row is dated and carries its source", () => {
  for (const [key, row] of Object.entries(PRICING)) {
    assertEquals(key, row.model, "the map key must BE the exact model id");
    assert(/^\d{4}-\d{2}-\d{2}$/.test(row.retrieved), `${key} has no date`);
    assert(row.source.length > 0, `${key} has no source`);
    assert(row.usd_per_mtok_input >= 0 && row.usd_per_mtok_output >= 0);
  }
});

Deno.test("pricing — every PINNED model has a row", async () => {
  const { PROVIDER_MODELS, PROVIDER_NAMES } = await import(
    "../../supabase/functions/_shared/adapters/mod.ts"
  );
  for (const name of PROVIDER_NAMES) {
    const model = PROVIDER_MODELS[name];
    assert(
      priceRow(model) !== null,
      `${name} is pinned to "${model}" with no pricing row — the benchmark ` +
        `would report its cost as n/a`,
    );
  }
});

Deno.test("costOf — the four terms are summed at the row's rates", () => {
  const c = costOf("claude-haiku-4-5", {
    input_tokens: 1_000_000,
    output_tokens: 1_000_000,
    cache_read_tokens: 1_000_000,
    cache_write_tokens: 1_000_000,
    reasoning_tokens: null,
    total_tokens: null,
  });
  assertEquals(c?.usd_input, 1);
  assertEquals(c?.usd_output, 5);
  assertAlmostEquals(c!.usd_cache_read, 0.1, 1e-9);
  assertEquals(c?.usd_cache_write, 1.25);
  assertAlmostEquals(c!.usd_total, 7.35, 1e-9);
  assertEquals(c?.partial, false);
});

Deno.test("costOf — an unpriced model is null, never $0", () => {
  // A missing row must read "n/a". Pricing it as free would make an unknown
  // model look like the cheapest option on the board.
  assertEquals(costOf("no-such-model-9", emptyUsage()), null);
});

Deno.test("costOf — an unreported token count marks the total a lower bound", () => {
  const c = costOf("gpt-5.6-luna", {
    ...emptyUsage(),
    input_tokens: 1_000_000,
  });
  assertEquals(c?.usd_input, 0.2);
  assertEquals(c?.partial, true); // output/cache were never reported
});

Deno.test("costOf — tokens in a category the provider does not bill cost nothing", () => {
  // OpenAI reports no cache-write rate; tokens there must not silently fall
  // back to the input rate, and must not flip `partial` either — they are
  // genuinely unbilled, not unknown.
  const c = costOf("gpt-5.6-luna", {
    input_tokens: 0,
    output_tokens: 0,
    cache_read_tokens: 0,
    cache_write_tokens: 1_000_000,
    reasoning_tokens: 0,
    total_tokens: 0,
  });
  assertEquals(c?.usd_cache_write, 0);
  assertEquals(c?.partial, false);
});

Deno.test("addUsage — null + null stays null, so 'unreported' survives summing", () => {
  const summed = addUsage(emptyUsage(), {
    ...emptyUsage(),
    input_tokens: 5,
  });
  assertEquals(summed.input_tokens, 5);
  assertEquals(summed.output_tokens, null); // NOT 0
});

Deno.test("usd — sub-cent amounts keep enough digits to be readable", () => {
  assertEquals(usd(0), "$0");
  assertEquals(usd(0.000123), "$0.000123");
  assertEquals(usd(0.5), "$0.5000");
  assertEquals(usd(12.5), "$12.50");
  assertEquals(zeroCost().usd_total, 0);
});

// --- usage flows through runBenchmark into a cost summary --------------------

Deno.test("runBenchmark — captures one call per case and costs the run", async () => {
  const cases = await loadGold();
  const adapter = new MockAdapter({
    name: "mock-oracle",
    sanitizeWith: (blob) => {
      const c = cases.find((x) => goldToBlob(x.gold).text === blob.text);
      return c!.gold;
    },
  });
  const report = await runBenchmark({
    provider: "mock-oracle",
    adapter,
    cases,
    stage: "D2",
    path: "page_text",
  });
  assertEquals(report.calls.length, cases.length);
  assert(report.calls.every((c) => c.call !== null));
  assertEquals(report.cost?.model, MOCK_MODEL);
  assertEquals(report.cost?.calls, cases.length);
  assertEquals(report.cost?.imports, cases.length);
  // The mock is priced at $0, so the assertion that matters is that tokens were
  // actually aggregated — a silent zero here would hide a broken observer.
  assert((report.cost?.usage.input_tokens ?? 0) > 0);
  assert((report.cost?.usage.output_tokens ?? 0) > 0);
});

Deno.test("runBenchmark — restores whatever observer the adapter already had", async () => {
  const cases = (await loadGold()).slice(0, 1);
  const outer: string[] = [];
  const adapter = new MockAdapter({
    name: "mock",
    sanitizeWith: () => cases[0].gold,
  });
  const sink = (c: { model: string }) => outer.push(c.model);
  adapter.onCall = sink;
  await runBenchmark({
    provider: "mock",
    adapter,
    cases,
    stage: "D2",
    path: "page_text",
  });
  // The pre-existing observer still saw the call, AND is still attached.
  assertEquals(outer, [MOCK_MODEL]);
  assertEquals(adapter.onCall, sink);
});

Deno.test("summarizeCost — $/100 imports is $/import × 100", () => {
  const usage = mockUsage("x".repeat(4000), {
    title: "t",
  } as unknown as GoldRecipe);
  const s = summarizeCost("claude-haiku-4-5", [
    {
      id: "a",
      input_text: "",
      error: null,
      call: {
        provider: "claude-haiku",
        model: "claude-haiku-4-5",
        op: "sanitize",
        usage,
        latency_ms: 1,
        raw: null,
      },
    },
  ], 4);
  assert(s.cost.usd_total > 0);
  assertAlmostEquals(s.usd_per_import, s.cost.usd_total / 4, 1e-12);
  assertAlmostEquals(s.usd_per_100_imports, s.usd_per_import * 100, 1e-12);
});

// --- persistence + rescore round-trip ----------------------------------------

Deno.test("run_store — slug and runDir build a dated, safe directory name", () => {
  assertEquals(slug("My Run / 2"), "my-run-2");
  assertEquals(slug("!!!"), "run");
  const dir = runDir("Nightly Compare", new URL("file:///tmp/base/"));
  assert(
    /\/tmp\/base\/\d{4}-\d{2}-\d{2}-nightly-compare\/$/.test(dir.pathname),
  );
});

Deno.test("run_store — a mock run round-trips: persist, reload, rescore identically", async () => {
  const cases = await loadGold();
  const byText = new Map(cases.map((c) => [goldToBlob(c.gold).text, c.gold]));
  // A DEGRADED mock, not the oracle: a round-trip that only ever carries
  // perfect scores would not notice a decoder that drops half the payload.
  const adapter = new MockAdapter({
    name: "mock-degraded",
    sanitizeWith: (blob) => degrade(byText.get(blob.text)!),
  });
  const live = await runBenchmark({
    provider: "mock-degraded",
    adapter,
    cases,
    stage: "D2",
    path: "page_text",
  });

  const base = new URL(`file://${await Deno.makeTempDir()}/`);
  const dir = runDir("roundtrip", base);
  for (const c of live.calls) {
    await writeCase(
      dir,
      await toSavedCase({
        caseId: c.id,
        stage: "D2",
        path: "page_text",
        inputText: c.input_text,
        call: c.call,
        provider: "mock-degraded",
        model: MOCK_MODEL,
        error: c.error,
      }),
    );
  }
  await writeManifest(
    dir,
    buildManifest({
      label: "roundtrip",
      gitRev: "deadbeef",
      stage: "D2",
      path: "page_text",
      providers: [{ provider: "mock-degraded", model: MOCK_MODEL }],
      caseIds: cases.map((c) => c.id),
    }),
  );

  const loaded = await loadRun(dir);
  assertEquals(loaded.manifest?.git_rev, "deadbeef");
  assertEquals(loaded.manifest?.providers[0].model, MOCK_MODEL);
  const saved = loaded.byProvider.get("mock-degraded");
  assertEquals(saved?.length, cases.length);

  const goldById = new Map(cases.map((c) => [c.id, c.gold as GoldRecipe]));
  const re = await rescoreProvider(
    "mock-degraded",
    saved!,
    goldById,
    goldToBlob,
  );

  // THE assertion: every headline number reproduced from disk, no API call.
  assertEquals(re.summary.n, live.summary.n);
  assertAlmostEquals(re.summary.line_f1, live.summary.line_f1, 1e-12);
  assertAlmostEquals(re.summary.qty_acc, live.summary.qty_acc, 1e-12);
  assertAlmostEquals(re.summary.unit_acc, live.summary.unit_acc, 1e-12);
  assertAlmostEquals(
    re.summary.normalize_agree,
    live.summary.normalize_agree,
    1e-12,
  );
  assertEquals(re.summary.ledger, live.summary.ledger);
  assertAlmostEquals(
    re.summary.calibration.ece,
    live.summary.calibration.ece,
    1e-12,
  );
  assertEquals(re.cost.usage, live.cost?.usage);
  assertEquals(re.input_drift, []); // same gold ⇒ same rendered input
  assertEquals(re.orphans, []);

  // And the whole-directory driver finds the same thing.
  const viaRun = await rescoreRun(dir);
  assertEquals(viaRun.length, 1);
  assertAlmostEquals(viaRun[0].summary.line_f1, live.summary.line_f1, 1e-12);

  await Deno.remove(new URL(".", base), { recursive: true });
});

Deno.test("run_store — a saved case carries the input hash, and drift is reported", async () => {
  const cases = (await loadGold()).slice(0, 1);
  const gold = cases[0].gold as GoldRecipe;
  const rec = await toSavedCase({
    caseId: cases[0].id,
    stage: "D2",
    path: "page_text",
    inputText: "TEXT THE MODEL NEVER ACTUALLY SAW",
    call: {
      provider: "mock-degraded",
      model: MOCK_MODEL,
      op: "sanitize",
      usage: emptyUsage(),
      latency_ms: 0,
      raw: gold,
    },
    provider: "mock-degraded",
    model: MOCK_MODEL,
    error: null,
  });
  assertEquals(rec.input.sha256, await sha256Hex(rec.input.text));

  const re = await rescoreProvider(
    "mock-degraded",
    [rec],
    new Map([[cases[0].id, gold]]),
    goldToBlob,
  );
  // The gold renders differently now than the saved input, so the rescore says
  // so rather than grading the model on text it was never shown.
  assertEquals(re.input_drift, [cases[0].id]);
});

Deno.test("run_store — a case with no gold today is an orphan, not a zero", async () => {
  const rec = await toSavedCase({
    caseId: "recipe-that-was-renamed",
    stage: "D2",
    path: "page_text",
    inputText: "x",
    call: null,
    provider: "mock-degraded",
    model: MOCK_MODEL,
    error: "boom",
  });
  const re = await rescoreProvider(
    "mock-degraded",
    [rec],
    new Map(),
    goldToBlob,
  );
  // Scoring it as a total miss would look identical to a model that failed the
  // case — the run must say "there is no gold for this" instead.
  assertEquals(re.orphans, ["recipe-that-was-renamed"]);
  assertEquals(re.summary.n, 0);
});

Deno.test("decodeSaved — an unknown provider is a hard error, not a silent zero", () => {
  let threw = false;
  try {
    decodeSaved({
      schema: "mise.eval.extraction-response/1",
      case_id: "c",
      provider: "some-new-provider",
      model: "m",
      stage: "D2",
      path: "page_text",
      op: "sanitize",
      captured_at: "",
      latency_ms: 0,
      usage: null,
      input: { text: "", sha256: "" },
      raw: {},
      error: null,
    });
  } catch (e) {
    threw = true;
    assert(String(e).includes("RESPONSE_DECODERS"));
  }
  assert(threw, "an undecodable run must fail loudly");
});
