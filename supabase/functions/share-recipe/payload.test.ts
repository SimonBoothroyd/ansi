// The payload query against a real Postgres with every migration applied:
// which tokens answer, and that the rows it selects are the rows the page
// renders from.
//
// Runs only where `SHARE_TEST_DB_URL` names a disposable database (it inserts
// and rolls back): `supabase start` locally, or any Postgres with the
// migrations applied. Everywhere else it is reported as ignored, not passed.

import { assert, assertEquals } from "@std/assert";
import { loadSharePayload, type SqlExecutor } from "./payload.ts";
import { bundledRenderer } from "./bundle.ts";

function dbUrl(): string | undefined {
  try {
    return Deno.env.get("SHARE_TEST_DB_URL") || undefined;
  } catch {
    // `deno task test` grants a fixed list of variables; this is not one.
    return undefined;
  }
}

const url = dbUrl();

const A = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const B = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const LIVE = "LiveLiveLiveLiveLive_1";
const REVOKED = "RevokedRevokedRevoked1";
const DELETED = "DeletedDeletedDeleted1";

/** House A: the fixture's recipe, its butter, a stub, and three shares. */
const SEED = `
insert into household (id, name) values ('${A}', 'A'), ('${B}', 'B');
insert into ingredient (id, household_id, canonical_name, default_unit,
                        match_text, status, macros, macros_basis,
                        density_g_per_ml) values
 ('a0000000-0000-0000-0000-000000000001', '${A}', 'Udon', 'g', 'udon',
  'complete', '{"kcal":130,"protein":3,"carb":27,"fat":0.5}', 'g', null),
 ('a0000000-0000-0000-0000-000000000002', '${A}', 'Soy sauce', 'ml', 'soy',
  'complete', '{"kcal":53,"protein":8,"carb":5,"fat":0}', 'g', 1.2),
 ('a0000000-0000-0000-0000-000000000003', '${A}', 'Butter', 'g', 'butter',
  'complete', '{"kcal":717,"protein":0.9,"carb":0.1,"fat":81}', 'g', null),
 ('a0000000-0000-0000-0000-000000000004', '${A}', 'White miso', 'g', 'miso',
  'complete', '{"kcal":198,"protein":12,"carb":26,"fat":6}', 'g', null);
insert into recipe (id, household_id, title, servings_base, steps,
                    total_time_seconds, yield_qty, yield_unit, deleted_at) values
 ('a1000000-0000-0000-0000-000000000001', '${A}', 'Miso Noodles', 2,
  '["Boil the udon.","Toss with the miso butter and the soy."]', 1500,
  null, null, null),
 ('a1000000-0000-0000-0000-000000000002', '${A}', 'Miso butter', 1,
  '["Beat the butter and miso together."]', null, 150, 'g', null),
 ('a1000000-0000-0000-0000-000000000003', '${A}', 'Gone Stew', 2, '[]', null,
  null, null, now()),
 ('b1000000-0000-0000-0000-000000000001', '${B}', 'Dal', 2, '[]', null,
  null, null, null);
insert into recipe_measure (id, household_id, recipe_id, label, amount, unit)
values ('a2000000-0000-0000-0000-000000000001', '${A}',
        'a1000000-0000-0000-0000-000000000002', 'blob', 15, 'g');
insert into ingredient_group (id, household_id, recipe_id, sort_order) values
 ('a3000000-0000-0000-0000-000000000001', '${A}',
  'a1000000-0000-0000-0000-000000000001', 0),
 ('a3000000-0000-0000-0000-000000000002', '${A}',
  'a1000000-0000-0000-0000-000000000002', 0);
insert into recipe_line_item (id, household_id, group_id, ingredient_id,
                              sub_recipe_id, quantity, unit,
                              recipe_measure_id, note, sort_order) values
 ('a4000000-0000-0000-0000-000000000001', '${A}',
  'a3000000-0000-0000-0000-000000000001',
  'a0000000-0000-0000-0000-000000000001', null, 400, 'g', null, null, 0),
 ('a4000000-0000-0000-0000-000000000002', '${A}',
  'a3000000-0000-0000-0000-000000000001', null,
  'a1000000-0000-0000-0000-000000000002', 2, null,
  'a2000000-0000-0000-0000-000000000001', null, 1),
 ('a4000000-0000-0000-0000-000000000003', '${A}',
  'a3000000-0000-0000-0000-000000000001',
  'a0000000-0000-0000-0000-000000000002', null, 1, 'tbsp', null, 'light', 2),
 ('a4000000-0000-0000-0000-000000000004', '${A}',
  'a3000000-0000-0000-0000-000000000002',
  'a0000000-0000-0000-0000-000000000003', null, 100, 'g', null, null, 0),
 ('a4000000-0000-0000-0000-000000000005', '${A}',
  'a3000000-0000-0000-0000-000000000002',
  'a0000000-0000-0000-0000-000000000004', null, 50, 'g', null, null, 1);
insert into recipe_share (household_id, recipe_id, token, deleted_at) values
 ('${A}', 'a1000000-0000-0000-0000-000000000001', '${LIVE}', null),
 ('${A}', 'a1000000-0000-0000-0000-000000000001', '${REVOKED}', now()),
 ('${A}', 'a1000000-0000-0000-0000-000000000003', '${DELETED}', null);
`;

