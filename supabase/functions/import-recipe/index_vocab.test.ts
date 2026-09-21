// A URL import through the real spine, the real match cascade and the real
// seed vocabulary (`supabase/seed/snapshot.jsonl`), with no network and no LLM.
//
// `index.test.ts` fakes every seam and `golden_payload.test.ts` pins the wire
// shape against a tiny vocab; band behaviour (§6) only shows over real
// ingredient surfaces. This runs the replay fixture under `testdata/` through
// MockAdapter → `matchLines` → `inMemoryVocabMatcher` and asserts properties
// that hold for any vocab: a sane band mix, `none` carries no candidates, and
// the flattened line order. It asserts no per-line matches, because the vocab
// is edited often; per-ingredient precision is `_shared/match.test.ts`.

import { assert, assertEquals } from "@std/assert";
import { type ImportDeps, makeHandler } from "./index.ts";
import type {
  ExtractionResult,
  RawBlob,
  ReconciliationPayload,
} from "../_shared/types.ts";
import { fixedMock } from "../_shared/adapters/mock.ts";
import { titleCaseIfUncased } from "../_shared/adapters/schema.ts";
import { matchLines } from "../_shared/match.ts";
import { collectSse } from "./sse_test_helper.ts";
import {
  inMemoryVocabMatcher,
  type VocabEntry,
} from "../_shared/match_trgm.ts";
import { normalize } from "../_shared/normalize.ts";

const REPO = new URL("../../../", import.meta.url);

/** The real seed vocabulary as a `VocabMatcher` (canonical name + aliases). */
function realVocabMatcher(): ReturnType<typeof inMemoryVocabMatcher> {
  const raw = Deno.readTextFileSync(
    new URL("supabase/seed/snapshot.jsonl", REPO).pathname,
  );
  const entries: VocabEntry[] = raw
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean)
    .map((l) =>
      JSON.parse(l) as {
        canonical_name: string;
        aliases?: { alias_text: string }[];
      }
    )
    .map((v, i) => ({
      ingredient_id: `v-${i}`,
      canonical_name: v.canonical_name,
      match_texts: [
        ...new Set(
          [
            v.canonical_name,
            ...(v.aliases ?? []).map((a) => a.alias_text),
          ].map(normalize).filter(Boolean),
        ),
      ],
    }));
  // A silent empty vocab would make every assertion below pass vacuously.
  assert(
    entries.length > 100,
    `snapshot.jsonl looks empty (${entries.length})`,
  );
  return inMemoryVocabMatcher(entries);
}

/** The extraction result inside a saved-run-shaped case file. */
function loadGold(id: string): ExtractionResult {
  const path = new URL(`./testdata/${id}.json`, import.meta.url).pathname;
  const saved = JSON.parse(Deno.readTextFileSync(path)) as {
    raw: { content: { text: string }[] };
  };
  return JSON.parse(saved.raw.content[0].text) as ExtractionResult;
}

async function importGold(id: string): Promise<{
  gold: ExtractionResult;
  payload: ReconciliationPayload;
}> {
  const gold = loadGold(id);
  const matcher = realVocabMatcher();
  const blob: RawBlob = {
    source: "page_text",
    url: `https://example.test/${id}`,
    jsonld: null,
    text: "(the mock adapter returns the gold; this text is provenance only)",
  };
  const deps: ImportDeps = {
    adapter: fixedMock(gold, "mock-gold"),
    matchLines: (lines) => matchLines(lines, matcher),
    fetchBlob: () => Promise.resolve(blob),
  };
  const res = await makeHandler(deps)(
    new Request("https://edge.test/import-recipe", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ url: blob.url }),
    }),
  );
  assertEquals(res.status, 200);
  // The payload is the stage stream's last event (§4.7).
  const events = await collectSse(res);
  const result = events[events.length - 1];
  assertEquals(result.event, "result");
  return { gold, payload: result.data as ReconciliationPayload };
}

