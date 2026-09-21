// UnitHints deriver: the unit-aware bias fed to the ① sanitize stage (§4.4).
//
// A hand-maintained server mirror of `kAllUnits` in
// app/lib/core/units/units.dart and the SIZES set in _shared/normalize.ts;
// keep them in step.
//
// The hints are canonical units, imprecise words, size words and generic
// count-measure nouns (`clove`, `head`, `can`), so ① emits unit="clove"
// instead of force-fitting "piece". They are not the ingredient vocab and not
// the per-ingredient measure table (ADR-0004). Pure.

import type { UnitHints } from "./types.ts";

type HintFamily = "mass" | "volume" | "count" | "imprecise";

interface UnitMirror {
  id: string;
  family: HintFamily;
}

/**
 * Mirror of `kAllUnits` in app/lib/core/units/units.dart (same order, same
 * ids). `id` is the value persisted as `recipe_line_item.unit`. Imprecise
 * members carry no ratio and never scale.
 */
const UNIT_CATALOG: readonly UnitMirror[] = [
  // Mass (base: gram).
  { id: "g", family: "mass" },
  { id: "kg", family: "mass" },
  { id: "oz", family: "mass" },
  { id: "lb", family: "mass" },
  // Volume (base: ml).
  { id: "ml", family: "volume" },
  { id: "l", family: "volume" },
  { id: "tsp", family: "volume" },
  { id: "tbsp", family: "volume" },
  { id: "fl_oz", family: "volume" },
  { id: "cup", family: "volume" },
  { id: "pt", family: "volume" },
  { id: "qt", family: "volume" },
  // Count.
  { id: "piece", family: "count" },
  // Imprecise (non-scaling, non-converting).
  { id: "pinch", family: "imprecise" },
  { id: "dash", family: "imprecise" },
  { id: "to_taste", family: "imprecise" },
];

/**
 * Vague-amount words accepted alongside the mirror above; ① may keep one as
 * an imprecise `unit` with `unit_mappable: false`. `handful` is a unit in
 * units.dart too; both lists land in `imprecise`. Only genuinely unmeasurable
 * words belong here.
 */
const EXTRA_IMPRECISE: readonly string[] = ["handful"];

/**
 * Generic count-measure nouns the model may emit as a `unit` ("2 garlic
 * cloves", "1 head of broccoli"). Not canonical units and not the
 * per-ingredient measure table. "tin" is absent: the prompt normalises it to
 * "can".
 */
const MEASURE_NOUNS: readonly string[] = [
  "clove",
  "head",
  "sprig",
  "loaf",
  "block",
  "slice",
  "can",
  "bunch",
  "stalk",
];

/** Size adjectives: mirror of the SIZES set in _shared/normalize.ts. */
const SIZE_WORDS: readonly string[] = [
  "large",
  "medium",
  "small",
  "big",
  "tiny",
];

/**
 * Derives the {@link UnitHints} handed to `ExtractAdapter.sanitize`: mappable
 * unit ids in `units`, imprecise ids and vague words in `imprecise`, size
 * adjectives in `size_words`.
 */
export function deriveUnitHints(): UnitHints {
  const units = UNIT_CATALOG
    .filter((u) => u.family !== "imprecise")
    .map((u) => u.id);
  const imprecise = [
    ...UNIT_CATALOG.filter((u) => u.family === "imprecise").map((u) => u.id),
    ...EXTRA_IMPRECISE,
  ];
  return {
    units,
    imprecise,
    size_words: [...SIZE_WORDS],
    measures: [...MEASURE_NOUNS],
  };
}
