// Generates supabase/seed.sql from the arbiter's curated vocabulary
// (out/seed_vocab.jsonl). The LLM arbiter makes the ingredient judgments; this
// step is deterministic — it computes each row's match_text with the SHARED §7
// normalizer (so stored match_text is symmetric with the runtime cascade) and
// emits plain SQL. Run: deno task gen-seed
//
// Everything seeds as status='stub' (no density/macros yet — honest numbers).

import { normalize } from "../../functions/_shared/normalize.ts";
import { readOverrides } from "./overrides.ts";
import {
  FAO_DATASET,
  FAO_PROVENANCE,
  LINK_DENSITY_MAX,
  LINK_DENSITY_MIN,
  resolveFaoFills,
} from "./fao.ts";

// A fixed household so re-generating is stable and the seed is idempotent under
// `supabase db reset`.
const HOUSEHOLD_ID = "00000000-0000-0000-0000-0000000000aa";
const HOUSEHOLD_NAME = "Home";

// Valid units.dart ids (default_unit must be one of these).
const UNIT_IDS = new Set([
  "g",
  "kg",
  "oz",
  "lb",
  "ml",
  "l",
  "tsp",
  "tbsp",
  "fl_oz",
  "cup",
  "pt",
  "qt",
  "piece",
  "pinch",
  "dash",
  "to_taste",
]);

export interface VocabRow {
  canonical_name: string;
  category?: string;
  default_unit?: string;
  aliases?: string[];
  source_examples?: string[];
  notes?: string;
}

export interface SeedIngredient extends VocabRow {
  /** `normalize(canonical_name)` — the row's stored `match_text`. */
  match: string;
}

export interface SeedAlias {
  /** The owning ingredient's match_text — what the SQL joins on. */
  ing_match: string;
  alias_text: string;
  alias_match: string;
}

export interface SeedPlan {
  ingredients: SeedIngredient[];
  aliases: SeedAlias[];
  /** Every reason the seed must not be written. Empty means go. */
  problems: string[];
}

const sqlStr = (s: string) => `'${s.replace(/'/g, "''")}'`;

/**
 * Validates the vocab and computes every `match_text` the seed will store.
 *
 * ONE namespace for the lot — ingredient and alias keys together — because
 * that is how the runtime reads them: the cascade's exact tier searches both
 * tables as a single surface, and the picker's row surface is the union of a
 * row's own key and its aliases. An alias that normalizes onto ANOTHER
 * ingredient's key (or another ingredient's alias) would therefore route
 * every exact hit for that text to whichever row the query happened to reach
 * first — silently, and differently on each side. So it is a build failure
 * naming both sides, never a skip. The only aliases dropped quietly are the
 * ones the ingredient itself already covers: its own canonical key, or a
 * second alias of the same ingredient landing on the same text.
 */
export function planSeed(rows: VocabRow[]): SeedPlan {
  const problems: string[] = [];
  // match_text → who holds it, phrased for the failure message.
  const owner = new Map<string, { name: string; via: string }>();

  const ingredients = rows.map((r) => {
    const match = normalize(r.canonical_name);
    if (!match) problems.push(`empty match_text for ${r.canonical_name}`);
    const held = owner.get(match);
    if (held) {
      problems.push(
        `match_text "${match}" collides: ${held.name} vs ${r.canonical_name}`,
      );
    }
    owner.set(match, { name: r.canonical_name, via: "canonical name" });
    if (r.default_unit && !UNIT_IDS.has(r.default_unit)) {
      problems.push(
        `bad default_unit "${r.default_unit}" on ${r.canonical_name}`,
      );
    }
    return { ...r, match };
  });

  const aliases: SeedAlias[] = [];
  for (const ing of ingredients) {
    for (const alias of ing.aliases ?? []) {
      const am = normalize(alias);
      if (!am) continue;
      const held = owner.get(am);
      if (held?.name === ing.canonical_name) continue; // already covered
      if (held) {
        problems.push(
          `alias "${alias}" of ${ing.canonical_name} normalizes to "${am}", ` +
            `already held by ${held.name} (${held.via})`,
        );
        continue;
      }
      owner.set(am, { name: ing.canonical_name, via: `alias "${alias}"` });
      aliases.push({
        ing_match: ing.match,
        alias_text: alias,
        alias_match: am,
      });
    }
  }

  return { ingredients, aliases, problems };
}

