// Generates supabase/seed_measures.sql — the template vocab's ingredient
// MEASURES ("1 potato, medium = 213 g") — from USDA FoodData Central
// `food_portion` rows (CC0), joined to the vocab through the committed
// `usda_links.jsonl` (match_text → fdc_id). Step 7.6 follow-up: the old file
// was hand-curated; this makes it GENERATED output with per-row provenance.
//
//   deno run --allow-read --allow-write gen_measures.ts <dataset_dir> [...]
//
// (pass the same Foundation + SR Legacy dirs as gen_usda.ts — see ../README.md
// for fetching the ~40 MB CSV bundles; they are NOT committed).
//
// **Extraction is GENEROUS; curation is the decider** (plan 0013, Simon's
// call: rules were being used as the taste filter, which is the curation
// pass's job). Every portion that names a physical human unit is emitted —
// all size classes, fragments (slice, wedge, strip, stick, cube…), container
// and dimension-described portions — ordered most-kitchen-useful first
// (container > medium > large > small > extra sizes > whole > fragment).
// The committed `curation_overrides.jsonl` then drops (or adds) rows a
// human judged senseless, with reasons; this script applies it last.
//
// Still excluded AT EXTRACTION (unchanged, ADR-0008):
//   * pure volume portions (cup/tbsp/tsp/fl oz…) — those are densities in
//     disguise and become `usda_food.density_g_per_ml` via gen_usda.ts;
//   * prepared-state volume qualifiers (chopped/diced/mashed/…) — they only
//     ride volume rows;
//   * mass aliases ("1 oz") and nutrition-label servings ("NLEA serving") —
//     label servings aren't physical units;
//   * the imprecise "dash".
//
// Two tiers, both with explicit `source` provenance (migration 0010):
//
//   * Tier 1 — each vocab ingredient's OWN linked FDC food's piece-type
//     portions (russet vs red potato get their own weights).
//     `source = usda_fdc:<fdc_id> (<portion>)`.
//
//   * Tier 2 — BORROWS for varieties whose own FDC food lacks usable piece
//     portions (gold potato ← russet; canned bean varieties ← pinto's
//     drained-can weight). The borrow map below is explicit and committed;
//     `source` gains a "— borrowed" marker so the approximation is visible.
//     The same marker is applied AUTOMATICALLY when several vocab rows link
//     one FDC food: the row(s) whose words best match the food description
//     own it, every other sharer is an implicit borrow ("berry" borrowing
//     the blueberry food). And a food whose description carries a basis
//     qualifier (without peel / drained / cooked / dried) emits no
//     whole-item measure unless the vocab row or the label owns that basis.
//
// A short survivor list of `seed:typical` hand rows remains for important
// items where FDC genuinely has no usable portion (see TYPICAL below).
//
// Amounts are emitted as `basis_amount` (0012): the amount in the
// ingredient's basis unit. Every vocab row is per-100 g today
// (macros_basis = 'g'), so FDC gram weights ARE basis amounts verbatim; a
// per-ml vocab row would need its portions divided through a density first —
// the script asserts the assumption instead of guessing.
//
// Measures stay PER-INGREDIENT rows (no shared portion-class entity): user
// overrides must remain variety-specific — see exec plan 0010's decision log.

import { parse } from "@std/csv/parse";
import { normalize } from "../../functions/_shared/normalize.ts";
import { readOverrides } from "./overrides.ts";

const HOUSEHOLD_ID = "00000000-0000-0000-0000-0000000000aa";

