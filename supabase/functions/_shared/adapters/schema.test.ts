import { assert, assertEquals, assertThrows } from "@std/assert";
import {
  CAPS,
  coerceExtractionResult,
  ExtractionParseError,
  MAX_PARSE_WARNINGS,
  structuralIssues,
  titleCaseIfUncased,
  validateExtractionResult,
} from "./schema.ts";
import type { ExtractionResult, RefToken, TextToken } from "../types.ts";

// The narrowest payload that coerces: every required field, nothing extra.
const MINIMAL = {
  title: "T",
  servings_base: 2,
  servings_raw: "Serves 2",
  yield_raw: null,
  total_time_seconds: { low_seconds: 600, high_seconds: 600 },
  cook_time_seconds: null,
  truncated: false,
  image_quality: "ok",
  parse_warnings: [],
  groups: [{ name: null, line_items: [] }],
  steps: [],
};

const lineItem = (over: Record<string, unknown> = {}) => ({
  qty: 1,
  qty_low: null,
  qty_high: null,
  unit: "g",
  unit_mappable: true,
  ingredient_text: "onion",
  notes: null,
  raw_amount: "1 g",
  optional: false,
  confidence: 0.9,
  ...over,
});

// --- coerceExtractionResult ---------------------------------------------------

Deno.test("coerceExtractionResult — a payload that is not an object throws", () => {
  for (const bad of [null, undefined, 42, "{}", [], true]) {
    assertThrows(
      () => coerceExtractionResult(bad),
      ExtractionParseError,
      undefined,
      `expected a throw for ${JSON.stringify(bad) ?? "undefined"}`,
    );
  }
});

Deno.test("coerceExtractionResult — missing fields default the honest way", () => {
  const r = coerceExtractionResult({});
  assertEquals(
    r,
    {
      title: "",
      servings_base: null,
      servings_raw: null,
      yield_raw: null,
      total_time_seconds: null,
      cook_time_seconds: null,
      truncated: false,
      image_quality: "ok",
      parse_warnings: [],
      groups: [],
      steps: [],
    } satisfies ExtractionResult,
  );
});

Deno.test("coerceExtractionResult — wrong types coerce or null out, never throw", () => {
  const cases: [string, unknown, (r: ExtractionResult) => unknown, unknown][] =
    [
      [
        "numeric string qty",
        { groups: [{ line_items: [lineItem({ qty: "2" })] }] },
        (r) => r.groups[0].line_items[0].qty,
        2,
      ],
      [
        "unparseable qty",
        { groups: [{ line_items: [lineItem({ qty: "lots" })] }] },
        (r) => r.groups[0].line_items[0].qty,
        null,
      ],
      [
        "NaN-ish confidence",
        { groups: [{ line_items: [lineItem({ confidence: null })] }] },
        (r) => r.groups[0].line_items[0].confidence,
        0,
      ],
      [
        "non-boolean optional",
        { groups: [{ line_items: [lineItem({ optional: "yes" })] }] },
        (r) => r.groups[0].line_items[0].optional,
        false,
      ],
      [
        "fractional servings round",
        { servings_base: 3.6 },
        (r) => r.servings_base,
        4,
      ],
      [
        "bogus image_quality",
        { image_quality: "sublime" },
        (r) => r.image_quality,
        "ok",
      ],
      [
        "bare-number time",
        { total_time_seconds: 900 },
        (r) => r.total_time_seconds,
        900,
      ],
      [
        "equal range collapses",
        { cook_time_seconds: { low_seconds: 60, high_seconds: 60 } },
        (r) => r.cook_time_seconds,
        60,
      ],
      [
        "real range survives",
        { cook_time_seconds: { low_seconds: 60, high_seconds: 90 } },
        (r) => r.cook_time_seconds,
        { low_seconds: 60, high_seconds: 90 },
      ],
      ["groups not an array", { groups: "nope" }, (r) => r.groups, []],
      [
        "line_items not an array",
        { groups: [{ name: "g", line_items: 7 }] },
        (r) => r.groups[0].line_items,
        [],
      ],
      [
        "warnings stringified",
        { parse_warnings: [1, null, "x"] },
        (r) => r.parse_warnings,
        ["1", "null", "x"],
      ],
    ];
  for (const [label, raw, pick, want] of cases) {
    assertEquals(pick(coerceExtractionResult(raw)), want, label);
  }
});

