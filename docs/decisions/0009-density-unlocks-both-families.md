# ADR-0009 — A density unlocks the other mass/volume family whatever the default unit's family

- **Status:** accepted (2026-08-31, Simon + agent — exec plan
  [0020](../exec-plans/active/0020-ingredients-manager.md) D4, owner-signed)
- **Supersedes:** the second sentence of
  [ADR-0008](./0008-unit-admission-model.md) §Decision ¶2 ("Density … unlocks
  the whole other family"), which both implementations read as *gated on the
  default unit's family*. Everything else in ADR-0008 stands.

## Context

ADR-0008 §2 already said a density "unlocks the whole other family". Both
mirrors implemented something narrower:

```dart
// allowed_units.dart
if (ingredient.densityGPerMl != null &&
    (d.family == UnitFamily.mass || d.family == UnitFamily.volume)) { … }
```

```sql
-- 0012_unit_admission.sql
if p_density_g_per_ml is not null
   and default_family in ('mass', 'volume') then …
```

The gate was defended in a comment as "a density can't describe a piece". That
is true of a *count*, and false of the substance: a **piece-default row with a
perfectly good density** — mango, tomato, onion, avocado — admitted no volume
unit at all. "1 cup diced mango" is an ordinary recipe line, and it failed
import with `Pick a supported unit` on 49 template rows that had carried an
honest density all along.

The seed pipeline papered over it with a category-gated
`allowed_units` patch in `seed_curation.sql`, explicitly labelled as standing
"until ADR-0008 is amended". A seed patch cannot help a household that creates
a piece-default ingredient **in the app**, which is the actual bug — and step
8.5 is building the form that makes such rows routine.

Found while reading the same code: the SQL and Dart imprecise legs had
**already drifted** — Dart emitted `pinch, dash, handful, toTaste`, the SQL
`pinch, dash, to_taste`. The shared vectors covered no imprecise-gated row, so
nothing caught it.

## Decision

**A stored density unlocks the other mass/volume family for the ingredient,
whatever the default unit's family.** Density is a property of the substance,
not of how the shop sells it: a mango is bought by the piece and still has a
cup.

- **Mass default** → the volume workhorses `tsp, tbsp, cup, ml` (unchanged).
- **Volume default** → `g`, plus `kg` at cup/lb scale (unchanged).
- **Count or imprecise default** → there is no "other" family, so **both**:
  `tsp, tbsp, cup, ml` **and** `g` (plus `kg` at cup/lb scale, unreachable in
  practice — no count or imprecise default is big). Minus whatever the basis
  leg already admits, which set semantics do for free.
- The unlocked units stay **demoted below the measures** in chip order, exactly
  as ADR-0008 §Consequences already says.

Three rules follow from "one source of the fact":

1. **The rule lives in `default_allowed_units()` and its
   `densityUnlockedUnits` / `defaultAllowedUnitSet` Dart mirror** — plus a
   `density_unlocked_units()` SQL function so the defaults, the migration
   backfill and the runtime triggers all read the same one copy.
2. **The seed's produce patch is retired**, replaced by a pgTAP assertion that
   the amended rule yields those admissions (`supabase/tests/unit_admission.sql`).
   A safety net belongs in a test, not in a duplicated write. The seed keeps
   only its genuinely non-derivable per-row overrides (liquid smoke `tsp`;
   allspice/clove/nutmeg `tsp`; hot sauce/soy sauce `to_taste`) — those are not
   density-derived and have nowhere else to live.
3. **Existing rows are backfilled by UNION, never by re-materializing.**
   `allowed_units` is user-owned after creation (ADR-0008 §4). Recomputing the
   defaults over the table would silently discard both the seed's curated
   overrides and every edit the step-8.5 flesh-out form is about to make
   possible.

**Also decided here, as parity housekeeping:** the SQL imprecise leg emits
`handful` alongside `pinch`, `dash` and `to_taste`, matching the Dart mirror.
The shared vector file gains an imprecise-gated row so the two cannot drift
silently again. This is a *rule* change only — it is deliberately **not**
backfilled onto existing lists, which are the user's.

## Consequences

- `default_allowed_units()` gains no new argument and loses one guard; a
  piece-default row with a density now materializes the volume workhorses at
  creation, everywhere, including a row typed into the app.
- A density **arriving** on an existing row (the USDA prefill, a template
  reseed, a cloud operator's backfill, the in-app density write) unions the
  same set into `allowed_units` — migration 0014's
  `ingredient_density_unlocks_units` trigger. This closes a long-standing
  tech-debt row: before it, only the in-app `setDensity` path extended the
  list.
- A household that deliberately **removed** a density-unlocked unit and later
  edits the density gets it back. Accepted: it is the same behaviour the in-app
  density write already had, and the honest one — the unit is sayable again.
- Slightly more generous chip rows on count-default foods. A cup of bay leaves
  is odd but computable; ADR-0008's ordering rule already demotes it below the
  measures, and the flesh-out form can retire it per row.
- The `handful` parity fix reaches every seasoning/oil row. The seed's curated
  imprecise removals were extended to cover it (nobody takes a handful of olive
  oil, or of liquid smoke).

## Rejected alternatives

- *Keep the rule and keep the seed patch as belt-and-braces* — two stored
  copies of one derived fact, which ADR-0008 itself rejects for density. It
  also cannot reach an in-app-created row, which is the bug.
- *Don't amend; extend the seed patch to more categories* — the status quo
  that already failed, category by category, forever.
- *Make the count/imprecise unlock category-gated (produce only)* — the gate
  would be a second rule to remember, and the physical fact does not depend on
  the category. If a count row has a density, the conversion is honest.
