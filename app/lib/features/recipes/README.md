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

What the priced lines DO come to is printed under that refusal as a **floor** —
`at least $1.65 a serving · at least $6.60 the recipe`, each figure wearing its
own `at least` so neither half can be read as the cost — and it is a field of
its own (`pricedCents`, `pricedPerServingCents`), never a partial `totalCents`.
That is the whole of the rule: the cost stays null, so the week's figure, the
shop's estimate and a parent recipe's component share are untouched, and a
component whose target is incomplete stays unpriced in its parent rather than
passing a floor upward. A recipe with nothing priced keeps the plain refusal —
`at least $0` would read as free rather than as unknown — and under
`Show line figures` every priced line prints its own chain either way.

Money never enters the macro record and macros never enter the cost one; they
share the walk and nothing else, and
`test/structure/cost_and_macros_stay_apart_test.dart` is what keeps it that
way. Costs ride their own stream (`RecipeRepository.watchRecipeCosts`, and
`watchVariantRecipeCosts` for a week that varies the recipe) because a cost
moves when a receipt lands, which the summaries' watch knows nothing about.

## The domain, and what a component line counts

`domain/` is pure Dart end to end (invariant 2). The files that carry a rule
rather than a shape:

- **`component_math.dart`** — `resolveComponentAmount`, the one answer to *how
  many batches of the target does this line ask for*. It returns a sealed
  `ComponentAmount`: resolved, or one of five honest refusals — no amount, no
  yield, a family the yield cannot answer, **a word the target no longer has**,
  a cycle. Nothing here ever falls back to "assume one batch", and every
  surface switches exhaustively, so a new refusal cannot be rendered as `1×` by
  a stale `else`.
- **`core/units/recipe_measure.dart`** — a recipe's own word for one of what a
  batch makes, defined as a named AMOUNT: *a blob is 15 g*, so `3 blob` is 45 g
  and — through the recipe's own `makes 300 g` — 0.15 of a batch
  ([ADR-0018](../../../../docs/decisions/0018-a-recipe-measure-is-a-named-amount.md)).
  It is `measure.dart`'s shape one level up, carrying its own `unit` because a
  recipe has no basis to lend it one, and it lives beside `measure.dart` for
  both reasons: it is the same kind of fact, and a component's dock offers both.
  The amount is absolute, so re-stating `makes` re-states the share — and the
  price of that is a gate, below.
- **`recipe_measure_authoring.dart`** — the word, read by the ingredient side's
  rule verbatim (trim, collapse whitespace, **case untouched**), duplicates
  merged on read oldest-first, a label that merely names a catalog unit — `cup`,
  `g`, `batch` — refused against the catalog's own lookup rather than a hand
  list, and **the `makes` gate**: a word can only be coined while the recipe
  states a yield in the unit's family, and the refusals name MAKES. Read
  backwards, that gate is `recipeMeasuresOrphanedBy`, which tells the editor
  which live words a `makes` edit would leave standing on nothing — a warning,
  never a refusal.
- **`component_units.dart`** — what a component's chip row offers, in order:
  the target's own words first (`wholeMeasureOfRecipe` ahead of them), then
  `batch`, then the yields' families. A word the recipe can no longer hold is
  omitted, unless a line stores it, where the 7.7 rule admits it off-filter. The
  whole-batch word is **found, never stored** — the one whose amount is the
  recipe's ENTIRE same-family yield within the app's single tolerance — which is
  ADR-0016's rule with *the whole yield* where the piece weight was.
  `componentUnitChoices` returns the same `UnitChoiceOffer` the ingredient
  filter does, and for the same reason: **there is one chip row in the app**
  (`ingredients/presentation/unit_chips.dart`), and a surface's job is to build
  the offer rather than to draw a row of its own. `firstComponentChoice` is
  where a fresh amount opens while the recipe leads with a word; a recipe that
  coins none keeps the yield's own unit, which is the line a page prints.
- **`line_basis.dart`** — the one conversion the macro and cost walks share, so
  a line can never weigh one thing for its macros and another for its cost.
