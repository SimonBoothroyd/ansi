import { assertEquals, assertMatch } from "@std/assert";
import { planSeed, type VocabRow } from "./gen_seed.ts";

const row = (canonical_name: string, aliases: string[] = []): VocabRow => ({
  canonical_name,
  default_unit: "g",
  aliases,
});

Deno.test("planSeed — a clean vocab plans every row and alias", () => {
  const plan = planSeed([
    row("Coconut Milk", ["coco milk"]),
    row("Coconut Cream"),
  ]);
  assertEquals(plan.problems, []);
  assertEquals(plan.ingredients.map((i) => i.match), [
    "coconut milk",
    "coconut cream",
  ]);
  assertEquals(plan.aliases, [{
    ing_match: "coconut milk",
    alias_text: "coco milk",
    alias_match: "coco milk",
  }]);
});

Deno.test("planSeed — an alias the ingredient already covers is dropped quietly", () => {
  // Its own canonical key, and a second alias landing on the same text: the
  // row matches those already, so there is nothing to seed and nothing wrong.
  const plan = planSeed([
    row("Garlic", ["garlic", "fat garlic", "Fat Garlic"]),
  ]);
  assertEquals(plan.problems, []);
  assertEquals(plan.aliases.map((a) => a.alias_match), ["fat garlic"]);
});

Deno.test("planSeed — an alias colliding with ANOTHER ingredient fails the build", () => {
  // The tracker row: the old check was per ingredient, so this shipped and
  // "coconut milk" then had two live owners at exact-match time.
  const plan = planSeed([
    row("Coconut Milk"),
    row("Coconut Cream", ["coconut milk"]),
  ]);
  assertEquals(plan.problems.length, 1);
  const [problem] = plan.problems;
  assertMatch(problem, /alias "coconut milk" of Coconut Cream/);
  assertMatch(problem, /already held by Coconut Milk \(canonical name\)/);
  // The colliding alias is not planned — the message is the outcome.
  assertEquals(plan.aliases, []);
});

Deno.test("planSeed — two ingredients' aliases colliding fails the build", () => {
  const plan = planSeed([
    row("Coconut Milk", ["coco milk"]),
    row("Coconut Cream", ["Coco Milk"]),
  ]);
  assertEquals(plan.problems.length, 1);
  assertMatch(
    plan.problems[0],
    /alias "Coco Milk" of Coconut Cream .* already held by Coconut Milk \(alias "coco milk"\)/,
  );
  assertEquals(plan.aliases.map((a) => a.ing_match), ["coconut milk"]);
});

Deno.test("planSeed — an alias colliding with a LATER ingredient's key still fails", () => {
  // Order in the file must not decide it: the ingredient namespace is filled
  // before any alias is planned.
  const plan = planSeed([
    row("Coconut Cream", ["coconut milk"]),
    row("Coconut Milk"),
  ]);
  assertEquals(plan.problems.length, 1);
  assertMatch(plan.problems[0], /already held by Coconut Milk/);
});

Deno.test("planSeed — the pre-existing checks still fire", () => {
  const plan = planSeed([
    row("Onions"),
    row("Onion"),
    { canonical_name: "Salt", default_unit: "spoon" },
    { canonical_name: "2 large" },
  ]);
  assertMatch(plan.problems[0], /match_text "onion" collides: Onions vs Onion/);
  assertMatch(plan.problems[1], /bad default_unit "spoon" on Salt/);
  assertMatch(plan.problems[2], /empty match_text for 2 large/);
});