function main(): void {
  const dir = new URL(".", import.meta.url).pathname;
  // Optional overrides for testing: gen_seed.ts [inputJsonl] [outputSql].
  // Default input is the committed curated vocab (LLM+human judgment — tracked,
  // unlike the regenerable raw mining outputs in out/).
  const inputPath = Deno.args[0] ?? `${dir}../vocab.jsonl`;
  const outputPath = Deno.args[1] ?? `${dir}../../seed.sql`;
  const rows: VocabRow[] = Deno.readTextFileSync(inputPath)
    .split("\n").map((l) => l.trim()).filter(Boolean).map((l) => JSON.parse(l));

  // A collision would break the alias join or shadow another row's exact
  // match, so fail loudly rather than emit a broken seed.
  const { ingredients, aliases, problems } = planSeed(rows);
  if (problems.length) {
    console.error(
      "seed vocab problems:\n" + problems.map((p) => "  " + p).join("\n"),
    );
    Deno.exit(1);
  }

  // Alias rows join to their ingredient by the ingredient's match_text.
  const aliasRows = aliases.map((a) =>
    `  (${sqlStr(a.ing_match)}, ${sqlStr(a.alias_text)}, ${
      sqlStr(a.alias_match)
    })`
  );

  const out: string[] = [];
  out.push(
    "-- seed.sql — GENERATED by scripts/gen_seed.ts from scripts/out/seed_vocab.jsonl.",
    "-- Do not edit by hand; edit the vocab and regenerate (deno task gen-seed).",
    "-- Initial household + starter ingredient vocabulary. All status='stub' —",
    "-- density/macros are filled later (honest numbers).",
    "",
    "begin;",
    "",
    '-- is_template (0008): "Home" is the member-less vocab template new',
    "-- households clone from at onboarding; template households are never",
    "-- joinable.",
    `insert into household (id, name, is_template)`,
    `values (${sqlStr(HOUSEHOLD_ID)}, ${sqlStr(HOUSEHOLD_NAME)}, true)`,
    "on conflict (id) do update set is_template = true;",
    "",
    "-- Re-runnable (0020): the template holds ONE live row per match_text, so",
    "-- an existing row is refreshed in place (name, category, default unit —",
    "-- never status/macros/density, which later seeds and humans own) and a",
    "-- new one is inserted. A household is never touched here.",
    "with v(canonical_name, category, default_unit, match_text) as (values",
  );
  out.push(
    ingredients.map((ing) =>
      "  (" + [
        sqlStr(ing.canonical_name),
        ing.category ? sqlStr(ing.category) : "null",
        sqlStr(ing.default_unit ?? "piece"),
        sqlStr(ing.match),
      ].join(", ") + ")"
    ).join(",\n") + ")",
    ", refreshed as (",
    "  update ingredient i",
    "     set canonical_name = v.canonical_name, category = v.category,",
    "         default_unit = v.default_unit, updated_at = now()",
    "    from v",
    `   where i.household_id = ${sqlStr(HOUSEHOLD_ID)}`,
    "     and i.match_text = v.match_text and i.deleted_at is null",
    "     and (i.canonical_name, i.category, i.default_unit)",
    "         is distinct from (v.canonical_name, v.category, v.default_unit)",
    "  returning i.match_text",
    ")",
    "insert into ingredient",
    "  (household_id, canonical_name, category, default_unit, status, source, match_text)",
    `select ${
      sqlStr(HOUSEHOLD_ID)
    }, v.canonical_name, v.category, v.default_unit, 'stub', 'seed', v.match_text`,
    "  from v",
    " where not exists (",
    "   select 1 from ingredient i",
    `    where i.household_id = ${sqlStr(HOUSEHOLD_ID)}`,
    "      and i.match_text = v.match_text and i.deleted_at is null);",
  );

  if (aliasRows.length) {
    out.push(
      "",
      "insert into ingredient_alias",
      "  (household_id, ingredient_id, alias_text, match_text, source)",
      `select ${
        sqlStr(HOUSEHOLD_ID)
      }, i.id, a.alias_text, a.alias_match, 'seed'`,
      "from ingredient i",
      "join (values",
      aliasRows.join(",\n"),
      ") as a(ing_match, alias_text, alias_match) on i.match_text = a.ing_match",
      `where i.household_id = ${sqlStr(HOUSEHOLD_ID)} and i.deleted_at is null`,
      "  and not exists (",
      "    select 1 from ingredient_alias x",
      "     where x.ingredient_id = i.id and x.match_text = a.alias_match",
      "       and x.deleted_at is null);",
    );
  }
  out.push("", "commit;", "");

  Deno.writeTextFileSync(outputPath, out.join("\n"));
  console.log(
    `wrote ${outputPath}\n  ${ingredients.length} ingredients, ${aliasRows.length} aliases`,
  );

  writePrefill(dir);
  writeCuration(dir, new Set(ingredients.map((i) => i.match)));
}

