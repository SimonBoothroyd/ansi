// Generates supabase/seed_vocab.sql from supabase/seed/snapshot.jsonl — the
// CURATED CLOUD VOCABULARY, exported from the owner's live household and
// committed as the seed.
//
// The direction is cloud → seed. The rows a person actually curated in the
// app (densities they filled, units they admitted, measures they kept, piece
// weights they borrowed) ARE the truth; this script's only job is to turn
// that snapshot into one deterministic, re-runnable SQL file. There is no
// second pipeline deciding what a row should say — no mined vocabulary, no
// USDA link table, no FAO fallback, no overrides file. Whatever the snapshot
// says, the seed says.
//
// What it still DECIDES, because a snapshot cannot:
//
//   * `match_text` is RECOMPUTED with the shared §7 normalizer and asserted
//     equal to the exported value, so stored keys stay symmetric with the
//     runtime cascade. A drift fails the build naming both values.
//   * One namespace across every ingredient key and every alias key (the
//     cascade's exact tier reads them as a single surface), so a collision
//     fails the build naming both sides.
//   * A seed row must CLONE: `ensure_onboarded` skips `source = 'manual'`
//     ingredients and `source = 'import_correction'` aliases as a household's
//     private typed-in data (0039), so those are re-stamped `'seed'`.
//
// Run: deno task gen-seed

import { normalize } from "../../functions/_shared/normalize.ts";

// A fixed household so re-generating is stable and the seed is idempotent
// under `supabase db reset`.
const HOUSEHOLD_ID = "00000000-0000-0000-0000-0000000000aa";
const HOUSEHOLD_NAME = "Home";

// The kitchen density band (R2). A number outside it is a parse artefact or
// the wrong physical quantity — crystal salt at 2.165 g/ml is not what a
// spoonful weighs.
const DENSITY_MIN = 0.03, DENSITY_MAX = 2.0;

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
  "handful",
  "to_taste",
]);

const VOLUME_DEFAULTS = new Set([
  "ml",
  "l",
  "tsp",
  "tbsp",
  "fl_oz",
  "cup",
  "pt",
  "qt",
]);

/** One exported alias. `updated_at`/ids in the export are ignored. */
export interface SnapshotAlias {
  alias_text: string;
  match_text: string;
  source?: string | null;
}

/** One exported measure. `id`/`updated_at` in the export are ignored. */
export interface SnapshotMeasure {
  label: string;
  basis_amount: number | null;
  sort_order: number | null;
  source?: string | null;
}

/**
 * One exported ingredient — the shape `seed/export_all.sql` produces. `id`,
 * `created_at` and `updated_at` may be present and are ignored: the seed
 * mints its own row identity in whatever database it lands in.
 */
export interface SnapshotRow {
  canonical_name: string;
  category?: string | null;
  default_unit: string;
  macros_basis?: string | null;
  density_g_per_ml?: number | null;
  macros?: Record<string, number> | null;
  status?: string | null;
  source?: string | null;
  source_label?: string | null;
  source_score?: number | null;
  source_edited?: boolean | null;
  piece_basis_amount?: number | null;
  piece_source?: string | null;
  allowed_units?: string[] | null;
  match_text: string;
  derived_allowed_units?: string[] | null;
  aliases?: SnapshotAlias[];
  measures?: SnapshotMeasure[];
}

export interface SeedIngredient extends SnapshotRow {
  /** `normalize(canonical_name)` — asserted equal to the exported key. */
  match: string;
}

export interface SeedAlias {
  /** The owning ingredient's match_text — what the SQL joins on. */
  ing_match: string;
  alias_text: string;
  alias_match: string;
  source: string;
}

export interface SeedPlan {
  ingredients: SeedIngredient[];
  aliases: SeedAlias[];
  /** Every reason the seed must not be written. Empty means go. */
  problems: string[];
  /** Rows whose `source` was re-stamped so the clone carries them. */
  restampedRows: string[];
  /** Aliases whose `source` was re-stamped so the clone carries them. */
  restampedAliases: string[];
}

const sqlStr = (s: string) => `'${s.replace(/'/g, "''")}'`;
const txt = (s: string | null | undefined) =>
  s === null || s === undefined ? "null::text" : `${sqlStr(s)}::text`;
