import { assertEquals, assertStringIncludes } from "@std/assert";
import {
  type SqlExecutor,
  sqlRecipeTitleMatcher,
  sqlVocabMatcher,
} from "./match_db.ts";
import { matchLines, matchOne, matchRecipeTitles } from "./match.ts";
import type { RawLineItem } from "./types.ts";

/** A line carrying nothing but its identity text — matching reads no other field. */
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

// A fake SqlExecutor: routes on a substring of the query and records calls, so the
// SQL contracts are testable without Postgres. `deno test` stays hermetic; the
// real pg_trgm behaviour is covered offline by match_trgm.ts + match.test.ts.
interface Call {
  text: string;
  params: unknown[];
}
function fakeExec(
  route: (text: string, params: unknown[]) => unknown[],
): { exec: SqlExecutor; calls: Call[] } {
  const calls: Call[] = [];
  const exec: SqlExecutor = (text, params) => {
    calls.push({ text, params });
    return Promise.resolve(route(text, params) as never);
  };
  return { exec, calls };
}

const isExact = (text: string) => text.includes("i.match_text = q.match_text");
const isTrigram = (text: string) => text.includes("similarity(i.match_text");

Deno.test("sqlVocabMatcher — exact query is household + text-SET parameterized", async () => {
  const { exec, calls } = fakeExec((text) =>
    isExact(text)
      ? [{
        match_text: "onion",
        ingredient_id: "id1",
        canonical_name: "Onion",
        score: 1,
      }]
      : []
  );
  const m = sqlVocabMatcher(exec, "hh-1");
  const cands = await m.exact(["onion", "garlic"]);
  assertEquals(cands.get("onion"), [{
    ingredient_id: "id1",
    canonical_name: "Onion",
    score: 1,
  }]);
  // An identity with nothing to show simply has no bucket.
  assertEquals(cands.get("garlic"), undefined);
  // ONE query for the whole set, and the set rides as a single array parameter
  // — nothing about this SQL grows with the line count.
  assertEquals(calls.length, 1);
  assertEquals(calls[0].params, ["hh-1", ["onion", "garlic"]]);
  assertStringIncludes(calls[0].text, "unnest($2::text[]) as q(match_text)");
  assertStringIncludes(calls[0].text, "ingredient_alias"); // unions aliases
  assertStringIncludes(calls[0].text, "deleted_at is null"); // soft-delete aware
  // Defence in depth: the alias branch scopes the INGREDIENT to the household
  // too, so a mis-written alias row cannot reach across households.
  assertStringIncludes(
    calls[0].text,
    "a.household_id = $1 and a.deleted_at is null",
  );
  assertStringIncludes(calls[0].text, "i.household_id = $1");
});

Deno.test("sqlVocabMatcher — trigram uses the % index op, similarity(), a per-identity cap", async () => {
  const { exec, calls } = fakeExec((text) =>
    isTrigram(text)
      ? [
        {
          match_text: "suger",
          ingredient_id: "a",
          canonical_name: "Sugar",
          score: 0.7,
        },
        {
          match_text: "suger",
          ingredient_id: "b",
          canonical_name: "Sumac",
          score: 0.4,
        },
        {
          match_text: "sumak",
          ingredient_id: "b",
          canonical_name: "Sumac",
          score: 0.6,
        },
      ]
      : []
  );
  const m = sqlVocabMatcher(exec, "hh-1");
  const cands = await m.trigram(["suger", "sumak"], 3);
  assertEquals(cands.get("suger")?.length, 2);
  assertEquals(cands.get("suger")?.[0].score, 0.7);
  assertEquals(cands.get("sumak")?.map((c) => c.canonical_name), ["Sumac"]);
  assertEquals(calls.length, 1);
  assertEquals(calls[0].params, ["hh-1", ["suger", "sumak"], 3]);
  assertStringIncludes(calls[0].text, "i.match_text % q.match_text"); // GIN path
  // The cap is per identity, so one query can carry many of them and each still
  // gets its own top-N.
  assertStringIncludes(calls[0].text, "partition by b.match_text");
  assertStringIncludes(calls[0].text, "where c.rank <= $3");
  // A TOTAL sort: score ties must break the same way on every run/plan.
  assertStringIncludes(
    calls[0].text,
    "order by b.score desc, b.canonical_name asc, b.ingredient_id asc",
  );
  assertStringIncludes(
    calls[0].text,
    "a.household_id = $1 and a.deleted_at is null",
  );
});

