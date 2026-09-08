# ADR-0014 — All to all: a family is admitted whole, and the user prunes

- **Status:** accepted (2026-09-08, Simon — owner-ruled)
- **Supersedes:** [ADR-0008](./0008-unit-admission-model.md) §Decision ¶1's
  kitchen trim ("Trimmed to kitchen-scale magnitudes near the default unit"),
  and with it [ADR-0012](./0012-tsp-mates-cup.md) and
  [ADR-0013](./0013-mass-ladder-symmetric.md) **entirely** — both were repairs
  to a list this ADR deletes. Everything else in ADR-0008 stands, as do
  [ADR-0009](./0009-density-unlocks-both-families.md) (a density unlocks the
  other family whatever the default unit is, and deleting it strips what it
  granted) and [ADR-0010](./0010-piece-is-an-admission-fact.md) (`piece` is a
  curated admission fact).

## Context

The trim was a per-default-unit mates list: `tsp` kept company with `tbsp`,
`cup` with `{cup, tbsp, ml, l, pt, qt}`, `g` with `{g, kg}`. It existed to keep
a picker at kitchen magnitudes — "no litres of yeast" — and to keep
label-reading units (`mg`, `fl oz`) out of everyone's chips.

In five days it needed two repairs, each found by the owner reading a screen:

- **ADR-0012**: `cup` admitted `tbsp` but not `tsp`, so a cup-default sugar
  could be said in litres and not in teaspoons — while the density sentence
  directly below the chips offered `tsp` as one of its spoons.
- **ADR-0013**: `oz` admitted `g` but not `kg`, so the vocabulary a row offered
  depended on which system the shop printed on the label.

Both fixes were correct and neither was the point. A rule that needs a
one-rung amendment every time somebody looks at it closely is not encoding a
fact about kitchens; it is a table of opinions about magnitudes, and the app
was holding those opinions on the household's behalf, per row, forever. The
owner's ruling:

> *"All to all, with the usual density caveat, and let the user prune."*

The thing that makes this affordable now is the flesh-out form. When ADR-0008
was written there was nowhere to say "not on this row"; since step 8.5 the
admission chips are one tap each. A generous default the user narrows is
strictly better than a narrow default the user cannot widen without
re-deriving the rule.

## Decision

**A mass/volume family is admitted whole or not at all.** The derived
admission set for a row is exactly four things:

1. **The whole basis family**, always. Per-100 g ⇒ every mass unit; per-100 ml
   ⇒ every volume unit. (ADR-0008 §1, with the trim removed.)
2. **The whole other mass/volume family**, only while a density is stored.
   ADR-0009 unchanged: a density is a property of the substance, whatever the
   default unit, so this fires for a count- or imprecise-default row too.
3. **`piece`** on a count-default row. ADR-0010 unchanged, including its rule
   that a row with a better measure has `piece` curated off it.
4. **The imprecise words** the row's category earns, per word, plus an
   imprecise default's own word (J3 unchanged).

No mates lists, no `big` magnitude gate, no per-unit exceptions. The row's own
default unit needs no clause: it is in the basis family, or in the other one
and therefore density-gated — which is exactly what
`unitSayableAsDefault` / the stranded-default rule (D4c) already refuses to
store without a number. **D4c stands unchanged**; it was about honesty, never
about trim.

Two catalog consequences ride along:

- **`mg` leaves the catalog entirely.** A milligram is how a supplement's
  label reads, not how a kitchen weighs, and a unit nobody may pick has no
  business being a family member the rule then has to except. It is gone from
  `kAllUnits`, `unit_words`, the fused-amount normalizer, the seed generators,
  the extraction hints, `unit_family()` and `default_allowed_units()`.
- **`fl oz` is an ordinary volume unit.** It was excepted beside `mg` as
  label-reading granularity; it is a kitchen unit in a British kitchen, and it
  now joins the volume family in every list like the others.

### The form: one lock left

