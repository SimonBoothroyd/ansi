# Exec plan: Picker uplift — ingredient & recipe selection

- **Status:** done
- **Owner:** agent (staged 2026-08-27; design-first)
- **Roadmap step:** Step 7.7 — picker uplift
- **Created:** 2026-08-27

## Goal

The two selection surfaces — the **ingredient picker** (recipe editor,
shopping top-up) and the **recipe picker** (week planning) — reach the
interaction quality of the best food-logging apps (reference: MacroFactor's
food/recipe pane), designed on the design board **before** any code. One
selection anatomy, two contents.

## The reference anatomy (what makes MacroFactor's pane work)

Studied 2026-08-27 from real usage screenshots:

1. **Bottom-anchored search** — the field sits directly above the keyboard
   with an explicit Done, so thumb → type → pick is one gesture chain; results
   fill the sheet above it, recents ("Latest") shown before any query.
2. **Dense, information-honest result rows** — icon · name · one-line data
   summary (`260🔥 7P 0F 59C · 299 g`) · one-tap add. The row answers "is
   this the right thing?" without a detail hop.
3. **Ingredient-specific unit chips on the keyboard accessory** — editing a
   quantity shows a chip row above the numeric pad: `g / oz / portion / lb`
   for packaged food, `potato large / potato medium / potato small / lb` for
   produce. The selected chip is highlighted; switching units never leaves
   the row. This is the UI face of plan 0010's measures.
4. **One pane, multiple sources** — tabs (Scan / Search / AI / Quick Add /
   Library) share the same shell, and *foods and recipes come back through
   the same search*.

## Reframe (2026-08-28, Simon): the recipe picker is the redesign

The board's existing "Add ingredient · controlled-vocab search" frame already
carries most of the ingredient-picker anatomy (category + has-density hints,
the honest `stub` badge, live "≈ 610 g · via density" conversion, add-new
affordance). So:

- **Ingredient picker = refresh of the existing frame**: unit dropdown →
  the measure-fed chip row (+ "+ add measure", source-at-a-glance),
  bottom-anchored search, and a macro line on rows (vocab macros sync now).
- **Recipe picker = the real redesign** — its rows are information-starved
  (title · book·section · keeps chip and nothing else). New frame: servings,
  honest per-serving macro summary, keeps/freezable, last-planned recency,
  the "already this week" strip.
- **Step-9 pull-forward (decision)**: recipe rows need computed recipe
  macros. The *domain summation* (line items × units/measures × vocab
  macros; `incomplete` when any line is a stub — never zeros) moves into
  this step to feed the row; step 9 shrinks to the recipe-page macro panel.

## Mise mapping (decide on the board, not in code)

- Ingredient rows: macro line only for `status = complete` (honest numbers —
  a stub shows a `stub` badge, never zeros); measure/density hint where it
  changes what you can do ("has density", "3 measures").
- Recipe rows (planning): existing keeps/freezable/servings chips, plus
  last-planned recency; "already this week" chip row stays.
- Unit chips: from `allowedUnitsFor` + 0010 measures; imprecise units grouped
  at the end; chip row also replaces the unit dropdown in the recipe editor
  and shopping top-up (the dropdown's scroll-to-find-g was the single
  clumsiest interaction in the step-7 walkthrough).
- Sources: Search + Library now; Scan/AI slots reserved for step 8 import —
  the shell should anticipate the tabs, not build them.
- Open question (deliberate): planning search returning *foods as ad-hoc
  meals* (MacroFactor logs either interchangeably). v1 keeps planning =
  recipes; revisit with step 8.
- Open question: fold the favorites-tab tracker row in here or keep dropped.

## Acceptance criteria

- [x] **Design board frames first**: a "Pickers v2" section on
      `docs/product-specs/design-board.html` — (a) ingredient picker,
      (b) quantity + unit-chip entry, (c) planning recipe picker — in the
      board's visual language, reviewed/signed off before implementation
      starts. (Hard gate — passed 2026-08-28; frames revised through review,
      see the decision log.)
- [x] Ingredient picker v2 implemented per frames (top search per the
      review decision, recents, honest data rows, add-new manual stub),
      replacing the current sheet in the recipe editor and shopping top-up;
      search uses the step-7.4 normalizer + word-boundary matching.