// --- Tier 2: explicit borrow map (variety → representative food) -------------
// Only for varieties whose OWN linked food has no usable piece portion. Keep
// this list short and justified; every row's source is marked "— borrowed".
const BORROWS: { matchText: string; fdcId: string; why: string }[] = [
  // USDA sizes potatoes by diameter class, so russet's small/medium/large
  // weights describe gold potatoes equally well (no FDC gold-potato food).
  { matchText: "gold potato", fdcId: "170027", why: "russet size classes" },
  // These canned beans have no can-sized FDC portion of their own; pinto's
  // "can drained solids" (a standard 15 oz can) is the representative can.
  { matchText: "black bean canned", fdcId: "174286", why: "15 oz bean can" },
  {
    matchText: "cannellini bean canned",
    fdcId: "174286",
    why: "15 oz bean can",
  },
  {
    matchText: "great northern bean canned",
    fdcId: "174286",
    why: "15 oz bean can",
  },
  { matchText: "navy bean canned", fdcId: "174286", why: "15 oz bean can" },
  {
    matchText: "black eyed pea canned",
    fdcId: "174286",
    why: "15 oz bean can",
  },
  // The vocab's apple varieties link Foundation foods (fresher macros) that
  // carry NO piece portions; SR Legacy has the SAME varieties with USDA's
  // measured size classes — borrow each variety's own SR sibling.
  { matchText: "gala apple", fdcId: "168204", why: "SR gala size classes" },
  {
    matchText: "granny smith apple",
    fdcId: "168203",
    why: "SR granny smith size classes",
  },
  {
    matchText: "red delicious apple",
    fdcId: "168201",
    why: "SR red delicious size classes",
  },
];

// --- Curated survivors: FDC has nothing usable, the item matters -------------
// Deliberately rare, deliberately round, marked `seed:typical`.
const TYPICAL: { matchText: string; label: string; grams: number }[] = [
  // FDC shallots carry only "1 tbsp chopped" — no whole-bulb portion.
  { matchText: "shallot", label: "shallot, medium", grams: 30 },
  // FDC tempeh carries only "1 cup"; the 8 oz retail package is the unit.
  { matchText: "tempeh", label: "package (8 oz)", grams: 227 },
  // FDC canned coconut milk carries only cup/tbsp; the 400 ml can is the
  // unit recipes speak in (~1.0 g/ml).
  { matchText: "coconut milk canned", label: "can (400 ml)", grams: 400 },
  // FDC silken tofu (MORI-NU) has only a sub-package "slice"; the 12.3 oz
  // shelf-stable block is the purchasable unit.
  { matchText: "silken tofu", label: "block (12.3 oz)", grams: 349 },
  // FDC extra-firm tofu carries only "0.2 block" (a 455 g / 16 oz block —
  // a 5× extrapolation, and not the common pack); the 14 oz retail block is
  // the purchasable unit, framed like silken's.
  { matchText: "extra firm tofu", label: "block (14 oz)", grams: 397 },
  // FDC's only lemon food is "Lemons, raw, without peel" (58 g — the macro
  // basis, not what you buy). A typical whole lemon with peel is ~100 g.
  { matchText: "lemon", label: "lemon, whole", grams: 100 },
  // The 7 g yeast sachet is the near-universal printed standard — every
  // supermarket sachet says 7 g / ¼ oz on the packet (equivalently "2¼ tsp"
  // in US recipes). FDC's yeast foods carry only tsp/tbsp volume rows.
  { matchText: "instant yeast", label: "sachet", grams: 7 },
  { matchText: "active yeast dry", label: "sachet", grams: 7 },
  // FDC's king-oyster food (2003599) has NO portions, and its vocab link
  // resolves to plain oyster mushrooms (5–10× lighter). A typical king
  // oyster (trumpet) mushroom is ~90 g.
  { matchText: "king oyster mushroom", label: "mushroom, medium", grams: 90 },
];

// Tier-1 output is suppressed for these (their only surviving FDC portions
// are misleading); the TYPICAL row above covers them instead.
const SUPPRESS_TIER1 = new Set([
  "silken tofu", // MORI-NU sub-package slice
  "extra firm tofu", // 0.2-block extrapolation (see TYPICAL)
  "king oyster mushroom", // linked food is plain oyster — wrong species/size
]);

// --- Portion filtering / ranking ---------------------------------------------

// Portions that are not piece-type: volume (density's job — gen_usda.ts
// derives it from exactly these rows), mass aliases, nutrition-label
// servings, prepared-state volume qualifiers, and the imprecise dash.
// Deliberately NOTHING else (generous extraction, plan 0013): cubes, balls,
// twists, chips, slices and friends are physical human units — the curation
// pass trims the senseless ones with reasons.
const SKIP = new RegExp(
  "\\b(cup|cups|tablespoon|tbsp|teaspoon|tsp|fl oz|fluid|liter|litre|" +
    "milliliter|ml|pint|quart|gallon|oz|lb|pound|gram|grams|kg|" +
    "serving|servings|nlea|" +
    "chopped|diced|mashed|pureed|shredded|grated|dash)\\b",
);