/** Runs [body] inside a transaction that is always rolled back. */
async function inRollback(
  body: (exec: SqlExecutor) => Promise<void>,
): Promise<void> {
  // Loaded only when a database was named, so the ignored run fetches no
  // driver: a specifier in a variable is resolved at run time, not ahead.
  const driver = "postgres";
  const { default: postgres } = await import(driver);
  const sql = postgres(url!, { prepare: false, max: 1, onnotice: () => {} });
  try {
    // deno-lint-ignore no-explicit-any
    await sql.begin(async (tx: any) => {
      await tx.unsafe(SEED);
      await body(<T>(text: string, params: unknown[]) =>
        tx.unsafe(text, params as never[]) as unknown as Promise<T[]>
      );
      throw new Rollback();
    }).catch((e: unknown) => {
      if (!(e instanceof Rollback)) throw e;
    });
  } finally {
    await sql.end();
  }
}

class Rollback extends Error {}

Deno.test({
  name: "a live token answers with the recipe and the sub-recipe it reaches",
  ignore: url === undefined,
  fn: () =>
    inRollback(async (exec) => {
      const payload = JSON.parse((await loadSharePayload(exec, LIVE))!);
      assertEquals(
        payload.recipes.map((r: { title: string }) => r.title),
        ["Miso Noodles", "Miso butter"],
      );
      assertEquals(payload.groups.length, 2);
      assertEquals(payload.lines.length, 5);
      assertEquals(payload.recipe_measures.length, 1);
      // Postgres JSON's own representation, read by recipe_rows.dart.
      const butter = payload.lines.find((l: { sub_title?: string }) =>
        l.sub_title === "Miso butter"
      );
      assertEquals(
        butter.recipe_measure_id,
        "a2000000-0000-0000-0000-000000000001",
      );
      assertEquals(butter.optional, false);
    }),
});

Deno.test({
  name: "the selected rows render the page the fixture does",
  ignore: url === undefined,
  fn: () =>
    inRollback(async (exec) => {
      const html = bundledRenderer()(
        (await loadSharePayload(exec, LIVE))!,
        "https://getansi.app/r/" + LIVE,
        "/r/share.js",
      );
      for (
        const expected of [
          '<span class="amt">2 blob (30 g)</span>',
          '<span class="note">, light</span>',
          "makes 150 g",
          "<dt>kcal</dt><dd>346</dd>",
        ]
      ) {
        assert(html.includes(expected), `missing: ${expected}`);
      }
    }),
});

Deno.test({
  name: "a revoked token, a deleted recipe or an unknown token answers nothing",
  ignore: url === undefined,
  fn: () =>
    inRollback(async (exec) => {
      assertEquals(await loadSharePayload(exec, REVOKED), null);
      assertEquals(await loadSharePayload(exec, DELETED), null);
      assertEquals(
        await loadSharePayload(exec, "NeverNeverNeverNever_1"),
        null,
      );
    }),
});

Deno.test("a token of the wrong shape never reaches the database", async () => {
  const exec: SqlExecutor = () => {
    throw new Error("the database was asked");
  };
  assertEquals(await loadSharePayload(exec, "short"), null);
  assertEquals(await loadSharePayload(exec, "x".repeat(22) + "/"), null);
  assertEquals(await loadSharePayload(exec, "' or 1=1 --aaaaaaaaaaaa"), null);
});
