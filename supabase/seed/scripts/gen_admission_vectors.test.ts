import { assert, assertEquals, assertMatch } from "@std/assert";
import { join } from "@std/path";
import {
  type AdmissionVector,
  BEGIN_MARKER,
  END_MARKER,
  readVectors,
  renderBlock,
  repoRoot,
  spliceInto,
  SQL_PATH,
  VECTORS_PATH,
} from "./gen_admission_vectors.ts";

function committedBlock(): string {
  const sql = Deno.readTextFileSync(join(repoRoot(), SQL_PATH));
  const begin = sql.indexOf(BEGIN_MARKER);
  const end = sql.indexOf(END_MARKER);
  assert(begin >= 0, `${SQL_PATH} has lost the generated block's start marker`);
  assert(end > begin, `${SQL_PATH} has lost the generated block's end marker`);
  return sql.slice(begin, end + END_MARKER.length);
}

Deno.test("the vector file actually loaded", () => {
  // A missing or emptied fixture would make the drift check below vacuous —
  // it would compare one rendering of nothing against another.
  const vectors = readVectors();
  assert(vectors.length >= 9, `only ${vectors.length} vectors`);
  for (const v of vectors) {
    assert(v.shape && v.why, `a vector without a name or a reason`);
    assert(v.expect.length > 0, `${v.shape} admits nothing at all`);
  }
});

Deno.test("the committed pgTAP block is what the vectors render", () => {
  // The drift guard. Edit allowed_units_vectors.json and this fails until
  // `deno task gen-admission-vectors` has written the SQL side to match —
  // which is what stops the app's rule and default_allowed_units() moving
  // apart without anybody noticing.
  assertEquals(
    committedBlock(),
    renderBlock(readVectors()),
    `${SQL_PATH} is stale — run: deno task gen-admission-vectors`,
  );
});

Deno.test("every vector reaches the block as its own assertion", () => {
  const block = renderBlock(readVectors());
  for (const v of readVectors()) {
    assertMatch(block, new RegExp(`'${v.shape}',`));
  }
  // One `values` row per vector, under a single `select is(...)`.
  assertEquals(block.match(/^select is\($/gm)?.length, 1);
});

Deno.test("renderBlock — a quote in the prose is escaped, not emitted raw", () => {
  const vector: AdmissionVector = {
    shape: "test",
    why: "the oil class's words",
    defaultUnit: "tsp",
    basis: "g",
    density: null,
    category: "spices & seasoning",
    expect: ["g"],
  };
  const block = renderBlock([vector]);
  assertMatch(block, /'the oil class''s words'/);
});

Deno.test("renderBlock — the first row carries the column casts", () => {
  // Postgres types a VALUES column from its first row, and the first row's
  // density may well be null. Without the casts the whole block fails to
  // plan, so the shape of row one is load-bearing.
  const block = renderBlock(readVectors());
  const firstRow = block.slice(block.indexOf("from (values"));
  assertMatch(firstRow, /null::numeric|^\s+[\d.]+::numeric/m);
  assertMatch(firstRow, /::text,/);
  assertMatch(firstRow, /::jsonb,/);
});

Deno.test("spliceInto — replaces only what lies between the markers", () => {
  const sql = `before\n${BEGIN_MARKER}\nold\n${END_MARKER}\nafter`;
  const out = spliceInto(sql, `${BEGIN_MARKER}\nnew\n${END_MARKER}`);
  assertEquals(out, `before\n${BEGIN_MARKER}\nnew\n${END_MARKER}\nafter`);
});

Deno.test("the marker names the file it was generated from", () => {
  // The marker is the only thing telling a reader of the SQL where to make
  // the edit, so it has to name both halves.
  assertMatch(committedBlock(), new RegExp(VECTORS_PATH));
  assertMatch(committedBlock(), /do not hand-edit/);
});
