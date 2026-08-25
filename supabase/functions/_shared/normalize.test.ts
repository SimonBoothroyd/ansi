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
});
