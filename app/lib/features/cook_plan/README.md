# Feature: cook_plan

**Roadmap:** Step 5 — batch cook plan (derived) (see `docs/exec-plans/roadmap.md`,
[exec plan](../../../../docs/exec-plans/completed/0006-batch-cook-plan.md)).

The **Cook** screen: the derived counterpart to the Week. It groups the active
week's meals by recipe and splits each into **cook sessions** bounded by shelf
life (spec §4). Nothing here is planned; edit the Week and this re-derives.
Cook asks nothing: a cooked batch's card leads with a check (`Cooked Fri`),
shows its scale only when it isn't `×1`, and in place of its covers line says
what it left in one line (`2 left · freeze by Mon for Wed`), opening
**Leftovers**.

**Leftovers** (`/leftovers`) is this feature's one writing page: the
household's **fridge and freezer**, the derived batches merged with the
`leftover` rows it has stored (`readLeftovers`, below), soonest to go off
first, put right with each row's `N left` chip (it opens a stepper), Freeze and
Froze it, one Remove gone off link at the page's foot, and *Add a leftover*;
Freeze, Froze it and Remove gone off each raise an Undo toast. Its door is the fridge in the
Week header. The planning picker's *Leftovers* offers its rows back, judged on
the day being planned.

## Layout

```
cook_plan/
  domain/         PURE DART (no package:flutter)
    cook_plan.dart              CoveredMeal · PlannedRecipe · CookSession ·
                                RecipeCookPlan · CookPlan; clusterSessions +
                                plannedAcrossWeeks + buildCookPlan +
                                batchHintFor
    leftovers.dart              cookDayOf, useByOf, freezeShareOf;
                                StoredLeftover, Leftover, LeftoverMeal,
                                LeftoverShelves, readLeftovers,
                                leftoverOfferOn, leftoverWeekStarts
    cook_plan_repository.dart   the plan (read only)
    leftover_repository.dart    the shelves, and every write to them
  data/           SqliteCookPlanRepository (watch → buildCookPlan, and
                  loadCookPlan, read once; loadPlannedWeek, the week's
                  recipe meals across both week edges, which the shop reads
                  too); SqliteLeftoverRepository; providers
  presentation/   CookView (each session draws the compact week strip,
                  shared/week_strip.dart) + CookSheet; cook_format.dart (copy
                  + strip geometry, pure Dart); cook_view_models.dart;
                  batch_leftover_line.dart (a batch card's one line);
                  leftovers_view.dart (the page, its rows, Add a leftover,
                  and LeftoversDoor); leftovers_view_models.dart;
                  leftover_format.dart (`2 left`, `till Mon`, `for Sun`,
                  `freeze by Mon for Wed`, pure Dart)
```

## The clustering rule (spec §4)

Greedy, per recipe (`clusterSessions`): sort the days a dish appears; start a
session at the first; fold each later meal in while it stays within the fridge
window (`keeps_for_days`). A meal past the window folds in anyway as a **frozen**
share when the recipe is `freezable` and the meal is within `freezer_days`
(null = no limit); otherwise it opens a new session. O(n·log n).

- The session's `cookDay` is its earliest **planned** day: what the shop, the
  strip and the clustering read. When it was actually cooked is the ticks'
  (`cookDayOf`, below).
- The **scale factor** is the raw `total_portions / servings_base` — honest, not
  rounded to a whole batch (whole-ingredient scaling is deferred); the
  session's exact-or-whole switch is display only. Since plan
  0027 `total_portions` is a double: a meal's demand is Σ of its eaters'
  portion factors (`1¾` for a 1 and a ¾ eater), the batch math was already
  fractional, and every count is printed as a fraction (`core/units/
  portions.dart`), the whole-batch switch's spare portions included.
- A recipe with no `keeps_for_days` (unknown shelf life) is never split.

`batchHintFor` reuses `clusterSessions` so the planner's "same batch" hint on the
add-a-meal flow can never disagree with the cook plan.

### Across the week edge

