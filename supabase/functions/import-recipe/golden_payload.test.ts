// The TS→Dart contract test: runs the real orchestration spine with no network
// and no LLM, and pins its `ReconciliationPayload` as a committed golden JSON
// file that `app/test/features/import/golden_payload_contract_test.dart`
// parses.
//
// `types.ts` and `reconciliation_payload.dart` mirror each other by hand, and
// the Dart mirror defaults every field, so drift would decode silently. The
// Dart test asserts every load-bearing field of this file is non-default.
//
// `MockAdapter` supplies ① through the real coercion and validation; the real
// `matchLines` runs over a small vocab pinned here (the real-vocab run is
// `index_vocab.test.ts`); the request goes through the real `makeHandler`.
//
// Regenerate after an intentional contract change:
//   cd supabase/functions && deno task golden
// Review the diff, then update the Dart assertions if a shape moved.

import { assert, assertEquals } from "@std/assert";
import { type ImportDeps, makeHandler } from "./index.ts";
import { collectSse } from "./sse_test_helper.ts";
import type {
  ExtractionResult,
  RawBlob,
  ReconciliationPayload,
} from "../_shared/types.ts";
import { MockAdapter } from "../_shared/adapters/mock.ts";
import { matchLines } from "../_shared/match.ts";
import {
  inMemoryVocabMatcher,
  type VocabEntry,
} from "../_shared/match_trgm.ts";

const GOLDEN_PATH = new URL(
  "./__fixtures__/reconciliation_payload.golden.json",
  import.meta.url,
);

// --- The pinned vocab --------------------------------------------------------
// Small and committed, so the golden is reproducible. Chosen so the cascade
// produces all three bands over the sampler below.

const VOCAB: VocabEntry[] = [
  { ingredient_id: "v-onion", canonical_name: "Onion", match_texts: ["onion"] },
  {
    ingredient_id: "v-garlic",
    canonical_name: "Garlic",
    match_texts: ["garlic"],
  },
  {
    ingredient_id: "v-coconut-milk",
    canonical_name: "Coconut Milk",
    match_texts: ["coconut milk"],
  },
  {
    ingredient_id: "v-parsley",
    canonical_name: "Flat-Leaf Parsley",
    match_texts: ["flat leaf parsley"],
  },
  {
    // No exact surface for the sampler's bare "parmesan": trigram lands it in
    // the mid band, a `suggest` line.
    ingredient_id: "v-parmesan",
    canonical_name: "Parmesan Cheese",
    match_texts: ["parmesan cheese"],
  },
];

// --- The contract sampler ----------------------------------------------------
// Not a real recipe: a compact fixture carrying every shape the Dart mirror
// has to decode. Keep it structurally valid (no `structural-review:` warning).

