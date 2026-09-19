// THE GUARANTEE: a receipt teaches the vocabulary nothing.
//
// Plan 0049's decision log, from the owner: "No alias learning from receipts.
// A receipt's words are one store's abbreviations, confirming one teaches the
// vocabulary nothing, and a whole-line alias scoped to a store was weighed and
// refused." The recipe pipeline does the opposite — a correction at review is
// written back as an alias (§8, the learning loop) — so this is not a thing
// that is merely absent by accident. It is a difference between two doors that
// share a cascade, and the kind of difference a later change quietly erases.
//
// The door DOES remember the household's own answers per printed name
// (`_shared/receipt_memory.ts`), and that is not a hole in this guarantee but
// the reason the guarantee can be kept at all: the memory is a SELECT over
// this household's own saved receipt lines, so a store's abbreviation stays on
// the receipt it was printed on and never enters the language the recipe door
// matches against.
//
// Two tests hold it, because either one alone can be walked around:
//
//   1. a SQL SPY under the real matcher AND the real recall, through the real
//      spine: whatever the function actually issues, all of it is a SELECT;
//   2. a SOURCE guard over every file the function owns: no alias table is
//      named and no write verb appears, so a write cannot be introduced
//      without this failing and being read.

import { assert, assertEquals } from "@std/assert";
import { importReceipt, type ReceiptDeps } from "./index.ts";
import { matchLines } from "../_shared/match.ts";
import { sqlVocabMatcher } from "../_shared/match_db.ts";
import { sqlReceiptMemory } from "../_shared/receipt_memory.ts";
import type { ReceiptAdapter } from "../_shared/receipt_types.ts";

const HH = "11111111-2222-3333-4444-555555555555";

/** A receipt whose every line WOULD teach something, if anything could. */
const adapter: ReceiptAdapter = {
  name: "fake",
  transcribe: () =>
    Promise.resolve([
      "TJ ORG BANANAS 3.49\nTJ MED CHDR SHRD 3.79\nBAG FEE 0.10",
    ]),
  structure: () =>
    Promise.resolve({
      store_printed: "TRADER JOE'S #135",
      purchased_at_printed: "09/13/26 05:42 PM",
      subtotal_printed: "7.38",
      tax_printed: null,
      total_printed: "7.38",
      lines: [
        {
          printed_text: "TJ ORG BANANAS 3.49",
          name_printed: "TJ ORG BANANAS",
          amount_printed: "3.49",
          discount_printed: null,
          kind: "item" as const,
          weight: null,
          low_confidence: false,
        },
        {
          printed_text: "TJ MED CHDR SHRD 3.79",
          name_printed: "TJ MED CHDR SHRD",
          amount_printed: "3.79",
          discount_printed: null,
          kind: "item" as const,
          weight: null,
          low_confidence: false,
        },
        {
          printed_text: "BAG FEE 0.10",
          name_printed: "BAG FEE",
          amount_printed: "0.10",
          discount_printed: null,
          kind: "not_food" as const,
          weight: null,
          low_confidence: false,
        },
      ],
      notes: [],
    }),
};

Deno.test("no alias — every statement the function issues is a SELECT", async () => {
  const issued: string[] = [];
  // The REAL Postgres-backed matcher over a spying executor: whatever SQL the
  // cascade would send, we see it, in the shape it would send it.
  const spy = (text: string) => {
    issued.push(text);
    return Promise.resolve([]);
  };
  const matcher = sqlVocabMatcher(spy, HH);
  const deps: ReceiptDeps = {
    adapter,
    matchLines: (lines) => matchLines(lines, matcher),
    // The REAL recall too: the match memory reads this household's own saved
    // lines, and "reads" is exactly the thing this test exists to hold.
    recallMatches: sqlReceiptMemory(spy, HH),
  };

  const payload = await importReceipt({ images: [new Uint8Array([1])] }, deps);
  assertEquals(payload.lines.length, 3);
  assert(issued.length > 0, "the cascade ran at all");

  for (const sql of issued) {
    const lower = sql.toLowerCase();
    assert(
      lower.trimStart().startsWith("\n  select") ||
        lower.trimStart().startsWith("select"),
      `not a select:\n${sql}`,
    );
    for (
      const verb of ["insert into", "update ", "delete from", "merge into"]
    ) {
      assert(!lower.includes(verb), `a write reached the database:\n${sql}`);
    }
  }
});

Deno.test("no alias — nothing in this function's own sources can write one", async () => {
  // Every file the receipt pipeline owns. Listed rather than crawled so that
  // ADDING one is a deliberate act: a new file not named here is caught by the
  // completeness check below.
  const OWNED = [
    "import-receipt/index.ts",
    "import-receipt/live.ts",
    "import-receipt/auth.ts",
    "import-receipt/replay.ts",
    "_shared/receipt_types.ts",
    "_shared/receipt_join.ts",
    "_shared/receipt_parse.ts",
    "_shared/receipt_assemble.ts",
    "_shared/receipt_memory.ts",
    "_shared/prompts/receipt.ts",
    "_shared/adapters/receipt_schema.ts",
    "_shared/adapters/claude_receipt.ts",
  ];

  for (const path of OWNED) {
    const src = await Deno.readTextFile(new URL(`../${path}`, import.meta.url));
    const lower = src.toLowerCase();
    assert(
      !lower.includes("ingredient_alias"),
      `${path} names the alias table — a receipt must not write one`,
    );
    for (const verb of ["insert into", "delete from", "merge into"]) {
      assert(!lower.includes(verb), `${path} contains "${verb}"`);
    }
  }

  // Completeness: every non-test module in the function's own folder is on the
  // list above, so a file added tomorrow is covered or this fails today.
  const dir = new URL("./", import.meta.url);
  for await (const entry of Deno.readDir(dir)) {
    if (!entry.isFile || !entry.name.endsWith(".ts")) continue;
    if (entry.name.endsWith(".test.ts")) continue;
    assert(
      OWNED.includes(`import-receipt/${entry.name}`),
      `import-receipt/${entry.name} is not covered by the no-alias guard`,
    );
  }
});

Deno.test("no alias — the match cascade's DB module offers no writer to call", async () => {
  // The cascade's Postgres side is shared with the recipe door. If a write
  // contract is ever added there, a receipt must not be able to reach it by
  // simply importing the module it already imports.
  const src = await Deno.readTextFile(
    new URL("../_shared/match_db.ts", import.meta.url),
  );
  const exported = [...src.matchAll(/^export (?:async )?function (\w+)/gm)]
    .map((m) => m[1]);
  assertEquals(exported.sort(), ["sqlRecipeTitleMatcher", "sqlVocabMatcher"]);
});
