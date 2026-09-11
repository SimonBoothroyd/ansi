import { assertEquals, assertMatch } from "@std/assert";
import { planSeed, type SnapshotRow, unitDiff } from "./gen_seed.ts";
import { normalize } from "../../functions/_shared/normalize.ts";

/**
 * A snapshot row as the export writes it — `match_text` is the cloud's stored
 * key, so the fixtures compute it the same way the cloud did and the drift
 * test is the one place that deliberately disagrees.
 */
const row = (
  canonical_name: string,
  aliases: string[] = [],
  extra: Partial<SnapshotRow> = {},
): SnapshotRow => ({
  canonical_name,
  default_unit: "g",
  match_text: normalize(canonical_name),
  aliases: aliases.map((a) => ({
    alias_text: a,
    match_text: normalize(a),
    source: "seed",
  })),
  ...extra,
});

Deno.test("planSeed — a clean snapshot plans every row and alias", () => {
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
    source: "seed",
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
    { canonical_name: "Salt", default_unit: "spoon", match_text: "salt" },
    { canonical_name: "2 large", default_unit: "g", match_text: "" },
  ]);
  assertMatch(plan.problems[0], /match_text "onion" collides: Onions vs Onion/);
  assertMatch(plan.problems[1], /bad default_unit "spoon" on Salt/);
  assertMatch(plan.problems[2], /empty match_text for 2 large/);
});

Deno.test("planSeed — a match_text the normalizer disagrees with fails, naming both", () => {
  // The whole point of recomputing: the seed must store the key THIS
  // normalizer writes, or the vocabulary and the runtime cascade drift apart.
  const plan = planSeed([
    { canonical_name: "Molasses", default_unit: "tbsp", match_text: "molass" },
  ]);
  assertEquals(plan.problems.length, 1);
  assertMatch(plan.problems[0], /match_text drift on Molasses/);
  assertMatch(plan.problems[0], /snapshot says "molass"/);
  assertMatch(plan.problems[0], /normalizer says "molasses"/);
});

Deno.test("planSeed — an alias whose stored key drifted fails too", () => {
  const plan = planSeed([{
    canonical_name: "Garlic",
    default_unit: "piece",
    match_text: "garlic",
    aliases: [{
      alias_text: "fat garlic",
      match_text: "fat garlick",
      source: "seed",
    }],
  }]);
  assertEquals(plan.problems.length, 1);
  assertMatch(plan.problems[0], /alias "fat garlic" of Garlic/);
  assertMatch(plan.problems[0], /snapshot says "fat garlick"/);
});

Deno.test("planSeed — the clone-blind stamps are re-stamped 'seed'", () => {
  // ensure_onboarded (0039) skips source='manual' ingredients and
  // source='import_correction' aliases, so a seed row carrying either would
  // seed and then reach no household at all. Nothing else is rewritten: the
  // other stamps are the row's real provenance and the app prints them.
  const plan = planSeed([
    row("Harissa", ["rose harissa"], { source: "manual" }),
    row("Miso", [], { source: "usda_fdc:172443" }),
    row("Gochujang", [], { source: "import_stub" }),
    {
      ...row("Tempeh"),
      source: "seed",
      aliases: [{
        alias_text: "soy tempeh",
        match_text: "soy tempeh",
        source: "import_correction",
      }],
    },
  ]);
  assertEquals(plan.problems, []);
  assertEquals(
    plan.ingredients.map((i) => i.source),
    ["seed", "usda_fdc:172443", "import_stub", "seed"],
  );
  assertEquals(plan.restampedRows, ["Harissa"]);
  // The corrected alias becomes a seed alias; the ordinary one is untouched.
  assertEquals(plan.aliases.map((a) => a.source), ["seed", "seed"]);
  assertEquals(plan.restampedAliases, ["soy tempeh → Tempeh"]);
});

Deno.test("unitDiff — names what the curator added and withheld", () => {
  assertEquals(
    unitDiff(["g", "kg", "cup"], ["g", "kg", "tsp"]),
    { added: ["cup"], withheld: ["tsp"] },
  );
  assertEquals(unitDiff(["g"], ["g"]), { added: [], withheld: [] });
  assertEquals(unitDiff(null, ["g"]), { added: [], withheld: ["g"] });
});
