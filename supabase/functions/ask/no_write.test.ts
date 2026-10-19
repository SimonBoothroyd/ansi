// THE GUARANTEE: this door issues no SQL at all. The household's rows reach
// the model only as tool results the app chose to send, and nothing the model
// says is written anywhere by this function.
//
// As at `read-label`, there is no database seam to spy on, so the guard is the
// stronger, simpler one: no file the function owns may name a statement, a
// driver or the connection string.

import { assert } from "@std/assert";

/** Every module the ask door owns, listed rather than crawled. */
const OWNED = [
  "ask/index.ts",
  "ask/live.ts",
  "ask/auth.ts",
  "_shared/ask_types.ts",
  "_shared/prompts/ask.ts",
  "_shared/adapters/claude_ask.ts",
];

/** A statement verb, the driver, and the connection string it would need. */
const FORBIDDEN = [
  "insert into",
  "update ",
  "delete from",
  "merge into",
  "select ",
  'from "postgres"',
  "supabase_db_url",
];

Deno.test("no write — nothing this function owns can reach the database", async () => {
  for (const path of OWNED) {
    const src = await Deno.readTextFile(new URL(`../${path}`, import.meta.url));
    const lower = src.toLowerCase();
    for (const needle of FORBIDDEN) {
      assert(
        !lower.includes(needle),
        `${path} contains "${needle}" — this door must issue no SQL`,
      );
    }
  }
});

Deno.test("no write — every module in the folder is covered by the guard", async () => {
  const dir = new URL("./", import.meta.url);
  for await (const entry of Deno.readDir(dir)) {
    if (!entry.isFile || !entry.name.endsWith(".ts")) continue;
    if (entry.name.endsWith(".test.ts")) continue;
    assert(
      OWNED.includes(`ask/${entry.name}`),
      `ask/${entry.name} is not covered by the no-write guard`,
    );
  }
});