- **`effective_lines.dart`** — the one seam deciding *which* lines a derivation
  runs over (optional, and this week's overrides).

**A line's amount is said in a catalog unit OR in one of the target's words,
never both and never neither.** `LineItem.unit` is null exactly when
`recipeMeasureId` is set, which is the database's
`num_nonnulls(unit, recipe_measure_id) = 1` stated in Dart, with two asserts
holding it. There is no companion unit a measured line could honestly carry:
the line's number counts WORDS, so the measure's own `g` beside it would read as
`3 g` where the line means 45; `batch` is the right dimension with the wrong
number; and `piece` is the count degradation ADR-0018 exists to refuse — a word
that has gone leaves the line **unresolved and named**, with its number kept,
rather than re-read as a count of whatever the batch is measured in.

Everything below that resolution seam consumes `batches` and only `batches`,
which is why the cook plan, the cost walk and the macro walk each needed one
new case rather than a new path.

## The data layer for a recipe's own words

`data/recipe_measure_repository_impl.dart` is the **only** file that writes
`recipe_measure`, and the only one whose SQL names it. Four things live there:

- **`_columns` / `_rowOf` / `_insertRow` / `_updateRow`** — the four sites that
  name what a measure IS, which is an `amount` and the `unit` it is said in. A
  row whose `unit` is not in this build's catalog is **skipped on read**, so a
  line naming it reads `ComponentMeasureMissing`: the only fallback available
  would be `pieces`, and that is the confidently wrong batch share ADR-0018 rule
  7 refuses.
- **`loadRecipeMeasures`** — every live recipe's words, keyed by recipe id,
  duplicates merged. **One query per load for the whole household**, never one
  per recipe or per line: a measured line is looked up in its TARGET's list, so
  every loader that builds a `SubRecipeTarget`, a `SubRecipeNode` or a
  `ComponentRecipe` wants the whole map anyway. The callers are the summaries,
  the recipe page, `loadRecipeMacroNodes` (the one node loader behind recipe
  macros, recipe costs and the week's re-summations) and `cook_plan`'s
  `loadComponentGraph`, which feeds both Cook and the shop's walk.
- **`writeRecipeMeasures`** — the diff `saveRecipe` runs inside its
  transaction, **before** the lines, because a word and a line saying it have to
  land in that order for the server's own guard. It runs the authoring gate on
  what the Save **states** — a new word, or one whose label, amount or unit
  changed — against the yields read back off the recipe row *inside the same
  transaction*, so a `makes` edit and a word edit arriving together are judged
  against each other. A word carried through unchanged is never re-authored:
  ADR-0018 rule 4 says a `makes` edit that orphans a word **warns**, and a gate
  that refused the Save would trap the person in the editor instead.
- **`countRecipeMeasureReferrers`** — the delete gate, over both tables that can
  carry a pointer (`recipe_line_item`, `week_recipe_line_override`).
- **`SqliteRecipeMeasureRepository`** — the direct doors.

**Two doors write a word, and the difference is whether the host has a Save**
(ADR-0011) — the pair the ingredient side has worn since 7.6. The recipe editor's
MEASURES list, under MAKES, **defers**: it rides `Recipe.measures` through
`saveRecipe`'s child diff, so a word typed there lands with the recipe. The
manage-measures page behind the ＋ on a component's dock has no Save, so it writes
**on tap**, through `RecipeMeasureRepository` — `addRecipeMeasure`,
`restateRecipeMeasure`, `reorderRecipeMeasures`, `softDeleteRecipeMeasure`. Both
land the same rows under the same rules, because the rules are
`authorRecipeMeasure`'s rather than either door's.

## The authoring UI

`presentation/recipe_measures_editor.dart` is the one list-and-form, and it
**knows no repository and no host**: it takes the recipe's yields, its words and
three callbacks (`onAdd`, `onRestate`, `onDelete`, plus an optional `onReorder`),
runs `authorRecipeMeasure` at the moment of each add or re-statement, and prints
every refusal under the field with what was typed still there. The add form is
the shared `MeasureForm` the ingredient side wears — extracted to `shared/`
rather than forked — so a word and an ingredient's `can (400 g)` are typed into
the same run at the same control height. A landed word clears both slots, KEEPS
the unit and puts the keyboard back in the label.

The unit chip offers `recipeMeasureUnitChoices` — every catalog unit of a family
MAKES states, which is the authoring gate read forwards, so a chip can never
produce a refusal on its own. With no yield the form is replaced by
`kRecipeMeasureNoYieldRefusal`, one sentence and no controls; the words the
recipe already has stay listed, each carrying `recipeMeasureOrphanedRowNote`.

**Its first host is the header form**, where `RecipeHeaderSection.measures` sits
directly under MAKES in the section list both hosts render — so the import review
hosts it too, prefilling nothing (there is nothing to prefill from), and its
commit carries `CommitPayload.measures` through the same `writeRecipeMeasures`.
The wide editor gives it the band under the four dense cells, at the cap's full
width: it is the one section that is a list with a form under it.

Three rules live in the host rather than in the widget, because only a host knows
them:

- **the delete gate** — `mayDeleteRecipeMeasure` asks the repository at the tap
  (never a list, and never a one-shot `.future` on an autoDispose provider) and
  refuses with `recipeMeasureDeleteRefusalText` plus a **Show me where** door
  onto the recipes. A word no Save has written yet has no referrer, so the same
  question answers yes for it without a special case;
- **the orphan warning** — the editor's Save asks `measuresOrphanedBySave()`,
  which is `recipeMeasuresOrphanedBy` between the yields the editor OPENED with
  and the ones the draft now states, and puts `recipeMeasuresOrphanedWarning` in
  front of the person. It warns, never refuses, and deletes nothing;
- **the repository's own refusal** — a Save that both edits `makes` and re-states
  a word throws `RecipeMeasureRefused`, and the editor prints that sentence
  rather than the write door's "Couldn't save the recipe", with the draft intact.

**Its second host is the `＋` on a component's quantity dock**
(`presentation/component_quantity_sheet.dart`), aimed at the **target** recipe —
the sauce being measured, not the one being written — because that is the recipe
the word belongs to. It has no Save, so each callback is a write through
`RecipeMeasureRepository` wrapped in `ref.write`: a `RecipeMeasureRefused`
becomes `RecipeMeasureTurnedDown` and prints under the field, any other failure
is `RecipeMeasureNotLanded` and has already been said by the write door. Three
things follow from a door opened mid-sentence — the sheet **watches**
`recipeMeasuresProvider(target.id)` rather than trusting the snapshot its caller
passed, so a coined word is a chip on return with nothing reloaded; the word is
**selected** as it lands, so back reads `3 blob`; and the selection is re-read
from the live row every build, so a re-statement follows through and a
retirement lights no chip. Retiring the word the open line was counting
reconciles the choice to the yield's own unit with a note — Done must never
write a tombstone. The `＋` is drawn for the two recipe-editor doors, the method
editor's and week mode's, and **not** for the import review's two, which strip
the target's words for the same reason: a review line has no column for a
pointer.

**The drag is not built.** `sort_order` is stored, read and re-stamped by
position on every Save, and the widget draws a grip only where a host passes
`onReorder` — which no shipped host does (ADR-0018, "out of the first slice").
The order a household types their words in is the order they get.

**The `makes` gate is the repository's, not a parameter.** `addRecipeMeasure` and
`restateRecipeMeasure` read the recipe's stated yields off the row inside their
own transaction and hand them to `authorRecipeMeasure`: "only when we know what
the recipe makes" is a fact about the stored recipe, and a form must not be able
to assert its way past it.

**The word is CHOSEN on the component quantity sheet**
(`presentation/component_quantity_sheet.dart`), which rides the app's one chip
row fed by `componentUnitChoices`. It opens on the line's stored word where the
target still holds it, else its stored unit, else the word the offer leads with,
else the yield's own unit. It returns `ComponentQuantity`, which carries
**exactly one** denomination — picking a word clears the unit, picking a unit
clears the word — so no host can write a line the repository would refuse.

**Every door onto a component line opens it**: `_ComponentLineEditor` and the
add-a-component flow in the recipe editor, and week mode's amount cell, which
used to route a component line carrying a unit to the INGREDIENT sheet — whose
offer has no `batch`, no yield families and no way to say a recipe's word at
all, and which opens such a line preselected on `piece`. The import review's two
doors pass the target with its words stripped: a review line stores a unit id
and has no column for a word, so one picked there could only land as a whole
batch (ADR-0018 — the review prefills no word, and now offers none either).

**A line whose word has GONE lights no chip.** There is nothing honest to
preselect, so the row draws the ordinary offer with no selection, the number is
kept, and the pointer is kept with it until somebody taps a chip — which is the
repair, the other being to put the word back under the target's MEASURES.

**A retirement is refused, not cascaded.** `softDeleteRecipeMeasure` and the
deferred diff both ask the gate first and throw `RecipeMeasureInUse` — carrying
the counts `recipeMeasureDeleteRefusalText` prints — while anything still says
the word. Nothing follows a word out because nothing may: the lines saying it
would go unresolved for good.

**Two writes are refused before they are written**, and for one reason: the
server would refuse them on UPLOAD, and a refused upload makes the PowerSync
connector drop the WHOLE crud transaction — every write queued beside it, in
silence. `saveRecipe` throws `UndenominatedLineError` for a line denominated in
neither a unit nor a word; `saveOverrides` throws `WordlessOverrideError` for a
week's amount that names a word and no number. `LineItem`'s asserts say the same
thing, but an assert is compiled out of a release build.

**Every watch that reads a word joins `recipe_measure` and selects a column from
it** — `watchRecipes`, `watchRecipe`, `watchRecipeCosts`, the week variant's
two, the cook plan's and the shop's — so coining, re-stating or retiring one
re-fires them. SQLite drops a LEFT JOIN whose columns go unused, and a dropped
join is a table PowerSync never fires for.

**Deferred (implemented in later steps, not missing by accident):** cook mode,
method ingredient-chips/timers, Notes tab, photos. See the roadmap +
`tech-debt-tracker.md`.
