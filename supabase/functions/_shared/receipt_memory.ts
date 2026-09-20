// The receipt door's memory: what this household has already said about a
// printed name, read off its own saved receipt lines with one SELECT. It is
// never an alias and writes nothing (`import-receipt/no_alias.test.ts`); the
// design is `docs/product-specs/import-and-matching.md` §12.
//
// The household is the caller's, from the verified token, never the body's.
// The connection is service-role, so RLS narrows nothing: the
// `household_id = $1` predicates below are the whole fence.

import type { SqlExecutor } from "./match_db.ts";

/** What the household said about a printed name, the last time they said it. */
export type RememberedAnswer =
  | { kind: "item"; ingredient_id: string }
  | { kind: "not_food" };

/** Remembered answers by {@link recallKey}. Absent means nothing is known. */
export type ReceiptMemory = ReadonlyMap<string, RememberedAnswer>;

/** The recall seam — the household-scoped lookup, pre-bound at integration. */
export type RecallMatchesFn = (names: string[]) => Promise<ReceiptMemory>;

/**
 * How a printed name is compared: trimmed and upper-cased, nothing else —
 * fuzzy matching is the cascade's job. Where JS and Postgres upper-case a
 * character differently the keys differ and the line is simply not recalled.
 */
export function recallKey(name: string): string {
  return name.trim().toUpperCase();
}

/**
 * One query for the whole receipt. `distinct on` with `updated_at desc` is
 * latest-wins, `l.id desc` its tiebreak; the `where` runs before the pick, so
 * a retired or never-matched line gives way to an older answer that stands.
 * `upper(l.name_printed)` is spelled as migration 0047's index is.
 *
 * `supabase/tests/receipts.sql` runs a copy of this text: change both.
 */
export const RECALL_SQL = `
  select distinct on (q.name)
         q.name as name,
         l.kind as kind,
         i.id::text as ingredient_id
  from unnest($2::text[]) as q(name)
  join receipt_line l
    on l.household_id = $1
   and l.deleted_at is null
   and l.kind in ('item', 'not_food')
   and upper(l.name_printed) = q.name
  left join ingredient i
    on i.id = l.ingredient_id
   and i.household_id = $1
   and i.deleted_at is null
  where l.kind = 'not_food' or i.id is not null
  order by q.name, l.updated_at desc, l.id desc`;

interface MemoryRow {
  name: string;
  kind: string;
  ingredient_id: string | null;
}

/** The live recall, bound to one household. Nothing to ask is no round trip. */
export function sqlReceiptMemory(
  exec: SqlExecutor,
  householdId: string,
): RecallMatchesFn {
  return async (names: string[]): Promise<ReceiptMemory> => {
    const answers = new Map<string, RememberedAnswer>();
    const keys = [...new Set(names.map(recallKey))].filter((k) => k !== "");
    if (keys.length === 0) return answers;
    const rows = await exec<MemoryRow>(RECALL_SQL, [householdId, keys]);
    for (const row of rows) {
      if (row.kind === "not_food") {
        answers.set(row.name, { kind: "not_food" });
        continue;
      }
      // The `where` already refuses an item line with no live row; said again
      // here so a change to the SQL cannot produce a match to nothing.
      if (row.ingredient_id) {
        answers.set(row.name, {
          kind: "item",
          ingredient_id: String(row.ingredient_id),
        });
      }
    }
    return answers;
  };
}
