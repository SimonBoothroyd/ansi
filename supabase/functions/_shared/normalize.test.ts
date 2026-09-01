import { assertEquals } from "@std/assert";
import { normalize } from "./normalize.ts";

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
  // The same function runs on canonical_name at write time, so a tidy stored
  // name is already in its own normal form.
  assertEquals(normalize("Ginger, fresh"), "ginger fresh");
  assertEquals(normalize(normalize("fresh ginger")), normalize("fresh ginger"));
});

Deno.test("normalize — singularization edge cases", () => {
  assertEquals(normalize("tomatoes"), "tomato");
  assertEquals(normalize("berries"), "berry");
  assertEquals(normalize("asparagus"), "asparagus"); // not a plural
  // -ves: plain -s plurals, not -f (the regression that made "chives"→"chif")
  assertEquals(normalize("chives"), "chive");
  assertEquals(normalize("olives"), "olive");
  assertEquals(normalize("bay leaves"), "bay leaf"); // genuine -ves→-f (irregular)
});

Deno.test("normalize — preserves unicode letters", () => {
  assertEquals(normalize("jalapeño"), "jalapeño"); // not "jalapeo"
  assertEquals(normalize("2 jalapeños, diced"), "jalapeño");
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

Deno.test("normalize — a cut word is identity inside a canned phrase", () => {
  // The gold conventions' ruling (_SCHEMA.md): chopped / crushed / diced
  // tomatoes in a can are DIFFERENT PRODUCTS, so the cut cannot be stripped
  // as prep the way it is on a fresh tomato.
  assertEquals(normalize("Canned Diced Tomatoes"), "tomato canned diced");
  assertEquals(normalize("canned chopped tomatoes"), "tomato canned chopped");
  assertEquals(normalize("tinned chopped tomatoes"), "tinned tomato chopped");
  // It trails like any other state word, so word order doesn't matter.
  assertEquals(normalize("diced tomatoes, canned"), "tomato diced canned");

  // OUTSIDE a canned phrase the cut is prep, exactly as before — this is the
  // §7 own-goal guard read the other way round.
  assertEquals(normalize("diced tomatoes"), "tomato");
  assertEquals(normalize("2 diced tomatoes"), "tomato");
  assertEquals(normalize("1 onion, diced"), "onion");
  // The MEASURE "can" is not the STATE "canned": a line whose tin is the
  // amount is unaffected (this is eval case 7, which must not move).
  assertEquals(
    normalize("1  (28-ounce) can fire-roasted, chopped tomatoes"),
    "fire tomato roasted",
  );
  // "crushed" is not in the set — it still holds the generic canned key.
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
