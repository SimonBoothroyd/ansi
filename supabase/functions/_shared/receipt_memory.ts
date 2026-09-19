// The receipt door's memory: what this household has already said about a
// printed name, read off its OWN saved receipt lines.
//
// A whole-string trigram cannot score `ORG TRICOLOR QUINOA` against `Quinoa`
// above the suggest floor, and no tuning fixes that in general — the words are
// one store's abbreviations, not a language. What fixes it is the household:
// once somebody has said, on one receipt, what that line is, the next receipt
// does not have to guess.
//
// **This is not an alias and must never become one.** The vocabulary is the
// household's own language; a store's shorthand put into it would surface in
// every recipe import, every picker and every search. Nothing here is written
// anywhere — the module is one SELECT — the match cascade never sees these
// words, and `import-receipt/no_alias.test.ts` holds both facts structurally.
//
// Three properties come from the memory BEING the saved lines, and they are
// the reason it is shaped this way rather than as a second table:
//
//   * **Nothing to maintain.** A receipt already records what was said about
//     it, beside the words it was said about.
//   * **A mistake is corrected where it was made.** A saved receipt is
//     editable, and the most recently said answer wins — so correcting an old
//     receipt corrects the memory, with no second list to also correct.
//   * **A retired row cannot come back.** The answer is read through the
//     ingredient, so a match to something the household has since retired is
//     not an answer any more, and the cascade gets the line instead.
//
// The household is the caller's, from the verified token, and never the
// body's. The connection this runs on is service-role, so RLS does not narrow
// anything: the `household_id = $1` predicate below is the whole fence.

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
 * How a printed name is compared: trimmed and upper-cased, and NOTHING else.
 *
 * Exact, deliberately. Fuzzy matching is the cascade's job and it has a
 * calibrated floor; a second, looser matcher here would resolve lines the
 * cascade honestly refused and do it with `confidence: 1` on its face.
 */
export function recallKey(name: string): string {
  return name.trim().toUpperCase();
}

/**
 * One query for the whole receipt: every printed name rides as one `text[]`,
 * so nothing about this SQL grows with the line count.
 *
 * `distinct on (q.name)` with `updated_at desc` is the latest-wins rule, and
 * it is the whole answer to "how do I take a wrong match back": you edit the
 * receipt you got wrong, and its lines become the most recent thing said.
 * `l.id desc` is the tiebreak, so two lines stamped in the same millisecond
 * cannot make the answer depend on the plan.
 *
 * The `where` runs BEFORE that pick, which is what makes it *the latest LIVE
 * answer*: an item line whose row has been retired, or that nobody ever
 * matched, is not an answer at all, and an older line that still stands is
 * used instead.
 *
 * `upper(l.name_printed)` is spelled exactly as migration 0047's index is, or
 * the index is not used.
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

/**
 * The live recall, bound to one household.
 *
 * Empty in, empty out, without a round trip: a receipt whose reader named
 * nothing has nothing to ask about.
 */
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
      // The `where` above already refuses an item line with no live row; this
      // is the same refusal said in TS, so a change to one cannot quietly
      // produce a match to nothing.
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
