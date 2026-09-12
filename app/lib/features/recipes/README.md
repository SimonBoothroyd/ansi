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
a cook reads); the editor and the review's collapsed row print the same shape,
with the editor's two doors side by side instead of stacked — the amount cell
opens the quantity sheet, the name cell opens the identity picker. *used in N
steps* is a second muted line under the name, and only when N > 0: it is a fact
about the line, not a control.

Three details of that line are rules rather than styling:

- **A note is a modifier, not a second fact.** It follows the name after two
  spaces, in muted italic — no middle dot between a thing and its own
  qualifier.
- **The `optional` tag wears the sub-recipe chip's shape** (`OptionalTag`): a
  6 px box in the herb wash, muted mono, hung off the end of the identity. It
  is also the whole statement — a tagged row prints nothing in its macro slot,
  because *optional* twice on one line is once too many.
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

**Deferred (implemented in later steps, not missing by accident):** cook mode,
method ingredient-chips/timers, Notes tab, photos. See the roadmap +
`tech-debt-tracker.md`.