// seed_prefill.sql — fills macros/density from usda_food for the ingredients
// linked to a USDA fdc_id (auto trigram matches + arbiter picks, in
// usda_links.jsonl). Runs AFTER seed_usda.sql (see config.toml sql_paths).
function writePrefill(dir: string): void {
  const linksPath = `${dir}../usda_links.jsonl`;
  let text: string;
  try {
    text = Deno.readTextFileSync(linksPath);
  } catch {
    return; // no links yet — prefill is optional
  }
  const links = text.split("\n").map((l) => l.trim()).filter(Boolean)
    .map((l) => JSON.parse(l) as { match_text: string; fdc_id: number });
  if (links.length === 0) return;

  const rows = links.map((l) => `  (${sqlStr(l.match_text)}, ${l.fdc_id})`);
  const sql = [
    "-- seed_prefill.sql — GENERATED by scripts/gen_seed.ts from usda_links.jsonl.",
    "-- Fills macros/density from the usda_food reference for linked ingredients.",
    "-- Runs after seed_usda.sql. status → 'complete' once macros are present.",
    "",
    "update ingredient i set",
    "  -- only overwrite macros when the reference actually has them",
    "  macros = case when u.macros ? 'kcal' then u.macros else i.macros end,",
    "  density_g_per_ml = coalesce(u.density_g_per_ml, i.density_g_per_ml),",
    "  source = 'usda_fdc:' || u.fdc_id,",
    "  -- the label rides with the stamp, so a row never says usda_fdc:<id>",
    "  -- without being able to say WHICH food (0027's trigger keeps the same",
    "  -- rule for rows the server matches on its own)",
    "  source_label = u.description,",
    "  status = case when u.macros ? 'kcal' then 'complete' else i.status end",
    "from (values",
    rows.join(",\n"),
    ") as m(match_text, fdc_id)",
    "join usda_food u on u.fdc_id = m.fdc_id",
    `where i.match_text = m.match_text and i.household_id = ${
      sqlStr(HOUSEHOLD_ID)
    };`,
    "",
  ];
  const target = `${dir}../../seed_prefill.sql`;
  Deno.writeTextFileSync(target, sql.join("\n"));
  console.log(`wrote ${target}\n  ${links.length} usda prefill links`);
}

