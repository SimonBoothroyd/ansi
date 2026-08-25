import { assertEquals } from "jsr:@std/assert";
// import { normalize } from "./normalize.ts";

// Behaviour pinned up front (§7). Skipped until step 8 implements normalize().
Deno.test({
  name: "normalize — spec examples",
  ignore: true, // remove when normalize() is implemented
  fn: () => {
    // assertEquals(normalize("2 large Onions, diced"), "onion");
    // assertEquals(normalize("Chicken thighs, boneless"), "chicken thigh boneless");
    // assertEquals(normalize("1 can coconut milk"), "coconut milk");
    // assertEquals(normalize("fresh ginger, grated"), "ginger fresh");
    assertEquals(true, true);
  },
});