// Three groups, nine lines, a pinch and a handful, a re-mention and a timer —
// a small recipe, but every shape the spine has to carry.
Deno.test("URL import over the REAL vocab — band mix is sane", async () => {
  const { payload } = await importGold("replay_case");
  const flat = payload.groups.flatMap((g) => g.lines);
  assertEquals(flat.length, 9);

  const count = (b: string) => flat.filter((l) => l.band === b).length;
  const auto = count("auto"), suggest = count("suggest"), none = count("none");
  assertEquals(auto + suggest + none, flat.length, "every line got a band");

  console.log(
    `  replay_case over snapshot.jsonl: auto=${auto} suggest=${suggest} none=${none}`,
  );

  // A floor, well below today's number: it catches a collapse of the cascade
  // or of §7 normalize, not ordinary vocab drift.
  assert(
    auto >= flat.length * 0.4,
    `only ${auto}/${flat.length} lines auto-matched — the cascade regressed`,
  );
  // An all-auto run means the bands stopped discriminating.
  assert(
    auto < flat.length,
    "every single line auto-matched — the bands stopped discriminating",
  );
});

Deno.test("URL import over the REAL vocab — band/candidate invariants hold", async () => {
  const { payload } = await importGold("replay_case");
  const flat = payload.groups.flatMap((g) => g.lines);

  for (const [i, l] of flat.entries()) {
    if (l.band === "none") {
      // §6: `none` carries no candidates.
      assertEquals(
        l.candidates,
        [],
        `line ${i} is none but carries candidates`,
      );
      continue;
    }
    assert(
      l.candidates.length > 0,
      `line ${i} is ${l.band} with no candidates`,
    );
    assert(l.candidates.length <= 3, `line ${i} exceeds top-3`);
    // Candidates are best-first, and the top score agrees with the band.
    const scores = l.candidates.map((c) => c.score);
    assertEquals(
      [...scores].sort((a, b) => b - a),
      scores,
      `line ${i} candidates are not score-desc`,
    );
    if (l.band === "auto") assert(scores[0] >= 0.85, `line ${i} auto < 0.85`);
    if (l.band === "suggest") {
      assert(scores[0] >= 0.55 && scores[0] < 0.85, `line ${i} suggest OOB`);
    }
    // Distinct ingredients — never the same row twice.
    const ids = l.candidates.map((c) => c.ingredient_id);
    assertEquals(new Set(ids).size, ids.length, `line ${i} has duplicate ids`);
  }
});

Deno.test("URL import over the REAL vocab — line order and step refs survive", async () => {
  const { gold, payload } = await importGold("replay_case");

  // The flattened order is the `line_index` space step refs point into (§4.6).
  assertEquals(
    payload.groups.map((g) => g.name),
    gold.groups.map((g) => g.name),
    "group names/order changed",
  );
  assertEquals(
    payload.groups.map((g) => g.lines.length),
    gold.groups.map((g) => g.line_items.length),
    "group sizes changed",
  );
  const flatGold = gold.groups.flatMap((g) => g.line_items);
  const flat = payload.groups.flatMap((g) => g.lines);
  assertEquals(
    flat.map((l) => l.raw.ingredient_text),
    flatGold.map((li) => li.ingredient_text),
    "flattened line order changed — step refs would point at the wrong lines",
  );

  // Steps pass through untouched, and every ref still addresses a real line.
  assertEquals(payload.steps, gold.steps, "steps were not passed through");
  const refs = payload.steps
    .flatMap((s) => s.tokens)
    .filter((t) => t.t === "ref");
  assert(refs.length > 0, "the gold case has no ref tokens to check");
  for (const t of refs) {
    if (t.t !== "ref") continue;
    for (const i of t.refs) {
      assert(i >= 0 && i < flat.length, `step ref ${i} out of range`);
    }
  }
});

Deno.test("URL import over the REAL vocab — recipe-level fields pass through", async () => {
  const { gold, payload } = await importGold("replay_case");
  // Never-invent. The title is the one field the sanitizer may recase, and
  // only when the page carried no case; this one is already cased.
  assertEquals(payload.title, titleCaseIfUncased(gold.title));
  assertEquals(payload.title.toLowerCase(), gold.title.toLowerCase());
  assertEquals(payload.servings_base, gold.servings_base);
  assertEquals(payload.servings_raw, gold.servings_raw);
  assertEquals(payload.total_time_seconds, gold.total_time_seconds);
  assertEquals(payload.cook_time_seconds, gold.cook_time_seconds);
  assertEquals(payload.truncated, gold.truncated);
  assertEquals(payload.image_quality, gold.image_quality);
  assertEquals(payload.parse_warnings, gold.parse_warnings);
});