function contractSampler(): ExtractionResult {
  return {
    title: "Contract Sampler Stew",
    servings_base: 4,
    servings_raw: "Serves 4",
    yield_raw: "Makes about 1.5 litres",
    // Both TimeField forms in one payload: a bare number and a {low,high} range.
    total_time_seconds: 5400,
    cook_time_seconds: { low_seconds: 2700, high_seconds: 3600 },
    truncated: true,
    image_quality: "degraded",
    parse_warnings: [
      "Amount for the parsley was not printed — left blank for you to set.",
    ],
    groups: [
      {
        name: null,
        line_items: [
          {
            // exact hit → band auto; carries a cook-prep note.
            qty: 2,
            qty_low: null,
            qty_high: null,
            unit: "piece",
            unit_mappable: true,
            ingredient_text: "onion",
            notes: "finely diced",
            raw_amount: "2 medium",
            optional: false,
            confidence: 0.97,
          },
          {
            // a printed RANGE: qty null, both endpoints set.
            qty: null,
            qty_low: 2,
            qty_high: 3,
            unit: "clove",
            unit_mappable: true,
            ingredient_text: "garlic",
            notes: "sliced",
            raw_amount: "2–3 cloves",
            optional: false,
            confidence: 0.9,
          },
          {
            // unit_mappable FALSE: `unit` holds the printed word, UI resolves it.
            qty: 1,
            qty_low: null,
            qty_high: null,
            unit: "tin",
            unit_mappable: false,
            ingredient_text: "coconut milk",
            notes: null,
            raw_amount: "One 400 g tin",
            optional: false,
            confidence: 0.93,
          },
          {
            // no amount at all + optional true.
            qty: null,
            qty_low: null,
            qty_high: null,
            unit: null,
            unit_mappable: false,
            ingredient_text: "flat-leaf parsley",
            notes: "for garnish",
            raw_amount: "",
            optional: true,
            confidence: 0.71,
          },
        ],
      },
      {
        // A named second group: the flattened line_index space spans groups.
        name: "To finish",
        line_items: [
          {
            // A typo'd surface: trigram scores ~0.68 → `suggest`, well clear
            // of both band edges (0.55 / 0.85).
            qty: 30,
            qty_low: null,
            qty_high: null,
            unit: "g",
            unit_mappable: true,
            ingredient_text: "parmasan cheese",
            notes: "grated",
            raw_amount: "30 g",
            optional: false,
            confidence: 0.88,
          },
          {
            // nothing close in the vocab → band none, empty candidates.
            qty: 2,
            qty_low: null,
            qty_high: null,
            unit: "tbsp",
            unit_mappable: true,
            ingredient_text: "gochujang paste",
            notes: null,
            raw_amount: "2 tbsp",
            optional: false,
            confidence: 0.82,
          },
        ],
      },
    ],
    steps: [
      {
        tokens: [
          { t: "text", s: "Soften the " },
          {
            t: "ref",
            refs: [0],
            label: "onion",
            mention: "new",
            portion: null,
          },
          { t: "text", s: " with the " },
          {
            t: "ref",
            refs: [1],
            label: "garlic",
            mention: "new",
            portion: null,
          },
          { t: "text", s: " for " },
          // single time → low === high
          { t: "timer", low_seconds: 480, high_seconds: 480 },
          { t: "text", s: "." },
        ],
      },
      {
        tokens: [
          { t: "text", s: "Pour in the " },
          {
            t: "ref",
            refs: [2],
            label: "coconut milk",
            mention: "new",
            portion: null,
          },
          { t: "text", s: " and simmer " },
          // range timer
          { t: "timer", low_seconds: 2700, high_seconds: 3600 },
          { t: "text", s: ", stirring through " },
          {
            // a step sub-amount: portion with a number + unit, on a re-mention.
            t: "ref",
            refs: [5],
            label: "gochujang",
            mention: "rementioned",
            portion: {
              qty: 1,
              qty_low: null,
              qty_high: null,
              unit: "tbsp",
              qualifier: null,
            },
          },
          { t: "text", s: "." },
        ],
      },
      {
        tokens: [
          { t: "text", s: "Finish with " },
          {
            // COLLECTIVE chip: more than one ref → renders no number.
            t: "ref",
            refs: [3, 4],
            label: "the parsley and parmesan",
            mention: "fraction",
            portion: {
              // qualifier-only portion: a relative word, no number.
              qty: null,
              qty_low: null,
              qty_high: null,
              unit: null,
              qualifier: "the rest",
            },
          },
          { t: "text", s: "." },
        ],
      },
    ],
  };
}

// --- The spine ---------------------------------------------------------------

/** Deps wired to the real cascade + the mock adapter. No network, no LLM. */
function goldenDeps(): ImportDeps {
  const matcher = inMemoryVocabMatcher(VOCAB);
  const blob: RawBlob = {
    source: "page_text",
    url: "https://example.test/contract-sampler",
    jsonld: null,
    text: "Contract Sampler Stew\n(the mock adapter ignores this text)",
    // The readable page, so the fixture pins `source_text` and a mix of spans:
    // five lines this text prints, and the gochujang, which it does not.
    page_text: "Contract Sampler Stew. Serves 4. Ingredients: " +
      "2 medium onion, finely chopped; 2\u20133 cloves garlic; " +
      "One 400 g tin coconut milk; flat-leaf parsley, to serve; " +
      "30 g parmasan cheese, grated.",
  };
  return {
    adapter: new MockAdapter({
      name: "mock-contract",
      sanitizeWith: () => contractSampler(),
    }),
    matchLines: (lines) => matchLines(lines, matcher),
    fetchBlob: () => Promise.resolve(blob),
  };
}

/** Runs a URL import through the real HTTP handler and returns the payload. */
async function producePayload(): Promise<ReconciliationPayload> {
  const res = await makeHandler(goldenDeps())(
    new Request("https://edge.test/import-recipe", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ url: "https://example.test/contract-sampler" }),
    }),
  );
  assertEquals(res.status, 200, "the sampler must import cleanly");
  // The payload is the stream's last event.
  const events = await collectSse(res);
  const result = events[events.length - 1];
  assertEquals(result.event, "result", "the payload is the last event");
  return result.data as ReconciliationPayload;
}

const serialize = (p: ReconciliationPayload) =>
  JSON.stringify(p, null, 2) + "\n";

