# Exec plan: field test, round four — three fronts, signed off on the board

- **Status:** active
- **Owner:** Simon (rulings) · agent lanes (build) · orchestrator (landing)
- **Roadmap step:** 8.11
- **Created:** 2026-09-03

## Goal

Ship the three proposals the owner signed off on 2026-09-03 — board sections
"Macros from a label · per serving", "The USDA match · shown, undone,
re-chosen" and "A usual portion per person" — each exactly as its D-list
rules, with the tests the quality bar asks for, and verified on the sim.

The decision lists are the law. They live in the board sections and, verbatim,
in this session's scratchpad (`lanes/*-decisions.md`); the rulings that matter
are repeated here so a lane needs nothing outside the repo.

## The rulings (owner, 2026-09-03: "sg" on all three; USDA "I agree with your recommendations")

### Front M — macros from a per-serving label (`features/ingredients`)

- **M-D1** A `per` segment on the flesh-out form's macros section: `per 100 g ·
  per 100 ml · per serving`. *Per serving* reveals one row — serving amount +
  unit (g/ml, defaulting to the row's basis) — and the four fields take the
  label's figures as printed; a muted line under them shows the stored per-100
  derivation live. Default stays per 100 of the basis.
- **M-D2** Under the serving row, one opt-in line: when the serving is a spoon
  ("1 tbsp = 14 g") offer *set as this row's density* through the existing
  `densityFromVolumeWeight` path; when it names a thing ("1 slice = 28 g")
  offer it as a measure through the measures editor. Off by default, one tap,
  same save.
- **M-D3** Store the derived per-100 macros unrounded; nothing else is
  persisted. At entry the line says "from a 14 g serving — the label's
  rounding scales with it".
- **M-D4** No wire change.
- **M-D5** The barcode mapper's `perServingPanel` case carries the four printed
  values; the draft card opens in per-serving mode with the serving amount
  prefilled from OFF's numeric `serving_quantity` (+ unit) when present, else
  empty and flagged "type the serving weight from the pack". Still a stub.
- **M-D6** The model stays kcal · protein · carb · fat. Calories are kcal.

### Front U — the USDA match (`features/ingredients`, `supabase`)

- **U-D1** A provenance line at the head of the form's macros/density section:
  "Filled from USDA · *description* · FDC id · close match | a guess" (band from
  the score: ≥ 0.85 close, 0.5–0.85 a guess), with *Not this food* and *Choose
  another ▸*. The description is a new synced column `ingredient.source_label`,
  written by both prefill writers (the trigger and `applyUsdaProbe`) from
  `usda_probe` widened to return `description`.
- **U-D2** *Not this food* is one write: `clearDensity` (so the D4b strip of
  unlocked units runs), clear `macros`, set `source = 'usda_declined'`. The
  0015 rename trigger's WHEN clause does not list it, so no refill. Offered
  only while `source` starts with `usda_fdc:`.
- **U-D3** *Choose another ▸*: `probe_usda(name, limit)` (default 1), the form
  asks for 5; a sheet lists description · category · band; picking applies
  through `applyUsdaProbe` (declined guard lifted for an explicit pick),
  stamping id + label. Second slice, after D1/D2.
- **U-D4** Nothing here promotes a row; confirming stays a human act.
- **U-D5** Migration `0027_usda_source_label.sql`: the column, the widened
  probe, both writers set the label, `usda_declined` accepted wherever
  `source` is checked. `schema.dart` + both sync-rules YAMLs gain the column.
  pgTAP: trigger writes the label; a declined stub is not refilled on rename;
  the widened probe orders as before.
- **U-D7** The New-ingredient sheet's USDA leg becomes a search: the name
  field is the query, the rows are the top five with their band word, and
  Create applies the picked candidate as the row is made. Nothing picked ⇒ a
  plain stub that the server trigger fills with its best hit as today (owner:
  auto-fill stays). Offline the leg says the search cannot run; Manual is
  unchanged. The greyed "Look up in USDA" and its note go.

### Front P — a usual portion per person (`features/planning`, `cook_plan`, `supabase`)

- **P-D1** `household_member.portion_factor numeric(4,2) not null default 1`
  (migration `0026_portion_factor.sql`). Demand = Σ factors of the entry's
  eaters; the per-entry integer `portions` override still wins.
- **P-D2** A segment ×½ · ×¾ · ×1 · ×1¼ · ×1½ plus *custom* in quarter steps
  (0.25–3).
- **P-D3** Set from a *Household* row in the Library `⋯` menu → a sheet
  listing the members with their segment; either member may set either.
- **P-D4** Demand is fractional and printed as a fraction (½ ¾ ¼ glyphs, never
  1.75) everywhere: the entry sheet's Portions row ("1¾ portions — Ada 1 · Jun
  ¾"; the override stepper stays whole and its small print reads "overrides
  the eaters' 1¾"), `CookSession.portions` becomes a double, batches = demand
  ÷ `servings_base` as today, the whole-batch nudge speaks the fraction.
  Shopping is untouched. Week grid rows keep their avatars.
- **P-D5** The per-person macro lens weights by factor (× override ÷ Σ factors
  when an override is set) and names its denominator ("Jun · ¾ of 1¾
  portions"). An entry with an override and no eaters stays unattributable.
- **P-D6** Default 1 ⇒ every existing number unchanged; a test runs today's
  fixtures through the new derivations and asserts identity. `schema.dart` +
  both sync-rules YAMLs gain the column; RLS unchanged; pgTAP: default 1, a
  member may set the partner's factor.

## Acceptance criteria

- [ ] Each front lands as its D-list says; deviations are recorded in the
      decision log below with the reason, not silently.
- [ ] Tests at every layer the change touches: pure domain, repo on a real
      `PowerSyncDatabase`, widget over the real form/sheet, pgTAP for both
      migrations, the mapper's fixture test for M-D5.
- [ ] `make ci` green per lane; the orchestrator re-runs it at each landing.
- [ ] `make test-sim`: the ingredients file drives M-D1 + U-D1/D2 on the real
      stack (the trigger legs); the week file drives P-D3/D4. Recorded here.
- [ ] Docs: `docs/QUALITY.md` rows (Ingredients manager, Barcode add,
      Planning, Cook-plan), `app/AGENTS.md` if a rule changes, ADR-0009's
      density leg unaffected, the roadmap 8.11 row flipped, cloud ledger
      entry once `0026`/`0027` are pushed.

## Lanes

Three worktree lanes, parallel, no shared files except `schema.dart` and the
two sync-rules YAMLs (U and P both add a column — the orchestrator merges
those two lines at landing) and `docs/QUALITY.md`.

- **Lane M** — front M. No migration. `core/units/macros.dart` (the pure
  conversion), the form's macros section, the D2 opt-in line, the mapper +
  draft card branch.
- **Lane U** — front U. Migration `0027`. Slices in order: D1+D5 (column,
  probe, writers, provenance line) → D2 (undo) → D3 (choose another) → D7 (the
  sheet's search). Each slice its own commit.
- **Lane P** — front P. Migration `0026`. Slices: domain (demand, weights,
  fraction formatting, identity test) → data (column, member entity, repo) →
  Household sheet → entry sheet / cook / lens copy.

Traps (memory): ff-merge main first; copy `.env.local` into the worktree;
never `db-reset` the shared stack; sims are the orchestrator's at landing.

## Decision log

- 2026-09-03 — Board sections flipped proposed → signed off; migration numbers
  assigned up front (P = `0026`, U = `0027`) so the lanes cannot collide.
- 2026-09-03 — U-D7's sub-ruling: an unpicked USDA-leg create keeps today's
  auto-fill (owner agreed with the recommendation).

## Step-done checklist

- [ ] Roadmap 8.11 flipped with one line on what shipped / deferred.
- [ ] `docs/QUALITY.md` grades match reality.
- [ ] `app/AGENTS.md` still true.
- [ ] `make test-sim` recorded here.
- [ ] Tech-debt rows added / retired.
- [ ] `0026`/`0027` on cloud, ledger entry in `docs/cloud-setup.md`.
- [ ] `make ci` green.
