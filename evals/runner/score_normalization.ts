// Scores the normalization dimension (evals/AGENTS.md): each case's `raw`
// through normalize() must equal its `expect_normalized`. These expectations are
// HAND-LABELLED (independent of normalize's own output) — grading normalize
// against normalize(raw) would be circular, so this dataset is separate from the
// generated matching set. The match/band half waits on the server-side cascade
// (roadmap step 8). Run via runner/run.sh.

import { normalize } from "../../supabase/functions/_shared/normalize.ts";

const casesPath = new URL(
  "../datasets/normalization/cases.jsonl",
  import.meta.url,
);
const lines = (await Deno.readTextFile(casesPath))
  .split("\n").map((l) => l.trim()).filter(Boolean);

let pass = 0;
const failures: string[] = [];
for (const line of lines) {
  const { raw, expect_normalized } = JSON.parse(line);
  const got = normalize(raw);
  if (got === expect_normalized) pass++;
  else {failures.push(
      `  ✗ ${JSON.stringify(raw)} → ${JSON.stringify(got)} (expected ${
        JSON.stringify(expect_normalized)
      })`,
    );}
}

const total = lines.length;
console.log(`normalization: ${pass}/${total} exact`);
if (failures.length) {
  console.log(failures.join("\n"));
  Deno.exit(1);
}