Deno.test("coerceExtractionResult — extra keys are dropped, not carried", () => {
  const r = coerceExtractionResult({
    ...MINIMAL,
    nutrition: { calories: 900 },
    groups: [{
      name: "g",
      line_items: [lineItem({ brand: "Acme" })],
      extra: 1,
    }],
  });
  assert(!("nutrition" in r));
  assert(!("extra" in r.groups[0]));
  assert(!("brand" in r.groups[0].line_items[0]));
});

Deno.test("coerceExtractionResult — an unknown token kind is dropped", () => {
  const r = coerceExtractionResult({
    ...MINIMAL,
    steps: [{
      tokens: [{ t: "text", s: "a" }, { t: "sing" }, {
        t: "timer",
        low_seconds: 5,
      }],
    }],
  });
  assertEquals(r.steps[0].tokens.map((t) => t.t), ["text", "timer"]);
  assertEquals(r.steps[0].tokens[1], {
    t: "timer",
    low_seconds: 5,
    high_seconds: 5, // a lone bound mirrors, it does not invent a second one
  });
});

Deno.test("coerceExtractionResult — null refs filtered; a string is a key (unknown ⇒ -1)", () => {
  // Strings are line keys now, not junk: an unknown one resolves to -1 so the
  // out-of-range machinery reports and demotes it, same as a bad index.
  const r = coerceExtractionResult({
    ...MINIMAL,
    steps: [{ tokens: [{ t: "ref", refs: [0, "x", null, 2], label: "L" }] }],
  });
  assertEquals((r.steps[0].tokens[0] as RefToken).refs, [0, -1, 2]);
});

Deno.test("coerceExtractionResult — every string field is capped", () => {
  const long = "z".repeat(20_000);
  const r = coerceExtractionResult({
    ...MINIMAL,
    title: long,
    servings_raw: long,
    yield_raw: long,
    parse_warnings: [long],
    groups: [{
      name: long,
      line_items: [
        lineItem({
          ingredient_text: long,
          notes: long,
          raw_amount: long,
          unit: long,
        }),
      ],
    }],
    steps: [{
      tokens: [
        { t: "text", s: long },
        {
          t: "ref",
          refs: [0],
          label: long,
          portion: { qualifier: long, unit: long },
        },
      ],
    }],
  });
  const li = r.groups[0].line_items[0];
  assertEquals(r.title.length, CAPS.title);
  assertEquals(r.servings_raw?.length, CAPS.servings_raw);
  assertEquals(r.yield_raw?.length, CAPS.yield_raw);
  assertEquals(r.parse_warnings[0].length, CAPS.parse_warning);
  assertEquals(r.groups[0].name?.length, CAPS.group_name);
  assertEquals(li.ingredient_text.length, CAPS.ingredient_text);
  assertEquals(li.notes?.length, CAPS.notes);
  assertEquals(li.raw_amount.length, CAPS.raw_amount);
  assertEquals(li.unit?.length, CAPS.unit);
  assertEquals((r.steps[0].tokens[0] as TextToken).s.length, CAPS.step_text);
  const ref = r.steps[0].tokens[1] as RefToken;
  assertEquals(ref.label.length, CAPS.label);
  assertEquals(ref.portion?.qualifier?.length, CAPS.qualifier);
});

Deno.test("coerceExtractionResult — a warning storm is bounded", () => {
  const r = coerceExtractionResult({
    ...MINIMAL,
    parse_warnings: Array.from({ length: 5_000 }, (_, i) => `w${i}`),
  });
  assertEquals(r.parse_warnings.length, MAX_PARSE_WARNINGS);
  assertEquals(r.parse_warnings[0], "w0"); // the first ones are kept
});

// --- structuralIssues ---------------------------------------------------------

function resultWith(
  lines: number,
  steps: ExtractionResult["steps"],
  over: Partial<ExtractionResult> = {},
): ExtractionResult {
  return coerceExtractionResult({
    ...MINIMAL,
    groups: [{
      name: null,
      line_items: Array.from({ length: lines }, () => lineItem()),
    }],
    steps,
    ...over,
  });
}