// A label-serving row is rescued when the "serving" is a physically
// disguised unit ("serving packet" of sugar, "slice 1 serving", a granola
// "bar NLEA serving"): the serving words are deleted and the portion ships
// under its real name. A serving that names nothing physical stays skipped.
const SERVING_WORDS = /\b(nlea|servings?)\b/gi;
const PHYSICAL = new RegExp(
  "\\b(packet|bar|container|pouch|bottle|slice|stick|piece|pieces|patty|" +
    "link|wedge|cube)\\b",
);

// Words that carry no identity in a label (size details live in `source`;
// the trailing units of stripped size phrases — "5\" long" → "long" — go too).
const DROP_WORDS = new Set([
  "edible",
  "yields",
  "individual",
  "long",
  "dia",
  "thick",
  "approx",
]);

// Post-clean label rewrites (prettify without losing meaning).
const REWRITE: Record<string, string> = {
  "can drained solids": "can, drained",
  "can drained": "can, drained",
  "piece whole": "whole",
  fruit: "whole",
};

// Fragments of a whole thing (a slice of bread, a wedge of lemon, a cube of
// cheese) — all EMITTED now (generous extraction), ranked last so chips lead
// with the most kitchen-useful unit; the curation pass trims where a
// fragment is senseless for the food.
const FRAGMENT =
  /\b(slice|wedge|ring|strip|stick|tip|chunk|cube|ball|twist|chip)\b/;
const CONTAINER = /\b(can|block|package|packet|bunch|bag)\b/;

/// Kitchen usefulness → `sort_order` rank: chips render in this order
/// ("medium before jumbo").
function rank(label: string): number {
  if (FRAGMENT.test(label)) return 6;
  if (CONTAINER.test(label)) return 0;
  if (/\b(extra large|extra small|jumbo)\b/.test(label)) return 4;
  if (/\bmedium\b/.test(label)) return 1;
  if (/\blarge\b/.test(label)) return 2;
  if (/\bsmall\b/.test(label)) return 3;
  return 5; // a whole-ish named thing (clove, stalk, head, whole, …)
}

function singular(word: string): string {
  const irregular: Record<string, string> = { leaves: "leaf", halves: "half" };
  if (irregular[word]) return irregular[word];
  if (word.endsWith("ies")) return `${word.slice(0, -3)}y`;
  if (word.endsWith("s") && !word.endsWith("ss")) return word.slice(0, -1);
  return word;
}

/// The display label for a portion: paren details and digits stripped (they
/// stay in `source`), noise words dropped, plural singularised when the
/// portion counted several, trailing size normalised to ", size".
function cleanLabel(raw: string, amount: number): string | null {
  let s = raw
    .toLowerCase()
    .replace(/\([^)]*\)/g, " ") // parenthetical size notes
    .replace(/,?\s*ns as to .*$/, "") // "NS as to Florida or California"
    .replace(/\bwithout refuse\b/, "")
    .replace(/[^a-z\s,]/g, " ") // digits, quotes, dashes (size fragments)
    .replace(/\s+/g, " ")
    .replace(/\s*,\s*/g, ", ")
    .replace(/^[,\s]+|[,\s]+$/g, "")
    .trim();
  if (!s) return null;
  s = s
    .split(" ")
    .filter((w) => !DROP_WORDS.has(w.replace(/,$/, "")))
    .join(" ")
    .replace(/^[,\s]+|[,\s]+$/g, "");
  if (amount !== 1) {
    const words = s.split(" ");
    words[words.length - 1] = singular(words[words.length - 1]);
    s = words.join(" ");
  }
  s = REWRITE[s] ?? s;
  // "medium whole" → "medium" (the row IS the whole thing; "whole" is noise).
  s = s.replace(
    /^(extra large|extra small|jumbo|medium|large|small) whole$/,
    "$1",
  );
  // "potato medium" → "potato, medium" (matches the curated label style) —
  // but never split a bare size ("extra large" must not become "extra, large",
  // which would both misread and dodge the extra-size ranking).
  if (!/^((extra )?(large|medium|small)|jumbo)$/.test(s)) {
    s = s.replace(
      /^(.+?),? (extra large|extra small|jumbo|medium|large|small)$/,
      "$1, $2",
    );
  }
  return s || null;
}