const num = (n: number | null | undefined) =>
  n === null || n === undefined ? "null::numeric" : `${n}::numeric`;
const json = (v: unknown) =>
  v === null || v === undefined
    ? "null::jsonb"
    : `${sqlStr(JSON.stringify(v))}::jsonb`;
const bool = (b: boolean | null | undefined) => (b ? "true" : "false");

/**
 * `ensure_onboarded` (0039) refuses to clone a household's private typed-in
 * data: `source = 'manual'` ingredients and `source = 'import_correction'`
 * aliases stay behind. A seed row that never clones is not a seed row, so
 * exactly those two stamps become `'seed'` here — and nothing else is
 * rewritten, because every other stamp is the row's real provenance and the
 * app prints it.
 */
const CLONE_BLIND_SOURCE = "manual";
const CLONE_BLIND_ALIAS_SOURCE = "import_correction";

/**
 * Validates the snapshot and plans every row the seed will write.
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
export function planSeed(rows: SnapshotRow[]): SeedPlan {
  const problems: string[] = [];
  const restampedRows: string[] = [];
  const restampedAliases: string[] = [];
  // match_text → who holds it, phrased for the failure message.
  const owner = new Map<string, { name: string; via: string }>();

  const ingredients = rows.map((r) => {
    const match = normalize(r.canonical_name);
    if (!match) problems.push(`empty match_text for ${r.canonical_name}`);
    // The snapshot carries the key the cloud stored; the seed must store the
    // key THIS normalizer writes. If they disagree the vocabulary and the
    // runtime cascade have drifted apart, so say both numbers and stop.
    if (match && r.match_text !== undefined && match !== r.match_text) {
      problems.push(
        `match_text drift on ${r.canonical_name}: snapshot says ` +
          `"${r.match_text}", the shared normalizer says "${match}"`,
      );
    }
    const held = owner.get(match);
    if (held) {
      problems.push(
        `match_text "${match}" collides: ${held.name} vs ${r.canonical_name}`,
      );
    }
    owner.set(match, { name: r.canonical_name, via: "canonical name" });
    if (!UNIT_IDS.has(r.default_unit)) {
      problems.push(
        `bad default_unit "${r.default_unit}" on ${r.canonical_name}`,
      );
    }
    const source = r.source === CLONE_BLIND_SOURCE ? "seed" : r.source;
    if (source !== r.source) restampedRows.push(r.canonical_name);
    return { ...r, match, source };
  });

  const aliases: SeedAlias[] = [];
  for (const ing of ingredients) {
    for (const alias of ing.aliases ?? []) {
      const am = normalize(alias.alias_text);
      if (!am) continue;
      if (alias.match_text !== undefined && am !== alias.match_text) {
        problems.push(
          `match_text drift on alias "${alias.alias_text}" of ` +
            `${ing.canonical_name}: snapshot says "${alias.match_text}", ` +
            `the shared normalizer says "${am}"`,
        );
      }
      const held = owner.get(am);
      if (held?.name === ing.canonical_name) continue; // already covered
      if (held) {
        problems.push(
          `alias "${alias.alias_text}" of ${ing.canonical_name} normalizes ` +
            `to "${am}", already held by ${held.name} (${held.via})`,
        );
        continue;
      }
      owner.set(am, {
        name: ing.canonical_name,
        via: `alias "${alias.alias_text}"`,
      });
      const source = alias.source && alias.source !== CLONE_BLIND_ALIAS_SOURCE
        ? alias.source
        : "seed";
      if (source !== alias.source) {
        restampedAliases.push(`${alias.alias_text} → ${ing.canonical_name}`);
      }
      aliases.push({
        ing_match: ing.match,
        alias_text: alias.alias_text,
        alias_match: am,
        source,
      });
    }
  }

  return { ingredients, aliases, problems, restampedRows, restampedAliases };
}

/** The units `allowed_units` adds to / withholds from the derived rule. */
export function unitDiff(
  stored: string[] | null | undefined,
  derived: string[] | null | undefined,
): { added: string[]; withheld: string[] } {
  const s = new Set(stored ?? []), d = new Set(derived ?? []);
  return {
    added: [...s].filter((u) => !d.has(u)),
    withheld: [...d].filter((u) => !s.has(u)),
  };
}