Deno.test("structuralIssues — clean payload has none", () => {
  const r = resultWith(2, [{
    tokens: [{
      t: "ref",
      refs: [0, 1],
      label: "both",
      mention: "new",
      portion: null,
    }],
  }]);
  assertEquals(structuralIssues(r), []);
});

Deno.test("structuralIssues — the detectable self-inconsistencies", () => {
  const cases: [string, ExtractionResult, string][] = [
    [
      "qty AND a range",
      coerceExtractionResult({
        ...MINIMAL,
        groups: [{
          line_items: [lineItem({ qty: 1, qty_low: 1, qty_high: 2 })],
        }],
      }),
      "range_with_single_qty",
    ],
    [
      "a line with no identity",
      coerceExtractionResult({
        ...MINIMAL,
        groups: [{ line_items: [lineItem({ ingredient_text: "  " })] }],
      }),
      "empty_ingredient_text",
    ],
    [
      "a ref past the end",
      resultWith(1, [{
        tokens: [{
          t: "ref",
          refs: [5],
          label: "x",
          mention: "new",
          portion: null,
        }],
      }]),
      "ref_out_of_range",
    ],
    [
      "a negative ref",
      resultWith(1, [{
        tokens: [{
          t: "ref",
          refs: [-1],
          label: "x",
          mention: "new",
          portion: null,
        }],
      }]),
      "ref_out_of_range",
    ],
    [
      "a portion with qty AND a range",
      resultWith(1, [{
        tokens: [{
          t: "ref",
          refs: [0],
          label: "x",
          mention: "new",
          portion: {
            qty: 1,
            qty_low: 1,
            qty_high: 2,
            unit: null,
            qualifier: null,
          },
        }],
      }]),
      "portion_qty_and_range",
    ],
  ];
  for (const [label, result, kind] of cases) {
    const kinds = structuralIssues(result).map((i) => i.kind);
    assert(kinds.includes(kind as never), `${label}: got ${kinds.join(",")}`);
  }
});

// --- validateExtractionResult -------------------------------------------------

Deno.test("validateExtractionResult — a clean result passes through unchanged", () => {
  const r = resultWith(1, [{ tokens: [{ t: "text", s: "stir" }] }]);
  assertEquals(validateExtractionResult(r), r);
});

Deno.test("validateExtractionResult — out-of-range refs are DROPPED, not shipped", () => {
  // 2 lines; the token points at 0 (valid) and 9 (not).
  const r = validateExtractionResult(
    resultWith(2, [{
      tokens: [{
        t: "ref",
        refs: [0, 9],
        label: "onion",
        mention: "new",
        portion: null,
      }],
    }]),
  );
  const tok = r.steps[0].tokens[0] as RefToken;
  assertEquals(tok.t, "ref");
  assertEquals(tok.refs, [0]); // the impossible index is gone
  assert(r.parse_warnings.some((w) => w.includes("ref_out_of_range")));
});

Deno.test("validateExtractionResult — a wholly-invalid ref demotes to its label text", () => {
  const r = validateExtractionResult(
    resultWith(1, [{
      tokens: [
        { t: "text", s: "add " },
        {
          t: "ref",
          refs: [7, 8],
          label: "the sauce",
          mention: "new",
          portion: null,
        },
      ],
    }]),
  );
  assertEquals(r.steps[0].tokens.map((t) => t.t), ["text", "text"]);
  // The leading determiner relocates into the preceding text token BEFORE the
  // demotion, so the sentence still reads "add the sauce" across the two spans.
  assertEquals((r.steps[0].tokens[0] as TextToken).s, "add the ");
  assertEquals((r.steps[0].tokens[1] as TextToken).s, "sauce");
});

Deno.test("validateExtractionResult — an unlabelled invalid ref is removed entirely", () => {
  const r = validateExtractionResult(
    resultWith(1, [{
      tokens: [{
        t: "ref",
        refs: [7],
        label: "",
        mention: "new",
        portion: null,
      }],
    }]),
  );
  assertEquals(r.steps[0].tokens, []);
});

