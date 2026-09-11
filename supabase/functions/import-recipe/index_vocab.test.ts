// Server-real end-to-end for a URL import: the REAL orchestration spine, the
// REAL match cascade, and the REAL household vocabulary — no fakes on the
// matching side, and still no network and no LLM.
//
// `index.test.ts` proves the spine's wiring with hand fakes on every seam;
// `golden_payload.test.ts` pins the exact wire shape against a tiny pinned
// vocab. Neither exercises the cascade over the ~300-row seed vocab, which is
// where band behaviour actually lives — the ≥0.85 / 0.55–0.85 / <0.55 split
// (§6) is a property of real ingredient surfaces, not of a 5-row fixture.
//
// So this file runs a blessed gold recipe (`evals/datasets/extraction/gold/`)
// through MockAdapter → real `matchLines` → `inMemoryVocabMatcher` over
// `supabase/seed/snapshot.jsonl`, and asserts the PROPERTIES that must hold for
// any vocab: a sane band mix, the `none`-carries-no-candidates invariant, and
// the flattened line order the step refs depend on. It deliberately does NOT
// assert per-line matches — the vocab is edited often, and pinning individual
// rows here would make it a chore rather than a guard. (Per-ingredient
// precision over the real vocab is `_shared/match.test.ts`'s calibration test.)

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

/** A blessed gold recipe as the adapter's ① output. */
function loadGold(id: string): ExtractionResult {
  const path =
    new URL(`evals/datasets/extraction/gold/${id}.json`, REPO).pathname;
  return JSON.parse(Deno.readTextFileSync(path)) as ExtractionResult;
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
  return { gold, payload: await res.json() as ReconciliationPayload };
}

// `gumbo` is the richest gold case: 32 lines in one group, printed ranges,
// unmappable amounts, collective chips and step portions — the densest real
// exercise of the spine available offline.
Deno.test("URL import over the REAL vocab — band mix is sane", async () => {
  const { payload } = await importGold("gumbo");
  const flat = payload.groups.flatMap((g) => g.lines);
  assertEquals(flat.length, 32);

  const count = (b: string) => flat.filter((l) => l.band === b).length;
  const auto = count("auto"), suggest = count("suggest"), none = count("none");
  assertEquals(auto + suggest + none, flat.length, "every line got a band");

  console.log(
    `  gumbo over snapshot.jsonl: auto=${auto} suggest=${suggest} none=${none}`,
  );

  // A household stocked with a 300-row vocab should recognise a good share of a
  // mainstream recipe (currently 21/32). A FLOOR, not equality — the vocab is
  // edited over time and this must not become a chore, so it sits well below
  // today's number with room for ordinary drift. What it catches is a COLLAPSE:
  // if the cascade or §7 normalize regresses, `auto` goes to near zero.
  assert(
    auto >= flat.length * 0.4,
    `only ${auto}/${flat.length} lines auto-matched — the cascade regressed`,
  );
  // …and it should NOT match everything: a real recipe carries a few things the
  // household has never bought. An all-auto run means the bands stopped
  // discriminating.
  assert(
    auto < flat.length,
    "every single line auto-matched — the bands stopped discriminating",
  );
});

Deno.test("URL import over the REAL vocab — band/candidate invariants hold", async () => {
  const { payload } = await importGold("gumbo");
  const flat = payload.groups.flatMap((g) => g.lines);

  for (const [i, l] of flat.entries()) {
    if (l.band === "none") {
      // §6 / 0014: `none` carries NO candidates — no silent auto-stub.
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
  const { gold, payload } = await importGold("gumbo");

  // The flattened order IS the `line_index` space step refs point into (§4.6),
  // so the payload must reproduce the gold's group shape and line order exactly.
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

  // Steps pass through UNTOUCHED (refs stay by line_index until commit), and
  // every ref still addresses a real line.
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
  const { gold, payload } = await importGold("gumbo");
  // Never-invent: the orchestrator moves data, it never fills a value in.
  //
  // The title is the ONE field the sanitizer may recase, and only when the
  // page carried no case of its own: this gold's `gumbo z'fungi` is all
  // lower, so it arrives title-cased. The words, their order and their
  // punctuation are still the page's, which is what the comparison below
  // checks.
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