The flesh-out form's admission section draws **every** catalog unit of both
mass/volume families and **every** imprecise word as a chip. The only locked
(dashed) chips are the other family's units while no density is stored, under
the line they already had: *"tsp · tbsp · fl oz · cup · ml · l · pt · qt unlock
when this row has a density."* Everything else is the household's to turn on
or off, imprecise words included — the category still decides which of them
arrive pre-picked, but it no longer decides what may be picked.

### The widening fence

Migration `0037` widens existing rows, under ADR-0012's fence verbatim:

> a row gains the units the new rule adds only while its stored
> `allowed_units` still equals what the OLD rule derived for that row. A
> household that curated its list is left exactly as it is.

ADR-0009 rule 3 says a backfill may never *remove* from a stored list, because
the list is the household's after creation; this is the same principle in the
other direction — a backfill may not **overwrite a stated fact** either. The
change is far too broad to characterise as "the new answer minus one unit" the
way 0032 and 0035 could, so 0037 carries the old rule as a temporary function
(`default_allowed_units_pre_0037()`, 0035's body verbatim) purely to compute
the comparison, and drops it at the end. The new rule is a **superset** of the
old for every row — each old leg was a subset of the family the new rule
admits whole — which is what makes the union a widening and never a rewrite.

**The `mg` strip is deliberately outside the fence.** A unit that no longer
exists is not a curation, so `"mg"` comes out of every list, curated or
pristine.

## Consequences

- **A picker on a density-carrying row offers up to twelve catalog units**,
  plus measures and words. That is the cost, and it is the one the owner
  chose: a longer chip row the household shortens, rather than a short one it
  cannot lengthen without an ADR.
- **Stored `mg` data is converted, not stranded.** 0037 rewrites every stored
  quantity in `mg` to the same quantity in `g` (× 0.001) across
  `recipe_line_item`, `plan_entry`, `shopping_list_contribution`,
  `shopping_list_entry.unit` and both of `recipe`'s yield denominations,
  rewrites `ingredient.default_unit = 'mg'` to `'g'`, and strips `"mg"` from
  every `allowed_units` list — every household, soft-deleted rows included,
  idempotent, counted in a `raise notice`. The seed contains no `mg`, so this
  is entirely for household data.
- **Existing pristine rows are widened once**; existing curated rows are not,
  and stay narrower than a freshly created twin. That divergence is intended
  and is the same one ADR-0009's union-only backfill already accepts.
- **Two ADRs stop being live rules.** ADR-0012 and ADR-0013 are marked
  superseded; the asymmetries they fixed cannot be expressed in a rule that
  admits families.
- **Component lines keep their own, narrower ladder**
  (`kComponentKitchenUnits`). A component line restates the recipe's stated
  yield rather than denominating an ingredient, and there is no density for a
  recipe — so nothing here reaches it.
- **The seeded template widens on its next reseed**, because the seed
  re-materializes `allowed_units` from `default_allowed_units()` and applies
  its per-row overrides afterwards. The overrides remove single units from
  single rows; none of them removes a mass unit, and none could ever have
  removed `fl oz`, which is what lets `unit_admission.sql` assert the
  population outright.

## Rejected alternatives

- **Keep a smaller "default-on" subset with the rest unlocked** — chips
  selected by the old mates list, everything else offered unselected. It keeps
  every magnitude opinion in the code and adds a second rule ("what is on" vs
  "what is offered") for a reader to hold. The trim's own examples do not
  survive contact with a kitchen anyway: a litre of yeast is silly, and a
  litre of yeast *slurry* is a Tuesday. If a row should not say a unit, the
  household is the one who knows.
- **Repair the mates list a third time** — the status quo that had already
  failed twice in a week, each time after somebody happened to look.
- **Drop the density caveat too, and admit everything always** — that would
  hand the converter pairs it cannot resolve and put fabricated subtotals in
  the shopping list. The density gate is the one gate that is about honesty
  rather than taste, which is why it is the only one left.
- **Keep `mg` for label-reading** — it was only ever reachable as a row's own
  default unit, so it bought nothing but an exception in every list, and every
  quantity it can state is statable in grams.
