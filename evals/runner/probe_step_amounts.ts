// A paid probe of the import prompt's step amounts on the real model: three
// synthetic recipes, each step's tokens printed, and every expectation marked
// PASS or FAIL. A step's own amount (the can of water) must come back as an
// `amount` token; a food that IS a line, a time, a temperature, a pan size and
// equipment must not.
//
//   source ../.env.local   # ANTHROPIC_API_KEY
//   deno run --allow-read --allow-env --allow-net runner/probe_step_amounts.ts
//
// Synthetic text only: no recipe from a real source, no household data.

import { ClaudeHaikuAdapter } from "../../supabase/functions/_shared/adapters/claude.ts";
import {
  coerceExtractionResult,
  flattenLines,
} from "../../supabase/functions/_shared/adapters/schema.ts";
import type { StepToken } from "../../supabase/functions/_shared/types.ts";
import { UNIT_HINTS } from "./fixtures.ts";

/** The British word each American identity the prompt translates came from. */
const AMERICAN_OF: Record<string, string> = {
  zucchini: "courgette",
  eggplant: "aubergine",
  cilantro: "coriander",
  arugula: "rocket",
  shrimp: "prawns",
  canned: "tinned",
};

interface Expect {
  /** Words that must come back as one amount token, with this figure. */
  amounts: { text: string; qty: number; qty_high?: number; unit?: string }[];
  /** Words that must NOT be inside any amount token. */
  never: string[];
}

const CASES: { name: string; text: string; expect: Expect }[] = [
  {
    name: "chili: a can of water",
    text: `Weeknight Chili
Serves 4
Ingredients
1 tbsp olive oil
1 onion, diced
500 g beef mince
1 can (14.5 oz) crushed tomatoes
2 tsp chilli powder
Method
1. Heat the olive oil in a large pot and fry the onion for 5 minutes.
2. Add the beef mince and brown it, breaking it up.
3. Stir in the chilli powder.
4. Next add the crushed tomatoes, crushing them with your hands as you add them. Fill one empty can with water and add that in along with the rest. Simmer for 30 to 40 minutes.`,
    expect: {
      amounts: [{ text: "one empty can", qty: 1 }],
      never: ["5 minutes", "30 to 40 minutes", "tomatoes"],
    },
  },
  {
    name: "pasta: the pasta water",
    text: `Lemon Spaghetti
Serves 2
Ingredients
200 g spaghetti
1 lemon, zested and juiced
40 g parmesan, grated
2 tbsp butter
Method
1. Cook the spaghetti in a large pan of salted water for 10 minutes. Before draining, scoop out 1 cup of the pasta water.
2. Melt the butter, add the lemon zest and juice, then the spaghetti and 4 tablespoons of the pasta water. Toss with the parmesan, adding 2 to 3 more tablespoons of water if it looks dry.`,
    expect: {
      amounts: [
        { text: "1 cup", qty: 1 },
        { text: "4 tablespoons", qty: 4 },
        { text: "2 to 3 more tablespoons", qty: 2, qty_high: 3 },
      ],
      never: ["10 minutes", "200 g", "butter"],
    },
  },
  {
    name: "curry: an amount printed two ways",
    text: `Quick Chickpea Curry
Serves 4
Ingredients
1 can chickpeas, drained
2 tbsp curry paste
100 g spinach
Method
1. Blend the curry paste with 60–80ml (4–5 tbsp) water until smooth.
2. Simmer with the chickpeas for 10 minutes, then wilt in the spinach.`,
    expect: {
      amounts: [{ text: "4–5 tbsp", qty: 4, qty_high: 5, unit: "tbsp" }],
      never: ["10 minutes", "chickpeas"],
    },
  },
  {
    name: "traybake: nothing to scale",
    text: `Roast Vegetables
Serves 4
Ingredients
2 red peppers
1 courgette
2 tbsp olive oil
Method
1. Preheat the oven to 200°C. Line 2 baking sheets with paper.
2. Toss the red peppers and courgette with the olive oil in a 9-inch dish and roast for 25 minutes.`,
    expect: {
      amounts: [],
      never: ["200°C", "2 baking sheets", "9-inch", "25 minutes"],
    },
  },
];

/** `tbsp`, `tablespoon` and `tablespoons` name one spoon; likewise tsp. */
function sameSpoon(said: string | null, want: string): boolean {
  const spoon = (u: string) =>
    u.toLowerCase().replace(/^tablespoons?$/, "tbsp").replace(
      /^teaspoons?$/,
      "tsp",
    );
  return said !== null && spoon(said) === spoon(want);
}

