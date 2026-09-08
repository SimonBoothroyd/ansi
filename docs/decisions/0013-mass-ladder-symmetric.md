# ADR-0013 — The mass ladder is symmetric: the kitchen four mate each other

- **Status:** accepted (2026-09-08, Simon — owner-asked)
- **Supersedes:** the `g`, `kg` and `oz` rows of
  [ADR-0008](./0008-unit-admission-model.md) §Decision ¶1's kitchen trim
  ("Trimmed to kitchen-scale magnitudes near the default unit"), as that trim
  was implemented — `g` and `kg` admitted only each other, `oz` admitted
  `{oz, lb, g}` and refused `kg`. Everything else in ADR-0008, all of
  [ADR-0009](./0009-density-unlocks-both-families.md) and all of
  [ADR-0012](./0012-tsp-mates-cup.md) stands.

## Context

[ADR-0012](./0012-tsp-mates-cup.md) made the volume ladder symmetric and left
the mass one exactly as it was:

```
g   → {g, kg}
kg  → {kg, g}
oz  → {oz, lb, g}          ← no kg
lb  → {lb, oz, g, kg}
mg  → {mg, g}
```

So a bag of rice bought in grams could be said in grams and kilograms only,
while a pack of chicken thighs bought in pounds could be said in all four. The
two rows are the same kitchen quantity — a weight, at kitchen magnitudes,
convertible with no density and no assumption — and the vocabulary the app
offered depended on which system the shop happened to print on the label.

The owner's reading is the one that settles it: this is inconsistent, and
nothing in the trim defends it. The trim is about **magnitude** — "no litres of
yeast", no milligrams on a row that speaks in cups. `oz` and `g` are the same
magnitude; so are `lb` and `kg`. That is the same fact plan 0025's D2b already
acted on in the volume family, where **quart rides with litre and pint rides
with cup**: the customary unit and the metric one of the same size are one
quantity said in two systems, and admitting one while refusing the other is a
statement about systems, not about kitchens.

`lb`'s own list was already the complete four, which is the clearest evidence
that the other three were the accident: nobody decided a pound-default row
should be richer than a gram-default one.

## Decision

**The four kitchen mass units mate each other.** `oz` rides with `g`, `lb`
rides with `kg`:

```
g   → {g, kg, oz, lb}
kg  → {kg, g, oz, lb}
oz  → {oz, lb, g, kg}
lb  → {lb, oz, g, kg}      (unchanged)
mg  → {mg, g}              (unchanged)
```

`mg` does not move. It is label-reading granularity, not kitchen granularity —
the trim in the *other* direction, exactly what `tsp`'s own `{tsp, tbsp}` is in
the volume family. It reaches a picker only as a row's own default unit.

Nothing else moves either: the density cross leg, the basis leg, the `big`
magnitude gate and the kitchen display order are untouched. In particular, what
a density is *worth* to a mass-default row is unchanged — the widening happens
inside the mass family, which the density leg never supplied. A per-100 ml row
with a mass default and no density still admits no mass unit at all, because
the mates leg is what widened and a stranded default never reaches it.

Three places implement this one rule and move together:

1. **`_kitchenMates` in `app/lib/features/ingredients/domain/allowed_units.dart`**
   — the Dart mirror the pickers read.
2. **`default_allowed_units()`** — the SQL mirror, re-created in migration
   `0035` from `0032`'s body with the three arrays changed. `allowed_units` is
   **stored, not derived at read time** (ADR-0008 §4): a `before insert`
   trigger stamps the defaults, so the rule alone reaches no existing row.
3. **The shared admission vectors**
   (`app/test/features/ingredients/allowed_units_vectors.json`, rendered into
   `supabase/tests/unit_admission.sql`) — which had **no mass-default shape at
   all**, which is how the asymmetry survived two rounds of unit work. Three
   were added: a gram default, a pound default, and an ounce default with a
   density.

### The widening fence

Migration `0035` also **widens existing rows**, under ADR-0012's fence
verbatim:

> the new mates are added only to a row whose stored `allowed_units` still
> equals the **old derived default** for that row. A household that curated its
> list is left exactly as it is.

ADR-0009 rule 3 says a backfill may never *remove* from a stored list, because
the list is the household's after creation; this is the same principle in the
other direction — a backfill may not **overwrite a stated fact** either. A row
that has drifted from the defaults has had something said about it, and this
migration has nothing to say back. It gains the units the next time a human
saves it.

The old default is computable exactly, which is what makes the fence checkable
rather than a guess. The only change to `default_allowed_units()` is inside the
mates leg, and for a mass default no other leg of that function can emit a mass
unit: the basis leg fires only when the basis family differs from the default's
(so for a mass default it emits `ml`/`l`), the density cross leg for a mass
default emits the volume workhorses, and the imprecise tail emits words. So:

```
g, kg default:  old_default(row) = new_default(row) minus {oz, lb}
oz default:     old_default(row) = new_default(row) minus {kg}
every other:    old_default(row) = new_default(row)
```

One extra guard that 0032 did not need: the fresh defaults must actually
**name** the units being added. A `g`-default row on a per-100 ml basis with no
density passes the equality test — its stored `["ml"]` is both the old and the
new answer — and must still gain nothing, because its mates leg never fires.

## Consequences

- A mass-default row admits the whole kitchen mass family at creation,
  everywhere — the app's own create path, the server materialization, the
  template seed. The template's 45 `oz`-default rows are the visible half of
  that: they can now be weighed in kilos.
- Four of the shared vectors move: the three new mass shapes state the rule,
  and `oz`-default `butter` shows it composing with the density cross leg.
- **Existing pristine rows are widened once**; existing curated rows are not,
  and stay narrower than a freshly created twin. That divergence is intended
  and is the same one ADR-0009's union-only backfill already accepts.
- The migration is idempotent (a row that already names the added units no
  longer matches) and reset-safe, so `supabase db reset` re-runs it cleanly.
- Unlike ADR-0012's, this widening is not undone by curation anywhere: no
  entry in `curation_overrides.jsonl` removes a mass unit from any row, so
  `unit_admission.sql` can assert the template population outright rather than
  with a threshold.
- A recipe line already saying `oz` on a curated gram-default row keeps its
  ordinary `unitNotAllowed` flag on the import review until the household
  widens the row itself. Nothing is rewritten.

## Rejected alternatives

- *Narrow `lb` to `{lb, oz}` instead* — the symmetric fix in the other
  direction, and it is wrong twice over. It strands the canonical gram: a
  per-100 g `lb`-default row would no longer admit `g`, which ADR-0008 §1 makes
  unconditional ("the canonical dimension is always sayable"), and every macro
  total for that row is computed in grams. It would also be a **removal**,
  which ADR-0009 rule 3 forbids a backfill from doing at all — so the rule and
  the stored lists would diverge permanently.
- *Widen every row unconditionally* — the cheap version, and it silently
  overwrites curation. Symmetric with the removal ADR-0009 forbids.
- *Add `mg` to the ladder while we are here* — a milligram is how a
  supplement's label reads, not how a kitchen weighs. It would put `mg` in
  every mass row's picker to fix an asymmetry nobody has hit.
- *Drop the kitchen trim altogether and admit the whole family* — the trim is
  load-bearing at the other end: it is what keeps `l` off a spoon-default row
  and `mg` out of everyone's picker.
