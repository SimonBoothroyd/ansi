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
//   * density       {match_text, value, [source], reason} — set (value) or
//     clear (value: null) the template row's density (consumed by
//     gen_seed.ts → seed_curation.sql). An optional `source` is the fill's
//     PROVENANCE and is appended to the row's `source` column exactly the
//     way the FAO fallback appends its own ("fdc_density:<fdc_id>",
//     "label:…", "typical:…"), so a hand-curated density is auditable in
//     the database and not only in this file. Never `usda_fdc:<id>` — that
//     prefix is the server prefill's mark (Ingredient.isUsdaPrefilled) and
//     means the MACROS came from FDC, which a density fill does not say.
//   * allowed_units {match_text, [add], [remove], [set], reason} — adjust
//     the materialized allowed-unit list: `set` replaces wholesale, or
//     `add`/`remove` tweak the rule output (consumed by gen_seed.ts →
//     seed_curation.sql).
//   * piece_weight   {match_text, label | basis_amount, reason} — what ONE
//     of this ingredient WEIGHS, in the row's basis unit (ADR-0015). It is
//     the fact that admits `piece`, and it applies only where the template
//     row's `default_unit` is `piece`. Two forms, exactly one of which must
//     be given:
//       - `label`: borrow that curated measure's `basis_amount` (the row's
//         own `onion, medium` = 110 g), stamping
//         `piece_source = 'borrowed from <label>'`. A copy of a stated fact.
//       - `basis_amount`: an explicit number for a row whose measures say
//         nothing whole, stamping `piece_source = 'seed:typical'` so the
//         guess is visible rather than dressed as a citation.
//     Consumed by gen_measures.ts (label validity + exhaustiveness over the
//     piece-default rows) and gen_seed.ts → seed_curation.sql. This kind
//     replaces the retired `default_measure` (0023, seam D1): the same
//     judgment, recorded as the number the app can actually convert with.
//   * macros        {match_text, macros: {kcal, protein, fat, carb,
//     [fiber]}, source, reason} — label-sourced macros (per 100 g) for a
//     row FDC genuinely lacks (no-analogue rule keeps it link-less) or
//     whose FDC macros are wrong; flips the row to `complete` and stamps
//     `source` (e.g. "label:Bragg") so provenance stays visible
//     (consumed by gen_seed.ts → seed_curation.sql).

export interface CurationOverride {
  kind:
    | "drop_measure"
    | "add_measure"
    | "density"
    | "allowed_units"
    | "piece_weight"
    | "macros";
  match_text: string;
  reason: string;
  // add_measure / drop_measure / piece_weight (the borrowed measure's label)
  label?: string | null;
  basis_amount?: number;
  sort_order?: number;
  source?: string; // also: macros / density provenance ("label:…")
  // density
  value?: number | null;
  // allowed_units
  set?: string[];
  add?: string[];
  remove?: string[];
  // macros (per 100 g of the ingredient's basis)
  macros?: {
    kcal: number;
    protein: number;
    fat: number;
    carb: number;
    fiber?: number;
  };
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
    if (!o.match_text) {
      problems.push(`override without match_text: ${JSON.stringify(o)}`);
    }
    if (!o.reason) {
      problems.push(`override without a reason: ${JSON.stringify(o)}`);
    }
    if (o.kind === "drop_measure" && !o.label) {
      problems.push(`drop_measure without label: ${o.match_text}`);
    }
    if (o.kind === "add_measure" && (!o.label || !(o.basis_amount! > 0))) {
      problems.push(
        `add_measure needs label + positive basis_amount: ${o.match_text}`,
      );
    }
    if (o.kind === "density" && o.value !== null && !(o.value! > 0)) {
      problems.push(
        `density override needs a positive value or null: ${o.match_text}`,
      );
    }
    // A density fill must not claim the prefill's mark: `usda_fdc:<id>` is
    // what `Ingredient.isUsdaPrefilled` reads to say the MACROS came from
    // FDC. A density borrowed from an FDC food is `fdc_density:<id>`.
    if (o.kind === "density" && o.source?.startsWith("usda_fdc:")) {
      problems.push(
        `density source must not use the macro-prefill prefix ` +
          `"usda_fdc:" (use "fdc_density:<id>"): ${o.match_text}`,
      );
    }
    if (o.kind === "density" && o.source !== undefined && !o.source) {
      problems.push(
        `density source, when given, must be non-empty: ${o.match_text}`,
      );
    }
    if (o.kind === "density" && o.source && o.value === null) {
      problems.push(
        `density source on a CLEARING override says nothing: ${o.match_text}`,
      );
    }
    if (
      o.kind === "allowed_units" &&
      !o.set && !(o.add?.length) && !(o.remove?.length)
    ) {
      problems.push(`allowed_units override changes nothing: ${o.match_text}`);
    }
    // A piece weight is a NUMBER on the row, said one of exactly two ways:
    // borrowed from a curated measure's label, or stated outright. Neither
    // form is optional and they are not combinable — "which of these two does
    // this row mean?" is not a question a generator should have to answer.
    if (o.kind === "piece_weight") {
      const hasLabel = typeof o.label === "string" && o.label.length > 0;
      const hasAmount = o.basis_amount !== undefined;
      if (hasLabel === hasAmount) {
        problems.push(
          `piece_weight needs exactly one of label (borrow that measure's ` +
            `basis_amount) or basis_amount (an explicit weight): ` +
            `${o.match_text}`,
        );
      }
      if (hasAmount && !(o.basis_amount! > 0)) {
        problems.push(
          `piece_weight basis_amount must be positive: ${o.match_text}`,
        );
      }
      if (o.label === null) {
        problems.push(
          `piece_weight label may not be null — a piece-default row with no ` +
            `honest weight has its default unit changed in vocab.jsonl ` +
            `instead (ADR-0015): ${o.match_text}`,
        );
      }
    }
    if (o.kind === "macros") {
      const m = o.macros;
      if (
        !m || !(m.kcal >= 0) || !(m.protein >= 0) || !(m.fat >= 0) ||
        !(m.carb >= 0)
      ) {
        problems.push(
          `macros override needs kcal/protein/fat/carb >= 0: ${o.match_text}`,
        );
      }
      if (!o.source) {
        problems.push(`macros override needs a source: ${o.match_text}`);
      }
    }
  }
  if (problems.length > 0) {
    console.error("curation_overrides problems:\n  " + problems.join("\n  "));
    Deno.exit(1);
  }
  return overrides;
}
