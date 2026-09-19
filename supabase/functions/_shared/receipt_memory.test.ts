// The match memory: what it asks the database, and what it makes of the
// answer.
//
// The SQL itself is held here as text rather than run against a Postgres,
// which is the same bargain `match_db.test.ts` strikes: the two properties
// that make this correct — the household fence and latest-wins — are visible
// in the statement, and a change that dropped either would be a change to a
// string this file reads. `supabase/tests/receipts.sql` holds the column and
// the shape the statement stands on.

import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import { RECALL_SQL, recallKey, sqlReceiptMemory } from "./receipt_memory.ts";
import type { SqlExecutor } from "./match_db.ts";

const HH = "11111111-2222-3333-4444-555555555555";

/** Records every statement and its params; answers with `rows`. */
function spy(rows: Record<string, unknown>[] = []) {
  const calls: { text: string; params: unknown[] }[] = [];
  const exec = ((text: string, params: unknown[]) => {
    calls.push({ text, params });
    return Promise.resolve(rows);
  }) as SqlExecutor;
  return { exec, calls };
}

Deno.test("recallKey — trimmed and upper-cased, and nothing else", () => {
  assertEquals(recallKey("  org tricolor quinoa "), "ORG TRICOLOR QUINOA");
  assertEquals(recallKey("TJ ORG BANANAS"), "TJ ORG BANANAS");
  // No normalizing, no stemming, no fuzz: that is the cascade's job, and it
  // has a calibrated floor this lookup would be pretending to.
  assertEquals(recallKey("tj-org bananas"), "TJ-ORG BANANAS");
  assertEquals(recallKey("   "), "");
});

Deno.test("the statement says latest-wins, and says it deterministically", () => {
  // The whole answer to "how do I take a wrong match back": edit the receipt,
  // and its lines become the most recent thing said.
  assertStringIncludes(RECALL_SQL, "distinct on (q.name)");
  assertStringIncludes(
    RECALL_SQL,
    "order by q.name, l.updated_at desc, l.id desc",
  );
});

Deno.test("the statement fences the household, the tombstones and the kinds", () => {
  assertStringIncludes(RECALL_SQL, "l.household_id = $1");
  assertStringIncludes(RECALL_SQL, "l.deleted_at is null");
  assertStringIncludes(RECALL_SQL, "l.kind in ('item', 'not_food')");
  // Spelled as migration 0047's index is, or the index is not used.
  assertStringIncludes(RECALL_SQL, "upper(l.name_printed) = q.name");
});

Deno.test("the statement fences a retired row out of the answer", () => {
  // An item line whose row has been retired, or that nobody ever matched, is
  // not an answer — and the `where` runs before the pick, so an OLDER line
  // that still stands is used instead of nothing.
  assertStringIncludes(RECALL_SQL, "i.household_id = $1");
  assertStringIncludes(RECALL_SQL, "i.deleted_at is null");
  assertStringIncludes(
    RECALL_SQL,
    "where l.kind = 'not_food' or i.id is not null",
  );
});

Deno.test("one batched query, keyed, deduped, household first", async () => {
  const { exec, calls } = spy();
  await sqlReceiptMemory(exec, HH)([
    "  org tricolor quinoa ",
    "ORG TRICOLOR QUINOA",
    "TJ SRIRACHA",
  ]);
  assertEquals(calls.length, 1, "nothing about this grows with the line count");
  assertEquals(calls[0].text, RECALL_SQL);
  assertEquals(calls[0].params[0], HH);
  assertEquals(calls[0].params[1], ["ORG TRICOLOR QUINOA", "TJ SRIRACHA"]);
});

Deno.test("nothing to ask about is not a round trip", async () => {
  const { exec, calls } = spy();
  assertEquals((await sqlReceiptMemory(exec, HH)([])).size, 0);
  assertEquals((await sqlReceiptMemory(exec, HH)(["", "   "])).size, 0);
  assertEquals(calls.length, 0);
});

Deno.test("an item answer is the row the household said", async () => {
  const { exec } = spy([
    { name: "ORG TRICOLOR QUINOA", kind: "item", ingredient_id: "v-quinoa" },
  ]);
  const memory = await sqlReceiptMemory(exec, HH)(["org tricolor quinoa"]);
  assertEquals(memory.get("ORG TRICOLOR QUINOA"), {
    kind: "item",
    ingredient_id: "v-quinoa",
  });
});

Deno.test("a folded answer is a fold, and names no row", async () => {
  const { exec } = spy([
    { name: "PAPER TOWELS", kind: "not_food", ingredient_id: null },
  ]);
  const memory = await sqlReceiptMemory(exec, HH)(["PAPER TOWELS"]);
  assertEquals(memory.get("PAPER TOWELS"), { kind: "not_food" });
});

Deno.test("an item row naming nothing is no answer at all", async () => {
  // The `where` already refuses it; this is the same refusal said in TS, so a
  // change to one cannot quietly produce a match to nothing.
  const { exec } = spy([
    { name: "TJ ????", kind: "item", ingredient_id: null },
    { name: "TJ SRIRACHA", kind: "item", ingredient_id: "v-sriracha" },
  ]);
  const memory = await sqlReceiptMemory(exec, HH)(["TJ ????", "TJ SRIRACHA"]);
  assert(!memory.has("TJ ????"));
  assertEquals(memory.size, 1);
});

Deno.test("a name nobody has answered is simply absent", async () => {
  const { exec } = spy();
  const memory = await sqlReceiptMemory(exec, HH)(["TJ SOMETHING NEW"]);
  assertEquals(memory.size, 0);
  assertEquals(memory.get("TJ SOMETHING NEW"), undefined);
});
