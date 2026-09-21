import { assertEquals } from "@std/assert";
import { normalize, stripParentheticals } from "./normalize.ts";

Deno.test("normalize — spec §7 worked examples", () => {
  assertEquals(normalize("2 large Onions, diced"), "onion");
  assertEquals(normalize("Chicken thighs, boneless"), "chicken thigh boneless");
  assertEquals(normalize("1 can coconut milk"), "coconut milk");
  assertEquals(normalize("fresh ginger, grated"), "ginger fresh");
  assertEquals(normalize("a handful of curry leaves"), "curry leaf");
});

Deno.test("normalize — keeps form/state words (the §7 own-goal)", () => {
  // Over-stripping would collapse these distinct ingredients onto each other.
  assertEquals(normalize("ground ginger"), "ginger ground");
  assertEquals(normalize("fresh ginger"), "ginger fresh");
  assertEquals(normalize("coconut milk"), "coconut milk");
  assertEquals(normalize("coconut cream"), "coconut cream");
});

Deno.test("normalize — is symmetric on stored names", () => {
  // The same function runs on canonical_name at write time.
  assertEquals(normalize("Ginger, fresh"), "ginger fresh");
  assertEquals(normalize(normalize("fresh ginger")), normalize("fresh ginger"));
});

Deno.test("normalize — singularization edge cases", () => {
  assertEquals(normalize("tomatoes"), "tomato");
  assertEquals(normalize("berries"), "berry");
  assertEquals(normalize("asparagus"), "asparagus"); // not a plural
  // -ves: plain -s plurals, not -f ("chives" must not become "chif")
  assertEquals(normalize("chives"), "chive");
  assertEquals(normalize("olives"), "olive");
  assertEquals(normalize("bay leaves"), "bay leaf"); // genuine -ves→-f (irregular)
});

Deno.test("normalize — invariant words that only look plural", () => {
  // The regex guard spares -ss/-us/-is/-ous; "molasses" ends in -sses, so it
  // is in INVARIANT_WORDS (migration 0022 rewrote the old `molass`).
  assertEquals(normalize("molasses"), "molasses");
  assertEquals(normalize("Blackstrap Molasses"), "blackstrap molasses");
  assertEquals(normalize("2 tablespoons molasses"), "molasses");
  // The guard's own cases still hold.
  assertEquals(normalize("hummus"), "hummus");
  assertEquals(normalize("couscous"), "couscous");
  assertEquals(normalize("Swiss chard"), "swiss chard");
  assertEquals(normalize("watercress"), "watercress");
  // Real -es plurals keep singularizing.
  assertEquals(normalize("radishes"), "radish");
  assertEquals(normalize("2 peaches"), "peach");
  assertEquals(normalize("mashed potatoes"), "potato");
});

Deno.test("normalize — folds diacritics onto the base letter", () => {
  // The letter survives (never "jalapeo") but its accent does not, so a line
  // printed without the tilde reaches the row that has it.
  assertEquals(normalize("jalapeño"), "jalapeno");
  assertEquals(normalize("Jalapeño"), "jalapeno");
  assertEquals(normalize("jalapeno"), "jalapeno");
  assertEquals(normalize("2 jalapeños, diced"), "jalapeno");
  assertEquals(normalize("crème fraîche"), "creme fraiche");
  assertEquals(normalize("piment d'Espelette"), "piment despelette");
});

Deno.test("normalize — clove is a measure only next to an allium", () => {
  assertEquals(normalize("2 cloves garlic, minced"), "garlic"); // measure
  assertEquals(normalize("3 garlic cloves"), "garlic"); // measure
  assertEquals(normalize("Pinch ground cloves"), "clove ground"); // the spice
  assertEquals(normalize("pinch of cloves"), "clove"); // the spice, no allium
});

Deno.test("normalize — stick is identity only next to cinnamon", () => {
  assertEquals(normalize("2 cinnamon sticks"), "cinnamon stick"); // the quill
  assertEquals(normalize("Cinnamon Stick"), "cinnamon stick"); // stored name
  assertEquals(normalize("1 stick vegan butter (melted)"), "vegan butter"); // measure
  assertEquals(normalize("ground cinnamon"), "cinnamon ground"); // untouched
  assertEquals(normalize("cinnamon"), "cinnamon"); // bare word → the alias row
});

Deno.test("normalize — tinned folds onto canned", () => {
  // Only "canned" is a state word; without the fold "tinned" would lead the
  // nouns and miss the row.
  assertEquals(normalize("tinned chickpeas"), "chickpea canned");
  assertEquals(normalize("canned chickpeas"), "chickpea canned");
  assertEquals(normalize("1 tin of tinned black beans"), "black bean canned");
  // The cut word still trails behind it, in the order the phrase printed.
  assertEquals(normalize("tinned diced tomatoes"), "tomato canned diced");
});