// --- FDC loading -------------------------------------------------------------

interface Portion {
  fdcId: string;
  label: string;
  grams: number; // per ONE of the label (gram_weight / amount)
  rank: number;
  seq: number;
  id: number;
  source: string; // the verbatim FDC portion, for provenance
}

function readCsv(path: string): Record<string, string>[] {
  return parse(Deno.readTextFileSync(path), { skipFirstRow: true });
}

/// Raw FDC descriptions for the foods we consume — they drive the basis
/// guard ("without peel") and shared-link ownership detection.
function loadDescriptions(
  dirs: string[],
  keep: Set<string>,
): Map<string, string> {
  const descs = new Map<string, string>();
  for (const dir of dirs) {
    for (const f of readCsv(`${dir}/food.csv`)) {
      if (keep.has(f.fdc_id) && !descs.has(f.fdc_id)) {
        descs.set(f.fdc_id, f.description);
      }
    }
  }
  return descs;
}

/// All usable piece-type portions per fdc_id, filtered + ranked.
function loadPortions(
  dirs: string[],
  keep: Set<string>,
): Map<string, Portion[]> {
  const byFood = new Map<string, Portion[]>();
  for (const dir of dirs) {
    const units = new Map<string, string>();
    for (const u of readCsv(`${dir}/measure_unit.csv`)) units.set(u.id, u.name);
    for (const p of readCsv(`${dir}/food_portion.csv`)) {
      if (!keep.has(p.fdc_id)) continue;
      const amount = Number(p.amount);
      const gramWeight = Number(p.gram_weight);
      if (!(amount > 0) || !(gramWeight > 0)) continue;

      const unitName = units.get(p.measure_unit_id) ?? "";
      const raw = [
        unitName === "undetermined" ? "" : unitName,
        p.portion_description,
        p.modifier,
      ]
        .filter(Boolean)
        .join(" ")
        .trim();
      if (!raw) continue;
      // Skip-check runs on the paren-stripped text so a size note like
      // "(approx 1-1/4 lb)" doesn't disqualify a whole-item portion.
      const skippable = raw.toLowerCase().replace(/\([^)]*\)/g, " ");
      let effective = raw;
      if (SKIP.test(skippable)) {
        // Physically-disguised serving rescue (see SERVING_WORDS above).
        const deServed = skippable.replace(SERVING_WORDS, " ");
        if (PHYSICAL.test(deServed) && !SKIP.test(deServed)) {
          effective = raw.replace(SERVING_WORDS, " ");
        } else {
          continue;
        }
      }

      const label = cleanLabel(effective, amount);
      if (!label) continue;
      (byFood.get(p.fdc_id) ?? byFood.set(p.fdc_id, []).get(p.fdc_id)!).push({
        fdcId: p.fdc_id,
        label,
        grams: gramWeight / amount,
        rank: rank(label),
        seq: Number(p.seq_num) || 0,
        id: Number(p.id) || 0,
        source: `${p.amount} ${raw}`,
      });
    }
  }
  return byFood;
}

// --- Basis honesty guard ------------------------------------------------------
// A food description can carry a BASIS qualifier ("Lemons, raw, without
// peel"; "…canned, drained solids") — the macro link's basis leaking into a
// count measure would misweigh the thing you buy. A portion from such a food
// is only emitted when the qualifier is owned by the vocab row or stated in
// the label itself ("can, drained" is honest; a "whole lemon" at the
// without-peel weight is not).
const BASIS_QUALIFIERS = ["without peel", "drained", "cooked", "dried"];

function basisFilter(
  matchText: string,
  description: string,
  portions: Portion[],
): Portion[] {
  const desc = description.toLowerCase();
  let quals = BASIS_QUALIFIERS.filter((q) =>
    new RegExp(`\\b${q}\\b`).test(desc)
  );
  // Nuts and seeds are SOLD dried — "Nuts, brazilnuts, dried" describes the
  // retail kernel, so "dried" is not a basis mismatch there.
  if (/^(nuts|seeds),/.test(desc)) quals = quals.filter((q) => q !== "dried");
  if (quals.length === 0) return portions;
  return portions.filter((p) =>
    quals.every((q) => matchText.includes(q) || p.label.includes(q))
  );
}

