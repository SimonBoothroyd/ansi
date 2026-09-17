# Feature: recipes

**Roadmap:** Step 2 — single-user recipes (see `docs/exec-plans/roadmap.md`).

Create a recipe, group ingredients ("for the sauce"), scale it, and render the beautiful recipe page + method + cook mode.

## Layout

```
recipes/
  domain/         Recipe/IngredientGroup/LineItem (Freezed), RecipeRepository,
                  scaling.dart — PURE DART (no package:flutter)
  data/           SqliteRecipeRepository over the local PowerSync SQLite,
                  Riverpod providers
  presentation/   Forui Views (list · recipe page · editor) + Riverpod
                  ViewModels (recipe_view_models.dart)
```

Built in step 2 (see `docs/exec-plans/completed/0002-single-user-recipes.md`).
Notes:
- **Synced persistence (since step 7).** The app `.connect()`s PowerSync once
  signed in (`core/sync/session.dart`); recipes persist on-device and sync to the
  household, with writes queuing harmlessly while offline.
- **Scaling is a view concern** — `scaling.dart` scales displayed quantities for
  a target serving; the stored recipe is untouched. Imprecise units never scale.
- **Save replaces children** (groups/line-items) wholesale rather than diffing.
- The ingredient picker lives in `features/ingredients` (read-only vocab search).

The editor's **shelf-life inputs** (keeps / freezable / freezer days) landed in
step 5 — they feed the cook plan's clustering; the recipe page renders the
`keeps`/`freezable` chips from those values.

The editor's **ingredient list is one flat draggable list.** Group headings are
rows in it, and the lines after a heading belong to it — so dropping a line
under another heading files it there, and reordering a line and moving it
between groups are the same gesture rather than two features. The rule is
`domain/line_reorder.dart`, written over `List<List<T>>` so the import review's
sections (which hold flat line indexes, not `LineItem`s) drag by the same
arithmetic; the drag itself is `SliverReorderableList` +
`ReorderableDragStartListener` from `package:flutter/widgets.dart` — the
*styled* `ReorderableListView` is the Material one and is not what this uses.

- **The grip is the only thing that drags** (`DragGrip`). Long-press
  anywhere would turn a scroll into an accidental move on a list whose whole
  job is tapping. On the review, where a card expands, the grip is on collapsed
  rows only and an open card closes when a drag starts elsewhere.
- **A moved line keeps its id**, because the move carries the object across
  rather than rebuilding it — so every method chip pointing at it still does,
  and `saveRecipe`'s child diff issues an UPDATE rather than a delete + insert.
  That is the whole reason the gesture is worth having: delete + re-add already
  reordered a list, and cost every reference.
- **A group emptied by a move is kept.** The heading is the human's, and a
  group that empties while you rearrange is not a bug to fix behind them.
- Persistence is the existing save: `sort_order` from list position, `group_id`
  from the heading above. No migration, no second write path.

The **ingredient line is one layout on every surface** — `[amount] [name]
[note]` on a single row, the amount in its own `kLineAmountWidth` column so
every identity left-aligns. The recipe page is the reference (it is the screen
a cook reads); the editor and the review's collapsed row print the same shape.

The **editor's line is the review's card** (`presentation/line_card.dart`),
which is the chrome and the slots both screens fill: the surface, the head
(identity + bin + the chevron that closes it), the labelled `AMOUNT`, `UNIT`
and `NOTES` rows, the `optional` toggle, and the collapsed ⇄ open machinery —
local expansion state, the `collapseEpoch` that closes every open card when a
drag starts, and the grip rule. What each screen brings is its own: the review
keeps the match cascade, `from source:`, the never-invent flags, the Save gate
and the dropped state; the editor brings *used in N steps*, the component
variant and remove-with-chips.

One row, one gesture, and the doors are inside:

- **Anywhere on the collapsed row opens the card.** A row that meant the
  quantity sheet on its left 84 px and the identity picker on the rest was a
  row a cook had to aim at — and the fact that sent them looking, the note, was
  behind neither. Changing an amount is two taps now, and that is the price.
- **The head is the identity door** — the name with `change ›`, opening the
  line target picker on the line, which keeps its id and so keeps every method
  chip pointing at it.