Deno.test("validateExtractionResult — other issues are reported, not repaired", () => {
  // Honest numbers: a contradictory quantity is flagged for the human, and the
  // payload still carries exactly what the model said.
  const raw = coerceExtractionResult({
    ...MINIMAL,
    groups: [{ line_items: [lineItem({ qty: 1, qty_low: 1, qty_high: 2 })] }],
  });
  const r = validateExtractionResult(raw);
  assertEquals(r.groups, raw.groups);
  assert(r.parse_warnings.some((w) => w.includes("range_with_single_qty")));
});

Deno.test("validateExtractionResult — existing warnings are preserved", () => {
  const r = validateExtractionResult(
    resultWith(1, [{
      tokens: [{
        t: "ref",
        refs: [4],
        label: "x",
        mention: "new",
        portion: null,
      }],
    }], {
      parse_warnings: ["light grey type"],
    }),
  );
  assertEquals(r.parse_warnings[0], "light grey type");
  assertEquals(r.parse_warnings.length, 2);
});

Deno.test("coerce — string refs resolve through minted line keys", () => {
  const r = coerceExtractionResult({
    groups: [
      { name: "sauce", line_items: [{ key: "kale", ingredient_text: "kale" }] },
      {
        name: null,
        line_items: [
          { key: "salt", ingredient_text: "sea salt" },
          { key: "salt-2", ingredient_text: "smoked salt" },
        ],
      },
    ],
    steps: [{
      tokens: [{
        t: "ref",
        refs: ["salt-2", "kale"],
        label: "smoked salt",
        mention: "new",
        portion: null,
      }],
    }],
  });
  const tok = r.steps[0].tokens[0] as RefToken;
  // keys resolve to FLATTENED indices across groups, in printed order
  assertEquals(tok.refs, [2, 0]);
});

Deno.test("coerce — integer refs still resolve (legacy replay)", () => {
  const r = coerceExtractionResult({
    groups: [{
      name: null,
      line_items: [{ ingredient_text: "onion" }, { ingredient_text: "kale" }],
    }],
    steps: [{
      tokens: [
        { t: "ref", refs: [1], label: "kale", mention: "new", portion: null },
      ],
    }],
  });
  assertEquals((r.steps[0].tokens[0] as RefToken).refs, [1]);
});

Deno.test("coerce+validate — an unknown key degrades exactly like a bad index", () => {
  const r = validateExtractionResult(coerceExtractionResult({
    groups: [{
      name: null,
      line_items: [{ key: "kale", ingredient_text: "kale" }],
    }],
    steps: [{
      tokens: [{
        t: "ref",
        refs: ["no-such-key"],
        label: "basil",
        mention: "new",
        portion: null,
      }],
    }],
  }));
  // demoted to its label as plain text (dropOutOfRangeRefs) + warned
  assertEquals(r.steps[0].tokens, [{ t: "text", s: "basil" }]);
  assert(r.parse_warnings.some((w) => w.includes("ref_out_of_range")));
});

Deno.test("coerce — a leading determiner relocates into the preceding text token", () => {
  const r = coerceExtractionResult({
    groups: [{
      name: null,
      line_items: [{ key: "kale", ingredient_text: "kale" }],
    }],
    steps: [{
      tokens: [
        { t: "text", s: "Add " },
        {
          t: "ref",
          refs: ["kale"],
          label: "the kale",
          mention: "new",
          portion: null,
        },
      ],
    }],
  });
  assertEquals(r.steps[0].tokens, [
    { t: "text", s: "Add the " },
    { t: "ref", refs: [0], label: "kale", mention: "new", portion: null },
  ]);
});

Deno.test("coerce — a determiner opening a step gets its own text token", () => {
  const r = coerceExtractionResult({
    groups: [{
      name: null,
      line_items: [{ key: "kale", ingredient_text: "kale" }],
    }],
    steps: [{
      tokens: [
        {
          t: "ref",
          refs: ["kale"],
          label: "The kale",
          mention: "new",
          portion: null,
        },
        { t: "text", s: " goes in last." },
      ],
    }],
  });
  assertEquals(r.steps[0].tokens, [
    { t: "text", s: "The " },
    { t: "ref", refs: [0], label: "kale", mention: "new", portion: null },
    { t: "text", s: " goes in last." },
  ]);
});