// seed_curation.sql — the LAST seed step (config.toml sql_paths order):
//
//   1. applies the committed curation overrides (curation_overrides.jsonl,
//      plan 0013): per-ingredient macros and densities a human judged the
//      rules wrong about, each with its reason emitted as a SQL comment so
//      the generated file stays auditable on its own;
//   2. fills the density TAIL from the FAO/INFOODS fallback (fao.ts) —
//      strictly into rows the FDC derivation and the overrides both left
//      null;
//   3. sets each piece-default row's `piece_basis_amount` (ADR-0015) — what
//      ONE of it weighs — borrowed from the curated measure the ruling names,
//      which is why this runs after seed_measures.sql;
//   4. refreshes the template vocab's materialized `allowed_units` from
//      `default_allowed_units()` (0012) — the insert-time trigger ran before
//      seed_prefill landed densities and before the piece weights above, so
//      neither the density-unlocked family nor `piece` appears until this
//      refresh;
//   5. applies the allowed-unit overrides on top of that refresh.
//
// Measure overrides (drop/add) are gen_measures.ts's job — they change what
// seed_measures.sql emits rather than patching it afterwards.
function writeCuration(dir: string, vocabMatchTexts: Set<string>): void {
  const overrides = readOverrides(dir);
  const q = sqlStr;
  const sql: string[] = [
    "-- seed_curation.sql — GENERATED by scripts/gen_seed.ts from",
    "-- curation_overrides.jsonl. Do not edit by hand; edit the overrides",
    "-- (with reasons) and regenerate (deno task gen-seed).",
    "--",
    "-- Runs LAST: applies the audited curation overrides (plan 0013), fills",
    "-- the density tail from the FAO/INFOODS fallback, sets each counted",
    "-- row's piece weight (ADR-0015 — what ONE of it weighs), and refreshes",
    "-- the template vocab's materialized allowed_units now that every",
    "-- density source AND every piece weight has run.",
    "--",
    `-- Density fallback dataset: ${FAO_DATASET}`,
    "-- (see seed/fao_density.jsonl for the source URL + sha256, and",
    "--  seed/fao_density_links.jsonl for the reviewed mapping).",
    "",
    "begin;",
    "",
  ];

  // Label-sourced macros: rows FDC genuinely lacks (no-analogue keeps them
  // link-less) or whose FDC macros are wrong get honest label numbers, flip
  // to complete, and carry a visible "label:…" source.
  let macroFills = 0;
  for (const o of overrides) {
    if (o.kind === "macros") {
      macroFills++;
      // A stamp that names an FDC food — `usda_fdc:171413 — borrowed (…)`
      // — names it on the row too: the label is the food the numbers came
      // from, looked up in the reference at seed time. A `label:…` source
      // names no reference food, so its label is cleared rather than left
      // saying whatever the prefill wrote before the override.
      const fdc = /^usda_fdc:(\d+)/.exec(o.source!)?.[1];
      const label = fdc
        ? `(select description from usda_food where fdc_id = ${fdc})`
        : "null";
      sql.push(
        `-- ${o.match_text}: ${o.reason}`,
        "update ingredient set",
        `  macros = ${q(JSON.stringify(o.macros))}::jsonb,`,
        `  source = ${q(o.source!)},`,
        `  source_label = ${label},`,
        "  status = 'complete'",
        `where household_id = ${q(HOUSEHOLD_ID)} and match_text = ${
          q(o.match_text)
        };`,
        "",
      );
    }
  }

  // Density overrides FIRST, so the allowed_units refresh below sees them.
  //
  // A fill that carries a `source` also stamps its provenance onto the row,
  // by the same append rule the FAO fallback uses below: keep whatever the
  // row already says about its MACROS and add where the density came from,
  // so both are readable off the row. `usda_fdc:` is refused upstream
  // (overrides.ts) because that prefix is the macro prefill's mark.
  let densities = 0, unitTweaks = 0;
  for (const o of overrides) {
    if (o.kind === "density") {
      densities++;
      const value = o.value === null ? "null" : `${o.value}`;
      sql.push(`-- ${o.match_text}: ${o.reason}`);
      if (o.source) {
        sql.push(
          "update ingredient set",
          `  density_g_per_ml = ${value},`,
          "  source = case when source is null or source = 'seed'",
          `    then ${q(o.source)}`,
          `    else source || ${q(` + ${o.source}`)} end`,
        );
      } else {
        sql.push(`update ingredient set density_g_per_ml = ${value}`);
      }
      sql.push(
        `where household_id = ${q(HOUSEHOLD_ID)} and match_text = ${
          q(o.match_text)
        };`,
        "",
      );
    }
  }

  // FAO/INFOODS density fallback — LAST of the three density sources, and
  // only into the gap: every statement carries `density_g_per_ml is null`, so
  // an FDC-derived or curation-set density can never be overwritten no matter
  // what the mapping says.
  const fao = resolveFaoFills(
    dir,
    vocabMatchTexts,
    new Set(
      overrides.filter((o) => o.kind === "density").map((o) => o.match_text),
    ),
  );
  const faoFills = fao?.fills ?? [];
  if (fao) {
    sql.push(
      `-- Density fallback: ${FAO_DATASET}, via the reviewed`,
      "-- fao_density_links.jsonl map. Fills ONLY rows the FDC volume-portion",
      "-- derivation and the curation overrides above both left null; the",
      `-- null guard on each statement is what enforces that. ${faoFills.length} fills,`,
      `-- ${fao.rejected} tail rows audited and honestly left density-less,`,
      `-- ${fao.superseded} more audited against FAO with no match and since`,
      "-- filled by a cited curation override above (FDC sibling record,",
      "-- label, or family bracket) — the FAO verdict stands, it just is no",
      "-- longer the last word on those rows.",
      "",
    );
    for (const f of faoFills) {
      sql.push(
        `-- ${f.match_text} <- FAO "${f.food}" [${f.biblio}; ${f.section}]:`,
        `--   ${f.reason}`,
        "update ingredient set",
        `  density_g_per_ml = ${f.density},`,
        // Keep whatever provenance the row already carries (a macro source
        // like usda_fdc:… or label:…) and append the density's own, so a
        // reader can see BOTH where the numbers came from. Rows that only
        // ever said 'seed' just take the FAO tag.
        "  source = case when source is null or source = 'seed'",
        `    then ${q(`${FAO_PROVENANCE}:${f.food}`)}`,
        `    else source || ${q(` + ${FAO_PROVENANCE}:${f.food}`)} end`,
        `where household_id = ${q(HOUSEHOLD_ID)} and match_text = ${
          q(f.match_text)
        }`,
        "  and density_g_per_ml is null;",
        "",
      );
    }
  }

  // Piece weights (ADR-0015) — BEFORE the allowed_units refresh below, which
  // reads `piece_basis_amount` as the fifth argument of the rule. A borrowing
  // ruling copies the curated measure's `basis_amount` off the row's own live
  // measure (seed_measures.sql ran immediately before this file) and records
  // where it came from; an explicit `basis_amount` states the number outright
  // and says `seed:typical`, so a guess is visible rather than dressed as a
  // citation. Label validity is gen_measures.ts's gate (it owns the measure
  // list); a label that slipped through anyway sets nothing and is named by
  // the R3 check below.
  let pieceWeights = 0;
  for (const o of overrides) {
    if (o.kind !== "piece_weight") continue;
    pieceWeights++;
    sql.push(`-- ${o.match_text}: ${o.reason}`);
    if (o.basis_amount !== undefined) {
      sql.push(
        "update ingredient set",
        `  piece_basis_amount = ${o.basis_amount},`,
        "  piece_source = 'seed:typical'",
        `where household_id = ${q(HOUSEHOLD_ID)} and match_text = ${
          q(o.match_text)
        }`,
        "  and deleted_at is null;",
        "",
      );
    } else {
      sql.push(
        "update ingredient i set",
        "  piece_basis_amount = m.basis_amount,",
        "  piece_source = 'borrowed from ' || m.label",
        "  from ingredient_measure m",
        " where m.ingredient_id = i.id",
        "   and m.household_id = i.household_id",
        "   and m.deleted_at is null",
        `   and m.label = ${q(o.label as string)}`,
        `   and i.household_id = ${q(HOUSEHOLD_ID)}`,
        `   and i.match_text = ${q(o.match_text)}`,
        "   and i.deleted_at is null;",
        "",
      );
    }
  }

  sql.push(
    "-- Re-materialize allowed_units with post-prefill (and post-override)",
    "-- densities and the piece weights above: the insert trigger ran before",
    "-- seed_prefill landed them, so density-unlocked families and `piece`",
    "-- are missing until this refresh.",
    "update ingredient set allowed_units = default_allowed_units(",
    "  default_unit, macros_basis, density_g_per_ml, category,",
    "  piece_basis_amount)",
    `where household_id = ${q(HOUSEHOLD_ID)} and deleted_at is null;`,
    "",
    "-- RETIRED 2026-08-31 (migration 0014 / ADR-0009): the produce volume",
    "-- leg used to live here as a category-gated patch — 49 piece-default",
    "-- produce rows given cup/tbsp/ml explicitly because ADR-0008's density",
    "-- leg fired only for mass/volume defaults (\"a density can't describe",
    '-- a piece"), so "1 cup diced mango" failed on import even though the',
    "-- row had carried an honest density all along. ADR-0009 amended the",
    "-- rule instead: a density unlocks the other mass/volume family",
    "-- whatever the default unit's family, so the refresh above now emits",
    "-- those admissions on its own. One source of the fact; the safety net",
    "-- is a pgTAP assertion (supabase/tests/unit_admission.sql), not a",
    "-- second stored copy of the rule.",
    "",
  );

  for (const o of overrides) {
    if (o.kind === "allowed_units") {
      unitTweaks++;
      sql.push(`-- ${o.match_text}: ${o.reason}`);
      if (o.set) {
        sql.push(
          "update ingredient set allowed_units = " +
            `${q(JSON.stringify(o.set))}::jsonb`,
          `where household_id = ${q(HOUSEHOLD_ID)} and match_text = ${
            q(o.match_text)
          };`,
          "",
        );
      } else {
        for (const u of o.add ?? []) {
          sql.push(
            "update ingredient set allowed_units = " +
              `allowed_units || ${q(JSON.stringify([u]))}::jsonb`,
            `where household_id = ${q(HOUSEHOLD_ID)} and match_text = ${
              q(o.match_text)
            } and not allowed_units ? ${q(u)};`,
            "",
          );
        }
        for (const u of o.remove ?? []) {
          sql.push(
            "update ingredient set allowed_units = " +
              "(select coalesce(jsonb_agg(e), '[]'::jsonb)",
            "   from jsonb_array_elements_text(allowed_units) e",
            `   where e <> ${q(u)})`,
            `where household_id = ${q(HOUSEHOLD_ID)} and match_text = ${
              q(o.match_text)
            };`,
            "",
          );
        }
      }
    }
  }

  // `ingredient.default_measure_id` ("Counts as", 0023 seam D1) was set here
  // until 2026-09-08 and is RETIRED by ADR-0015: the same judgment now lands
  // as `piece_basis_amount` above, a number the converter can actually use.
  // The column stays on the table for one release (data is durable), but
  // nothing writes it on a fresh stack, and nothing reads it at all.

  sql.push(
    "-- R1 invariant (Simon, 2026-08-29): a volume default_unit REQUIRES a",
    "-- density — a volume line on a density-less per-g ingredient can never",
    "-- compute macros, so the class must not silently return. Fill an honest",
    "-- density (FDC / label / typical, tagged) or flip the default to a",
    "-- weight, always via the pipeline inputs.",
    "do $$",
    "declare violators text;",
    "begin",
    "  select string_agg(canonical_name || ' (' || default_unit || ')', ', ')",
    "    into violators",
    "  from ingredient",
    `  where household_id = ${q(HOUSEHOLD_ID)} and deleted_at is null`,
    "    and default_unit in ('ml', 'l', 'tsp', 'tbsp', 'fl_oz', 'cup',",
    "                         'pt', 'qt')",
    "    and density_g_per_ml is null;",
    "  if violators is not null then",
    "    raise exception",
    "      'seed_curation R1: volume-default rows with no density: %',",
    "      violators;",
    "  end if;",
    "",
    "  -- R2: every stored density is a KITCHEN density. A number outside",
    "  -- this band is a parse artifact or the wrong physical quantity (FAO",
    "  -- publishes salt at 2.165 and bicarbonate at 2.2 — crystal densities,",
    "  -- not what a spoonful weighs). Generation bounds the FAO fills; this",
    "  -- bounds what actually landed, whatever the source.",
    "  select string_agg(",
    "           canonical_name || ' (' || density_g_per_ml || ')', ', ')",
    "    into violators",
    "  from ingredient",
    `  where household_id = ${q(HOUSEHOLD_ID)} and deleted_at is null`,
    "    and density_g_per_ml is not null",
    `    and density_g_per_ml not between ${LINK_DENSITY_MIN} and ${LINK_DENSITY_MAX};`,
    "  if violators is not null then",
    "    raise exception",
    `      'seed_curation R2: densities outside ${LINK_DENSITY_MIN}-${LINK_DENSITY_MAX} g/ml: %',`,
    "      violators;",
    "  end if;",
    "",
    "",
    "  -- R3 (ADR-0015): `piece` is admitted by a WEIGHT, so the two halves of",
    "  -- that rule are the two halves of this invariant.",
    "  --",
    "  -- (a) Every counted row says what one of it weighs. A piece-default row",
    "  --     with no piece weight is a STRANDED default: it would offer a",
    "  --     `piece` nothing can convert, total or shop. Fix it by borrowing",
    "  --     the curated whole-item measure, stating an honest typical weight,",
    "  --     or moving the row off a count default — always via the pipeline",
    "  --     inputs. A ruling whose label no longer names a live measure lands",
    "  --     nothing and is caught here.",
    "  select string_agg(canonical_name, ', ') into violators",
    "  from ingredient",
    `  where household_id = ${q(HOUSEHOLD_ID)} and deleted_at is null`,
    "    and default_unit = 'piece' and piece_basis_amount is null;",
    "  if violators is not null then",
    "    raise exception",
    "      'seed_curation R3a: piece-default rows with no piece weight: %',",
    "      violators;",
    "  end if;",
    "",
    "  -- (b) …and nothing else admits `piece`. The refresh above derives it",
    "  --     only for a weighed count default, and no allowed-unit override",
    "  --     adds it back; this is what stops a regenerated seed offering a",
    "  --     `piece` of a row nobody counts.",
    "  select string_agg(canonical_name || ' (' || default_unit || ')', ', ')",
    "    into violators",
    "  from ingredient",
    `  where household_id = ${q(HOUSEHOLD_ID)} and deleted_at is null`,
    "    and default_unit <> 'piece' and allowed_units ? 'piece';",
    "  if violators is not null then",
    "    raise exception",
    "      'seed_curation R3b: rows admitting piece without a count default: %',",
    "      violators;",
    "  end if;",
    "",
    "  raise notice 'seed_curation: allowed_units refreshed; " +
      `${macroFills} macro + ${densities} density + ${unitTweaks} ` +
      `allowed-unit overrides + ${faoFills.length} FAO density fills; ` +
      `${pieceWeights} piece weights; ` +
      "R1 (volume default => density), R2 (kitchen density band) and " +
      "R3 (every counted row weighed, and only counted rows admit piece) " +
      "hold';",
    "end $$;",
    "",
    "commit;",
    "",
  );

  const target = `${dir}../../seed_curation.sql`;
  Deno.writeTextFileSync(target, sql.join("\n"));
  console.log(
    `wrote ${target}\n  ${macroFills} macro + ${densities} density + ` +
      `${unitTweaks} allowed-unit overrides + ${pieceWeights} piece weights` +
      (fao
        ? `\n  ${faoFills.length} FAO density fills, ${fao.rejected} audited ` +
          `rejections still bare, ${fao.superseded} since filled by ` +
          `curation (${fao.table.length} rows in ${FAO_DATASET})`
        : ""),
  );
}

if (import.meta.main) main();