Deno.test("normalize — an amount fused to its unit is still an amount", () => {
  // "400g" is neither wholly numeric (QUANTITY) nor a bare unit (MEASURES).
  assertEquals(normalize("400g tin of black beans"), "black bean");
  assertEquals(normalize("400g tin chickpeas"), "chickpea");
  assertEquals(normalize("1.5kg potatoes"), "potato");
  assertEquals(normalize("\u00bdoz dried porcini"), "porcini dried");
  // Split or fused, the same key.
  assertEquals(normalize("2 lb ground beef"), "beef ground");
  assertEquals(normalize("2lb ground beef"), "beef ground");
});

Deno.test("normalize — a cut word is identity inside a canned phrase", () => {
  // _SCHEMA.md: chopped / crushed / diced tomatoes in a can are different
  // products, so the cut is not stripped as prep.
  assertEquals(normalize("Canned Diced Tomatoes"), "tomato canned diced");
  assertEquals(normalize("canned chopped tomatoes"), "tomato canned chopped");
  // British phrasing folds onto the stored word, so it lands on the same row.
  assertEquals(normalize("tinned chopped tomatoes"), "tomato canned chopped");
  // It trails like any other state word, so word order doesn't matter.
  assertEquals(normalize("diced tomatoes, canned"), "tomato diced canned");

  // Outside a canned phrase the cut is prep.
  assertEquals(normalize("diced tomatoes"), "tomato");
  assertEquals(normalize("2 diced tomatoes"), "tomato");
  assertEquals(normalize("1 onion, diced"), "onion");
  // The measure "can" is not the state "canned" (eval case 7 must not move).
  assertEquals(
    normalize("1  (28-ounce) can fire-roasted, chopped tomatoes"),
    "fire tomato roasted",
  );
  // "crushed" is not in the set; it still holds the generic canned key.
  assertEquals(normalize("Canned Crushed Tomatoes"), "tomato canned");
});

Deno.test("normalize — hyphenated compounds split into words", () => {
  assertEquals(normalize("all-purpose flour"), "all purpose flour");
  assertEquals(normalize("extra-virgin olive oil"), "extra virgin olive oil");
});

Deno.test("normalize — drops vague amount words", () => {
  assertEquals(normalize("Few cracks black pepper"), "black pepper");
  assertEquals(normalize("Drizzle olive oil"), "olive oil");
  assertEquals(
    normalize("Heaping tablespoon nutritional yeast"),
    "nutritional yeast",
  );
  assertEquals(
    normalize("hot chili or red pepper flakes"),
    "hot chili red pepper flake",
  );
  // "and"/"of" are filler: "1 head of garlic, peeled and chopped" → "garlic".
  assertEquals(normalize("garlic, peeled and chopped"), "garlic");
});

// --- the shared vectors ------------------------------------------------------

Deno.test("normalize — agrees with the shared Dart/TS vectors", () => {
  // The same file the Dart port's parity test reads, so an entry added for
  // Dart alone still has to hold here.
  const path = new URL(
    "../../../app/test/features/ingredients/normalize_vectors.json",
    import.meta.url,
  );
  const { vectors } = JSON.parse(Deno.readTextFileSync(path)) as {
    vectors: { from: string; in: string; out: string }[];
  };
  if (vectors.length < 30) throw new Error("vector file did not load");
  for (const v of vectors) {
    assertEquals(normalize(v.in), v.out, `[${v.from}] "${v.in}"`);
  }
});

// --- stripParentheticals -----------------------------------------------------

Deno.test("stripParentheticals — drops a printed cross-reference", () => {
  assertEquals(
    stripParentheticals("Romesco Aioli (page 38)"),
    "Romesco Aioli",
  );
  assertEquals(
    stripParentheticals("Pretzel Buns (see page 97)"),
    "Pretzel Buns",
  );
  assertEquals(
    stripParentheticals("Garlic Butter (p. 17), melted"),
    "Garlic Butter, melted",
  );
});

Deno.test("stripParentheticals — nested and mid-phrase asides", () => {
  assertEquals(
    stripParentheticals("Tortilla chips (to serve (optional))"),
    "Tortilla chips",
  );
  assertEquals(
    stripParentheticals("coconut milk (400 g) tin"),
    "coconut milk tin",
  );
  assertEquals(stripParentheticals("(see below) aioli"), "aioli");
});

Deno.test("stripParentheticals — an unbalanced bracket is left alone", () => {
  // An unbalanced bracket truncates nothing: the tail survives.
  assertEquals(
    stripParentheticals("Romesco Aioli (page 38"),
    "Romesco Aioli (page 38",
  );
});

Deno.test("stripParentheticals — an all-aside line strips to nothing", () => {
  // The caller (recipeMatchText) falls back to the unstripped text here.
  assertEquals(stripParentheticals("(see the aioli recipe)"), "");
});

Deno.test("normalize — is unchanged by 8.6: parentheticals still reach it", () => {
  // The ingredient cascade must not move: gold and the benchmark are built on
  // these exact strings.
  assertEquals(normalize("coconut milk (400 g)"), "coconut milk");
  assertEquals(normalize("romesco aioli (page 38)"), "romesco aioli page");
});
