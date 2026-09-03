# Exec plan: 0025 — Field test, round three — seven owner-raised fronts on `v0.3.0`

- **Status:** active — all eight items landed on main 2026-09-03 (`29a3345`; `make ci` green at every landing, pgTAP 297); `make test-sim` running; cloud push + tag to follow
- **Owner:** Simon (rules) + Claude (orchestrator; design lane for the frames, then build lanes)
- **Roadmap step:** 8.10 (follow-up to 8.9 / plan 0024)
- **Created:** 2026-09-03

## Goal

The `v0.3.0` build on the Pixel surfaced seven things. Two are bugs with a
single root cause each (1, 5), one is a catalogue gap (2), and four are
behaviour the app is missing or has drawn wrong (3, 4, 6, 7). Land them as one
slice: frames for 3/4/6/7 signed off on the board first, then build lanes,
`make ci` + `make test-sim` green, one tag.

The owner's words, verbatim, because every decision below answers to them:

> 1. "if I edit a recipe save, then hit back I land on the recipe again and
>    need to hit back again … we should audit similar routes"
> 2. "we should support quart"
> 3. "if I add an ingredient when creating a recipe I expected to be taken to
>    the new ingredient modal, instead it just created a placeholder and
>    obviously I couldn't select the right units because the ingredient wasn't
>    set up yet"
> 4. "on import recipe review I can't enter fridge life / freezes"
> 5. "After importing a recipe the chip editor says pieces for parsed number
>    amounts, even though the ingredient correctly states e.g avocado. If I
>    save then edit the recipe the chip editor is correct"
> 6. "I don't think there's a way in the UI to flag / unflag an ingredient as
>    optional, but import can flag ingredients as being?"
> 7. "cook and shop follow the same week as week — it would probably be better
>    to show the same picker instead so we can see previous weeks
>    independently rather than the current title"

## Scoping — root cause, fix, blast radius, per item

### 1. Save then back re-lands on the recipe (bug)

**Root cause.** `recipe_editor_view.dart` ends Save with
`context.pushReplacement('/recipes/$id')` for *both* a new and an existing
recipe. For an existing one the stack is
`[shell, /recipes/:id, /recipes/:id/edit]`; replacing the top page yields
`[shell, /recipes/:id, /recipes/:id]` — two copies of the recipe page, so back
shows the same page again. The replacement is only right for `/recipes/new`,
where nothing but the opener sits beneath.

**Fix.** Edit-existing → `context.pop()`: the recipe page beneath is a watched
query, so it already shows the saved content. New → keep `pushReplacement`.
The stated rule becomes: *editing returns you to where you opened the editor;
creating lands you on the thing you made.*

**Audit of the other post-action landings** (every `pushReplacement`/`go`/
pop-then-push in `lib/`):

| Site | Stack before → after | Verdict |
|---|---|---|
| `import_view.dart` commit → `pushReplacement('/recipes/:id')` | `[shell, /import]` → `[shell, recipe]` | correct — no recipe page beneath |
| `recipe_view.dart` delete → `go('/')` | `[shell, recipe]` → `[shell]` | correct (navigation.md §3) |
| `new_ingredient_sheet.dart` create → pop sheet, `pushOnce(detail)` | `[…, /ingredients]` → `[…, /ingredients, detail]` | correct |
| `ingredient_picker.dart` / `line_target_picker.dart` "flesh out now" → pop, `pushOnce(detail)` | picker closes, form opens over the editor | **wrong in a subtler way** — the picker's future completes, so the editor's `_addLine` resumes and opens the quantity sheet over the form the user just asked for (traced from code, not reproduced; see item 3) |
| `entry_sheet.dart`, `recipe_picker_sheet.dart` pop-then-push | sheet closes, page opens | correct |
| `ingredient_detail_view.dart` | no post-save navigation; stays on the form | correct |
| editor opened from Cook's gap card (`cook_view.dart` → `/recipes/:id/edit`) | after the fix: save pops to Cook, whose gap card resolves live | acceptable; the recipe page was never beneath |
| editor's "set yield" sub-editor (`recipe_editor_view.dart` → `/recipes/:target/edit`) | after the fix: save pops back into the parent editor (today it lands on the target's page over the parent editor) | improves |

