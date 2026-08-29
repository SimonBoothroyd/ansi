# ADR-0008 — Units are admitted per ingredient via basis mapping; density is the only volume⇄mass fact

- **Status:** accepted (2026-08-29, Simon + agent design session)
- **Supersedes / refines:** the 7.6 `allowedUnitsFor` gating (family + density +
  measures) and the 7.7 "no volume-named measures" rule.

## Context

Step 7.7's chip row exposed that unit gating by *convertibility* produces
nonsense at entry time: yeast (default `tsp`, no density) offered `ml · l`
but not `g`; flour refused `g`; everything offered `pinch/dash/to taste`.
Meanwhile "allow `g` everywhere" breaks the other way once macros carry a
basis (`macros_basis` shipped in 7.7): a gram line on a density-less per-ml
ingredient can never compute macros. And measurement is humanly messy —
spoons for solids, sachets, "1 medium", "a cm of ginger" — with no clean
automatable rule.

## Decision

**The macro basis is the ingredient's canonical dimension. Every other unit
is admitted only via an explicit mapping into that basis.**

1. **Basis family is allowed by default** — /g → weights; /ml → volumes
   (spoons included). Trimmed to kitchen-scale magnitudes near the default
   unit (no litres of yeast).
2. **Density is the single stored volume⇄mass fact** and unlocks the whole
   other family (demoted in chip ordering — "g of milk" is doable but
   strange). It is enterable two equivalent ways: as g/ml, or as **"a spoon
   of this weighs N g"** (`1 tbsp = 15 g` ⇒ `15 / 14.787` g/ml). A
   volume-named weight mapping *is* a density — so volume-named measures
   never exist as measures, and no conflict between the two is possible.
3. **Measures are count-like human units only** (sachet, can, block,
   small/medium/large, cm, …), each mapped to an amount **in the basis
   unit** (not always grams — a /ml ingredient's measures map to ml).
   "Size", "length" and other human unit types are just measures.
4. **Allowed units are an explicit per-ingredient attribute**, materialized
   at ingredient creation from the defaults above and editable in the
   flesh-out form (rows are cheap; explicit beats derived-and-implicit).
5. **Imprecise units (`pinch/dash/to taste`) are category-gated**
   (seasonings/spices/oils), not universal.

The seed pipeline follows suit: FDC **spoon portions become derived
densities** for density-less /g ingredients (they are densities in
disguise), never measure rows — this also lifts density coverage well past
the current 7/291.

## Consequences

- Entry freedom and macro honesty stop fighting: what you may *say* is the
  per-ingredient allowed list; what we may *compute* still degrades
  honestly (split subtotals, `incomplete` macros) exactly as before.
- `ingredient_measure` needs basis-aware amounts (currently grams-only) and
  a UI/validation rule that volume-named labels are redirected to density
  entry.
- The flesh-out form (step 8) gains the allowed-units section: basis shown,
  family pre-ticked, density input (either entry style) unlocking the other
  family, measures list, category imprecise toggle. Board frame (d) grows
  accordingly.
- Chip ordering becomes: default unit → basis-family kitchen sizes →
  (density-unlocked family, demoted) → measures → imprecise-if-category.

## Rejected alternatives

- *`g` always available for everything* — breaks macros for density-less
  /ml ingredients; "g of milk" front-and-center is strange.
- *Volume-named measures alongside density* — two stored copies of one
  physical fact, guaranteed to disagree eventually.
- *Fully derived (unstored) allowed-unit rules* — cheap but implicit;
  explicit per-ingredient lists were chosen for editability and
  predictability.
