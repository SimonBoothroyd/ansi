# ADR-0012 — The volume ladder is symmetric: `tsp` mates `cup`

- **Status:** accepted (2026-09-04, Simon — exec plan
  [0036](../exec-plans/completed/0036-ingredient-entry-and-units.md) Front B,
  owner-asked)
- **Supersedes:** the `cup` row of [ADR-0008](./0008-unit-admission-model.md)
  §Decision ¶1's kitchen trim ("Trimmed to kitchen-scale magnitudes near the
  default unit"), as that trim was implemented — `cup` admitted
  `{cup, tbsp, ml, l, pt, qt}` and refused `tsp`. Everything else in ADR-0008,
  and all of [ADR-0009](./0009-density-unlocks-both-families.md), stands.

## Context

The trim exists to keep a picker at kitchen magnitudes: no litres of yeast, no
milligrams on a row that speaks in cups. It is stated as a mates list per
default unit, and the volume ladder it produced was **asymmetric**:

```
tsp  → {tsp, tbsp}
tbsp → {tbsp, tsp, cup, ml, pt}
cup  → {cup, tbsp, ml, l, pt, qt}      ← no tsp
```

`tsp` mates `tbsp`; `tbsp` mates `cup`; `cup` does not mate `tsp`. So
`Granulated Sugar` — a cup-default row with a density — could be written in
cups, tablespoons, millilitres, litres, pints and quarts, and **not in
teaspoons**. A teaspoon of sugar in a dressing and a teaspoon of salt in a
dough are ordinary lines; the vocabulary refused both.

The owner hit it in one frame: the *ALLOWED UNITS* row reading `cup · tbsp · ml
· l · pt · qt · g · kg` sits directly above a density sentence that offers
`tsp` as one of its four spoons. The same screen both refuses the unit and
measures in it.

The magnitude argument does not defend the gap. ADR-0008's own example is
"no **litres** of yeast" — the trim is about units that are too **big** for the
row, and `tsp` is the smallest unit in the family. Nothing about a cup-default
food makes a teaspoon of it unsayable.

## Decision

**`cup`'s kitchen mates gain `tsp`**, making the volume ladder symmetric: if a
row may be said in tablespoons it may be said in teaspoons.

```
cup  → {cup, tsp, tbsp, ml, l, pt, qt}
```

Nothing else moves. `tsp`'s own mates stay `{tsp, tbsp}` (the trim in the other
direction — a teaspoon-default row is not a cup-scale food), the density cross
leg already named `tsp`, and no other default unit's list changes.

Three places implement this one rule and move together:

1. **`_kitchenMates` in `app/lib/features/ingredients/domain/allowed_units.dart`**
   — the Dart mirror the pickers read.
2. **`default_allowed_units()`** — the SQL mirror, re-created in migration
   `0032` from `0024`'s body with the single array changed. `allowed_units` is
   **stored, not derived at read time** (ADR-0008 §4): a `before insert`
   trigger stamps the defaults, so the rule alone reaches no existing row.
3. **The shared admission vectors**
   (`app/test/features/ingredients/allowed_units_vectors.json`, rendered into
   `supabase/tests/unit_admission.sql`) — regenerated, so neither mirror can
   move without the other.

### The widening fence

Migration `0032` also **widens existing rows**, and the fence on it is the
point:

> `tsp` is added only to a row whose stored `allowed_units` still equals the
> **old derived default** for that row. A household that curated its list is
> left exactly as it is.

ADR-0009 rule 3 says a backfill may never *remove* from a stored list, because
the list is the household's after creation. This is the same principle in the
other direction: a backfill may not **overwrite a stated fact** either. A row
that has drifted from the defaults — every `stopOfferingPiece` removal, every
toggled chip, every seed curation override — has had something said about it,
and this migration has nothing to say back. It gains `tsp` the next time a
human saves it.

The old default is computable exactly, which is what makes the fence checkable
rather than a guess: the only change to `default_allowed_units()` is `'tsp'`
appearing in the `cup` branch of the mates leg, and no other leg of that
function emits `tsp` for a `cup` default (the basis leg emits `g`/`kg` or
`ml`/`l`, the density cross leg for a volume default emits `g`/`kg`, and the
imprecise tail emits words). So for a `cup`-default row the old answer is the
new answer minus `tsp`, and for every other row the two are identical.

## Consequences

- A cup-default row admits `tsp` at creation, everywhere — the app's own
  create path, the server materialization, the template seed.
- Three of the shared vectors change: `flour` (cup /g with a density),
  `broth` (cup /ml, no density) and `milk` (cup /ml with one) each gain `tsp`.
- **Existing pristine rows are widened once**; existing curated rows are not,
  and stay one unit narrower than a freshly created twin. That divergence is
  intended and is the same one ADR-0009's union-only backfill already accepts.
- The migration is idempotent (a row that already names `tsp` no longer
  matches) and reset-safe, so `supabase db reset` re-runs it cleanly.
- A recipe line already saying `tsp` on a curated cup-default row keeps its
  ordinary `unitNotAllowed` flag on the import review until the household
  widens the row itself. Nothing is rewritten.

## Rejected alternatives

- *Widen every row unconditionally* — the cheap version, and it silently
  overwrites curation. Symmetric with the removal ADR-0009 forbids.
- *Drop the kitchen trim altogether and admit the whole family* — the trim is
  load-bearing at the other end: it is what keeps `l` off a spoon-default row
  and `mg` out of everyone's picker.
- *Leave the rule and let the household add `tsp` per row in the flesh-out
  form* — possible since step 8.5, and it makes every cook re-derive a rule
  the app already knows. The asymmetry was a bug in the trim, not a per-row
  preference.
