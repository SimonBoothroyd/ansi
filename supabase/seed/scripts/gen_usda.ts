// Builds the usda_food reference seed from USDA FoodData Central CSV bundles
// (Foundation Foods + SR Legacy, CC0). Server-side reference only — never synced,
// never matched against at import (ADR-0005). See ../README.md for how to fetch
// the data (it is NOT committed — ~40MB of CSV; only the compact seed is).
//
//   deno run --allow-read --allow-write gen_usda.ts <dataset_dir> [<dataset_dir>...]
//
// Emits supabase/seed_usda.sql (a COPY block, ~8k rows). Keeps only the four
// macros (per 100 g) and a density derived from a volume food_portion. match_text
// is the shared §7 normalizer over the description, so the same normalizer the
// household vocab and cascade use also indexes the reference.

import { parse } from "@std/csv/parse";
import { normalize } from "../../functions/_shared/normalize.ts";

// FDC nutrient ids for the macros we keep. Fiber uses ONLY 1079 (Fiber, total
// dietary — the standard). 2033 (AOAC 2011.25) is deliberately not used: some
// Foundation entries carry absurd 2033 values (e.g. russet potato at 14.93 g).
const KCAL = "1008", PROTEIN = "1003", CARB = "1005", FAT = "1004";
const FIBER = "1079";
// Only these data_types are real foods to seed (Foundation ships sample rows too).
const FOODS = new Set(["foundation_food", "sr_legacy_food"]);

// Volume portion words → millilitres, for deriving density (g / ml). Matched
// against the WHOLE portion text (unit name + portion_description + modifier):
// SR Legacy mostly stores `measure_unit_id = undetermined` with the real unit
// in the modifier ("cup, diced", "tbsp"), so keying on the unit table alone
// found almost nothing — the 7/291 density famine (plan 0013). Order matters:
// spoons before cups so "1 tablespoon" never half-matches, ml last so the
// bare word can't shadow "milliliter".
const VOLUME_WORDS: [RegExp, number, number][] = [
  // [matcher, ml, preference rank] — cup preferred (largest common measure,
  // least rounding error), then tbsp, tsp (plan 0013: prefer tbsp/tsp/cup).
  [/\btablespoons?\b|\btbsp\b/, 14.7868, 1],
  [/\bteaspoons?\b|\btsp\b/, 4.92892, 2],
  [/\bcups?\b/, 236.588, 0],
  [/\bfl(?:uid)?\s?oz\b|\bfluid ounces?\b/, 29.5735, 3],
  [/\bliters?\b|\blitres?\b/, 1000, 3],
  [/\bpints?\b/, 473.176, 3],
  [/\bquarts?\b/, 946.353, 3],
  [/\bgallons?\b/, 3785.41, 3],
  [/\bmilliliters?\b|\bml\b/, 1, 3],
];

// A derived density outside this range is a parse artifact or a food form no
// kitchen density describes (puffed cereals ~0.05, syrups are fine at ~1.4;
// nothing edible is 5 g/ml) — skip rather than store nonsense (invariant 3).
const DENSITY_MIN = 0.1, DENSITY_MAX = 2.0;

interface Row {
  fdc_id: string;
  description: string;
  category: string | null;
  density: number | null;
  macros: Record<string, number>;
}

function readCsv(path: string): Record<string, string>[] {
  return parse(Deno.readTextFileSync(path), { skipFirstRow: true });
}