Deno.test("golden payload — the spine's output matches the committed fixture", async () => {
  const produced = serialize(await producePayload());

  if (Deno.env.get("UPDATE_GOLDEN")) {
    await Deno.mkdir(new URL("./", GOLDEN_PATH), { recursive: true });
    await Deno.writeTextFile(GOLDEN_PATH, produced);
    console.log(`  golden REWRITTEN: ${GOLDEN_PATH.pathname}`);
    return;
  }

  let committed: string;
  try {
    committed = await Deno.readTextFile(GOLDEN_PATH);
  } catch (e) {
    throw new Error(
      `the golden fixture is missing (${GOLDEN_PATH.pathname}). ` +
        `Regenerate it with \`deno task golden\`. Cause: ${
          e instanceof Error ? e.message : String(e)
        }`,
    );
  }

  assertEquals(
    produced,
    committed,
    "the import spine's ReconciliationPayload no longer matches the committed " +
      "golden. If the contract change is INTENTIONAL: run `deno task golden`, " +
      "review the diff, and update app/test/features/import/" +
      "golden_payload_contract_test.dart to match. If it is not, this is drift.",
  );
});

// If the sampler stops producing one of these shapes, the Dart assertions
// would pass vacuously.
Deno.test("golden payload — the fixture covers every load-bearing shape", async () => {
  const p = await producePayload();
  const flat = p.groups.flatMap((g) => g.lines);

  assertEquals(flat.length, 6, "line count");

  // All three bands present.
  const bands = new Set(flat.map((l) => l.band));
  assert(bands.has("auto"), "no `auto` line in the golden");
  assert(bands.has("suggest"), "no `suggest` line in the golden");
  assert(bands.has("none"), "no `none` line in the golden");

  // `none` never carries candidates; `suggest`/`auto` always do.
  for (const l of flat) {
    if (l.band === "none") assertEquals(l.candidates.length, 0);
    else assert(l.candidates.length > 0, `${l.band} line with no candidates`);
  }

  // Line-level shapes.
  assert(flat.some((l) => l.raw.qty_low !== null && l.raw.qty_high !== null));
  assert(flat.some((l) => l.raw.unit_mappable === false));
  assert(flat.some((l) => l.raw.notes !== null && l.raw.notes !== ""));
  assert(flat.some((l) => l.raw.optional));
  assert(flat.some((l) => l.raw.qty === null && l.raw.qty_low === null));

  // Recipe-level shapes: both TimeField forms in one payload.
  assertEquals(typeof p.total_time_seconds, "number");
  assert(
    p.cook_time_seconds !== null && typeof p.cook_time_seconds === "object",
    "cook_time_seconds must be the {low,high} range form",
  );
  assert(p.truncated);
  assertEquals(p.image_quality, "degraded");
  // Every span indexes `source_text`, and the line the page never printed
  // carries none.
  assert(p.source_text !== undefined, "no source_text in the golden");
  const spanned = flat.filter((l) => l.source_span !== undefined);
  assertEquals(spanned.length, 5, "spanned line count");
  assert(
    flat.some((l) => l.source_span === undefined),
    "no unplaceable line in the golden",
  );
  for (const l of spanned) {
    const { start, end } = l.source_span!;
    assert(start >= 0 && end <= p.source_text!.length && start < end);
    assert(
      p.source_text!.slice(start, end).length === end - start,
      "a span must index the text the payload carries",
    );
  }
  assert(p.parse_warnings.length > 0);
  assertEquals(p.groups.length, 2);
  assertEquals(p.groups[0].name, null);
  assert(p.groups[1].name !== null, "a named group");

  // Step tokens: text, ref (new/rementioned/collective), timer (single+range),
  // and both portion forms.
  const tokens = p.steps.flatMap((s) => s.tokens);
  const refs = tokens.filter((t) => t.t === "ref");
  const timers = tokens.filter((t) => t.t === "timer");
  assert(tokens.some((t) => t.t === "text"));
  assert(
    timers.some((t) => t.t === "timer" && t.low_seconds === t.high_seconds),
  );
  assert(
    timers.some((t) => t.t === "timer" && t.low_seconds !== t.high_seconds),
  );
  assert(
    refs.some((t) => t.t === "ref" && t.refs.length > 1),
    "collective ref",
  );
  assert(refs.some((t) => t.t === "ref" && t.mention === "rementioned"));
  assert(
    refs.some((t) => t.t === "ref" && t.portion?.qty !== null && t.portion),
    "a numeric portion",
  );
  assert(
    refs.some((t) =>
      t.t === "ref" && t.portion?.qualifier !== null && t.portion
    ),
    "a qualifier-only portion",
  );

  // Step refs are by flattened line_index, so every ref must be in range.
  for (const t of refs) {
    if (t.t !== "ref") continue;
    for (const i of t.refs) {
      assert(i >= 0 && i < flat.length, `ref ${i} out of range`);
    }
  }
});
