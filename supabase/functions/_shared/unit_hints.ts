// UnitHints deriver — the unit-aware bias fed to the ① sanitize stage (§4.4).
//
// SERVER MIRROR of app/lib/core/units/units.dart (the SINGLE SOURCE OF TRUTH for
// the unit catalog) + the size adjectives in _shared/normalize.ts. This file is
// hand-maintained: when units.dart's `kAllUnits` catalog changes, or normalize's
// SIZES set changes, update the mirrors below to match. Keep them in step.
//
// What this is NOT (ADR-0004 + 0014 decision log): it is NOT the ingredient
// vocab, and NOT the per-ingredient MEASURE TABLE (the gram/ml basis riding on
// ONE ingredient — a garlic clove ≈ 3 g, a 400 g can — which stays app-side and
// never biases sanitize). It DOES now include the generic count-measure NOUNS
// (`clove`, `head`, `can`, `slice`…) as a distinct `measures` list, so ① emits
// "2 garlic cloves" → unit="clove" instead of force-fitting "piece"; those nouns
// are counting words, not the ingredient-specific gram basis. The hint set is:
// canonical units + accepted imprecise/vague words + size words + count-measure
// nouns, so ① lands qty/unit in-system while staying ingredient-blind.
//
// Deterministic and pure: no I/O, no model.

import type { UnitHints } from "./types.ts";

type HintFamily = "mass" | "volume" | "count" | "imprecise";

interface UnitMirror {
  id: string;
  family: HintFamily;
}

/**
 * Mirror of `kAllUnits` in app/lib/core/units/units.dart (same order, same ids).
 * `id` is the value persisted as `recipe_line_item.unit` — the string ① should
 * emit. The mass/volume/count members are the mappable canonical units; the
 * imprecise members carry no ratio and never scale.
 */
const UNIT_CATALOG: readonly UnitMirror[] = [
  // Mass (base: gram).
  { id: "g", family: "mass" },
  { id: "kg", family: "mass" },
  { id: "mg", family: "mass" },
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
 * Accepted vague-amount words that aren't in the unit catalog. ① may keep one as
 * an imprecise `unit` (with `unit_mappable: false`) rather than force-fitting a
 * number (honest numbers). Extend cautiously — a word here tells the model the
 * amount is legitimately imprecise, so only genuinely unmeasurable words belong
 * (the vague subset of normalize.ts's MEASURES set).
 */
const EXTRA_IMPRECISE: readonly string[] = ["handful"];

/**
 * Generic count-measure NOUNS the model may emit as a `unit` when the recipe
 * counts by them ("2 garlic cloves", "1 head of broccoli", "One 400 g can").
 * These are NOT canonical convertible units (they stay out of `units`) and NOT
 * the per-ingredient measure table (a gram/ml basis riding on ONE ingredient);
 * they are the everyday counting nouns a recipe prints in place of "piece".
 * Handing them to ① as acceptable unit words stops it force-fitting them all to
 * "piece" (the clove→piece failure). "tin" is deliberately absent — the prompt
 * normalises "tin" → "can" so measure labels don't fragment.
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

/**
 * Size adjectives that scale the amount, not the identity — mirror of the SIZES
 * set in _shared/normalize.ts. ① uses these as size words, never as units.
 */
const SIZE_WORDS: readonly string[] = [
  "large",
  "medium",
  "small",
  "big",
  "tiny",
];

/**
 * Derives the {@link UnitHints} handed to `ExtractAdapter.sanitize`. Canonical
 * (mappable) unit ids in `units`; imprecise unit ids plus accepted vague words in
 * `imprecise`; size adjectives in `size_words`.
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