- **The bin is in the head, the grip on the row.** A delete beside a whole-row
  tap target is a misfire waiting to happen, and removing a referenced line
  stops to ask anyway.
- ***used in N steps* is on the card**, under the head: nobody needs it while
  scanning a list, it is exactly what a reader wants standing over the two
  controls that can break a chip, and without it every collapsed row is one
  height — which is what makes the drag surface honest.
- **Rows are bare at rest.** The review borders every line because every line
  there is a claim waiting to be checked; here the border is what *open* looks
  like (`LineCard.borderAtRest`).

Three details of that line are rules rather than styling:

- **A note is a modifier, not a second fact**, and it is printed by one
  function (`noteSpans`): the name, a middle dot in the hairline, then the note
  in muted italic at the name's own size. Every surface that prints a note goes
  through it — the page, the editor's row, the review's row — and
  `test/structure/one_note_grammar_test.dart` is why a fourth cannot invent its
  own grammar.
- **The `optional` tag wears the sub-recipe chip's shape** (`OptionalTag`): a
  6 px box in the herb wash, muted mono, hung off the end of the identity. It
  is also the whole statement — a tagged row prints nothing in its macro slot,
  because *optional* twice on one line is once too many. Handed an
  `onToggle` it becomes a switch: an empty ring before the word, and ticked, a
  filled herb box with a check reading `included` — week mode's answer to *this
  time, yes*. The card's own control (`OptionalFlagToggle`) is the same
  geometry with the recipe's question in it: outline and an empty ring for
  *not optional*, the herb wash for *optional*. On a recipe line that toggle is
  the one door — the editor's amount sheet stopped carrying the switch, so a
  fact the row states has exactly one place that sets it.
- **A line's own macros** (the `⋯` toggle) print under the name in the panel's
  order, `kcal · P C F · fibre`, one size down. They are the line *as shown*,
  so they move with the scaler; the panel underneath does not.

