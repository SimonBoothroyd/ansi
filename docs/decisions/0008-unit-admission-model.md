# ADR-0008 — Units are admitted per ingredient via basis mapping; density is the only volume⇄mass fact

- **Status:** accepted (2026-08-29, Simon + agent design session) — **amended
  2026-08-31 by [ADR-0009](./0009-density-unlocks-both-families.md)**, and
  §Decision ¶1's kitchen trim **superseded 2026-09-08 by
  [ADR-0014](./0014-all-to-all-admission.md)** (a family is admitted whole and
  the household prunes per row; `mg` left the catalogue with it)
- **Supersedes / refines:** the 7.6 `allowedUnitsFor` gating (family + density +
  measures) and the 7.7 "no volume-named measures" rule.
- **Amended 2026-08-31:** §Decision ¶2's second sentence ("Density … unlocks
  the whole other family") is superseded by
  [ADR-0009](./0009-density-unlocks-both-families.md). Both implementations
  had read it as gated on the *default unit's* family, so a piece-default row
  with a density admitted no volume unit at all. ADR-0009 states the rule
  positively — a density unlocks the other mass/volume family whatever the
  default unit's family, and **both** families for a count- or
  imprecise-default row — and retires the seed-level produce patch that stood
  in for it. Everything else below stands unchanged.

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

   *Amended 2026-09-04 (plan 0028 design pass + [ADR-0011](./0011-one-save-one-write.md)).*
   The two ways stopped being two **controls**: nobody divides grams by
   millilitres in their head, so the phrasing segment was a choice with one
   real answer and it is deleted. What remains is one sentence — *"1 `[tsp]`
   `[tbsp]` `[cup]` `[ml]` of this weighs `__` g"* — and `ml`'s ratio to base
   is 1, so a known g/ml is still typeable **exactly**, as a different pick in
   the same row. Both ways are unchanged in what they store. What did change
   is *when*: on the flesh-out form the density now lands through that form's
   own Save, in the one transaction with everything else (ADR-0011); the
   quantity sheet, which has no Save, still writes it on tap.
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
- The flesh-out form (deferred to step 8; actually built in **step 8.5**,
  `/ingredients/:id`) gains the allowed-units section: basis shown,
  family pre-ticked, density input (either entry style) unlocking the other
  family, measures list, category imprecise toggle. Board frame (d) grows
  accordingly.
- Chip ordering becomes: the row's own **measures** → default unit →
  basis-family kitchen sizes → (density-unlocked family, demoted) →
  imprecise-if-category. The measures lead because a measure is a word for
  *this* row alone, where a catalog unit is offered on every row.
- **The default unit is fronted whatever its family** (owner). A row whose
  default IS an imprecise word — Ground Allspice, Flaky Salt — leads with that
  word, behind its own measures and ahead of the basis family, rather than
  sinking to the imprecise tail and opening on `g`; what a row leads with and
  what a surface with nothing stored opens on (`firstOfferedChoice`) are one
  thing, so the second follows the first. The word is offered **once**: the
  tail after the chip row's divider is the words the row merely admits.

## Rejected alternatives

- *`g` always available for everything* — breaks macros for density-less
  /ml ingredients; "g of milk" front-and-center is strange.
- *Volume-named measures alongside density* — two stored copies of one
  physical fact, guaranteed to disagree eventually.
- *Fully derived (unstored) allowed-unit rules* — cheap but implicit;
  explicit per-ingredient lists were chosen for editability and
  predictability.