Deno.test("coerce — name-internal grammar is NOT relocated (cream of tartar)", () => {
  const r = coerceExtractionResult({
    groups: [{
      name: null,
      line_items: [{ key: "cot", ingredient_text: "cream of tartar" }],
    }],
    steps: [{
      tokens: [
        { t: "text", s: "Whisk in the " },
        {
          t: "ref",
          refs: ["cot"],
          label: "cream of tartar",
          mention: "new",
          portion: null,
        },
      ],
    }],
  });
  assertEquals((r.steps[0].tokens[1] as RefToken).label, "cream of tartar");
});

Deno.test("decodeClaudeSanitize — a two-phase wrapper merges lines and steps", async () => {
  const { decodeClaudeSanitize } = await import("./claude.ts");
  const asResponse = (obj: unknown) => ({
    content: [{ type: "text", text: JSON.stringify(obj) }],
    stop_reason: "end_turn",
  });
  const r = decodeClaudeSanitize({
    two_phase: true,
    lines: asResponse({
      title: "Two Phase Stew",
      groups: [{
        name: null,
        line_items: [
          { key: "kale", ingredient_text: "kale" },
          { key: "salt", ingredient_text: "sea salt" },
        ],
      }],
      steps: [], // phase 1 emits none
    }),
    steps: asResponse({
      steps: [{
        tokens: [
          { t: "text", s: "Massage the " },
          {
            t: "ref",
            refs: ["kale"],
            label: "kale",
            mention: "new",
            portion: null,
          },
        ],
      }],
    }),
  });
  assertEquals(r.title, "Two Phase Stew");
  assertEquals(r.groups[0].line_items.length, 2);
  assertEquals(r.steps.length, 1);
  const tok = r.steps[0].tokens[1] as RefToken;
  assertEquals(tok.refs, [0]); // "kale" key resolved against the phase-1 lines
});

// --- the title arrives cased like a title ------------------------------------
//
// A photographed page shouts and a scraped one sometimes whispers; neither is
// a decision the page made about capitalisation, so we supply the ordinary
// one. A page that DID decide is left alone — the words, the order, the
// punctuation and any case it actually carries are all the page's.

Deno.test("a SHOUTED title is title-cased", () => {
  assertEquals(titleCaseIfUncased("PEANUT TOFU NOODLES"), "Peanut Tofu Noodles");
});

Deno.test("a whispered title is too", () => {
  assertEquals(titleCaseIfUncased("peanut tofu noodles"), "Peanut Tofu Noodles");
});

Deno.test("small words stay small, except at either end", () => {
  assertEquals(titleCaseIfUncased("SOUP OF THE DAY"), "Soup of the Day");
});

Deno.test("a MIXED-case title is left exactly alone", () => {
  assertEquals(titleCaseIfUncased("PIZZA alla Norma"), "PIZZA alla Norma");
});

Deno.test("punctuation and non-words are the page's", () => {
  assertEquals(titleCaseIfUncased("mac & cheese"), "Mac & Cheese");
});

Deno.test("a title with no letters at all is untouched", () => {
  assertEquals(titleCaseIfUncased("101"), "101");
  assertEquals(titleCaseIfUncased(""), "");
});

Deno.test("a word opening with a digit is an amount, not a word", () => {
  assertEquals(titleCaseIfUncased("400G BROWNIES"), "400g Brownies");
});

Deno.test("a small word that OPENS the title is capitalised", () => {
  assertEquals(titleCaseIfUncased("THE BEST BROWNIES"), "The Best Brownies");
});

Deno.test("à la survives a shouting page", () => {
  assertEquals(titleCaseIfUncased("CHICKEN À LA KING"), "Chicken à la King");
});

Deno.test("the page's own spacing survives", () => {
  assertEquals(
    titleCaseIfUncased("  SOUP  OF  THE DAY "),
    "  Soup  of  the Day ",
  );
});

Deno.test("the sanitizer applies it at the one choke point", () => {
  const r = coerceExtractionResult({ ...MINIMAL, title: "PEANUT TOFU NOODLES" });
  assertEquals(r.title, "Peanut Tofu Noodles");
});

Deno.test("and leaves a title that carries its own case", () => {
  const r = coerceExtractionResult({ ...MINIMAL, title: "PIZZA alla Norma" });
  assertEquals(r.title, "PIZZA alla Norma");
});
