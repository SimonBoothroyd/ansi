# Exec plan: the recipe page, up-levelled — and optional as a switch that tracks through

- **Status:** active
- **Owner:** agent (three lanes: `page`, `optional`, `page-week`)
- **Roadmap step:** — (owner's design pass on `v0.13.2`)
- **Created:** 2026-09-12

## Goal

Two things the owner asked for on one screen, from three screenshots of a
live recipe.

**The page reads better.** The design already holds — serif title, sans
lines, mono figures — so this is a pass on the details that fight it: the
Method tab's boxed chips break the sentence they sit in; the hero stacks four
filled shapes before the content starts; amounts wrap in the 84 px column;
a line's macros print in a different order from the panel two inches below
them; and an optional line says "optional" twice.

**Optional is a decision the cook can reach.** Today the recipe's `optional`
flag is honoured everywhere by rule (the seam drops the line from the macro
panel and the shop, and names it), and the only way to say *"yes, this
time"* is week mode in the editor — three screens deep. Owner's words:
*"going into the editor to toggle an optional ingredient seems too deep."*
And an optional **sub-recipe** is dropped from the shop and the macros but
still cooked: the cook plan reads the component graph with no week and no
flag, so it always spawns the session. Owner: *"they should only show in
cook if included."*

## Acceptance criteria

Lane `page` — `features/recipes/presentation`, `shared/method_step_text.dart`,
`core/units/number_format.dart`, `ingredients/presentation/macros_format.dart`:

- [x] A method chip is the ingredient's word in bold `herbDeep` with its live
      amount in a small `herbSoft` mono pill after it (design canvas, *Method
      · B*). No box around the word; the pill is the marked thing because the
      number is what is live. Punctuation after a chip hugs it (no 1 px
      side padding on the span). A chip whose amount is imprecise prints no
      amount when the prose right after it already says the same words
      (`salt` *to taste*, not `salt to taste` *to taste*).
- [x] Step numbers are `herb` mono digits, no ink disc.
- [x] The Method tab's bar carries `for 4 servings · 1×` at its right end,
      read off the same servings state the scaler holds, so the chips'
      numbers say what they are scaled to.
- [x] The planned band is one mono line with a calendar glyph and no fill:
      `Planned Wed this week`, gaining `· edited for this week` exactly as
      today. The chip row is the only filled shape above the tabs.
- [x] `formatAmount` prints vulgar fraction glyphs (`½`, `1½`, `⅔`, `⅛`) —
      the old comment's reason (fonts without them) is false for every
      bundled face, and a structural test reads each bundled font's `cmap`
      for the nine glyphs so the ruling cannot silently rot. `parseAmount`
      already reads them. Spacing: `1½`, no space before the glyph.
- [x] The middle dot between a name and its note is gone; the note is the
      italic muted run it already is, after two spaces.
- [x] The `optional` tag is the sub-recipe chip's shape: 6 px radius,
      `herbSoft` fill, same height — not an `FBadge` pill.
- [x] A line's own macros print in the panel's order — `kcal · P C F ·
      fibre` — one size smaller (10 pt) and lighter, and a row that wears the
      tag prints nothing in the macro slot rather than `optional` a second
      time. `formatMacroLine`, the glyph line and every test that pins the
      old `P F C` order move together.
- [x] Gram figures print whole at 1 g and above, one decimal below it
      (`25 g`, `0.4P`), in the one rule `formatGrams` already is — the
      panel, the line, the picker rows and the week strip all read it, and
      the form's field text with them. Energy is unchanged (whole).
- [x] Under the panel, `not counted` is two labelled rows, `NOT COUNTED ·
      names` and `OPTIONAL · names`, with one caption; the fibre line keeps
      its own row.
- [x] `docs/product-specs/board/recipe-page.html` redrawn to these frames,
      status date bumped; `features/recipes/README.md` says the chip and the
      tag shape.

Lane `optional` — `features/cook_plan`, `features/shopping`,
`features/planning/domain|data`, `features/import/domain`:

- [ ] The cook plan honours the seam: a **component line the recipe marks
      optional spawns a component session only when the week includes it**;
      a component line the week excludes spawns none. `buildCookPlan` takes a
      per-week component graph — the graph is filtered per recipe through
      `effectiveLines(lines, overrides:)` before demands are derived, so the
      cook plan, the shop and the week's macros keep reading one rule.
      Regression test: an optional sub-recipe with no include row → no
      session; with one → the session; an excluded one → none.
- [ ] `WeekVariantRepository.setLineIncluded(weekStart, recipeId, lineId,
      included:)` — adds or removes one `include` row inside the stored set
      (load, edit, `saveOverrides`), so a one-tap door needs no diff and no
      draft. Tested on the real database.
- [ ] The shop's echo row is a door: each name in `2 optional lines not
      listed — lime, coriander` is tappable and writes the include row for
      that week and recipe through `ref.write`. `OptionalLinesNote` carries
      the line ids beside the names. The item then appears with the
      `· this week, ticked in` provenance segment that already exists.
- [ ] An optional **component** line is a legitimate stored fact:
      `buildCommit` stops forcing `optional: false` on a linked line and the
      comment that called it a week-level question goes. (The editor and the
      review already allow it; the owner's live data has one.)
- [ ] `docs/product-specs/board/cook-shop.html` gains the echo-row-as-door
      frame; `product-spec.md` §recipes and §cook plan say the rule.

Lane `page-week` — `recipe_view.dart`, `ingredient_line.dart`, the view
models; runs after the other two land:

- [ ] Opened **from a week that plans it**, the page shows the week's
      effective lines: an included optional line unstruck with its tag lit,
      an excluded line struck and muted, a replaced amount as the week
      states it, an added line at the end of its group — the same grammar
      week mode draws, read-only. From the Library the page is untouched.
- [ ] On that page **the tag is the switch**: `optional` with a ring, one
      tap → `included` (filled `herb`, check glyph) and back, writing
      `setLineIncluded` through `ref.write`. The band gains `· edited for
      this week` on the first include, through the existing placement watch.
- [ ] The panel on that page reads the **week's** summary (the same
      re-summation `watchVariantRecipeMacros` runs), so ticking a line in
      recounts it; `not counted` names what is still out and an `INCLUDED ·
      names · for this week` row names what came in.
- [ ] From the Library the tag stays a tag and writes nothing. No reading
      posture, no session state: where there is no week there is no
      decision.
- [ ] Widget tests on the arrival test's fixtures; `recipe-page.html` frame
      *Optional is a switch*; `docs/design-docs/navigation.md` unchanged
      (no new route).

## Approach

1. **`page` and `optional` run in parallel worktrees** off this commit; they
   share no file. `page-week` starts from both landed.
2. The design canvas the owner reviewed is the source for the frames:
   Method B, the hero, the ingredients tab, line macros on, and the switch.
3. Nothing here needs a migration: every write is an `include` row on
   `week_recipe_line_override` (0040).

## Decision log

- 2026-09-12 — **Optional has two owners.** The recipe says *may be skipped*
  (the author's claim, from import or the editor; unchanged). The week says
  *this time, yes* (the cook's claim; the include row). If a household
  always wants the lime, the fix is to untick optional in the editor — for
  them it is not optional. No third "usually yes" state. Owner: *"this sounds
  good to me."*
- 2026-09-12 — **The doors are where the question comes up**: the recipe
  page opened from a week, and the shop's echo row. The meal sheet's door
  stays as the third for several changes at once. The editor's own tag stays
  display-only (plan 0043).
- 2026-09-12 — **From the Library, the tag is not a switch.** The canvas
  drew it as a reading posture that writes nothing (the scaler's precedent);
  rejected in the same conversation: a control that persists from one door
  and evaporates from another is a smell, and from the Library there is no
  decision to make.
- 2026-09-12 — **An included optional line shows in Cook and Shop; an
  optional sub-recipe shows in Cook only when included.** Owner's words.
  The cook plan becomes week-aware for exactly this: the component graph is
  filtered through the seam per (week, recipe). The product spec's line
  *"the component graph is read household-wide with no week"* is retired;
  sub-recipe **swaps** stay suppressed (0043) — this filters lines, it does
  not re-target them.
- 2026-09-12 — **Method chips: B.** The word plain-bold, the amount in the
  pill. Owner: *"lean method b."*
- 2026-09-12 — **Fraction glyphs.** The `number_format.dart` ruling against
  them rested on "the bundled fonts do not carry every one of them"; a
  `cmap` read of Plex Mono (Regular, Medium) and Spectral shows all nine.
  Reversed, with a structural test holding the new fact.
- 2026-09-12 — **Grams print whole at ≥ 1 g, one decimal below.** Agent's
  call, subject to the owner's veto: the canvas showed whole grams and was
  approved; the sub-gram decimal keeps `formatGrams`'s own reason (0.42 g of
  protein must not print as `0`).
- 2026-09-12 — **An optional component line is stored as such.** The commit
  payload's `optional: false` on linked lines contradicted the review, the
  editor and the owner's data. One ruling: the flag rides a component line
  as it rides an ingredient one (the seam already names the sub-recipe's
  title where it left).

## Notes / open questions

- Copy last week still drops the variant (0043), so an include choice is
  remade weekly. That is the model, not a gap: the choice is per cook.
- The recipe page from a week now reads three streams (recipe, placement,
  overrides + week summary). If it grows a fourth, fold them into one view
  model.

## Step-done checklist

- [ ] Roadmap row added.
- [ ] `ARCHITECTURE.md` standing table: recipes (the page holds the week),
      cook plan (week-aware component graph), shopping (the echo row is a
      door).
- [ ] `app/AGENTS.md` still true (the fraction rule's wording).
- [ ] `make test-sim`: the recipe editor, week variant and nested files at
      least, once, before landing `page-week`.
- [ ] Tech-debt rows: none added unless a corner is actually cut.
- [ ] `make ci` green.
