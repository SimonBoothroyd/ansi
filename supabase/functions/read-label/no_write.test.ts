// THE GUARANTEE: this door issues no SQL at all. It is read-only over one
// image — the reading goes back to the form as a draft, and the person's Save
// is the only thing that writes.
//
// The receipt door needs a SQL spy for its half of the same promise, because it
// legitimately SELECTs. This one has no database seam to spy on, so the guard is
// the stronger, simpler one: no file the function owns may name a statement, a
// driver or the connection string.

import { assert } from "@std/assert";

/** Every module the label door owns, listed rather than crawled. */
const OWNED = [
  "read-label/index.ts",
  "read-label/live.ts",
  "read-label/auth.ts",
  "_shared/label_types.ts",
  "_shared/prompts/label.ts",
  "_shared/adapters/label_schema.ts",
  "_shared/adapters/claude_label.ts",
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
      OWNED.includes(`read-label/${entry.name}`),
      `read-label/${entry.name} is not covered by the no-write guard`,
    );
  }
});
