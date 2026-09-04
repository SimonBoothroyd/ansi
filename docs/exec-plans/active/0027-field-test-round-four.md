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
  1.75) everywhere: the entry sheet's Portions row (`meal_editor_sheet`
  since week v3; same row, same words) ("1¾ portions — Ada 1 · Jun
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

- [x] Each front lands as its D-list says; deviations are recorded in the
      decision log below with the reason, not silently.
  - [x] **Front M** — landed 2026-09-03 (lane M): M-D1…D6 as ruled; the
        judgement calls are in the log.
- [x] Tests at every layer the change touches: pure domain, repo on a real
      `PowerSyncDatabase`, widget over the real form/sheet, pgTAP for both
      migrations, the mapper's fixture test for M-D5.
- [x] `make ci` green per lane; the orchestrator re-ran it at each landing
      (M: 1623 · +P: 1644 · +U: 1684 app tests; 155 deno; docs-check).
- [x] `make test-sim`: the ingredients file drives M-D1 + U-D1/D2 on the real
      stack (the trigger legs); the week file drives P-D3/D4. Recorded here.
  - [x] **Week (front P)** — landed 2026-09-03 (lane D): `week_test.dart`'s
        3d leg drives P-D3 (Ada sets Jun's ×¾ from Library `⋯` ▸ Household),
        proves the `0026` UPDATE door (the upload queue drains and a direct
        PostgREST read of `household_member.portion_factor` returns `0.75`),
        P-D4 (the Saturday entry sheet's "1¾ portions — Ada 1 · Jun ¾ — their
        usual"; Cook's "covers Sat dinner · 1¾ portions", "×0.88" and the
        ¼-portion nudge; Monday's override + Wednesday's lone eater still 4)
        and P-D5 (Jun's lens: "434 kcal" · "1 meal · Jun · ¾ of 1¾
        portions"). *(Week v3, 2026-09-03: the "entry sheet" this leg
        opens is now `meal_editor_sheet`, reached by tapping a row's
        avatar/portions cluster instead of `Edit` then the meal — the
        leg was rewritten in place, the assertions are unchanged.)*
        `make test-sim FILE=week` on the iPhone 17: **39 s of test time, 1:16 wall** (24 s of it the Xcode build) — the 3d leg adds about five seconds to the file.
- [x] Docs: `docs/QUALITY.md` rows (Ingredients manager, Barcode add,
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
- [x] **Lane U** — front U. Migration `0027`. Slices in order: D1+D5 (column,
  probe, writers, provenance line) → D2 (undo) → D3 (choose another) → D7 (the
  sheet's search). Each slice its own commit. **Landed 2026-09-03** — four
  feature commits + docs; `make ci` green (1625 app tests); pgTAP 131 in
  `unit_admission.sql`, run against a scratch Postgres (the shared stack was
  not reset — see the decision log); sim leg left to the landing.
- **Lane P** — front P. Migration `0026`. Slices: domain (demand, weights,
  fraction formatting, identity test) → data (column, member entity, repo) →
  Household sheet → entry sheet / cook / lens copy (the entry sheet became `meal_editor_sheet` under week v3, same Portions row). ✅ **Built 2026-09-03**
  (`828573d` domain · `2b08ed4` wire · `75de314` Household sheet · `da7fbba`
  the fraction everywhere), `make ci` green in the lane; pgTAP run against
  the shared local stack with `0026` applied *inside* the test transaction
  and rolled back (no reset, no residue) — 9/9. The sim leg (`week_test`
  driving P-D3/D4/D5) landed 2026-09-03 with lane D — see the acceptance
  line above.

Traps (memory): ff-merge main first; copy `.env.local` into the worktree;
never `db-reset` the shared stack; sims are the orchestrator's at landing.

## Decision log

- 2026-09-03 — Board sections flipped proposed → signed off; migration numbers
  assigned up front (P = `0026`, U = `0027`) so the lanes cannot collide.
- 2026-09-03 — U-D7's sub-ruling: an unpicked USDA-leg create keeps today's
  auto-fill (owner agreed with the recommendation).
- 2026-09-03 (lane M) — **The serving unit is the basis.** M-D1's serving row
  is amount + g/ml; picking `ml` flips `macros_basis` to per-100 ml rather
  than converting, so a 240 ml serving stores per 100 ml and the admission
  chips follow live. One stored fact, named by the serving.
- 2026-09-03 (lane M) — **How M-D2 reads the serving's name.** The row has a
  free-text "as the pack calls it" field (seeded from OFF's `serving_size`
  with its parenthetical weight dropped). An optional leading count and a
  word: a volume word with a *mass* serving is a density **per spoon** ("2
  Tbsp = 32 g" offers 16 g a tablespoon, through `densityFromVolumeWeight`);
  a volume word with an ml serving offers nothing (a volume of itself); any
  other word is a measure of one, and a count above one ("2 slices") is not
  offered rather than singularised by guess. Off by default; a taken offer
  unticks itself after the Save that landed it.
- 2026-09-03 (lane M) — **The add sheet's per-serving leg is the serving
  row, not the full segment.** The sheet already draws the printed four on
  the result card; under it sits the shared `ServingRow` (amount + g/ml,
  prefilled or flagged) and the stored-line preview, and Create stores the
  derivation. Without a serving weight the row saves as a panel-less stub
  and the note says so — the printed four are not persisted anywhere (M-D3),
  so retyping them on the form is the honest fallback. The M-D2 offer is the
  form's only (the sheet creates, it does not admit units).
- 2026-09-03 (lane M) — **Fixtures.** OFF's search API was down and no US
  product probed by hand was flagged `nutrition_data_per: serving` with the
  plain `*_serving` four (the flagged ones carry `*_prepared_serving` only —
  captured as `kraft_mac_per_serving`, which maps to *no panel*). The
  happy-path fixture is a real capture (Peanut Butter & Co, 0851087000250)
  with that one flag flipped, stated in the test's header; the
  serving-quantity variants (absent, ml, oz, zero) are constructed in its
  shape. `serving_quantity` + `serving_quantity_unit` joined the client's
  `fields=` projection.
- 2026-09-03 — **P-D6 "RLS unchanged" could not hold as written.** The board
  read the household-scoped UPDATE on `household_member` as "already in
  place"; `0001` ships the table with a read policy and a `select` grant
  only (the client never wrote a member row). P-D3 — either member sets
  either's — needs an UPDATE door, so `0026` adds one: a household-scoped
  `household_member_update` policy (the same `current_household_id()` anchor
  every table uses) and a **column-narrow** grant on `portion_factor` +
  `updated_at` (what the connector PATCHes), so `display_name` and
  `auth_user_id` stay server-owned. pgTAP pins all of it, including the
  `42501` on the other columns.
- 2026-09-03 — **Shopping's data layer reads the factor; its domain is
  untouched.** "Shopping is untouched" (P-D4) is kept as *no per-person
  split, still scaled by the session's batch factor* — but the shopping
  repo derives `CoveredMeal.portions` from the rows itself, so leaving it on
  the head-count would have bought for 2 while the cook plan cooked 1¾. Both
  derived repos now read demand through one `eatersDemand` over one
  `loadMembers`, and watch `household_member`.
- 2026-09-03 — **Only the quarter glyphs (¼ ½ ¾) are used.** Every factor is a
  quarter step and any sum of quarters is a quarter, so those cover every
  demand the household can state; a non-quarter value (a lens share under an
  override, `3 × ¾ ⁄ 1¾ = 1.29`; a leftover against a `serves 2.5` recipe)
  prints as a trimmed decimal rather than a glyph the bundled faces might
  lack. `formatPortions` reads singular at or below one ("¾ portion").
- 2026-09-03 — **`membersProvider` is a stream.** The Portions rows and the
  Household sheet read the roster live (`watchMembers`), so a factor set on
  the partner's phone lands mid-sheet; the derived tabs' watches join
  `household_member` for the same reason.
- 2026-09-03 — **The grid's portions chip is the override**, drawn only when
  it differs from the eaters' own summed demand (identical to the old rule
  when every factor is 1); a fractional usual never earns a chip — the
  avatars are the who, the sheet says the how much.
- 2026-09-03 — **Lane U, one column beyond U-D5's letter: `source_score`
  beside `source_label`.** U-D1's band word ("close match" ≥ 0.85, "a guess"
  below) is a function of the score, and the row did not carry one — so a
  trigger-filled row (the common case) could not print the band offline. The
  two alternatives were worse: asking `probe_usda` when the form opens is
  online-only on an offline-first screen and, after a rename, names a
  different food than the one that filled the row (the board rejected it);
  re-deriving a trigram similarity on the phone is a second matcher under
  invariant 1. `real`, written by both writers in the same statement, cleared
  by a decline. Rows filled before 0027 print the FDC id alone — no band is
  invented for a score never stored.
- 2026-09-03 — Lane U: the sync-rules YAMLs are **unchanged** — both select
  `*` from `ingredient`, so the columns ride down without a rule edit (the
  drift check passes as-is); `schema.dart` gained the two client columns.
- 2026-09-03 — Lane U: the form's "Look up in USDA" button retires on a row
  USDA already filled or a person declined — there the provenance line's two
  doors are the way the match changes, and an automatic probe would have
  nothing it may write. It stays on every other stub. *Choose another* on a
  `usda_fdc:` row replaces the prefill's own fill whole (both prefill writers
  are fill-null-only, so the prefill authored both numbers); the D-list's
  "declined guard lifted for an explicit pick" is read as also covering that
  case, since frame (a) offers the door on a filled row. Numbers a person
  supplied are never overwritten, pick or no pick.
- 2026-09-03 — Lane U: U-D7's "offline the leg says the search cannot run"
  — the probe collapses "offline" and "no confident hit" into one empty
  answer by design (0016), and the app deliberately reports no "offline"
  state anywhere (`sync_health.dart`), so the leg's copy says both: "nothing
  came back — offline, or nothing close enough", with the standing note that
  the search runs on the server and Manual still works.
- 2026-09-03 — Lane U: pgTAP was run against a **scratch** Supabase Postgres
  container (all 27 migrations + seeds applied by hand), never the shared
  stack, whose reset is forbidden while other lanes share it. On that image
  the CLI-provisioned assertions (RLS via `auth.uid()`, the client-role grant
  on `usda_food`, the token hook) fail identically before and after 0027 —
  environmental, not a regression; the trigger/probe/data assertions,
  including all twenty new ones, pass. The orchestrator's `supabase test db`
  on a reset stack is the authoritative run.
- 2026-09-03 (lane D) — **The sim's lens leg plans a second, seeded recipe.**
  P-D5's "¾ of 1¾ portions" is the denominator under a *total*, and the
  week file's curry has no total to put it under — Garlic by the clove and
  Onion by the piece are count lines, refused by rule (invariant 3), and a
  refused day names no share. Rather than weaken the curry (its refusal is
  what the picker, confirm and week assertions lean on), the file seeds
  "Macro Bowl" (200 g Almonds, serves 2 — a line the seeded vocab resolves)
  and plans it on Sunday for both, so the lens has 579 kcal a serving to
  split. It runs last, after 3a–3c, so every earlier number stays the
  all-factors-1 identity P-D6 promised.
- 2026-09-03 (lane D) — **The RLS door is proven by a server read, not only
  the queue.** A drained upload queue says the connector's PATCH was not
  refused; the test also reads `household_member.portion_factor` back
  through the signed-in Supabase client, which is the table's own word that
  `0026`'s policy + column-narrow grant let Ada set Jun's row. A test-only
  REST read — `lib/` still reads synced data from SQLite alone.

- 2026-09-03 — **All three fronts landed on main** (M `c2888ba`…`8d83102`,
  P `4ea19a9`…`3bd1dfd`, U `e4ff333`…`919c1aa`), by cherry-pick; the only
  conflicts were additive (the form's doc comment and imports, the three
  docs files' appended sections). `0026`/`0027` applied to the local stack
  with `supabase migration up` (no reset) and the PowerSync container
  recreated for the streams; the whole smoke directory then ran **6/6 in
  7:53** on iPhone 17. The M/U/P legs themselves are Lanes C and D's.
- 2026-09-03 — **pgTAP on the migrated stack found a pre-existing bug**, not
  a regression: `unit_admission` #49 failed because every app-created
  ingredient had uploaded `allowed_units` as a jsonb *string* (the connector's
  jsonb map never listed the 0012 column). Fixed in the connector, repaired
  by `0028_allowed_units_jsonb_repair.sql`, held by
  `test/structure/jsonb_columns_test.dart`; pgTAP 327/327 after (`ceebc66`).
  `0028` rides to cloud with `0026`/`0027`.

## Step-done checklist

- [x] Roadmap 8.11 flipped with one line on what shipped / deferred.
- [x] `docs/QUALITY.md` grades match reality.
- [x] `app/AGENTS.md` still true.
- [x] `make test-sim` recorded here (ingredients 2:20 test / 2:58 wall — M-D1/D2/D3 + U-D1/D2; week 39 s / 1:16 — P-D3/D4/D5).
- [x] Tech-debt rows added / retired.
- [ ] `0026`/`0027`/`0028` on cloud, ledger entry in `docs/cloud-setup.md` — **the one open item**; the plan moves to `completed/` when it lands.
- [x] `make ci` green (1685 app · 155 deno at the last landing).