// Colours / preparation / generic words that must never count as a variety
// marker for the keep-only rule below.
const VARIETY_STOP = new Set([
  "red",
  "green",
  "yellow",
  "orange",
  "white",
  "black",
  "purple",
  "sweet",
  "hot",
  "baby",
  "dried",
  "canned",
  "frozen",
  "fresh",
  "whole",
  "ground",
  "leaf",
  "bean",
  "pea",
  "pod",
  "mixed",
  "extra",
  "firm",
  "silken",
  "dark",
  "light",
  "king",
]);

/// Variety honesty: when an ingredient is linked to a broader food ("cherry
/// tomato" → the generic tomato food), portions naming the variety ("1
/// cherry = 17 g") are the ONLY honest ones — a generic "medium (123 g)"
/// would misdescribe a cherry tomato by an order of magnitude. If any portion
/// label carries a non-head, non-generic word of the match_text, keep only
/// those portions; otherwise everything stands.
function varietyFilter(matchText: string, portions: Portion[]): Portion[] {
  const words = matchText.split(" ");
  if (words.length < 2) return portions;
  const variety = new Set(
    words.slice(0, -1).filter((w) => !VARIETY_STOP.has(w)),
  );
  if (variety.size === 0) return portions;
  const hits = portions.filter((p) =>
    p.label.split(/[,\s]+/).some((w) => variety.has(w))
  );
  return hits.length > 0 ? hits : portions;
}

// --- Label legibility (review N7) --------------------------------------------
// The hand seed read "<noun>, <size>" ("onion, medium"); a generated bare
// "medium (110 g)" loses the thing being counted. Prefix bare sizes and bare
// whole/each with the ingredient's head noun.

// A match_text's head noun: the last word, skipping trailing form/state
// qualifiers ("fig dried" → fig; "tomato canned whole" → tomato).
const FORM_WORDS = new Set([
  "canned",
  "dried",
  "frozen",
  "fresh",
  "cooked",
  "whole",
]);
function nounOf(matchText: string): string {
  const words = matchText.split(" ").filter((w) => !FORM_WORDS.has(w));
  return words[words.length - 1] ?? matchText;
}

function finalizeLabel(matchText: string, label: string): string {
  // "sweetpotato" is FDC's spelling of the vocab's "sweet potato".
  if (label.replace(/[\s,]/g, "") === matchText.replace(/\s/g, "")) {
    return matchText;
  }
  const noun = nounOf(matchText);
  if (/^(medium|large|small|extra large|extra small)$/.test(label)) {
    return `${noun}, ${label}`;
  }
  if (label === "whole" || label === "each") return `${noun}, whole`;
  // A generic stand-in noun ("pepper" on jalapeño, "piece" on tostada
  // shell) reads better as the ingredient's own noun.
  if (
    (label === "pepper" || label === "piece") &&
    !matchText.split(" ").includes(label)
  ) {
    return noun;
  }
  return label;
}

/// Usefulness-ordered and label-deduped — no cap, no fragment suppression
/// (generous extraction, plan 0013): every distinct physical unit ships,
/// most kitchen-useful first, and the curation pass does the trimming.
function pick(portions: Portion[]): Portion[] {
  const sorted = [...portions].sort(
    (a, b) => a.rank - b.rank || a.seq - b.seq || a.id - b.id,
  );
  const seen = new Set<string>();
  const out: Portion[] = [];
  for (const p of sorted) {
    if (seen.has(p.label)) continue;
    seen.add(p.label);
    out.push(p);
  }
  return out;
}

// --- Emission ----------------------------------------------------------------

interface Row {
  matchText: string;
  label: string;
  grams: number;
  sortOrder: number;
  source: string;
}

const q = (s: string) => `'${s.replace(/'/g, "''")}'`;
const num = (n: number) => String(Math.round(n * 100) / 100);