function show(tokens: StepToken[]): string {
  return tokens.map((t) => {
    switch (t.t) {
      case "text":
        return t.s;
      case "ref":
        return `[${t.label}]`;
      case "timer":
        return `⏱${t.low_seconds}-${t.high_seconds}s`;
      case "amount":
        return `{${t.text} = ${t.qty}${t.qty_high ? `–${t.qty_high}` : ""} ${
          t.unit ?? ""
        }}`;
    }
  }).join("");
}

const adapter = new ClaudeHaikuAdapter();
let failed = 0;
for (const c of CASES) {
  const raw = await adapter.sanitize(
    { source: "page_text", url: null, jsonld: null, text: c.text },
    UNIT_HINTS,
  );
  const result = coerceExtractionResult(raw);
  console.log(`\n== ${c.name} (${adapter.model})`);
  // The ingredient list is the recipe's; a step's water is an amount, never
  // a line the model adds. Every line must name a food the list printed.
  const printed = c.text.slice(
    c.text.indexOf("Ingredients"),
    c.text.indexOf("Method"),
  ).toLowerCase();
  const lines = flattenLines(result);
  console.log(
    `  lines: ${lines.map((l) => l.ingredient_text).join(" · ")}`,
  );
  for (const l of lines) {
    const head = l.ingredient_text.toLowerCase().split(/[ ,]/)[0];
    // The prompt's one allowed identity translation, British → American.
    const british = AMERICAN_OF[head];
    const ok = printed.includes(head) ||
      (british !== undefined && printed.includes(british));
    if (!ok) failed++;
    console.log(
      `  ${ok ? "PASS" : "FAIL"} line "${l.ingredient_text}" is in the list`,
    );
  }
  // Word for word: a step rebuilt from its tokens reads as the printed step,
  // its times aside (a timer token carries no words).
  const printedSteps = c.text.slice(c.text.indexOf("Method"))
    .split("\n").filter((l) => /^\d+\. /.test(l))
    .map((l) => l.replace(/^\d+\. /, ""));
  const words = (t: string) =>
    t.toLowerCase()
      .replace(/\b\d+(?:\s*(?:to|-|–)\s*\d+)?\s*minutes?\b/g, " ")
      .replace(/[^a-z0-9½¼¾⅓⅔–\-]+/g, " ")
      .trim().split(/\s+/).filter(Boolean).join(" ");
  for (const [i, step] of result.steps.entries()) {
    const rebuilt = step.tokens.map((t) =>
      t.t === "text"
        ? t.s
        : t.t === "ref"
        ? t.label
        : t.t === "amount"
        ? t.text
        : " "
    ).join(" ");
    const want = words(printedSteps[i] ?? "");
    const got = words(rebuilt);
    const ok = want === got;
    if (!ok) failed++;
    console.log(`  ${ok ? "PASS" : "FAIL"} step ${i + 1} reads as printed`);
    if (!ok) console.log(`     printed: ${want}\n     rebuilt: ${got}`);
  }
  const amounts: StepToken[] = [];
  for (const [i, step] of result.steps.entries()) {
    console.log(`  ${i + 1}. ${show(step.tokens)}`);
    amounts.push(...step.tokens.filter((t) => t.t === "amount"));
  }
  const said = amounts.flatMap((t) => (t.t === "amount" ? [t] : []));
  for (const want of c.expect.amounts) {
    const hit = said.find((t) =>
      t.text.toLowerCase().includes(want.text.toLowerCase()) ||
      want.text.toLowerCase().includes(t.text.toLowerCase())
    );
    const ok = hit !== undefined && hit.qty === want.qty &&
      (want.qty_high === undefined || hit.qty_high === want.qty_high) &&
      (want.unit === undefined || sameSpoon(hit.unit, want.unit));
    if (!ok) failed++;
    console.log(
      `  ${ok ? "PASS" : "FAIL"} amount "${want.text}" = ${want.qty}${
        want.qty_high ? `–${want.qty_high}` : ""
      }`,
    );
  }
  for (const words of c.expect.never) {
    const bad = said.find((t) =>
      t.text.toLowerCase().includes(words.toLowerCase())
    );
    if (bad) failed++;
    console.log(`  ${bad ? "FAIL" : "PASS"} no amount over "${words}"`);
  }
}
console.log(`\n${failed === 0 ? "ALL PASS" : `${failed} FAILED`}`);
if (failed > 0) Deno.exit(1);
