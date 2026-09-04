/**
 * Renders the shared unit-admission vectors as the `values` block in
 * `supabase/tests/unit_admission.sql`.
 *
 * The vectors live in `app/test/features/ingredients/allowed_units_vectors.json`
 * and the Dart suite loops the same file. This script is what keeps the pgTAP
 * mirror honest: the block it emits is COMMITTED into the SQL file, and
 * `gen_admission_vectors.test.ts` fails if what is committed no longer equals
 * what this renders. So a shape added or changed on the app's side fails the
 * seed-script leg of CI until the SQL block is regenerated, rather than
 * quietly leaving the server's `default_allowed_units()` unmirrored.
 *
 * Regenerate after editing the JSON:
 *
 *   deno task gen-admission-vectors
 *
 * `expect` is in the app's display order; `default_allowed_units()` emits its
 * own. The rendered assertion therefore compares the two lists as SETS —
 * membership is the mirror, order is each side's own business.
 */

import { dirname, fromFileUrl, join } from "@std/path";

/** One row of the shared vector file. */
export interface AdmissionVector {
  shape: string;
  why: string;
  defaultUnit: string;
  basis: string;
  density: number | null;
  category: string | null;
  expect: string[];
}

/** Repo-root-relative paths, so the emitted marker names them verbatim. */
export const VECTORS_PATH =
  "app/test/features/ingredients/allowed_units_vectors.json";
export const SQL_PATH = "supabase/tests/unit_admission.sql";
const SCRIPT_PATH = "supabase/seed/scripts/gen_admission_vectors.ts";

export const BEGIN_MARKER =
  `-- >>> GENERATED from ${VECTORS_PATH}\n-- by ${SCRIPT_PATH} — do not hand-edit.`;
export const END_MARKER = "-- <<< GENERATED";

/** `supabase/seed/scripts` → the repo root. */
export function repoRoot(): string {
  return join(dirname(fromFileUrl(import.meta.url)), "..", "..", "..");
}

export function readVectors(root = repoRoot()): AdmissionVector[] {
  const { vectors } = JSON.parse(
    Deno.readTextFileSync(join(root, VECTORS_PATH)),
  ) as { vectors: AdmissionVector[] };
  if (!vectors?.length) throw new Error(`no vectors in ${VECTORS_PATH}`);
  return vectors;
}

/** A SQL single-quoted literal. */
function lit(value: string): string {
  return `'${value.replaceAll("'", "''")}'`;
}

function nullable(value: string | null): string {
  return value === null ? "null" : lit(value);
}

/**
 * The whole block, markers included — exactly the text that lives in
 * `unit_admission.sql`.
 */
export function renderBlock(vectors: AdmissionVector[]): string {
  const rows = vectors.map((v, i) =>
    [
      "  (",
      `    ${lit(v.shape)},`,
      `    ${lit(v.defaultUnit)},`,
      `    ${lit(v.basis)},`,
      `    ${v.density === null ? "null" : v.density}${
        i === 0 ? "::numeric" : ""
      },`,
      `    ${nullable(v.category)}${i === 0 ? "::text" : ""},`,
      `    ${lit(JSON.stringify(v.expect))}${i === 0 ? "::jsonb" : ""},`,
      `    ${lit(v.why)}`,
      "  )",
    ].join("\n")
  ).join(",\n");

  return [
    BEGIN_MARKER,
    "--",
    "-- One assertion per shape in the shared vector file the app's",
    "-- allowed_units_test.dart loops. Membership is compared, not order:",
    "-- the app sorts for display, this function emits its own order.",
    "select is(",
    "  (",
    "    select jsonb_agg(u order by u)",
    "    from jsonb_array_elements_text(",
    "      default_allowed_units(v.default_unit, v.basis, v.density, v.category)",
    "    ) as u",
    "  ),",
    "  (",
    "    select jsonb_agg(u order by u)",
    "    from jsonb_array_elements_text(v.expect) as u",
    "  ),",
    "  'the ' || v.shape || ' shape: ' || v.why",
    ")",
    "from (values",
    rows,
    ") as v(shape, default_unit, basis, density, category, expect, why);",
    END_MARKER,
  ].join("\n");
}

/** Splices a freshly rendered block into the pgTAP file, in place. */
export function spliceInto(sql: string, block: string): string {
  const begin = sql.indexOf(BEGIN_MARKER);
  const end = sql.indexOf(END_MARKER);
  if (begin < 0 || end < 0) {
    throw new Error(`markers not found in ${SQL_PATH}`);
  }
  return sql.slice(0, begin) + block + sql.slice(end + END_MARKER.length);
}

if (import.meta.main) {
  const root = repoRoot();
  const path = join(root, SQL_PATH);
  const before = Deno.readTextFileSync(path);
  const after = spliceInto(before, renderBlock(readVectors(root)));
  if (after === before) {
    console.log(`${SQL_PATH}: already up to date`);
  } else {
    Deno.writeTextFileSync(path, after);
    console.log(`${SQL_PATH}: regenerated the vector block`);
  }
}