function main(): void {
  const dirs = Deno.args;
  if (dirs.length === 0) {
    console.error("usage: gen_measures.ts <dataset_dir> [<dataset_dir>...]");
    Deno.exit(1);
  }
  const here = new URL(".", import.meta.url).pathname;

  // The committed links: vocab match_text → its own FDC food.
  const links: { match_text: string; fdc_id: number }[] = Deno
    .readTextFileSync(`${here}../usda_links.jsonl`)
    .split("\n")
    .filter((l) => l.trim())
    .map((l) => JSON.parse(l));

  // Every match_text we emit must exist in the vocab — fail loudly, never
  // emit rows that would silently miss the join (honest numbers). The value
  // is the row's default unit, which the piece-weight pass below needs: a
  // piece weight is a fact about a COUNTED row and about no other kind.
  const vocab = new Map<string, string>(
    Deno.readTextFileSync(`${here}../vocab.jsonl`)
      .split("\n")
      .filter((l) => l.trim())
      .map((l) => JSON.parse(l))
      .map((
        r,
      ) => [
        normalize(r.canonical_name as string),
        (r.default_unit as string | undefined) ?? "piece",
      ]),
  );

  const wanted = new Set<string>([
    ...links.map((l) => String(l.fdc_id)),
    ...BORROWS.map((b) => b.fdcId),
  ]);
  const byFood = loadPortions(dirs, wanted);
  const descs = loadDescriptions(dirs, wanted);

  // Shared-link ownership (review N6): several vocab rows can link the same
  // FDC food ("berry" and "blueberry" → Blueberries, raw). The row(s) whose
  // words best match the food's description own it; every other sharer's
  // measures are an implicit borrow and must say so in `source`.
  const sharers = new Map<string, string[]>();
  for (const l of links) {
    const id = String(l.fdc_id);
    (sharers.get(id) ?? sharers.set(id, []).get(id)!).push(l.match_text);
  }
  function isBorrowedLink(matchText: string, fdcId: string): boolean {
    const all = sharers.get(fdcId) ?? [];
    if (all.length < 2) return false;
    const descWords = new Set(normalize(descs.get(fdcId) ?? "").split(" "));
    const frac = (mt: string) => {
      const ws = mt.split(" ");
      return ws.filter((w) => descWords.has(w)).length / ws.length;
    };
    const max = Math.max(...all.map(frac));
    return frac(matchText) < max;
  }

  const rows: Row[] = [];
  let tier1 = 0, tier2 = 0, autoBorrowed = 0;

  // Tier 1: the ingredient's own linked food.
  for (const link of links) {
    if (SUPPRESS_TIER1.has(link.match_text)) continue;
    const id = String(link.fdc_id);
    const desc = descs.get(id) ?? "";
    const picked = pick(
      varietyFilter(
        link.match_text,
        basisFilter(link.match_text, desc, byFood.get(id) ?? []),
      ),
    );
    const borrowed = isBorrowedLink(link.match_text, id);
    picked.forEach((p, i) => {
      rows.push({
        matchText: link.match_text,
        label: finalizeLabel(link.match_text, p.label),
        grams: p.grams,
        sortOrder: i,
        source: `usda_fdc:${p.fdcId} (${p.source})${
          borrowed ? " — borrowed" : ""
        }`,
      });
      tier1++;
      if (borrowed) autoBorrowed++;
    });
  }

  // Tier 2: explicit borrows, marked as such.
  for (const b of BORROWS) {
    const picked = pick(
      basisFilter(
        b.matchText,
        descs.get(b.fdcId) ?? "",
        byFood.get(b.fdcId) ?? [],
      ),
    );
    if (picked.length === 0) {
      throw new Error(
        `borrow source ${b.fdcId} (${b.matchText}) has no portions`,
      );
    }
    picked.forEach((p, i) => {
      rows.push({
        matchText: b.matchText,
        label: finalizeLabel(b.matchText, p.label),
        grams: p.grams,
        sortOrder: i,
        source: `usda_fdc:${p.fdcId} (${p.source}) — borrowed`,
      });
      tier2++;
    });
  }

  // Curated survivors.
  for (const [i, t] of TYPICAL.entries()) {
    void i;
    rows.push({
      matchText: t.matchText,
      label: t.label,
      grams: t.grams,
      sortOrder: 0,
      source: "seed:typical",
    });
  }

  // Generous extraction means two raw labels can finalize to the same
  // display label ("fruit" and "whole" both → "whole"): keep the first
  // (best-ranked) occurrence rather than failing.
  {
    const seen = new Set<string>();
    const deduped = rows.filter((r) => {
      const key = `${r.matchText} ${r.label}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
    rows.length = 0;
    rows.push(...deduped);
  }

  // --- Curation overrides (plan 0013) ----------------------------------------
  // ../curation_overrides.jsonl is the committed, audited record of the
  // LLM/human curation pass over the generated output — every override
  // carries a reason. This script honours `drop_measure` and `add_measure`;
  // gen_seed.ts honours `density` and `allowed_units`. A drop that matches
  // nothing is stale and fails the run rather than rotting silently.
  let dropped = 0, added = 0;
  const curation = readOverrides(here);
  for (const o of curation) {
    if (o.kind === "drop_measure") {
      const before = rows.length;
      const keep = rows.filter(
        (r) => !(r.matchText === o.match_text && r.label === o.label),
      );
      if (keep.length === before) {
        console.error(
          `stale drop_measure override: ${o.match_text} / ${o.label}`,
        );
        Deno.exit(1);
      }
      dropped += before - keep.length;
      rows.length = 0;
      rows.push(...keep);
    } else if (o.kind === "add_measure") {
      rows.push({
        matchText: o.match_text,
        label: o.label as string,
        grams: o.basis_amount!,
        sortOrder: o.sort_order ?? 0,
        source: o.source ?? "seed:typical",
      });
      added++;
    }
  }

  // Validate: every match_text resolves in the vocab; labels unique per
  // ingredient (no unique index guards this since 0011 — the seed's own
  // not-exists guard would silently keep only the first duplicate).
  const problems: string[] = [];
  const labelSeen = new Set<string>();
  for (const r of rows) {
    if (!vocab.has(r.matchText)) {
      problems.push(`match_text not in vocab: "${r.matchText}"`);
    }
    const key = `${r.matchText} ${r.label}`;
    if (labelSeen.has(key)) {
      problems.push(`duplicate label for ${r.matchText}: "${r.label}"`);
    }
    labelSeen.add(key);
    if (!(r.grams > 0)) {
      problems.push(`non-positive basis_amount: ${r.matchText}`);
    }
  }

  // --- The piece-weight pass (ADR-0015) --------------------------------------
  // This script owns the final measure list, so it is the only place that can
  // check a borrowing `piece_weight` label against what the row actually
  // carries. Three gates, all exhaustiveness rather than taste:
  //   * a label that names no live measure on its row is STALE — the same
  //     failure a stale `drop_measure` gets;
  //   * every PIECE-DEFAULT vocab row must carry a ruling, so a regenerated
  //     USDA seed cannot quietly add a counted row nobody weighed. A row that
  //     has no honest whole has its `default_unit` changed in vocab.jsonl
  //     instead (mint) — there is no "no answer" answer any more;
  //   * a ruling on a row that is NOT piece-default says nothing under the
  //     rule, so it is a leftover rather than a decision.
  const labelsByRow = new Map<string, Set<string>>();
  for (const r of rows) {
    let labels = labelsByRow.get(r.matchText);
    if (labels === undefined) {
      labels = new Set<string>();
      labelsByRow.set(r.matchText, labels);
    }
    labels.add(r.label);
  }
  const ruled = new Set<string>();
  for (const o of curation) {
    if (o.kind !== "piece_weight") continue;
    if (ruled.has(o.match_text)) {
      problems.push(`two piece_weight rulings for ${o.match_text}`);
    }
    ruled.add(o.match_text);
    if (vocab.get(o.match_text) !== "piece") {
      problems.push(
        `piece_weight on a row whose default_unit is ` +
          `"${vocab.get(o.match_text) ?? "(not in vocab)"}": ${o.match_text} ` +
          `— a piece weight only says something about a counted row`,
      );
      continue;
    }
    if (o.label === undefined) continue; // an explicit basis_amount
    const have = labelsByRow.get(o.match_text);
    if (!have) {
      problems.push(
        `piece_weight borrows a label on a row with no measures: ` +
          `${o.match_text}`,
      );
    } else if (!have.has(o.label as string)) {
      problems.push(
        `stale piece_weight override: ${o.match_text} / "${o.label}" ` +
          `(row carries: ${[...have].join(", ")})`,
      );
    }
  }
  for (const [matchText, unit] of vocab) {
    if (unit === "piece" && !ruled.has(matchText)) {
      problems.push(
        `no piece_weight ruling for the piece-default row "${matchText}" — ` +
          `add one to curation_overrides.jsonl (a measure label to borrow, ` +
          `or an explicit basis_amount), or move the row off a count default`,
      );
    }
  }

  if (problems.length > 0) {
    console.error(problems.join("\n"));
    Deno.exit(1);
  }

  rows.sort(
    (a, b) =>
      a.matchText.localeCompare(b.matchText) || a.sortOrder - b.sortOrder,
  );
  const matchTexts = [...new Set(rows.map((r) => r.matchText))].sort();

  const out: string[] = [
    "-- seed_measures.sql — GENERATED by seed/scripts/gen_measures.ts. Do NOT",
    "-- hand-edit; edit the script (borrow map / typical survivors / filter",
    "-- rules) and re-run it against the FDC CSV bundles (seed/README.md).",
    "--",
    "-- Starter measures for the template vocab (step 7.6): piece-type USDA",
    "-- FDC food_portion weights joined by match_text, per-row provenance in",
    "-- `source` (0010), amounts in the ingredient's basis unit (0012 —",
    "-- every seeded vocab row is per-100 g, so FDC gram weights carry",
    "-- verbatim). Generously extracted, then trimmed by the committed",
    "-- curation_overrides.jsonl (plan 0013). Idempotent: re-runs no-op on",
    "-- existing live labels",
    "-- (a `where not exists` guard — 0011 dropped the unique index the old",
    "-- `on conflict` targeted; offline dupes must never fail upload), and",
    "-- the trailing check names any match_text the vocab no longer carries",
    "-- instead of silently seeding nothing for it.",
    "",
    "begin;",
    "",
    "insert into ingredient_measure",
    "  (household_id, ingredient_id, label, basis_amount, sort_order, source)",
    `select '${HOUSEHOLD_ID}', i.id, m.label, m.basis_amount, m.sort_order, m.source`,
    "from ingredient i",
    "join (values",
    rows
      .map(
        (r) =>
          `  (${q(r.matchText)}, ${q(r.label)}, ${num(r.grams)}, ` +
          `${r.sortOrder}, ${q(r.source)})`,
      )
      .join(",\n"),
    ") as m(ing_match, label, basis_amount, sort_order, source)",
    "  on i.match_text = m.ing_match",
    `where i.household_id = '${HOUSEHOLD_ID}' and i.deleted_at is null`,
    "  and not exists (",
    "    select 1 from ingredient_measure im",
    "    where im.ingredient_id = i.id and im.label = m.label",
    "      and im.deleted_at is null",
    "  );",
    "",
    "-- Every seeded match_text must still exist in the vocab: a regeneration",
    "-- that drops or renames one would otherwise silently drop its measures.",
    "do $$",
    "declare",
    "  missing text;",
    "  n int;",
    "begin",
    "  select string_agg(m.mt, ', ') into missing",
    "  from (values",
    matchTexts.map((m) => `    (${q(m)})`).join(",\n"),
    "  ) as m(mt)",
    "  where not exists (",
    "    select 1 from ingredient i",
    `    where i.household_id = '${HOUSEHOLD_ID}'`,
    "      and i.deleted_at is null and i.match_text = m.mt",
    "  );",
    "  -- raise, not ASSERT: plpgsql.check_asserts can be disabled, and this",
    "  -- check must never be.",
    "  if missing is not null then",
    "    raise exception",
    "      'seed_measures: no live vocab ingredient for: %', missing;",
    "  end if;",
    "  select count(*) into n from ingredient_measure",
    `  where household_id = '${HOUSEHOLD_ID}' and deleted_at is null;`,
    `  raise notice 'seed_measures: % live template measures (% seeded)', n, ${rows.length};`,
    "end $$;",
    "",
    "commit;",
    "",
  ];

  const target = `${here}../../seed_measures.sql`;
  Deno.writeTextFileSync(target, out.join("\n"));
  console.log(
    `wrote ${target}\n  ${rows.length} rows over ${matchTexts.length} ` +
      `ingredients (tier1 ${tier1} incl. ${autoBorrowed} auto-borrowed, ` +
      `tier2/borrowed ${tier2}, typical ${TYPICAL.length}; curation ` +
      `dropped ${dropped}, added ${added})`,
  );
  for (const r of rows) {
    console.log(
      `  ${r.matchText} | ${r.label} | ${num(r.grams)} g | ${r.source}`,
    );
  }
}

if (import.meta.main) main();