function loadDataset(dir: string, rows: Map<string, Row>): void {
  const categories = new Map<string, string>();
  for (const c of readCsv(`${dir}/food_category.csv`)) {
    categories.set(c.id, c.description);
  }
  const units = new Map<string, string>();
  for (const u of readCsv(`${dir}/measure_unit.csv`)) units.set(u.id, u.name);

  for (const f of readCsv(`${dir}/food.csv`)) {
    if (!FOODS.has(f.data_type)) continue;
    rows.set(f.fdc_id, {
      fdc_id: f.fdc_id,
      description: f.description,
      category: categories.get(f.food_category_id) ?? null,
      density: null,
      macros: {},
    });
  }

  // Macros: food_nutrient.csv is large; hand-split (its numeric/id fields carry
  // no embedded commas) and keep only the four nutrients for foods we loaded.
  const KEEP: Record<string, string> = {
    [KCAL]: "kcal",
    [PROTEIN]: "protein",
    [CARB]: "carb",
    [FAT]: "fat",
    [FIBER]: "fiber",
  };
  const nutrientText = Deno.readTextFileSync(`${dir}/food_nutrient.csv`);
  let first = true;
  for (const line of nutrientText.split("\n")) {
    if (first) {
      first = false;
      continue;
    }
    if (!line) continue;
    const c = line.slice(1, -1).split('","'); // strip outer quotes, split
    const key = KEEP[c[2]];
    if (!key) continue;
    const row = rows.get(c[1]);
    if (row) row.macros[key] = Number(c[3]);
  }

  // Density from the best-ranked usable volume portion. Candidates are
  // ranked by unit preference (cup > tbsp > tsp > other volumes), with an
  // unqualified portion ("1 cup") beating a prepared-state one ("1 cup,
  // chopped") of the same unit, then deterministically by seq/id.
  const best = new Map<
    string,
    { density: number; rank: number; seq: number; id: number }
  >();
  for (const p of readCsv(`${dir}/food_portion.csv`)) {
    const row = rows.get(p.fdc_id);
    if (!row) continue;
    const amount = Number(p.amount), grams = Number(p.gram_weight);
    if (!(amount > 0) || !(grams > 0)) continue;

    const unitName = units.get(p.measure_unit_id) ?? "";
    const text = [
      unitName === "undetermined" ? "" : unitName,
      p.portion_description === "undetermined" ? "" : p.portion_description,
      p.modifier,
    ]
      .filter(Boolean)
      .join(" ")
      .toLowerCase();
    const hit = VOLUME_WORDS.find(([re]) => re.test(text));
    if (!hit) continue;
    const [re, ml, unitRank] = hit;
    const density = grams / (amount * ml);
    if (density < DENSITY_MIN || density > DENSITY_MAX) continue;
    // Anything left once the unit word goes is a qualifier (chopped, sliced,
    // packed…): still a real density of that form, but ranked behind the
    // food's plain measure.
    const qualified = text.replace(re, "").replace(/[\s,]+/g, "") !== "";
    const rank = unitRank + (qualified ? 10 : 0);
    const seq = Number(p.seq_num) || 0, id = Number(p.id) || 0;
    const cur = best.get(p.fdc_id);
    if (
      !cur ||
      rank < cur.rank ||
      (rank === cur.rank &&
        (seq < cur.seq || (seq === cur.seq && id < cur.id)))
    ) {
      best.set(p.fdc_id, { density, rank, seq, id });
    }
  }
  for (const [fdcId, b] of best) {
    const row = rows.get(fdcId);
    if (row && row.density === null) row.density = b.density;
  }
}

function main(): void {
  const dirs = Deno.args;
  if (dirs.length === 0) {
    console.error("usage: gen_usda.ts <dataset_dir> [<dataset_dir>...]");
    Deno.exit(1);
  }
  // Foundation first so it wins on any fdc_id overlap (it won't, but for macros
  // quality the earlier dataset is preferred — pass Foundation before SR Legacy).
  const rows = new Map<string, Row>();
  for (const dir of dirs) loadDataset(dir, rows);

  // Batched multi-row INSERTs — the Supabase CLI seeder can't stream COPY.
  const q = (s: string) => `'${s.replace(/'/g, "''")}'`;
  const cols =
    "(fdc_id, description, category, density_g_per_ml, macros, match_text)";
  const out: string[] = [
    "-- seed_usda.sql — GENERATED by scripts/gen_usda.ts (USDA FDC, CC0).",
    "-- Server-side reference only: never synced, never matched at import (ADR-0005).",
  ];
  const all = [...rows.values()];
  let withDensity = 0, withFiber = 0;
  const BATCH = 500;
  for (let i = 0; i < all.length; i += BATCH) {
    const tuples = all.slice(i, i + BATCH).map((r) => {
      if (r.density !== null) withDensity++;
      const m = r.macros;
      if (m.fiber !== undefined) withFiber++;
      return "(" + [
        r.fdc_id,
        q(r.description),
        r.category === null ? "null" : q(r.category),
        r.density === null ? "null" : r.density.toFixed(4),
        `${q(JSON.stringify(m))}::jsonb`,
        q(normalize(r.description)),
      ].join(", ") + ")";
    });
    out.push(`insert into usda_food ${cols} values`, tuples.join(",\n") + ";");
  }
  out.push("");

  const target = new URL("../../seed_usda.sql", import.meta.url).pathname;
  Deno.writeTextFileSync(target, out.join("\n"));
  console.log(
    `wrote ${target}\n  ${rows.size} foods (${withDensity} density, ${withFiber} fiber)`,
  );
}

if (import.meta.main) main();