The **method is prose with live numbers in it** (`shared/method_step_text.dart`).
An ingredient chip is the word set bold in `herbDeep` with its live amount in a
small herb-soft mono pill after it — no box around the word, because a boxed
noun mid-sentence breaks the reading, and nothing pads the chip sideways so the
comma after it hugs. A timer chip keeps its outlined paper pill: it is not a
word in the sentence. A chip whose amount is an imprecise unit prints no pill
when the prose right after it already says the same words — *Season with salt
to taste*, not *salt `to taste` to taste*. Step numbers are herb mono digits in
a column, not ink discs, and the Method tab's own bar carries `for 4
servings · 1×` at its right end, read off the same servings state the
Ingredients tab's scaler holds.

**Ticking off while cooking.** On the recipe page a method chip answers a tap:
it goes muted and ruled through — the Shop's own *got it* — so a cook can track
what has actually gone into the pan. A tap anywhere else on the step rules the
prose through **and** every chip in it, because a decoration on a text span does
not cross into the widget spans the chips are; chips still toggle one at a time
otherwise, and un-striking a step leaves each chip exactly as it was. Timer
chips are not tappable: a duration is not a thing you add. The set is
**ephemeral** — a `useState` beside the servings scaler, keyed positionally
(`s2`, `s2:c0`, the nth chip in the nth step), dying with the page. Nothing is
stored, nothing syncs, and both bands share the one set because the method is
built once and placed by the layout. Every knob on `MethodStepText` is
null-defaulted, so the import review and the editor's *Reads as* preview render
exactly what they always did. A line **this week leaves out** reads muted in the
method and is never ruled through — the rule belongs to the cook's hand, and the
two states must not read alike. Full **cook mode** stays deferred (owner: *"I
don't think we need a full cook mode"*); see `docs/exec-plans/backlog.md`.

The editor's **header is one widget with two hosts** (plan 0025 #4):
`presentation/recipe_header_form.dart` renders TITLE · SERVES · MAKES · TIMES ·
SHELF LIFE · FILE UNDER from `kRecipeHeaderSections` over a `RecipeHeaderHost`
— the editor notifier here, the import controller on the review screen — with
an optional per-section note slot for what a host knows and the form does
not. The rules every setter holds (both halves of a yield or neither, no
freezer window on a dish that does not freeze…) are `domain/
recipe_header_edits.dart`, shared by both hosts. `Recipe` carries the printed
`cookTimeSeconds` / `totalTimeSeconds`; the page prints them as `cook 35 min`
/ `1 h 10 min total` chips through `formatDuration`, the timer's own voice.

The **per-serving macro panel** (step 9) closes the recipe page's Ingredients
tab: four cells (kcal · protein · carb · fat) off `Recipe.macros`, derived from
the shared `summarizeRecipeMacros` summation — the same one the pickers use, so
page and row can never disagree. It renders the `incomplete` badge and its
reason (`shared/incomplete_macros.dart`) rather than a fabricated number, and it
is **per serving**, so the servings scaler never moves it. Under the cells, what
the total left out by rule is two labelled rows — `NOT COUNTED` for the lines
that carry no weight to count, `OPTIONAL` for the ones the rule drops — with
one caption under both; the fibre line keeps its own row.

**The page holds the week it was opened from.** A `?week=` link that the week
still plans (`weekRecipePlacement` is the guard) turns the Ingredients tab into
that week's effective lines, in week mode's own grammar and read-only: a
replaced line at the week's absolute amount, a line it leaves out struck and
muted with neither door, an added line after the last group — all of it still
scaling with the servings control. On that page the `optional` tag is **the
switch**: one tap writes the week's `include` row through
`WeekVariantRepository.setLineIncluded` (a folded multi-use row ticks in every
optional use, one tap being one intent), the band gains `· edited for this
week`, and the panel recounts, because it reads the week's own re-summation
(`watchVariantRecipeMacros`) rather than the Library's figure. A third row
under it, `INCLUDED · names · for this week`, names what came in. From the
Library none of this exists — optional has two owners, the recipe saying *may
be skipped* and the week saying *this time, yes*, and only a surface holding a
week can answer the second.

Each named reason under the badge is a **door to the fix it implies**, and one
of them points off the recipe entirely: **`needs a piece weight`** — a bare
count on a row that states no `piece_basis_amount`
([ADR-0015](../../../../docs/decisions/0015-piece-weight-is-a-row-fact.md)) —
opens that **ingredient's form**, not this recipe's editor. The missing number
is the row's, and typing it once fixes every bare count of that ingredient in
every recipe, the way a density fixes every `cup` line. Only a row created
before that ruling can be in the state at all: the form and the import both
refuse to make a new one. A `piece` line on a weighed row is an ordinary
convertible line and is not named here.

## The panel's second reading — cost

The strip that closes the Ingredients tab reads one of **two** things about the
same lines. A `Macros | Cost` chip pair sits where `PER SERVING` sat, with
`per serving` beside it; it is a **session posture**
(`CostReading`, keep-alive), held across recipes and written nowhere. The `⋯`
item is one item — **Show line figures / Hide line figures**
(`ShowLineFigures`) — and the lines print whichever the panel above them is
reading.

`recipe_cost.dart` is the macro summation's twin
([ADR-0017](../../../../docs/decisions/0017-a-cost-is-a-unit-price-never-an-allocation.md)):
the same walk over the same lines, through the conversion both now share
(`line_basis.dart`), with a price per basis unit multiplied in at the end
instead of per-100 macros. Imprecise and optional lines leave by **exactly** the
macro rule, through the same `effectiveLines` seam, and are named in a
`NOT COUNTED` / `OPTIONAL` row rather than as a gap. A line with no price — or
with no honest path from its amount to the row's basis — is **unpriced**, named
under `UNPRICED`, and takes the recipe's cells with it, exactly as a stub takes
the macro total. `OLDEST` names the one line whose price month differs from the
newest, so a July jar under a September recipe is visible rather than averaged
away.

Money never enters the macro record and macros never enter the cost one; they
share the walk and nothing else, and
`test/structure/cost_and_macros_stay_apart_test.dart` is what keeps it that
way. Costs ride their own stream (`RecipeRepository.watchRecipeCosts`, and
`watchVariantRecipeCosts` for a week that varies the recipe) because a cost
moves when a receipt lands, which the summaries' watch knows nothing about.

**Deferred (implemented in later steps, not missing by accident):** cook mode,
method ingredient-chips/timers, Notes tab, photos. See the roadmap +
`tech-debt-tracker.md`.