Stale comment to fix on the way: `recipe_view.dart` header back says "After
Save's `context.go`…" — that `go` is two designs old.

**Tests.** A widget test over a real `GoRouter` in
`test/features/recipes/`: edit → Save → one back shows the opener; new → Save →
the recipe page → one back shows the opener. Update the reason string for the
editor's entry in `guarded_navigation_test.dart`'s exception list (it stays an
exception for the new-recipe case). Docs: navigation.md §3 back table row
"A page landed on after a save" splits into the two cases.

No decision needed.

### 2. Quart (catalogue gap)

The unit catalogue is one Dart file mirrored in **nine** places; adding a unit
is a sweep, not an edit. `units.dart` is the source; every mirror is pinned by
a test that will go red, which is the point.

| Mirror | What changes |
|---|---|
| `app/lib/core/units/units.dart` (+ `units_test`) | `quart` (`qt`, 946.352946 ml) — and `pint` (`pt`, 473.176473 ml) under D2a; exact by definition of the US gallon, like the rest |
| `app/lib/features/ingredients/domain/allowed_units.dart` (+ test vectors) | the volume list, `_kitchenMates`, the `big` gate, the density-unlock volume list — per D2b |
| `app/lib/features/import/domain/yield_prefill.dart` | `quart`/`quarts`/`qt` (and pint words) in the unit-word map |
| `supabase/functions/_shared/unit_hints.ts` (+ test) | `UNIT_CATALOG` entry — this is what makes "1 quart stock" arrive `unit_mappable` instead of flagged |
| `evals/runner/fixtures.ts` | `units` list + label pairs |
| **new migration `0024_quart.sql`** | `create or replace` `unit_family()` (0017), `default_allowed_units()` and `density_unlocked_units()` (0021's versions) with the new ids; then an additive UNION backfill of `allowed_units` for rows whose default now admits them (the 0014 pattern: extend, never re-materialize — household edits survive) |
| `supabase/tests/nested_recipes.sql`, `unit_admission.sql` | family vector + admission vectors |
| `supabase/seed/scripts/gen_seed.ts` + regenerated `seed_curation.sql` | the "volume-default ⇒ density" assertion's unit list |
| `docs/design-docs/unit-and-measure-matching.md` (§ table, §matching row) | the two volume rows |

**Data is durable** (owner, 2026-09-03): the migration is additive and the
backfill is a UNION. Cloud push + ledger entry
at landing.

**D2a — quart alone, or the US pair?** Options: (A) `qt` only; (B) **`qt` +
`pt` — recommended**: same shape, same exactness, one sweep instead of two,
and pint is the other unit American stock/cream lines are printed in; (C) add
`gal` too — rejected for now, it never appears in a home recipe and its
magnitude would distort the `big` gate.

**D2b — what admits a quart?** Admission is per-ingredient and materialized
(ADR-0008), so a new unit is useless until some default admits it. Vegetable
Broth's default is `cup`; today a "1 quart broth" line would be flagged with
a `cup`/`l` chip. Options: (A) `qt` rides with `l` and `pt` rides with `cup` —
**recommended**: wherever a mates list already contains `l`, add `qt`;
wherever it contains `cup`, add `pt`; `qt` and `pt` themselves get
`{qt, pt, cup, l, ml}` / `{pt, cup, qt, ml}`. One sentence, mirrors cleanly in
SQL, and reaches every broth/stock/milk row through the `big` gate it already
passes; (B) only admit them when they are the default — safe and pointless;
(C) admit them on every volume row — the "no litres of yeast" rule says no.

### 3. Add-new ingredient from the editor (behaviour gap)

**What happens today.** The editor's picker (`line_target_picker.dart`) shows
`AddNewIngredientRow`: tapping it writes a `stub` (USDA-enriched when online),
then swaps to a two-line mono strip — *"added X as a stub · use it · flesh
out now →"*. "use it" hands the stub straight to the quantity sheet, whose
admissible units are whatever a stub has (nothing curated), which is exactly
what the owner hit. And "flesh out now" is itself broken under the shell: it
pops the picker *with* the ingredient and pushes the detail form, so the
editor's `_addLine` resumes and opens the quantity sheet over the form, before
any unit has been set (traced from code, not yet reproduced on the sim).
The strip is easy to miss; the path that isn't is the wrong one.

**Fix (D3).** The picker's add-new row becomes the front door the manager
already has: `showNewIngredientSheet` (manual · USDA · barcode — one answer to
"what does creating an ingredient mean", plan 0020 D7b), name prefilled from
the query. The sheet hands the created row back to its host instead of pushing
the form itself; the picker pushes the flesh-out form and **awaits the pop**,
then resolves with the ingredient, so the quantity sheet opens *after* the form
and offers the units the form just set. The manager's list keeps its current
behaviour (create → form) through the same hook.

**D3 — ruled (owner): "move away from allowing stubs; ideally only the
seeded rows are stubs".** So the rule is stronger than the picker fix: **no
path in the app creates an ingredient without landing on the flesh-out
form.** The seed's stubs stay (curation debt, tracked); the app stops minting
new ones as a side effect of something else.

Where the app mints stubs today, and what each becomes:

| Path | Today | After |
|---|---|---|
| editor picker (`line_target_picker.dart`) add-new | stub + "use it / flesh out" strip | New-ingredient sheet (name prefilled) → form → back → quantity sheet with the set-up units |
| ingredient picker (`ingredient_picker.dart`) add-new — shopping top-up host | stub, no router in scope | same flow (ruled); the top-up sheet gets the router in scope |
| import review "create new" (`CreateNewStub`, `source='import_stub'`) | commit mints a stub per unmatched name, coalesced | the line's create-new opens the same sheet → form → back with the line resolved to the new row; `CommitStub` and the coalescing leg retire once no line can carry a stub key |
| manager "New ingredient" (`new_ingredient_sheet.dart`) | manual/USDA/barcode → stub → form | unchanged in shape; the sheet hands the row to its host instead of pushing the form itself |

The one thing that stays a stub is a row whose macros are not yet filled —
`status` is still the honest fact about the data (plan 0020 D5: confirming is
a human act). What changes is that nobody *leaves* the form to reach a recipe
line; the form is on the way, not an optional detour.

Mechanics worth naming for the lane: `pushOnce` is fire-and-forget by design
(`guarded_navigation.dart`); this needs a `push<T>` that returns the pop
result, added beside it with the same top-location guard rather than a bare
`context.push` (the structural test would catch it). The import review's
line-card sheet runs on the root navigator over the review page, so "sheet →
form → back to the card" is the same push-and-await. Board frames: the picker
footer + the sheet with the prefilled name; the review card's create-new.

### 4. The review is missing the editor's header — reuse it (behaviour gap)

**What the editor has that the review does not.** Side by side:

| Section | Editor | Review |
|---|---|---|
| Title | editable | read-only text (`payload.title`, or "Untitled recipe") |
| Serves | stepper | stepper |
| Makes | qty + unit, plus the SECOND denomination | qty + unit only |
| Shelf life (fridge days · freezes · freezer days) | yes | **absent** — no state, no `CommitPayload` field, not in the INSERT |
| File under (book · section) | yes | **absent** — commit files into the default book silently |
| Cook / total time | **neither** — `cook_time_seconds` / `total_time_seconds` exist only in the schema and the import INSERT; the `Recipe` entity, the repo's read/write, the editor and the recipe page never touch them (ruled: both get them) | — |

So "fridge life" is one symptom of the review having grown its own copy of
the header (`_ServingsRow`, `_MakesRow`) and stopping there. Adding a third
copy of the shelf-life section would be the same drift one section later.

**Fix (D4, ruled "same as recipe editor").** One header, two hosts:

- The `Recipe` entity gains `cookTimeSeconds` / `totalTimeSeconds`; the repo
  reads and writes them (today an editor save would not even preserve what
  import wrote — verify, and pin it); the recipe page shows them in its header
  meta line.
- Lift the editor's five header sections — six with a new TIMES section
  (cook · total, minutes steppers, unset allowed) — into
  `features/recipes/presentation/recipe_header_form.dart`, bound to a small
  `RecipeHeaderHost` interface (the current values as a `Recipe`, plus the
  setters the editor notifier already has: `setTitle`, `setServings`,
  `setYield`, `setKeepsForDays`, `setFreezable`, `setFreezerDays`, `setBook`,
  `setSection`, plus new `setCookTime` / `setTotalTime`). `RecipeEditor`
  implements it with two new setters.
- The import controller stops carrying its own `servings` / `yieldQty` /
  `yieldUnit` and holds a **header draft `Recipe`** instead (the preview
  recipe is already a `Recipe`; this is the same object earlier). It
  implements the same host interface; `buildCommit` reads the header from the
  draft; the INSERT writes every header column the editor's save writes.
- The review keeps what is import-specific *around* the shared header: the
  source notes, the "from source: …" line under MAKES (the review's honesty
  over `yield_raw`), the never-invent flags, the cards and the Save gate.
- A structural test pins the seam: the header form declares its section list
  once, and both hosts are asserted to render every section — the next
  section added to the editor cannot silently miss the review.

**Tests.** Header-host contract test run against both implementations; a
repository commit test asserting title / yield×2 / shelf life / book on a real
`PowerSyncDatabase`; the review widget test; the existing editor tests
unchanged.

### 5. The chip editor says "piece" for a resolved measure at review (bug)

**Root cause.** `preview_recipe.dart`'s `_unitOf` maps the resolution's unit
through `unitById`; a resolved *measure word* ("avocado", or a default measure
spent by 0024's D2) is not a catalogue id, so it degrades to `pieces` — and the
preview `LineItem` carries no `measureId`/`measure`. The chip sheet formats
through `item.measure` (`ingredient_line.dart`), so it prints "piece". The
review card itself is right because it reads `unitMeasure` off
`importValidationProvider` (`_measureNamed`), so the two surfaces on one screen
disagree. Commit resolves `measure_id` (`_measureIdFor`), which is why the saved
recipe's editor is correct.

**Fix.** `buildPreviewRecipe` takes the per-line measure the validation loader
already resolved (the batched `measuresByIngredients` result — no new query)
and writes the line exactly as commit will: `unit: pieces`, `measureId`,
`measure`. Pure Dart; the preview then cannot disagree with either the card or
the saved row. Test: `preview_recipe_test` with an avocado line resolved to
its measure, asserting the chip label.

No decision needed.

### 6. Optional lines (behaviour gap)

**Where the flag lives today.** The extractor emits `optional` per raw line
(`_shared/types.ts`); the app's `ReconciliationPayload` parses it; the review
card shows it as a raw tag. Then it stops: `LineResolution`, `CommitLine`,
`LineItem` and `recipe_line_item` (SQL `0003`, `schema.dart`) have no such
field, so commit drops it and nothing downstream — editor, page, cook, shop,
macros — has ever heard of it.

**Fix.** A first-class line fact end to end:

- **new migration `0025_optional_line.sql`**: `recipe_line_item.optional
  boolean not null default false` (additive; the cloud stream already selects
  `*`); `schema.dart` column; `LineItem.optional`; recipe repo read + child
  diff write.
- import: `LineResolution.optional` seeded from the raw flag, toggleable on the
  card; `CommitLine.optional`; the INSERT; the preview carries it.
- editor: a toggle per line (D6a); recipe page: a muted `optional` tag after
  the note, the same voice as the stub badge.
- downstream semantics per D6b.

**D6a — where the toggle sits in the editor.** (A) **a switch row in the
quantity/unit sheet — recommended**: the sheet is already "everything about
this line's amount", it is one tap away on every line, and the same sheet is
reused at review so both hosts get it for free; (B) a per-line `⋯` menu — the
editor has none today (a line has a remove button only) and this would be its
only item.

**D6b — ruled (owner): exclude optional lines, for now.** Macros exclude
them and name them under the total (0024's D6 "not counted" mechanism);
shopping excludes them and the recipe's provenance line says so ("2 optional
lines not listed"), never a silent drop; cook plan unaffected.

**Designed for, not built this wave — per-week recipe overrides.** The owner
wants, later, to edit a recipe *for one planned week only*: tick an optional
line in, substitute an ingredient. The shape to leave room for now:

- a `plan_entry_line_override` table (`plan_entry_id`, `line_item_id`,
  `included boolean`, `substitute_ingredient_id`, `quantity`, `unit`,
  `measure_id`) — one row per touched line, the untouched recipe stays the
  recipe;
- cook-plan and shopping derivation already run over a recipe's lines per
  entry; this wave routes that through one `effectiveLines(recipe, entry)`
  function whose only rule today is "drop `optional`", so the override join
  later slots into one place instead of three;
- the recipe page's "Used in" tab is where a week-specific edit would be
  visible.

Nothing above is a migration this wave; it is the seam the exclusion goes
through. Tracker row at landing.

**Tests.** Repo round-trip on a real db (incl. child diff), `buildCommit`,
`recipe_macros` exclusion + reason, `buildShoppingList` tag, editor + page
widget tests; smoke scenario 4 gains one optional line.

### 7. The week switcher on Cook and Shop (behaviour change)

**What's there.** `cook_view.dart` and `shopping_view.dart` draw a static
title with a derived suffix (`Batch cook plan · next week`) and a
`BackToThisWeekPill`; the Week screen's title *is* the `WeekSwitcher`
(chevrons + menu). All three read one keep-alive `viewedWeekStartProvider`
(Week v2 D3), so the switcher already works from any tab — but the owner's
"independently" points past a header swap.

**D7a — ruled (owner): one shared position.** Changing the week on Shop
changes it on Cook and Week. This is the state the app already has
(`viewedWeekStartProvider`, keep-alive, read by all three); the change is a
header one: the `WeekSwitcher` becomes the title of all three tabs. The Week
banner ("Cook and Shop follow it too") and the two `BackToThisWeekPill`s
retire — the switcher in every header, with its herb dot and "This week" menu
item, is the same information where the eye already is.

**D7b — the switcher's menu on a derived tab.** Its "Copy last week into
this one" is a Week *write*. Recommend hiding it on Cook/Shop (their stated
rule is "edit the Week, and this re-derives"); "This week / Next week / Last
week / Jump to today" stay.

**D7c — the screen name.** Today the Cook header reads *Batch cook plan* and
Shop's reads *Shopping list*. The switcher takes that title slot, so those
words would no longer appear on the screen — only the lit tab in the bar
(*Cook*, *Shop*) says where you are. Options: (A) **switcher only, as Week
already does** (its header says "‹ This week · 31 Aug ▾ ›" and no "Week") —
recommended, one header grammar across the loop; (B) a small mono eyebrow
above the switcher (`BATCH COOK PLAN` in the `_Label` voice) — keeps the name
at the cost of a taller header on two of three tabs; (C) name as the title,
switcher as a second row — heaviest, and the switcher stops being *the*
title. **Ruled (owner): (A)** — "the switcher only / nav bar is the right
indicator".

**D7d — the bar's selected contrast (owner, with D7c).** With the header no
longer naming the screen, the lit tab carries the whole "where am I", and
the owner finds the selected icon too close to the unselected ones. The bar
takes Forui's default item style: selected = `primary` (`AnsiColors.herb`),
unselected = `mutedForeground` (`AnsiColors.muted`), weight 400 → 700
(`ansi_bottom_nav.dart` deliberately sets no colour of its own). Options:
(A) **selected steps to `herbDeep`** via an `FBottomNavigationBarStyle`
override in `ansi_theme.dart`, unselected unchanged — recommended, it is the
same darkening the secondary foreground already uses; (B) unselected lightens
instead — risks the labels falling under the contrast floor; (C) both, plus a
2 px herb underline on the selected item — heavier than the bar wants. The
lane measures the contrast ratio of both states against the bar's ground and
records it. Frame on the board beside the Cook header.

**Blast radius.** No state change. `week_header.dart` (the switcher gains a
`showCopyLastWeek` flag; pill + banner deleted), the two headers,
`week_view_models`'s doc block; `cook_screen_test` (four title asserts), `shopping_screen_test`,
the week tests that drive `viewedWeekStartProvider`, and the smoke — scenarios
3/6 anchor on `find.text('Batch cook plan')` / `'Shopping list'` five times
and need a stable anchor (a semantics label on the switcher, or a key on each
tab root). Docs: product-spec Week v2 D3 wording; board section "Week v2" D3.
Board frames: Cook and Shop headers.

### 8. Scan a barcode from the flesh-out form (owner-added 2026-09-03)

> "manual flesh out ingredient form has option to scan barcode to populate.
> same for ingredient editor. ideally these are the same forms."

**What's there.** They are already one form: `ingredient_detail_view.dart`
serves both the just-created row and an existing one (edit + confirm). The
barcode door (`scanBarcodeForDraft`) is reachable only from the New
ingredient sheet's Barcode segment, and only *before* the row exists — the
sheet applies the draft at creation (name, macros + basis, pack measure,
`off:<barcode>` provenance). A row that was created manually, or seeded, has
no way to be populated from a label afterwards.

**Fix.** The form gains a "Scan barcode" action that runs the same door and
applies the draft through ONE shared apply function the sheet also uses (one
answer to "what does a draft do to a row"). The draft **prefills and never
confirms** (plan 0020 D1/D5): it fills fields that are empty and leaves a
value the human already typed alone, saying in the draft card which fields it
skipped; provenance becomes `off:<barcode>` only when the row had none. Rides
in the **no-stubs** lane (same files). Sim-covered by the typed-barcode path
(scenario 5's idiom); the live camera stays the physical-device errand.

## Acceptance criteria

- [x] Board frames for 3, 4, 6, 7 signed off ("go", 2026-09-03, no re-review); D1–D7 recorded in the decision log.
- [x] 8: the flesh-out form scans a barcode into empty fields through the sheet's own apply function; never confirms; widget test + the typed path on the sim.
- [x] 1: edit → Save → one back returns to the opener; new → Save → recipe page; widget test; navigation.md §3 updated.
- [x] 2: `qt` + `pt` (D2a) in every mirror in the table; migration `0024` additive with UNION backfill; pgTAP vectors; `unit_hints` test; docs table.
- [x] 3: no app path mints a stub as a side effect — picker, top-up and import review all run sheet → form → back; `CommitStub` retired; verified on the real sim.
- [x] 4: one shared header form under both hosts; the review commits title / yield×2 / shelf life / book; a structural test pins the section list to both hosts.
- [x] 5: the review's chip sheet prints the measure label; `preview_recipe_test` pins it.
- [x] 6: `optional` survives import → save → edit → page, toggles in the unit sheet, is excluded-and-named in macros and shopping (D6b) through one `effectiveLines` seam.
- [x] 7: the one shared viewed week (D7a), the switcher as the only title on all three tabs (D7c), the pill and banner retired, the bar's selected state stepped up (D7d) with the measured contrast recorded.
- [ ] Migrations renumbered at landing if a parallel lane mints the same number (the 0024 trap).
- [ ] `make ci` green; `make test-sim` 6/6 (scenarios 3, 4, 6 touched); cloud push + ledger entry; tag `v0.4.0` (minor — new unit, new line fact, new review fields).
- [ ] Docs: navigation.md, unit-and-measure-matching.md, product-spec (Week v2 D3, import review, optional), QUALITY grades for the areas touched.

## Approach

1. **Design lane** (scratchpad only): frames for 3 (picker footer + prefilled sheet), 4 (KEEPS section), 6 (toggle in the sheet; page tag; shopping tag; macro "not counted" line), 7 (Cook/Shop headers with the switcher) → merged onto the board → one message with D1–D7 → sign-off.
2. **Build lanes** (worktrees, `git merge --ff-only main` first, one conventional commit per slice, `make ci` green, no merge):
   - **nav** — item 1 (small; can go first and alone).
   - **units** — item 2 (Dart + TS + SQL + seed regen + docs).
   - **header** — item 4: the shared header form + both hosts; item 5 rides with it (same preview/commit seam).
   - **line-fact** — item 6 end to end (migration `0025`, schema, `LineItem`, repo, import carry-through, the unit-sheet toggle, page tag, `effectiveLines` in macros + shopping).
   - **no-stubs** — item 3 across the picker, the top-up and the review's create-new; retires `CommitStub`; plus item 8 (scan-to-populate on the form).
   - **weeks** — item 7.
   Seams the structural tests will catch at landing: the guarded-navigation exception list (1, 3), the write-guard (3, 6), the tab-root scaffold test (7), the smoke anchors (7).
3. Orchestrator rebases and fast-forwards main per lane, re-running gates; `make test-sim` from the main checkout; cloud push; tag.

## Decision log

- 2026-09-03 — Scoped from the owner's seven-point list on `v0.3.0`; root
  causes traced to code for all seven (this file). Nothing built. Awaiting
  D2a/D2b, D3, D4, D6a/D6b, D7a/D7b/D7c.
- 2026-09-03 — Owner rulings: **D2a** pint and quart; **D2b** as recommended
  (qt rides with l, pt with cup); **D3** yes — and further: "move away from
  allowing stubs; ideally only our seeded can be stubs" (scoped above as "no
  app path mints a stub"); **D4** "same as recipe editor" — read as reuse the
  editor's header, not copy one more section (the diff above showed the review
  also lacks an editable title, the second yield denomination and File under);
  **D6a** the unit sheet; **D6b** exclude for now, and design for per-week
  recipe overrides (optional-in, substitute) without building them;
  **D7a** shared position ("changing week on shopping also changes week on
  cook"); **D7c** pending — options restated with what "the name leaves the
  header" means.
- 2026-09-03 — Owner: cook and total time "*should* be included on both
  while we're at it" (they are on neither — the entity does not carry them;
  scoped into the shared header as TIMES); stubs plan "perfect" (the top-up
  gets the flow); **D7c** (A) switcher only; and the bar's selected tab
  needs more contrast against the unselected ones → **D7d**. Every decision
  is now ruled; next is the design lane for the board frames (3, 4, 6, 7 +
  the bar), then sign-off, then build lanes.
- 2026-09-03 — Landed on main: **#1** `73f0d1e` (edit pops, create replaces;
  the editor test harness now hosts the editor over a blank opener), **#5**
  `45c04a8` (preview takes `measureByLine` from the validation map — the
  card's own value, so the two cannot disagree; commit's case-insensitive
  label match vs the card's exact match left as is, every writer rides the
  raw label), **#2** `4e32081` (18 files; migration `0024_quart_pint.sql`
  unions `qt` only where the stored list already names `l`, `pt` where it
  names `cup`, so a household that removed litres does not get a quart back;
  the density cross leg gains `pt` not `qt` because it never named `l`).
  Gates on `210d964`: format · analyze · 1506 app tests · 155 fn tests ·
  docs-check · pgTAP 296. Left for the tracker at close-out: the barcode
  module's OFF pack-size word table and `component_units.dart`'s yield chip
  list don't know pt/qt (both deliberately narrow lists). Board section
  merged and published (`147c506`), awaiting sign-off.
