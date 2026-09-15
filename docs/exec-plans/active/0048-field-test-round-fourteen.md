# Exec plan: field test, round fourteen — the desk in use: the Week redrawn, the type scale, and seven web notes

- **Status:** in progress
- **Owner:** Simon (design), agents in lanes
- **Roadmap step:** — (the first days on `v0.17.0` in a browser)
- **Created:** 2026-09-14

## Goal

Nine owner notes from the first use of the wide build on a desk, one of them a
design miss and the rest bugs or gaps with one cause each.

> *"Week is probably actually a miss in terms of design... left and right
> duplicate too much information, and text on left looks big and angry...
> maybe the two panes should swap sides, and the days of week pane should
> be a more compact repr so it's not 100% repeating right pane info while
> also being useful to scan?"*

> *"On ingredients when selecting, on the right pane I very briefly see
> 'Ingredients' and a back button as a header before the ingredient panel
> fills in properly."* · *"The ingredient panel isn't URL ↔ UI connected."*
> · *"When I click an ingredient on a recipe it should take to the ingredient
> AND highlight it."*

> *"I think we've started to use inconsistent font sizes, esp. for recipe
> titles."* · *"On recipes the servings chooser is comically big."* · *"The
> search font seems off? and the icon too far left? same on phone."*

> *"When viewing the recipe, it would be nice if you tap a chip (and maybe
> the whole step) to toggle a line through it, to easily track what you've
> added during cooking. I don't think we need a full cook mode."*

> *"On shopping the sync bar comes and goes, causing the page to shift
> annoyingly."*

The tenth — the import review's "the page's own text did not come back" — is
not a bug: `import-recipe` gained `source_text` additively in 0047 and the
deploy-supabase run is still owed. It is on the ship checklist, not a lane.

## Acceptance criteria

Lane `week` — `features/planning`, the board:

- [x] The wide Week's panes swap. **Left, the agenda at 340**: per day a
      heading (day name, date, `TODAY`, the meals count at the right edge);
      every meal as ONE wrapping dot-run in the mono at 10.5, muted, names
      whole and never truncated, an eater initial only where the meal is not
      for everyone, a snack in the muted colour; then the day's macros as the
      phone's own strip (`MacroStrip`, `3 383 🔥 · 182P 361C 152F · 69 🌾`).
      An empty day says `nothing planned`; a day with an unstated meal draws
      no strip and says why in the existing refusal words. The open day keeps
      the herb rule; a tap anywhere on a day opens it.
- [x] **Right, the day pane** takes the rest: day name at 24, a dish at 17,
      each meal's macros as the muted strip, the pinned ledger keeping its
      spelt-out grams. Every control stays — eaters, `−`, the cook marker,
      `edited for this week`, and the ONE `＋ add a meal`, which lives here
      and nowhere in the agenda (owner call).
- [x] The week band (total, average, `n of 7 days`) pins to the agenda's foot
      in the strip grammar, closing 0047's open question.
- [x] `week.html`'s wide frames are redrawn to the built screen; the status
      line's `wide:` clause re-verifies. `week_wide_test.dart` extended: the
      run names every meal, the strip is `MacroStrip`, the agenda has no add
      door, the band is drawn.

Lane `scale` — `core/theme`, every serif title (queued behind `week`):

- [ ] `ansi_theme.dart` gains a named type scale for the serif (display,
      title, heading, row, small — whatever the sweep shows the app actually
      uses), and every serif title in `app/lib` reads one of them. A
      structural test bans a raw `ansiSerif(size:` literal outside the theme.
- [ ] A recipe's name is set at one size per role across the Library ledger,
      the phone Library, the Week (both bodies), the picker, the cook sheet
      and the book page — the table in the decision log says which.

Lane `ingredients` — `features/ingredients`:

- [ ] The wide manager's detail pane never draws a titled header or a back
      chevron while loading: the pre-data branch honours `embedded` like the
      loaded branch does. A `pump()`-only test after a tap asserts it.
- [ ] A tap on a ledger row restates `/ingredients/:id` (the Week's
      `restateOnce` shape), so the URL is the selection and a refresh or the
      browser's Back keeps it; the stub band restates `?edit=1` the same way.
      The list keeps its scroll across the restate.
- [ ] Arriving on `/ingredients/:id` — from a recipe's ingredient door or a
      pasted link — scrolls the lit row into view.

Lane `smallfix` — `features/recipes`, `shared`, `features/shopping`:

- [ ] The servings scaler is capped at the wide hero's width in every band
      and uses the small stepper; it never stretches to the measure.
- [ ] `AnsiSearchField` is styled once: hint and content in the app's sans
      at the row size, the magnifier with a start inset that matches the
      text's, on every body.
- [ ] The Shop's sync line reserves its height, so a tick never shifts the
      list; the waiting state shows only when a queue outlives a short
      delay, so a fast upload draws nothing. Existing readout tests hold.

Lane `strike` — `shared/method_step_text.dart`, `features/recipes`:

- [ ] On the recipe page a tap on a method chip strikes it (muted +
      line-through, the Shop's own "got it" style); a tap on a step strikes
      its prose and every chip in it; chips toggle independently otherwise.
      Timer chips are not tappable. The set is ephemeral view state beside
      the servings scaler, and dies with the page.
- [ ] The renderer's toggle is a null-default callback, so the import review
      and the editor's preview stay inert and pixel-identical.
- [ ] A week-struck line's chip in the method reads muted only, so it cannot
      be confused with a cook-struck one (closes 0047's stated gap).

Gate: `make analyze` · `make test` · `make docs-check` per lane; one full
`make test-sim` on the integrated branch before the tag.

## Decision log

- 2026-09-14 — **The wide Week swaps sides and the agenda goes small.** The
  owner read the built pane on his own household: the day pane's 38 pt day
  and 24 pt dishes were *"big and angry"* and the two panes said every title
  twice. Four mocks. *Grams only* on the left was refused — *"I do want some
  view of the recipes"*; *one name + n more* lost to *every name, small* — and
  the run **wraps** rather than listing one per line (owner call). Macros in
  the agenda are the phone's strip, not spelt out, because the strip is the
  one grammar every day foot and recipe row already speak; the pane's
  per-meal lines join it, and only the pinned ledger keeps the words. The
  batch story stays out of the agenda, as 0047 ruled.
- 2026-09-14 — **One add door.** *"Yes add only in day pane."* The agenda has
  nowhere honest for seven.
- 2026-09-14 — **The band's wide home is the agenda's foot.** The week's own
  ledger under the week's own days.
- 2026-09-14 — **Two small departures from the `week` mock, both toward the
  app's existing words.** A refused day draws the shared `incomplete` badge
  before `no total — …` in the agenda, as every other refusal on the screen
  does, rather than the mock's bare grey line; and under a person's lens the
  band's sub-line names the scope (`avg 1 752 · 5 of 7 days · Ada`), because a
  rescoped total that does not say whose it is is the one number on the screen
  that could be read as the household's.
- 2026-09-14 — **Strike is the chip's tap.** Method chips were inert on the
  recipe page, so the tap was free; navigation for a sub-recipe chip, when
  it exists, is a different token type. A chip strikes only itself; a step
  strikes all of its own.

## Notes / open questions

- The theme is unconditionally `touch: true`, which is why Forui's controls
  are 44 px tall on a desk. Left alone this round: flipping it re-lays every
  phone control and wants its own pass.
- The agenda's five-meal day wraps to three lines at 340. Accepted knowingly
  over truncation.
