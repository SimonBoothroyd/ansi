// Reader for ../curation_overrides.jsonl — the committed, audited record of
// the LLM/human curation pass over generated seed output (plan 0013, Simon's
// seed-default methodology: rules are scaffolding, not the decider; every
// place the pipeline assigns per-ingredient defaults gets a final judgment
// pass, and every override is recorded WITH A REASON so the pass is
// auditable, like the borrow map).
//
// One JSON object per line. Kinds:
//   * drop_measure  {match_text, label, reason} — remove a generated measure
//     (consumed by gen_measures.ts; stale drops fail the run).
//   * add_measure   {match_text, label, basis_amount, [source], [sort_order],
//     reason} — add a measure the rules can't derive.
//   * density       {match_text, value, reason} — set (value) or clear
//     (value: null) the template row's density (consumed by gen_seed.ts →
//     seed_curation.sql).
//   * allowed_units {match_text, [add], [remove], [set], reason} — adjust
//     the materialized allowed-unit list: `set` replaces wholesale, or
//     `add`/`remove` tweak the rule output (consumed by gen_seed.ts →
//     seed_curation.sql).

export interface CurationOverride {
  kind: "drop_measure" | "add_measure" | "density" | "allowed_units";
  match_text: string;
  reason: string;
  // add_measure / drop_measure
  label?: string;
  basis_amount?: number;
  sort_order?: number;
  source?: string;
  // density
  value?: number | null;
  // allowed_units
  set?: string[];
  add?: string[];
  remove?: string[];
}

/// Reads and validates the overrides file beside the seed data; absent file
/// → no overrides (the pre-curation state).
export function readOverrides(scriptsDir: string): CurationOverride[] {
  let text: string;
  try {
    text = Deno.readTextFileSync(`${scriptsDir}../curation_overrides.jsonl`);
  } catch {
    return [];
  }
  const overrides = text
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("//"))
    .map((l) => JSON.parse(l) as CurationOverride);
  const problems: string[] = [];
  for (const o of overrides) {
    if (!o.match_text) problems.push(`override without match_text: ${JSON.stringify(o)}`);
    if (!o.reason) problems.push(`override without a reason: ${JSON.stringify(o)}`);
    if (o.kind === "drop_measure" && !o.label) {
      problems.push(`drop_measure without label: ${o.match_text}`);
    }
    if (o.kind === "add_measure" && (!o.label || !(o.basis_amount! > 0))) {
      problems.push(`add_measure needs label + positive basis_amount: ${o.match_text}`);
    }
    if (o.kind === "density" && o.value !== null && !(o.value! > 0)) {
      problems.push(`density override needs a positive value or null: ${o.match_text}`);
    }
    if (
      o.kind === "allowed_units" &&
      !o.set && !(o.add?.length) && !(o.remove?.length)
    ) {
      problems.push(`allowed_units override changes nothing: ${o.match_text}`);
    }
  }
  if (problems.length > 0) {
    console.error("curation_overrides problems:\n  " + problems.join("\n  "));
    Deno.exit(1);
  }
  return overrides;
}