- 2026-09-03 — Owner: "go" on the frames without re-review, and item 8 added
  (scan a barcode from the flesh-out form; the editor and the flesh-out form
  are already one form). Four build lanes launched: header, line-fact,
  no-stubs (+8), weeks. Owner also rolled in the two pt/qt stragglers the
  units lane flagged (OFF pack-size words, the yield chip list) — done on
  main directly (`20ce01d`).
- 2026-09-03 — Landed, in order: **#7** `b8d3e4a` (switcher as the title of
  Cook/Shop, pill + banner deleted, selected tab herbDeep — 9.34:1 vs 6.50:1,
  gap 1.88:1 vs 1.31:1, pinned in `ansi_theme_test`; the menu's trailing
  count labels only the viewed week's row — the other rows would cost two
  derivations per tab, easy to widen later), **#4** `ea179de` (the six-section
  `recipe_header_form.dart` iterated from one list, `RecipeHeaderHost` under
  both the editor and the import controller, shared `recipe_header_edits.dart`
  so semantics cannot drift either, `recipe_insert_columns_test` pins that
  import's INSERT and the editor's save write the same columns; the editor
  was not dropping times, its UPDATE simply never named them and nothing
  could read them; the review's MAKES row now defaults to `g` like the editor
  instead of the old `piece`/"—"), **#6** `8625cde` (migration `0025`,
  `effectiveLines` with an accepted-and-unread `planEntryId` pinned by a
  test, "not counted · N optional lines: …", the Shop echo row, cook plan
  asserted unchanged; names print as the vocab stores them — "Lime", not the
  frame's lowercase), **#3 + #8** `80becaf` + `29a3345` (a page pushed from a
  root sheet lands ABOVE the sheet and pops back to it — tested — so the
  picker stays open, pushes the form with `pushOnceFor`, awaits, re-reads,
  resolves; `applyDraft` is pure Dart used by the sheet and the form: name
  fills only an empty field, macros only when no panel is present,
  provenance becomes `off:<barcode>` only over null/`manual`, the pack size
  is an offer never a write, status untouched; `CommitStub` / `CreateNewStub`
  / the coalescing leg retired, the created row resolves as an existing one
  with the raw text written back as its alias; legacy `import_stub` rows and
  the SQL `source in (…)` legs left as they are). Smoke steps changed by the
  lanes: Cook/Shop finders → root keys; scenario 4 creates the chilli row
  through the form and asserts zero `import_stub` rows; scenario 5's
  precondition is the stub row scenario 4 created.

## Notes / open questions

- Item 5 is worth landing with item 4 rather than alone: both are the review
  screen's preview/commit seam, and the measure map both need is already in
  `importValidationProvider`.
- Item 6's migration number collides with nothing today (`0023` is the last on
  main; `0024` is the quart migration) — but the debt pass (`0023-debt-pass.md`)
  is still active, so check before minting.
- Item 7 retires the Week's `ViewedWeekBanner`, not rewords it; the switcher
  in every header is the honest signal.

## Step-done checklist

- [ ] Roadmap row 8.10 flipped, with what shipped and what was deferred.
- [ ] `docs/QUALITY.md` grade for every area touched matches reality.
- [ ] `app/AGENTS.md` "Current focus" and command list still true.
- [ ] `make test-sim` run on a booted simulator; result recorded here.
- [ ] Tech-debt rows added and retired.
- [ ] Migrations `0024`/`0025` reach cloud; `docs/cloud-setup.md` ledger entry.
- [ ] `make ci` green.