A dish that freezes is cooked once for two weeks. The week's **last** batch of
a freezable recipe folds in the next week's meals of it (`PlannedRecipe.
nextWeek`), in day order, while each is within `freezer_days` of the batch's
planned cook day and **one whole recipe covers them**: the batch's portions
plus the folded ones are at most `servings_base`, a scale of ×1 or less. The
fold stops at the first meal that fails either test. A folded meal is a cover
on days 7..13 (`CookSession.nextWeekCovers`), so the batch is scaled, bought
and costed for it in its own week.

`plannedAcrossWeeks` walks the weeks before in order: each week's meals the
week before's batch folded in are taken out of it, and what is left
clusters and folds the next week in its turn, naming the meals it took in
`CookPlan.foldedBack` with that batch. So a batch made of a folded meal
never folds forward, and any other batch does: a dish planned every week
folds each week its batch can. Whether a week takes a fold hangs on every
week before it, so every reader cuts that chain in the same place
(`foldCutsBefore`): after a week without the dish, and, for a dish planned
each of the four weeks before, where the calendar starts a run
(`weeksIntoFoldRun`, every `kFoldRunWeeks`). `loadPlannedWeek` reads
`kFoldLookbackWeeks` (8) back and one ahead, which always reaches a cut. That read is the **one choke point** the cook plan and the shop
share, as `leftover_of` / `from_leftover` are; the Week's cost passes over
`foldedBack` and adds `CookPlan.cookedForNextWeek` (the household view only).
A Saturday never ticked makes the folded Thursday its cook day by the ticks'
rule, with nothing bought again. The batch's card says `covers Sat + next Thu
breakfast` and `freeze 2 by Tue for next Thu` (weekdays, never dates;
`leftover_format.dart`), Saturday's meal sheet `cook it all · freeze 2 for
next Thu` (`nextWeekShareLine`), and next week's Cook lists the meal as one
line, `Beef Ragù · Thu · from the freezer` (`foldedMealLines`), or `cook it`
once it has become the cook day.

## The cook day, by the ticks

**No tick means you didn't eat it.** `cookDayOf` reads a batch's cook day off
its meals' ticks on a day: the earliest calendar day with an eaten portion,
whatever order the ticks came in (an untick works it out again); with no tick,
the first of its meals not yet behind us (`Cook Fri`); with every meal behind
and none ticked, null: never cooked, nothing left. `useByOf` is that day plus
`keeps_for_days`, that day included, and never stretches to a later meal; a
recipe with no fridge life keeps `kAssumedFridgeDays` (7), derived and stored
rows alike. `sessionByTicks` is a batch with that cook day in place of its
planned one: what the strips on Cook, its wide sheet and the meal's sheet
draw, live as ticks come in. `freezeShareOf` is the part of a freezable batch past that date,
which Cook's batch line says until the freeze is due: `freeze 2 by Tue for
Thu`.

The Week reads the same rule (`cookMarkerFor` in `planning`): a meal before
the cook day says nothing, the cook day says `cooks Fri · batch of 6` (`cooked Fri` once ticked), and a
later meal of a batch already cooked wears the `leftover` tag, blue past the
fridge date; a meal the week before cooks wears it too, until it becomes that
batch's cook day.

## The fridge and the freezer

`readLeftovers` is the one seam (pure) that says what cooked food the
household has on a day, and judges every meal served from it
(`LeftoverShelves`: the rows, and the meals by `plan_entry` id):

- **Derived rows** are the batches of the last four weeks (`kLeftoverHorizon`,
  `leftoverWeekStarts`) with a cook day. **Made is what was planned**: what is
  left is the portions of its meals behind us that nobody ate (a skipped meal
  before the cook day included), less the meals planned from it. A cooked
  batch's later meals ride on the row as spoken for (`own` meals, in
  `planned`). A batch not cooked yet but with a skipped meal behind it is a row
  dated from its next meal: the picker offers it from then, the page and
  Cook's line do not show it. A batch an older build's Cook was told was
  binned or eaten (`batch_leftover`, which takes no new writes) reads as gone.
- **Stored rows** (`leftover`) are what was said: a correction, a freeze, a
  dish the app never saw. A row with a `batch` replaces that batch's derived
  row, gone or not; two rows for one batch read as the newest `updated_at`.
  Its `portions` are the box as said at `updated_at`. **On a row naming a
  batch, that count is an adjustment**: the box reads what the batch derives
  now, plus what was said less what the batch derived when it was said
  (`_batchBox`), so every tick or untick after it moves it, whichever meal
  it is on. What was ticked then is read off the `meal_eaten` rows' own
  `created_at` and `deleted_at` (`TickSpan`; an untick soft-deletes, a tick
  again inserts), so no column was added. A row with no batch read moves
  only by the meals planned from it since. Every meal planned from it
  (`from_leftover` and the batch's `leftover_of` alike) and the batch's own
  later meals ride on it as on a derived row: still to come, they are
  spoken for. The box never reads below nothing.
  A fridge row is good until `since` + `keeps_for_days` (7 when unknown), a
  freezer row until `since` + `freezer_days` (null: no limit); `since` is the
  cook day. A row in words keeps a week in the fridge; in the freezer it has
  no date, only an age.
- **Each row's portions fall by the meals planned from it**: `leftover_of`
  for a derived batch, `from_leftover` for a stored row (summed across a
  batch's duplicates). `Leftover.inBox` is what is in the box, spoken for or
  not (the `N left` the page and Cook print); `portions` is what is free to
  plan (the picker's `N left`); `planned` is spoken for by meals still to
  come. A row shows while its box holds anything or meals are still to come.
- **Each meal planned from a row is judged on its own day**, in day order:
  `notEnoughLeft` once the meals before it and it ask more than is left (or
  it falls before the cook day, or the row is gone or never cooked; the
  page and Cook say `Wed needs 2` in amber),
  `pastItsDate` when its day is past every date the row can reach. The Week
  prints either in amber on the meal's tag. Nothing edits the plan.
- **Freeze by.** A fridge row of a dish that freezes reaches past its fridge
  date from the freezer, until its freezer date counted from the cook day
  (`Leftover.shelfOn`). A meal planned that far marks the row `freezeBy` its
  fridge date (`freeze by Mon for Wed`); once that date is behind us the
  freeze is taken as done and the row reads as a freezer row, dated from the
  cook day.
- **The picker** (`leftoverOfferOn`) judges a row on the day being planned: a
  fridge row in date then, from the fridge; one that would need freezing by
  then, under Freezer as `freeze by Mon`; a freezer row in date then. A row
  past its date today, a row in words and a row with nothing left are never
  offered.
- **Nothing clears itself.** A row stays until `gone_at`; `pastItsDate`
  says when it is behind its date.

### The writes

Every write names a `Leftover` as the page drew it
(`LeftoverRepository`). A derived row has no stored row yet: the first write
about it stores one at the count it showed, naming its `batch`, and a later
write finds that row (the newest live one for the batch) rather than storing
another. Local tables are views, so each is a SELECT then an INSERT or
UPDATE.

- **The stepper** sets the box (`inBox`), down to nothing, and stores it as
  said, so the read gives back what was set and later ticks move it.
  Nothing takes a row off the page sooner.
- **Freeze** and **Froze it** set `place = freezer`, keep `since`, the cook
  day (freezer dates count from it), and store the count as it stands, since
  `updated_at` moves. **Remove gone off** sets `gone_at` on every row past
  its date, on both shelves.
- **Undo** (`restoreLeftovers`) puts rows back as the page drew them: a
  derived row by soft-deleting the row the write stored for its batch, a
  stored one by saying its place, date and count again, not gone.
- **Add a leftover** inserts a row with no `batch`: a recipe or the
  household's words, either place, `since` from the chip (today, 7 or 14
  days back).
- A refused upload names the row by its dish or words and opens
  `/leftovers` (`shared/dropped_write_subject.dart`).

A meal from either kind is never cooked again: the cook plan's query reads
`leftover_of IS NULL AND from_leftover IS NULL` in `loadPlannedWeek`, which the
shop reads too, and `test/structure/leftover_meal_seam_test.dart` holds every
such pass to both columns.

## Nested recipes, for one week

A planned recipe's **component** lines derive sessions of their own, scaled in
batches (`expandComponentDemands`; the math lives in
`recipes/domain/component_math.dart`). The household's graph is read whole
(`loadComponentGraph`) and then filtered for the week on screen
(`componentGraphForWeek`): every recipe's component lines go through the
`effectiveLines` seam with that week's overrides before a single demand is
derived, so an **optional sub-recipe is cooked only when the week ticks it in**,
one the week excluded is not cooked at all, and a replaced line is cooked at the
week's amount. The shop runs the same filter over the same graph, and the watch
query joins `week_recipe_line_override` so ticking a line in re-derives the
plan. A component the batch math cannot resolve stays a named `ComponentGap` —
never a `1×` assumption. Each demanding source carries the line that names the
sub-recipe (`lineId`) and, below depth one, the recipe holding it (`via`,
`viaRecipeId`), so the card's **Fix the line in {parent} ›** opens that line in
that recipe's editor (`?line=`) and **Set the yield ›** opens the sub-recipe at
MAKES (`?focus=makes`), both through `gapFixes`. A line a week added (its id is
the override row's) is not in the recipe's editor, which then opens at the top.

**A line said in one of the target's own measures flows through this graph with
its pointer**
([ADR-0018](../../../../docs/decisions/0018-a-recipe-measure-is-a-named-amount.md)).
`loadComponentGraph` carries every recipe's
live words beside its yields (`loadRecipeMeasures`, one query keyed by recipe
id), and the watch joins `recipe_measure`, so re-stating a word re-derives the
plan. The loader's `unit == null` branch is measure-aware: it skips a line only
when it says **neither** a unit nor a word, because a measured line dropped there
is a whole sauce gone from the plan and the shop in silence. A word the target no
longer has is a named `ComponentMeasureMissing` gap whose demanding source keeps
the number and says `saysAMeasure` — never re-read as a count of the yield.

## Deferred

- **Whole-ingredient scaling** (spec §4) — shown as the raw factor for now;
  stretch.
- **No *Cooked on* override**, by ruling: the cook day is the ticks'.