- [x] Unit chip row implemented wherever a quantity + unit is edited;
      dropdowns retired (editor line items, shopping add sheet,
      edit-top-up). Chips dock in-sheet directly above the keyboard — the
      documented accessory call, see the decision log.
- [x] Recipe picker refreshed with the same shell/components (Recent ·
      Books · Favorites, day-tagged chips, recency + honest macro rows,
      eating footer) + confirm & place v2 (Day · Slot dropdown, macro line,
      full batch prose).
- [x] `make test-sim` scenarios updated for the new flows (incl. a
      favorites assertion and a manage-measures add-measure assertion).
- [x] Tests cover the new logic; Forui-only, glyph rule respected. *(Honesty
      note: this box shipped ticked while the quantity sheet still rendered
      two raw `＋` (U+FF0B) glyphs — the exact tofu the rule bans, missed
      because the library-view glyph test doesn't cover this surface. Fixed
      in the 2026-08-29 post-ship review pass: both are `FLucideIcons.plus`
      now, and a quantity-sheet widget test pins `findsNothing` for `＋`.)*
- [x] Docs updated: design board committed, spec picker sections, QUALITY.

## Approach

1. Board frames (a)–(c) + review gate.
2. Shared picker shell widget (search anchor, recents, source tabs slot).
3. Ingredient picker v2 + unit chips (depends on 0010 for measures; can land
   against family/density rules first if 0010 is in flight).
4. Recipe picker refresh.
5. Sim scenarios + polish.

## Decision log

- 2026-08-27 — Staged, explicitly design-first at Simon's request; both
  pickers in scope, one anatomy.
