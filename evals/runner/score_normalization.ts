// Scores the normalization dimension of the matching eval (evals/AGENTS.md):
// each case's `raw` through normalize() must equal its `expect_normalized`.
// This is the exact-output half of the harness; the match/band half waits on the
// server-side cascade (roadmap step 8). Run via runner/run.sh.

import { normalize } from "../../supabase/functions/_shared/normalize.ts";

const casesPath = new URL("../datasets/matching/cases.jsonl", import.meta.url);
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
