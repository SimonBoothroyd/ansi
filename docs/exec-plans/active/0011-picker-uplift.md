# Exec plan: Picker uplift — ingredient & recipe selection

- **Status:** draft
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

- [ ] **Design board frames first**: a "Pickers v2" section on
      `docs/product-specs/design-board.html` — (a) ingredient picker,
      (b) quantity + unit-chip entry, (c) planning recipe picker — in the
      board's visual language, reviewed/signed off before implementation
      starts. (Hard gate.)
- [ ] Ingredient picker v2 implemented per frames (bottom search, recents,
      honest data rows), replacing the current sheet in the recipe editor and
      shopping top-up; search uses the step-7.4 normalizer + word-boundary
      matching.
- [ ] Unit chip row implemented (keyboard accessory pattern) wherever a
      quantity + unit is edited; dropdowns retired.
- [ ] Recipe picker refreshed with the same shell/components.
- [ ] `make test-sim` scenarios updated for the new flows.
- [ ] Tests cover the new logic; Forui-only, glyph rule respected.
- [ ] Docs updated: design board committed, spec picker sections, QUALITY.

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

## Notes / open questions

- **Scope added 2026-08-28 (Simon):** the in-app **measure editor** moves into
  this step — an "+ add measure" affordance in the unit-chip row (and the
  ingredient sheet) writing `manual`-sourced `ingredient_measure` rows. The
  seeded "retail pack"/"typical" guesses are being dropped in favor of
  FDC-provenanced pipeline rows + the user's own values (see the measures
  provenance follow-up); the board frames should show the add-measure moment
  and how a measure's source (USDA vs yours) reads at a glance.

- See "Mise mapping" — two open questions to settle at the board review.
- Keyboard-accessory chips on Flutter/iOS: verify the pattern under the sim's
  keyboard handling early (spike in step 1, not a late surprise).

## Step-done checklist

- [ ] Roadmap row updated: status flipped, one line on what shipped and what was
      deliberately deferred.
- [ ] `docs/QUALITY.md` grade for every area touched matches reality.
- [ ] `app/AGENTS.md` "Current focus" and command list still true.
- [ ] Feature steps: `make test-sim` run on a booted simulator, result recorded
      here.
- [ ] Tech-debt rows added for corners knowingly cut, and retired for debt this
      step paid off.
- [ ] `make ci` green.