- 2026-08-28 — **Frames drafted, awaiting Simon's review.** A "Pickers v2 ·
  step 7.7" section (marked *proposed — pending review*) is on the design
  board: (a) ingredient picker v2 (a refresh of the existing "Add
  ingredient" frame), (b) quantity + unit chips with the add-measure moment
  and source-at-a-glance, (c) recipe picker v2 + confirm & place v2
  (refreshes of the existing "Choose a recipe" / "Confirm & place" pair —
  they supersede those on sign-off; until then the originals stay as the
  shipped-state record; the refreshes keep the pair's implementation-owed
  ideas the app never picked up: the Favorites tab, day-tagged
  already-this-week chips, the eating footer, the combined slot dropdown,
  and the full batch prose the app truncates to a one-liner), (d)
  macros-basis toggle note for step 8's form. Nothing in acceptance is
  ticked — the review gate holds. **Proposals to settle at the review (for
  sign-off, not decided):**
  1. *Planning search scope* — propose planning search stays **recipes-only
     in v1**; foods-as-ad-hoc-meals is revisited with step 8.
  2. *Favorites tab* — the board's original frame already commits to it, so
     this is a real either/or: **keep Favorites per the board** (needs a
     `favorite` flag on recipe — small but real implementation cost), or
     **drop it in the refresh** if recency makes it redundant.
     Recommendation: keep — recency only resurfaces what was recently
     planned, while favorites are a curated shortlist; different jobs. The
     refreshed frame shows the tab.
  3. *N3, `measure_live_label_uq` vs offline writes* — propose **dropping
     the index** in the editor's migration and merging duplicate labels on
     read (the shopping-entry doctrine), rather than client-side collision
     handling.
  4. *N4, backfill zero-live gate vs user deletions* — propose a
     per-household **`backfilled_at` marker** so the template-measure
     backfill runs once and never resurrects deliberately deleted measures.
- 2026-08-28 — **Search position resolved (Simon): TOP-anchored.** Frames
  (a) and (c) keep the search field at the top of the sheet, as the shipped
  frames had it; the bottom-anchored field + stylized keyboard idea is
  dropped from the board. The quantity keypad accessory in (b1) is
  unaffected — that's quantity entry, not search.
- 2026-08-28 — **Sign-off (Simon): the frames are the spec; the four
  proposals are DECIDED as recommended.** (1) planning search stays
  **recipes-only** in v1 (foods-as-ad-hoc-meals revisited with step 8);
  (2) **Favorites KEPT** per the board — a new household-shared
  `recipe.favorite` flag, marked via a star toggle in the recipe page's
  header menu; (3) **`measure_live_label_uq` DROPPED** (0011) — duplicate
  labels merge deterministically on read, oldest row canonical (the
  shopping-entry doctrine: an offline dupe must never fail upload);
  (4) **`household.backfilled_at` run-once gate** — the measure backfill
  runs exactly once per household and never resurrects user-deleted
  measures (fresh households stamp at creation; the migration stamps
  measure-having households; operators clear the marker for a template
  reseed rollout).
- 2026-08-28 — **Frame-(b) review outcome (Simon — the draft failed review:
  "I don't understand").** The single stacked drawing overloaded three
  layers; built (and redrawn on the board as b1/b2) as TWO states: the
  everyday **quantity surface** shows only the ingredient card (name +
  macro line — **no density on the card**; density appears only in the live
  conversion line where it's doing work), the quantity input, the chip row
  (precise units · measure chips · imprecise after a divider · a `＋`
  chip), the conversion line, and Done; the `＋` chip opens **manage
  measures** — the list (label · grams · humanized source: "USDA portion" /
  "borrowed" / "typical" / "yours", never raw `usda_fdc:…` strings; the
  four-dot colour code stays as a subtle secondary channel) plus the
  add-measure form (label + grams → `manual`). Measures never duplicate
  volume units: chip row / manage list exclude, and the add form rejects,
  labels that merely name a volume unit — density owns volume conversion.
- 2026-08-28 — **Keyboard-accessory call (the flagged spike):** a true iOS
  `inputAccessoryView` fights Flutter's insets model, so the sheet
  bottom-pads itself by the viewInsets and the chip row rides the keyboard
  **in-sheet** with no accessory plumbing. *(Wording trued up 2026-08-29:
  the stack above the keyboard is chips → Done → keyboard — Done sits
  between the chips and the keypad, so this is the frame's spirit, not its
  literal chips-touch-keypad adjacency. Keeping Done at the bottom was the
  deliberate call — a confirm above the selection row would read worse.)*
  Verified on the sim via `make test-sim`; documented in
  `quantity_unit_sheet.dart`'s library doc.
- 2026-08-28 — **Built and verified.** Backend: migration 0011 (favorite,
  backfilled_at, index drop, macros_basis + clone legs), seed switched to a
  `WHERE NOT EXISTS` guard (idempotency re-proven, 183 rows stable), 67
  pgTAP green. App: measure merge-on-read + `addMeasure`/`softDeleteMeasure`;
  pure-Dart `summarizeRecipeMacros` (step-9 pull-forward — **step 9 shrinks
  to the recipe-page macro panel**); shared `PickerShell`; ingredient picker
  v2 (recents from usage, honest rows, add-new manual stub); the quantity +
  unit-chip sheet replacing every unit dropdown; recipe picker v2 + confirm
  & place v2. 311 host tests, analyze/custom_lint clean, `make test-sim`
  green on the booted sim, `supabase test db` green on the dirty result.

- 2026-08-29 — **Post-ship review fixes (Opus review of 7.7).** Blockers:
  an EMPTY line set summed to a "complete" zero total, so line-less recipes
  fabricated "~0 kcal /serving" picker rows — now honestly `incomplete`
  with a distinct `noLines` reason ("no ingredients yet"), the defending
  test flipped and a repo-level twin added. The chip row had dropped the
  retired dropdowns' "stored selection is always offered" rule — restored
  centrally in `allowedUnitChoicesFor` (off-filter admission, flagged
  "not in filter"). Deleting the selected measure left it selected and Done
  wrote a tombstoned `measure_id` — deletion now reconciles the choice to
  the default unit with a visible note (call: reset-with-note over
  keep-with-flag; the admission path covers merely-hidden duplicates). Two
  raw `＋` (U+FF0B) glyphs violated the glyph rule (see the acceptance-box
  honesty note). Minors: repo-level `addMeasure` validation, plural-robust
  volume-label guard, `incompleteNote` fallback reasons, mounted guard in
  the manage save, tombstone-aware recents, offered-only measure counts,
  Recent-tab order aligned with the recency rows display, future
  last-planned dates ("in 3w"), normalized picker search, density citation
  formatting, parsed-instant merge tie-break, `macros_basis` pgTAP.

## Notes / open questions

- **Scope added 2026-08-28 (Simon):** the in-app **measure editor** moves into
  this step — an "+ add measure" affordance in the unit-chip row (and the
  ingredient sheet) writing `manual`-sourced `ingredient_measure` rows. The
  seeded "retail pack"/"typical" guesses are being dropped in favor of
  FDC-provenanced pipeline rows + the user's own values (see the measures
  provenance follow-up); the board frames should show the add-measure moment
  and how a measure's source (USDA vs yours) reads at a glance.

- **Measure-editor prerequisites — settle BOTH at kickoff (2026-08-28,
  review follow-up):**
  1. *The `measure_live_label_uq` unique index vs offline writes.* Migration
     0010's live `(ingredient_id, label)` index is exactly the
     offline-dupe-fails-upload pattern this repo deliberately rejected for
     shopping entries: two offline devices adding the same label produce a
     23505 on upload, and the connector drops the whole crud transaction.
     Inert today (only seed/clone/backfill write measures — all server-side),
     but it must be resolved before the editor ships: either drop the index
     in a migration and merge duplicate labels on read (the shopping-entry
     doctrine), or make the editor collision-safe client-side. Tracker row
     `measures/sync` holds it.
  2. *The backfill's zero-live gate vs user deletions.* `ensure_onboarded`
     re-clones template measures into a household with zero LIVE measures —
     correct for healing and template rollouts today, but once the editor
     lets users delete measures, a household that deliberately deleted its
     last one gets it resurrected at next sign-in. Candidate: a per-household
     `backfilled_at` marker (or checking tombstones too once deletion
     exists). Tracker row `measures/backfill` holds it.

- **Per-100 ml macro entry (2026-08-28, Simon):** the New-ingredient /
  flesh-out form asks for macros per 100 g, but liquid labels read per
  100 ml — and densities are sparse, so conversion-at-entry can't be the
  design. Instead: a free 100 g / 100 ml basis toggle, and the macros are
  **stored with their basis** (data model: a basis tag beside `macros`;
  USDA prefill rows are per-100 g). Consumers apply the shopping-aggregation
  doctrine: a line whose unit family matches the basis computes directly
  (liquids in ml × per-100 ml — the common case, no density needed);
  cross-basis uses a density when present; otherwise that line renders the
  recipe's macros honestly `incomplete`. Design the toggle here; the basis
  tag + computation land with the macro summation (pulled into this step)
  and the full form with step 8.
- See "Mise mapping" — two open questions to settle at the board review.
- Keyboard-accessory chips on Flutter/iOS: verify the pattern under the sim's
  keyboard handling early (spike in step 1, not a late surprise).

## Step-done checklist

- [x] Roadmap row updated: status flipped, one line on what shipped and what was
      deliberately deferred (step 9 shrinkage noted on its own row too).
- [x] `docs/QUALITY.md` grade for every area touched matches reality
      (vocab/measures, recipes, planning rows refreshed).
- [x] `app/AGENTS.md` "Current focus" and command list still true (points at
      the roadmap; commands unchanged).
- [x] Feature steps: `make test-sim` run on the booted iPhone 17 sim —
      **all 3 scenarios green** through the new picker/chip flows (incl. the
      favorites and add-measure assertions), 2026-08-28. The dirty result
      then ran `supabase test db`: 67 pgTAP green (the onboarding suite now
      soft-deletes stray households at start — freed seats made "fresh
      clone" users join test-sim residue instead). The frame-b flow was also
      driven live (`flutter run` + sim): picker rows, chip row over the
      keypad, manage measures, add "half can = 200 g" → chip returns
      selected with the honest conversion line.
- [x] Tech-debt rows added for corners knowingly cut (stub match_text
      character-normalizer, usage-derived recents, favorite-not-on-aggregate),
      and retired for debt this step paid off (measure editor, measures/sync
      index, measures/backfill gate, favorites tab).
- [x] `make ci` green.