Deno.test("sqlVocabMatcher — drives the cascade end to end", async () => {
  // Wire the fake DB through the real cascade: exact miss → trigram suggest.
  const { exec } = fakeExec((text, params) => {
    if (isExact(text)) return []; // no exact
    if (isTrigram(text)) {
      return (params[1] as string[]).includes("corn tortila")
        ? [{
          match_text: "corn tortila",
          ingredient_id: "t",
          canonical_name: "Corn Tortilla",
          score: 0.72,
        }]
        : [];
    }
    return [];
  });
  const r = await matchOne("corn tortila", sqlVocabMatcher(exec, "hh"));
  assertEquals(r.band, "suggest");
  assertEquals(r.candidates[0].canonical_name, "Corn Tortilla");
});

Deno.test("the whole cascade is two queries for a long recipe, and the trigram tier only sees what exact missed", async () => {
  // The shape this file exists to pin: a 35-line recipe used to cost 70 round
  // trips through one pool. Tier 1 answers most lines; tier 2 is asked ONLY
  // about the remainder, and each tier is one query whatever the line count.
  const vocab = ["onion", "garlic", "celery", "bay leaf", "tamari"];
  const { exec, calls } = fakeExec((text, params) => {
    const asked = params[1] as string[];
    if (isExact(text)) {
      return asked.filter((t) => vocab.includes(t)).map((t) => ({
        match_text: t,
        ingredient_id: `i-${t}`,
        canonical_name: t,
        score: 1,
      }));
    }
    if (isTrigram(text)) {
      return asked.map((t) => ({
        match_text: t,
        ingredient_id: "i-onion",
        canonical_name: "onion",
        score: 0.6,
      }));
    }
    return [];
  });

  // `tamari` three times over, plus two identities exact cannot answer.
  const texts = [
    ...vocab,
    "tamari",
    "tamari",
    "liquid smoke",
    "rubbed sage",
  ];
  const lines = texts.map((t) => line(t));
  const out = await matchLines(lines, sqlVocabMatcher(exec, "hh"));

  assertEquals(calls.length, 2, "one query per tier, not one per line");
  assertEquals(calls[0].params[1], vocab.concat("liquid smoke", "rubbed sage"));
  // Repeated identities are asked about once and share the answer; the trigram
  // tier is handed the remainder only.
  assertEquals(calls[1].params[1], ["liquid smoke", "rubbed sage"]);
  assertEquals(out.length, texts.length);
  assertEquals(out.map((l) => l.band), [
    "auto",
    "auto",
    "auto",
    "auto",
    "auto",
    "auto",
    "auto",
    "suggest",
    "suggest",
  ]);
});

// --- The sub-recipe tier's DB seam (8.6 / 0021 D6) ---------------------------

Deno.test("sqlRecipeTitleMatcher — one household-scoped, live-only title read", async () => {
  const { exec, calls } = fakeExec(() => [
    { recipe_id: "r-aioli", title: "Romesco Aioli" },
    { recipe_id: "r-buns", title: "Pretzel Buns" },
  ]);
  const m = sqlRecipeTitleMatcher(exec, "hh-1");

  const hits = await m.exact("romesco aioli");
  assertEquals(hits, [{
    recipe_id: "r-aioli",
    title: "Romesco Aioli",
    score: 1,
  }]);
  assertEquals(calls[0].params, ["hh-1"]);
  assertStringIncludes(calls[0].text, "from recipe r");
  assertStringIncludes(calls[0].text, "r.household_id = $1");
  assertStringIncludes(calls[0].text, "r.deleted_at is null"); // soft-delete aware

  // Lazily loaded ONCE: an import matches many lines against one household.
  await m.trigram("pretzle bun", 3);
  await m.exact("pretzel bun");
  assertEquals(calls.length, 1, "the title list is read once per matcher");
});

Deno.test("sqlRecipeTitleMatcher — no query at all until a line asks", () => {
  const { exec, calls } = fakeExec(() => []);
  sqlRecipeTitleMatcher(exec, "hh-1"); // constructed per request, in buildDeps
  assertEquals(calls.length, 0, "constructing the matcher must not hit the DB");
});

Deno.test("sqlRecipeTitleMatcher — titles are normalized on read (no match_text column)", async () => {
  const { exec } = fakeExec(() => [
    { recipe_id: "r-buns", title: "Pretzel Buns" },
  ]);
  const m = sqlRecipeTitleMatcher(exec, "hh-1");
  // Singularized by the SAME §7 normalizer the line's identity goes through.
  assertEquals((await m.exact("pretzel bun")).length, 1);
  assertEquals((await m.exact("Pretzel Buns")).length, 0);
});

Deno.test("sqlRecipeTitleMatcher — drives the sub-recipe tier end to end", async () => {
  const { exec } = fakeExec(() => [
    { recipe_id: "r-aioli", title: "Romesco Aioli" },
  ]);
  const hits = await matchRecipeTitles(
    "¼ cup Romesco Aioli (page 38)",
    sqlRecipeTitleMatcher(exec, "hh"),
  );
  assertEquals(hits.map((h) => h.recipe_id), ["r-aioli"]);
});