/** The ingredient columns the seed owns, in the order the SQL writes them. */
const COLUMNS = [
  "canonical_name",
  "category",
  "default_unit",
  "macros_basis",
  "density_g_per_ml",
  "macros",
  "status",
  "source",
  "source_label",
  "source_score",
  "source_edited",
  "piece_basis_amount",
  "piece_source",
  "allowed_units",
  "match_text",
];

function ingredientValues(ing: SeedIngredient): string {
  return "  (" + [
    txt(ing.canonical_name),
    txt(ing.category),
    txt(ing.default_unit),
    txt(ing.macros_basis ?? "g"),
    num(ing.density_g_per_ml),
    json(ing.macros ?? null),
    txt(ing.status ?? "stub"),
    txt(ing.source ?? "seed"),
    txt(ing.source_label),
    num(ing.source_score),
    bool(ing.source_edited),
    num(ing.piece_basis_amount),
    txt(ing.piece_source),
    json(ing.allowed_units ?? null),
    txt(ing.match),
  ].join(", ") + ")";
}

function buildSql(plan: SeedPlan): { sql: string; counts: Counts } {
  const { ingredients, aliases, restampedRows, restampedAliases } = plan;
  const q = sqlStr;
  const measures = ingredients.flatMap((i) =>
    (i.measures ?? []).map((m) => ({ ...m, ing_match: i.match }))
  );
  const complete = ingredients.filter((i) => i.status === "complete").length;
  const counts: Counts = {
    ingredients: ingredients.length,
    complete,
    stub: ingredients.length - complete,
    aliases: aliases.length,
    measures: measures.length,
    curated_unit_lists: 0,
  };

  const out: string[] = [
    "-- seed_vocab.sql — GENERATED by seed/scripts/gen_seed.ts from",
    "-- seed/snapshot.jsonl. Do NOT edit by hand: re-export the cloud",
    "-- household (seed/README.md) and re-run `deno task gen-seed`.",
    "--",
    "-- The template household and its whole curated vocabulary: every",
    "-- ingredient with the numbers a person actually curated (density,",
    "-- macros, basis, status, provenance, piece weight and the explicit",
    "-- allowed-unit list), its aliases, and its measures. This one file",
    "-- replaces the old five-stage pipeline (vocab → USDA prefill →",
    "-- measures → curation overrides → FAO density fallback): the cloud",
    "-- rows ARE the curation, so there is nothing left to re-derive.",
    "--",
    "-- seed_usda.sql and seed_usda_index.sql are untouched by this file —",
    "-- the USDA reference set is a different thing with a different owner",
    "-- (ADR-0005, seed/scripts/seed_usda.md).",
    "--",
    `-- ${counts.ingredients} ingredients (${counts.complete} complete, ` +
    `${counts.stub} stub), ${counts.aliases} aliases, ` +
    `${counts.measures} measures.`,
    "",
    "begin;",
    "",
    '-- is_template (0008): "Home" is the member-less vocab template new',
    "-- households clone from at onboarding; template households are never",
    "-- joinable.",
    "insert into household (id, name, is_template)",
    `values (${q(HOUSEHOLD_ID)}, ${q(HOUSEHOLD_NAME)}, true)`,
    "on conflict (id) do update set is_template = true;",
    "",
  ];

  // --- the clone-trap re-stamp -------------------------------------------
  out.push(
    "-- A seed row must CLONE. `ensure_onboarded` (0039) deliberately leaves",
    "-- a household's private typed-in data behind: `source = 'manual'`",
    "-- ingredients and `source = 'import_correction'` aliases are never",
    "-- copied into a new household. The exported rows are the TEMPLATE's",
    "-- vocabulary now, so the generator re-stamps exactly those two to",
    "-- 'seed' before they land here — otherwise the row would seed and then",
    "-- reach no household at all. Every other stamp is the row's real",
    "-- provenance and is carried verbatim.",
    `-- Re-stamped this run: ${restampedRows.length} ingredient sources, ` +
      `${restampedAliases.length} alias sources.`,
  );
  for (const r of restampedRows) out.push(`--   ingredient: ${r}`);
  for (const a of restampedAliases) out.push(`--   alias: ${a}`);
  out.push("");

  // --- ingredients --------------------------------------------------------
  out.push(
    "-- Re-runnable (0020): the template holds ONE live row per match_text,",
    "-- so an existing row is refreshed IN PLACE and a new one is inserted.",
    "-- The refresh owns every curated column now — name, category, default",
    "-- unit, basis, density, macros, status, provenance, piece weight and",
    "-- the allowed-unit list — because the snapshot is the whole truth about",
    "-- the row, not a first draft later steps corrected. A household is",
    "-- never touched here; the rollout scripts do that leg on purpose.",
    "--",
    "-- `allowed_units` is written EXPLICITLY. 0012's insert trigger fills it",
    "-- from `default_allowed_units()` only when the writer leaves it null, so",
    "-- passing the curated list is what keeps a curator's admission (and",
    "-- their refusals) instead of the derived default.",
    `with v(${COLUMNS.join(", ")}) as (values`,
    ingredients.map(ingredientValues).join(",\n") + ")",
    ", refreshed as (",
    "  update ingredient i",
    "     set canonical_name = v.canonical_name,",
    "         category = v.category,",
    "         default_unit = v.default_unit,",
    "         macros_basis = v.macros_basis,",
    "         density_g_per_ml = v.density_g_per_ml,",
    "         macros = v.macros,",
    "         status = v.status,",
    "         source = v.source,",
    "         source_label = v.source_label,",
    "         source_score = v.source_score,",
    "         source_edited = v.source_edited,",
    "         piece_basis_amount = v.piece_basis_amount,",
    "         piece_source = v.piece_source,",
    "         allowed_units = v.allowed_units,",
    "         updated_at = now()",
    "    from v",
    `   where i.household_id = ${q(HOUSEHOLD_ID)}`,
    "     and i.match_text = v.match_text and i.deleted_at is null",
    "     -- only a row that actually changed gets its updated_at bumped, so",
    "     -- a no-op reseed stays invisible to the rollout scripts.",
    "     and (i.canonical_name, i.category, i.default_unit, i.macros_basis,",
    "          i.density_g_per_ml, i.macros, i.status, i.source,",
    "          i.source_label, i.source_score, i.source_edited,",
    "          i.piece_basis_amount, i.piece_source, i.allowed_units)",
    "         is distinct from",
    "         (v.canonical_name, v.category, v.default_unit, v.macros_basis,",
    "          v.density_g_per_ml, v.macros, v.status, v.source,",
    "          v.source_label, v.source_score, v.source_edited,",
    "          v.piece_basis_amount, v.piece_source, v.allowed_units)",
    "  returning i.match_text",
    ")",
    "insert into ingredient",
    `  (household_id, ${COLUMNS.join(", ")})`,
    `select ${q(HOUSEHOLD_ID)}, ${COLUMNS.map((c) => "v." + c).join(", ")}`,
    "  from v",
    " where not exists (",
    "   select 1 from ingredient i",
    `    where i.household_id = ${q(HOUSEHOLD_ID)}`,
    "      and i.match_text = v.match_text and i.deleted_at is null);",
    "",
  );

  // --- the curated allowed-unit lists get the last word -------------------
  //
  // Two AFTER UPDATE triggers UNION units back into `allowed_units` when a
  // density (0014) or a piece weight (0039) ARRIVES on an existing row. They
  // exist so a server-side fill cannot leave a row's list half-honest, and
  // they are right for that — but on a REFRESH they would quietly re-admit a
  // unit the curator withheld, which is the one thing an explicit list is for.
  // They fire per statement, so the fix is one more statement: re-assert the
  // snapshot's list afterwards. A fresh insert never reaches this (the
  // triggers are update-only), and a no-op reseed changes nothing.
  out.push(
    "-- The curated list is the LAST WORD. `ingredient_density_unlocks_units`",
    "-- (0014) and `ingredient_piece_weight_unlocks_piece` (0039) union units",
    "-- into allowed_units when a density or a piece weight ARRIVES on an",
    "-- existing row — correct for a server-side fill, wrong for a reseed,",
    "-- where the exported list already IS the answer. So the refresh above",
    "-- may have been widened behind its back; this puts it back.",
    "update ingredient i set allowed_units = v.allowed_units",
    "from (values",
    ingredients.map((i) =>
      `  (${q(i.match)}, ${json(i.allowed_units ?? null)})`
    ).join(",\n"),
    ") as v(match_text, allowed_units)",
    `where i.household_id = ${q(HOUSEHOLD_ID)} and i.deleted_at is null`,
    "  and i.match_text = v.match_text",
    "  and i.allowed_units is distinct from v.allowed_units;",
    "",
  );

  // --- rows the snapshot no longer has are retired --------------------------
  //
  // The snapshot IS the template. An upsert keyed by match_text can only add
  // and refresh, so a row the owner deleted, or renamed (a new key beside the
  // old one), would live on in the template and clone into every new
  // household. Soft-delete keeps the rule every read already holds
  // (`deleted_at is null`), and the notice says how many went, because a
  // reseed that quietly retires rows is the same bug as one that quietly
  // keeps them.
  out.push(
    "-- Rows the snapshot no longer carries are retired: the snapshot is the",
    "-- template, and an upsert alone would leave a deleted or renamed row in",
    "-- place for the next household to clone. Soft-deleted, with their live",
    "-- aliases and measures, and counted.",
    "do $$",
    "declare n_retired int;",
    "begin",
    "  with gone as (",
    "    update ingredient i set deleted_at = now(), updated_at = now()",
    `    where i.household_id = ${q(HOUSEHOLD_ID)} and i.deleted_at is null`,
    "      and i.match_text not in (" +
      ingredients.map((i) => q(i.match)).join(", ") + ")",
    "    returning i.id",
    "  ), gone_aliases as (",
    "    update ingredient_alias a set deleted_at = now(), updated_at = now()",
    "    from gone where a.ingredient_id = gone.id and a.deleted_at is null",
    "  ), gone_measures as (",
    "    update ingredient_measure m set deleted_at = now(), updated_at = now()",
    "    from gone where m.ingredient_id = gone.id and m.deleted_at is null",
    "  )",
    "  select count(*) into n_retired from gone;",
    "  if n_retired > 0 then",
    "    raise notice 'seed_vocab: retired % template row(s) the snapshot no longer carries', n_retired;",
    "  end if;",
    "end $$;",
    "",
    "-- The same for a row's own words: a measure or alias the owner removed",
    "-- must not survive the reseed on a row that stays.",
    "update ingredient_measure m set deleted_at = now(), updated_at = now()",
    "from ingredient i",
    `where i.household_id = ${q(HOUSEHOLD_ID)} and i.deleted_at is null`,
    "  and m.ingredient_id = i.id and m.deleted_at is null",
    "  and not exists (select 1 from (values",
    measures.length
      ? measures.map((m) => `    (${q(m.ing_match)}, ${q(m.label)})`).join(
        ",\n",
      )
      : "    (null::text, null::text)",
    "  ) as keep(match_text, label)",
    "  where keep.match_text = i.match_text and keep.label = m.label);",
    "update ingredient_alias a set deleted_at = now(), updated_at = now()",
    "from ingredient i",
    `where i.household_id = ${q(HOUSEHOLD_ID)} and i.deleted_at is null`,
    "  and a.ingredient_id = i.id and a.deleted_at is null",
    "  and not exists (select 1 from (values",
    aliases.length
      ? aliases.map((a) => `    (${q(a.ing_match)}, ${q(a.alias_match)})`).join(
        ",\n",
      )
      : "    (null::text, null::text)",
    "  ) as keep(match_text, alias_match)",
    "  where keep.match_text = i.match_text and keep.alias_match = a.match_text);",
    "",
  );

  // --- aliases ------------------------------------------------------------
  if (aliases.length) {
    out.push(
      "-- Aliases join to their ingredient by the ingredient's match_text.",
      "-- Skip-existing (0020's per-(ingredient, match_text) unique index), so",
      "-- a reseed adds what is new and leaves the rest alone.",
      "insert into ingredient_alias",
      "  (household_id, ingredient_id, alias_text, match_text, source)",
      `select ${q(HOUSEHOLD_ID)}, i.id, a.alias_text, a.alias_match, a.source`,
      "from ingredient i",
      "join (values",
      aliases.map((a) =>
        `  (${q(a.ing_match)}, ${q(a.alias_text)}, ${q(a.alias_match)}, ${
          q(a.source)
        })`
      ).join(",\n"),
      ") as a(ing_match, alias_text, alias_match, source)",
      "  on i.match_text = a.ing_match",
      `where i.household_id = ${q(HOUSEHOLD_ID)} and i.deleted_at is null`,
      "  and not exists (",
      "    select 1 from ingredient_alias x",
      "     where x.ingredient_id = i.id and x.match_text = a.alias_match",
      "       and x.deleted_at is null);",
      "",
    );
  }

  // --- measures -----------------------------------------------------------
  if (measures.length) {
    out.push(
      "-- Measures (0009/0010/0012): amounts in the ingredient's basis unit,",
      "-- per-row provenance in `source`. Idempotent by a `where not exists`",
      "-- guard per LIVE LABEL — 0011 dropped the unique index the old `on",
      "-- conflict` targeted, because offline duplicates must never fail an",
      "-- upload, so the guard is the generator's job rather than the",
      "-- schema's.",
      "insert into ingredient_measure",
      "  (household_id, ingredient_id, label, basis_amount, sort_order, source)",
      `select ${q(HOUSEHOLD_ID)}, i.id, m.label, m.basis_amount,` +
        " m.sort_order, m.source",
      "from ingredient i",
      "join (values",
      measures.map((m) =>
        `  (${q(m.ing_match)}, ${q(m.label)}, ${num(m.basis_amount)}, ${
          m.sort_order ?? 0
        }::int, ${txt(m.source)})`
      ).join(",\n"),
      ") as m(ing_match, label, basis_amount, sort_order, source)",
      "  on i.match_text = m.ing_match",
      `where i.household_id = ${q(HOUSEHOLD_ID)} and i.deleted_at is null`,
      "  and not exists (",
      "    select 1 from ingredient_measure x",
      "     where x.ingredient_id = i.id and x.label = m.label",
      "       and x.deleted_at is null);",
      "",
      "-- A measure the owner re-weighed, reordered or re-sourced keeps its",
      "-- label, so the guard above skips it: carry the snapshot's figures",
      "-- onto the live row, and only where they differ.",
      "update ingredient_measure x",
      "   set basis_amount = m.basis_amount, sort_order = m.sort_order,",
      "       source = m.source, updated_at = now()",
      "from ingredient i",
      "join (values",
      measures.map((m) =>
        `  (${q(m.ing_match)}, ${q(m.label)}, ${num(m.basis_amount)}, ${
          m.sort_order ?? 0
        }::int, ${txt(m.source)})`
      ).join(",\n"),
      ") as m(ing_match, label, basis_amount, sort_order, source)",
      "  on i.match_text = m.ing_match",
      `where i.household_id = ${q(HOUSEHOLD_ID)} and i.deleted_at is null`,
      "  and x.ingredient_id = i.id and x.label = m.label",
      "  and x.deleted_at is null",
      "  and (x.basis_amount, x.sort_order, x.source)",
      "      is distinct from (m.basis_amount, m.sort_order, m.source);",
      "",
    );
  }

  // --- R4: the curated allowed-unit lists, auditable -----------------------
  const deviations = ingredients
    .map((i) => ({ i, d: unitDiff(i.allowed_units, i.derived_allowed_units) }))
    .filter(({ i, d }) =>
      i.derived_allowed_units !== undefined &&
      i.derived_allowed_units !== null &&
      (d.added.length > 0 || d.withheld.length > 0)
    );
  counts.curated_unit_lists = deviations.length;
  out.push(
    "-- R4: where the curated list differs from the derived rule -------------",
    "--",
    "-- `default_allowed_units()` (0012/0014/0039) derives what a row may be",
    "-- said in from its default unit, basis, density, category and piece",
    "-- weight. A curator may still overrule it on a row — admitting a unit",
    "-- the rule withholds, or withholding one it admits — and because",
    "-- `allowed_units` is a stored attribute the seed writes explicitly,",
    "-- that judgment survives the reseed. It must not survive INVISIBLY:",
    "-- every such row is listed here with its diff, which is what the old",
    "-- curation_overrides.jsonl `allowed_units` entries used to be for.",
    "--",
    `-- ${deviations.length} of ${ingredients.length} rows differ from the ` +
      "derived rule:",
  );
  if (deviations.length === 0) {
    out.push("--   (none — every row's list is exactly what the rule derives)");
  }
  for (const { i, d } of deviations) {
    const parts: string[] = [];
    if (d.added.length) parts.push(`+${d.added.join(" +")}`);
    if (d.withheld.length) parts.push(`-${d.withheld.join(" -")}`);
    out.push(
      `--   ${i.match} (${i.canonical_name}, default ${i.default_unit}): ` +
        parts.join("  "),
    );
  }
  out.push("");

  // --- R1/R2/R3 + the measure resolution check ----------------------------
  out.push(
    "-- The invariants. `supabase db reset` FAILS loudly on any of them, and",
    "-- they are checks on the EXPORTED data now: the cloud rows are curated,",
    "-- not derived, so the only thing that can still be wrong is that the",
    "-- curation itself is dishonest.",
    "do $$",
    "declare violators text;",
    "        missing text;",
    "        n_rows int; n_complete int; n_measures int;",
    "begin",
    "  -- R1: a volume default_unit on a PER-GRAM row REQUIRES a density — a",
    "  -- volume line on a density-less per-g ingredient can never compute",
    "  -- macros, so the class must not silently return. A per-100-ml row is",
    "  -- exempt: its volume family is native and needs no bridge. Fix it by",
    "  -- filling an honest density on the row (in the app), flipping its",
    "  -- default to a weight, or stating the label per 100 ml, then",
    "  -- re-exporting.",
    "  select string_agg(canonical_name || ' (' || default_unit || ')', ', ')",
    "    into violators",
    "  from ingredient",
    `  where household_id = ${q(HOUSEHOLD_ID)} and deleted_at is null`,
    "    and default_unit in (" +
      [...VOLUME_DEFAULTS].map((u) => q(u)).join(", ") + ")",
    "    and macros_basis = 'g'",
    "    and density_g_per_ml is null;",
    "  if violators is not null then",
    "    raise exception",
    "      'seed_vocab R1: volume-default per-g rows with no density: %',",
    "      violators;",
    "  end if;",
    "",
    "  -- R2: every stored density is a KITCHEN density. A number outside this",
    "  -- band is a parse artefact or the wrong physical quantity (2.165 is",
    "  -- crystal salt, not what a spoonful weighs).",
    "  select string_agg(",
    "           canonical_name || ' (' || density_g_per_ml || ')', ', ')",
    "    into violators",
    "  from ingredient",
    `  where household_id = ${q(HOUSEHOLD_ID)} and deleted_at is null`,
    "    and density_g_per_ml is not null",
    `    and density_g_per_ml not between ${DENSITY_MIN} and ${DENSITY_MAX};`,
    "  if violators is not null then",
    "    raise exception",
    `      'seed_vocab R2: densities outside ${DENSITY_MIN}-${DENSITY_MAX} ` +
      "g/ml: %',",
    "      violators;",
    "  end if;",
    "",
    "  -- R3 (ADR-0015): `piece` is admitted by a WEIGHT, so the two halves of",
    "  -- that rule are the two halves of this invariant.",
    "  --",
    "  -- (a) Every counted row says what one of it weighs. A piece-default",
    "  --     row with no piece weight is a STRANDED default: it would offer a",
    "  --     `piece` nothing can convert, total or shop.",
    "  select string_agg(canonical_name, ', ') into violators",
    "  from ingredient",
    `  where household_id = ${q(HOUSEHOLD_ID)} and deleted_at is null`,
    "    and default_unit = 'piece' and piece_basis_amount is null;",
    "  if violators is not null then",
    "    raise exception",
    "      'seed_vocab R3a: piece-default rows with no piece weight: %',",
    "      violators;",
    "  end if;",
    "",
    "  -- (b) …and nothing else admits `piece`. The curated lists above are",
    "  --     explicit, so this is the check that stops a reseed offering a",
    "  --     `piece` of a row nobody counts.",
    "  select string_agg(canonical_name || ' (' || default_unit || ')', ', ')",
    "    into violators",
    "  from ingredient",
    `  where household_id = ${q(HOUSEHOLD_ID)} and deleted_at is null`,
    "    and default_unit <> 'piece' and allowed_units ? 'piece';",
    "  if violators is not null then",
    "    raise exception",
    "      'seed_vocab R3b: rows admitting piece without a count default: %',",
    "      violators;",
    "  end if;",
    "",
    "  -- …and every measure resolved to a live vocab row. A measure whose",
    "  -- ingredient is not there seeds NOTHING and would do it silently, so",
    "  -- name the match_text instead. raise, not ASSERT: plpgsql.check_asserts",
    "  -- can be disabled, and this check must never be.",
    "  select string_agg(distinct m.mt, ', ') into missing",
    "  from (values",
    [...new Set(measures.map((m) => m.ing_match))].sort().map((mt) =>
      `    (${q(mt)})`
    ).join(",\n"),
    "  ) as m(mt)",
    "  where not exists (",
    "    select 1 from ingredient i",
    `    where i.household_id = ${q(HOUSEHOLD_ID)}`,
    "      and i.deleted_at is null and i.match_text = m.mt",
    "  );",
    "  if missing is not null then",
    "    raise exception",
    "      'seed_vocab: no live vocab ingredient for measures of: %', missing;",
    "  end if;",
    "",
    "  select count(*), count(*) filter (where status = 'complete')",
    "    into n_rows, n_complete",
    "  from ingredient",
    `  where household_id = ${q(HOUSEHOLD_ID)} and deleted_at is null;`,
    "  select count(*) into n_measures from ingredient_measure",
    `  where household_id = ${q(HOUSEHOLD_ID)} and deleted_at is null;`,
    "  raise notice",
    "    'seed_vocab: % template ingredients (% complete), % measures; " +
      "R1 (volume default => density), R2 (kitchen density band) and " +
      "R3 (every counted row weighed, and only counted rows admit piece) " +
      "hold', n_rows, n_complete, n_measures;",
    "end $$;",
    "",
    "commit;",
    "",
  );

  return { sql: out.join("\n"), counts };
}

