// The ask scorers' own tests, and the dataset's validity: the live runner's
// numbers are only as honest as these.

import { assert, assertEquals, assertThrows } from "@std/assert";
import { ASK_TOOLS } from "../../supabase/functions/_shared/prompts/ask.ts";
import {
  ASK_TOOL_NAMES,
  type AskCase,
  inputMatches,
  inventedNumbers,
  numbersIn,
  parseCases,
  scoreAnswer,
  scoreFirstMove,
} from "./score_ask.ts";

const CASE: AskCase = {
  id: "t",
  why: "test",
  screen: { route: "recipe", recipe_id: "r-ragu" },
  question: "how much tamari?",
  expect_tool: "recipe_lines",
  expect_input: { recipe_id: "r-ragu", ingredient: "tamari" },
  answer_includes: ["tbsp"],
};

Deno.test("the scorer's tool list is the function's", () => {
  assertEquals(ASK_TOOL_NAMES, ASK_TOOLS.map((t) => t.name));
});

Deno.test("inputs match loosely on strings, exactly otherwise", () => {
  assert(
    inputMatches({ ingredient: "Tamari sauce" }, { ingredient: "tamari" }),
  );
  assert(!inputMatches({ ingredient: "soy" }, { ingredient: "tamari" }));
  assert(inputMatches({ step: 2 }, { step: 2 }));
  assert(!inputMatches({ step: "2" }, { step: 2 }));
  assert(!inputMatches({}, { recipe_id: "r" }));
});

Deno.test("first move — right tool, wrong tool, none, forbidden", () => {
  const right = {
    name: "recipe_lines",
    input: { recipe_id: "r-ragu", ingredient: "tamari" },
  };
  assert(scoreFirstMove(CASE, right).pass);
  assert(!scoreFirstMove(CASE, { name: "method_step", input: {} }).pass);
  assert(!scoreFirstMove(CASE, null).pass);
  const refusal: AskCase = {
    ...CASE,
    expect_tool: null,
    forbid_tool: "start_step_timer",
  };
  assert(scoreFirstMove(refusal, null).pass);
  assert(
    !scoreFirstMove(refusal, { name: "start_step_timer", input: {} }).pass,
  );
});

Deno.test("numbers — the app's own forms are all found", () => {
  assertEquals(numbersIn("3 tbsp, 1½ tbsp, ½ tsp, 20–25 min, 2.5 cups"), [
    "3",
    "1½",
    "½",
    "20",
    "25",
    "2.5",
  ]);
});

Deno.test("numbers — one the model made up is caught", () => {
  const given = ['{"amount":"3 tbsp"}', "how much tamari for 6?"];
  assertEquals(inventedNumbers("3 tbsp tamari — serves 6.", given), []);
  assertEquals(inventedNumbers("About 45 ml (3 tbsp).", given), ["45"]);
});

Deno.test("answer — an invented number fails whatever else is right", () => {
  const given = ['{"amount":"3 tbsp"}'];
  assert(scoreAnswer(CASE, "3 tbsp tamari.", given).pass);
  assert(!scoreAnswer(CASE, "45 ml tamari, about 3 tbsp.", given).pass);
  assert(!scoreAnswer(CASE, "Three spoons.", given).pass);
});

Deno.test("the dataset parses and names only real tools", async () => {
  const text = await Deno.readTextFile(
    new URL("../datasets/ask/cases.jsonl", import.meta.url),
  );
  const cases = parseCases(text);
  assert(cases.length >= 25, `only ${cases.length} cases`);
  const ids = new Set(cases.map((c) => c.id));
  assertEquals(ids.size, cases.length, "case ids are unique");
  // Every canned result is the JSON the app would send.
  for (const c of cases) {
    if (c.result !== undefined) JSON.parse(c.result);
  }
  assertThrows(() =>
    parseCases(JSON.stringify({ ...CASE, expect_tool: "plan_week" }))
  );
});
