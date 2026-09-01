import { assertEquals, assertStringIncludes } from "@std/assert";
import { type SqlExecutor, sqlVocabMatcher } from "./match_db.ts";
import { matchOne } from "./match.ts";

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

Deno.test("sqlVocabMatcher — exact query is household + text parameterized", async () => {
  const { exec, calls } = fakeExec((text) =>
    text.includes("i.match_text = $2")
      ? [{ ingredient_id: "id1", canonical_name: "Onion", score: 1 }]
      : []
  );
  const m = sqlVocabMatcher(exec, "hh-1");
  const cands = await m.exact("onion");
  assertEquals(cands, [{
    ingredient_id: "id1",
    canonical_name: "Onion",
    score: 1,
  }]);
  assertEquals(calls[0].params, ["hh-1", "onion"]);
  assertStringIncludes(calls[0].text, "ingredient_alias"); // unions aliases
  assertStringIncludes(calls[0].text, "deleted_at is null"); // soft-delete aware
  // Defence in depth: the alias branch scopes the INGREDIENT to the household
  // too, so a mis-written alias row cannot reach across households.
  assertStringIncludes(
    calls[0].text,
    "a.household_id = $1 and i.household_id = $1",
  );
});

Deno.test("sqlVocabMatcher — trigram uses the % index op, similarity(), limit", async () => {
  const { exec, calls } = fakeExec((text) =>
    text.includes("similarity(i.match_text, $2)")
      ? [
        { ingredient_id: "a", canonical_name: "Sugar", score: 0.7 },
        { ingredient_id: "b", canonical_name: "Sumac", score: 0.4 },
      ]
      : []
  );
  const m = sqlVocabMatcher(exec, "hh-1");
  const cands = await m.trigram("suger", 3);
  assertEquals(cands.length, 2);
  assertEquals(cands[0].score, 0.7);
  assertEquals(calls[0].params, ["hh-1", "suger", 3]);
  assertStringIncludes(calls[0].text, "match_text % $2"); // GIN-index path
  // A TOTAL sort: score ties must break the same way on every run/plan.
  assertStringIncludes(
    calls[0].text,
    "order by score desc, canonical_name asc, ingredient_id asc",
  );
  assertStringIncludes(
    calls[0].text,
    "a.household_id = $1 and i.household_id = $1",
  );
});

Deno.test("sqlVocabMatcher — drives the cascade end to end", async () => {
  // Wire the fake DB through the real cascade: exact miss → trigram suggest.
  const { exec } = fakeExec((text, params) => {
    if (text.includes("i.match_text = $2")) return []; // no exact
    if (text.includes("similarity")) {
      return params[1] === "corn tortila"
        ? [{ ingredient_id: "t", canonical_name: "Corn Tortilla", score: 0.72 }]
        : [];
    }
    return [];
  });
  const r = await matchOne("corn tortila", sqlVocabMatcher(exec, "hh"));
  assertEquals(r.band, "suggest");
  assertEquals(r.candidates[0].canonical_name, "Corn Tortilla");
});