export interface Counts {
  ingredients: number;
  complete: number;
  stub: number;
  aliases: number;
  measures: number;
  /** Rows whose allowed_units differs from the derived rule (R4). */
  curated_unit_lists: number;
}

function main(): void {
  const dir = new URL(".", import.meta.url).pathname;
  // gen_seed.ts [inputJsonl] [outputSql] — the defaults are the committed
  // snapshot and the one generated seed file.
  const inputPath = Deno.args[0] ?? `${dir}../snapshot.jsonl`;
  const outputPath = Deno.args[1] ?? `${dir}../../seed_vocab.sql`;
  const rows: SnapshotRow[] = Deno.readTextFileSync(inputPath)
    .split("\n").map((l) => l.trim()).filter(Boolean).map((l) => JSON.parse(l));

  const plan = planSeed(rows);
  if (plan.problems.length) {
    console.error(
      "snapshot problems:\n" + plan.problems.map((p) => "  " + p).join("\n"),
    );
    Deno.exit(1);
  }

  const { sql, counts } = buildSql(plan);
  Deno.writeTextFileSync(outputPath, sql);

  // The counts are COMPUTED, never typed: scripts/cloud_verify.sh and the
  // docs quote this file rather than a number somebody remembered.
  const countsPath = `${dir}../counts.json`;
  Deno.writeTextFileSync(
    countsPath,
    JSON.stringify(counts, null, 2) + "\n",
  );

  console.log(
    `wrote ${outputPath}\n` +
      `  ${counts.ingredients} ingredients ` +
      `(${counts.complete} complete, ${counts.stub} stub)\n` +
      `  ${counts.aliases} aliases\n` +
      `  ${counts.measures} measures\n` +
      `  ${counts.curated_unit_lists} curated allowed-unit lists ` +
      `differing from the derived rule (R4)\n` +
      `  ${plan.restampedRows.length} ingredient + ` +
      `${plan.restampedAliases.length} alias sources re-stamped 'seed' ` +
      `so the clone carries them\n` +
      `wrote ${countsPath}`,
  );
}

if (import.meta.main) main();
