# Feature: cook_plan

**Roadmap:** Step 5 — batch cook plan (derived) (see `docs/exec-plans/roadmap.md`,
[exec plan](../../../../docs/exec-plans/completed/0006-batch-cook-plan.md)).

The **Cook** screen: the counterpart to the Week. It groups the active week's
meals by recipe into **cook sessions**: a **cooking** (one pot, remembered)
for each the week buys, and shelf-life groups (spec §4) for meals not in one
yet. Edit the Week and this re-derives. A dish's card lists its sessions in
day order under the portions its week's own meals plan (`4 portions across
the week`: a pot's later-week meals and what a cooking made beyond the plan
are its sessions' to say). Cook asks nothing: a cooked batch's card leads
with a check (`Cooked Fri`), shows its scale only when it isn't `×1`, and in
place of its covers line says what it left in one line (`2 left · freeze by
Mon for Wed`), opening **Leftovers**. A batch not cooked yet tints its keep
days on the strip only until the dish's next cook (`timelinesOf`).

**Leftovers** (`/leftovers`) is this feature's one writing page: the
household's **fridge and freezer**, every cooking read on today
(`readCookings`, below), soonest to go off first, put right with each row's
`N left` chip (it opens a stepper), Freeze and Froze it, one Remove gone off
link at the page's foot, and *Add a leftover*; Freeze, Froze it and Remove
gone off each raise an Undo toast. Its door is the fridge in the Week header.
The planning picker's *Leftovers* offers its rows back, judged on the day
being planned, with the pots not cooked yet (`cooks Sat`). A cooking not
cooked yet is not on the page.

## Layout

```
cook_plan/
  domain/         PURE DART (no package:flutter)
    cook_plan.dart              CoveredMeal · PlannedCooking · PlannedRecipe ·
                                CookSession · RecipeCookPlan · CookPlan;
                                clusterSessions + buildCookPlan +
                                batchHintFor
    cooking.dart                Cooking · CookingMeal: made, the cook day,
                                the buy week, the group before birth and
                                the id it is born under
    leftovers.dart              cookDayOf, useByOf, freezeShareOf (a
                                session's); Leftover, LeftoverMeal,
                                LeftoverShelves, readCooking + readCookings,
                                plannedPots (pots not born yet),
                                leftoverOfferOn
    cook_plan_repository.dart   the plan (read only)
    leftover_repository.dart    the shelves, and every write to them
  data/           SqliteCookPlanRepository (watch → buildCookPlan, and
                  loadCookPlan, read once; loadPlannedWeek, the week's
                  recipe meals and the cookings it buys, which the shop
                  reads too); SqliteLeftoverRepository; cooking_store.dart
                  (the flat cooking read, the unborn meals' read, the
                  tick's birth, the pick's, and the carry-over); providers
  presentation/   CookView (each session draws the compact week strip,
                  shared/week_strip.dart; a meal eaten from an earlier
                  cooking is one line) + CookSheet; cook_format.dart (copy
                  + strip geometry, pure Dart); cook_view_models.dart (the plan,
                  and chooseWholeBatch);
                  batch_leftover_line.dart (a batch card's one line);
                  leftovers_view.dart (the page, its rows, Add a leftover,
                  and LeftoversDoor); leftovers_view_models.dart;
                  leftover_format.dart (`2 left`, `till Mon`, `for Sun`,
                  `freeze by Mon for Wed`, `cooks Sat`, `cooked last Sat`,
                  pure Dart)
```

## The clustering rule (spec §4)

Greedy, per recipe (`clusterSessions`), over the week's meals **not yet in a
cooking**, days 0..6 of that week alone: sort the days a dish appears; start
a session at the first; fold each later meal in while it stays within the
fridge window (`keeps_for_days`, `kAssumedFridgeDays` (7) when unknown). A
meal past the window folds in anyway as a **frozen** share when the recipe
is `freezable` and the meal is within `freezer_days` (null = no limit);
otherwise it opens a new session. O(n·log n). Each cooking the week buys
follows as one session of its own (`CookSession.cookingId`), never split or
merged.

- The session's `cookDay` is its earliest **planned** day: what the shop, the
  strip and the clustering read. When it was actually cooked is the ticks'
  (`cookDayOf`, below).
- The **scale factor** is the raw `total_portions / servings_base` — honest, not
  rounded to a whole batch (whole-ingredient scaling is deferred) unless the
  cook chose the **whole batch**. The session's exact-or-whole switch is kept
  on its cooking (`setWholeBatch`, born then if need be): a `cooking_change`
  row with a fixed id (`wholeBatchChangeId`) that moves no portions, and
  soft-deleted to go back. With it, `totalPortions` and what the cooking made
  round up to whole batches, so the shop and the cost buy the whole batch
  and its spare is left over once cooked. A cooked batch shows no switch.
  A cooking's `plannedPortions` is what it **made** once fixed, else the
  live sum of its meals. A meal's demand is Σ of its eaters' portion factors
  (`1¾` for a 1 and a ¾ eater), and every count is printed as a fraction
  (`core/units/portions.dart`), the whole-batch switch's spare portions
  included.

`batchHintFor` reuses `clusterSessions` so the planner's "same batch" hint on the
add-a-meal flow can never disagree with the cook plan.

## Cookings

A **cooking** (`cooking`, migration 0061) is one pot, remembered rather than
re-derived (`domain/cooking.dart`).

- **Birth.** The first tick on a meal of a group, or the first pick from it,
  births the cooking (`ensureCookingFor`, `cookingForPick`). The group is the
  meal's week's unlinked meals of the recipe, grouped as above
  (`cookingGroupOf`). The cooking reuses one already linked to a group meal,
  or one whose id is a group meal's id; otherwise its id is the group's first
  meal (`birthIdFor`), so two phones compute the same id. A birth checks for
  the id first: local tables are views, and the other phone's birth may have
  synced here. The connector uploads a cooking's (and a change's) PUT as an
  insert that leaves a row already there alone (`insertOnceTables`). Then the
  whole group links (`plan_entry.cooking`). Choosing the whole batch on a
  group not in a cooking births it too.
- **Joining a pot not cooked yet.** While nobody has ticked a cooking, an
  unlinked meal of its recipe in the week it is bought in that the grouping
  puts with its meals joins it (`joinersOf`, `loadJoiners`): Ragù Saturday
  picked for next Thursday, then added for Friday, is one pot cooked Friday.
  Every reader (Cook, the shop, the Leftovers read, the picker) counts the
  joiner in the pot; its next write links it (`joinUncookedCooking` before a
  tick lands, `linkJoiners` on a pick). After the first tick, a meal added to
  the week is a choice (*From leftovers · Cook fresh*), never a join.
- **Made** is fixed at the first tick, from the live sum of its meals; before
  that it is that live sum (`madeOf`), rounded up to whole batches while the
  whole batch is chosen. Deleting a meal or cutting portions after the first
  tick leaves that food in the fridge; raising them warns.
- **A meal removed after somebody ticked it** is still read
  (`CookingMeal.removed`): its live ticks still cook the pot, date it and
  take from it, and it plans nothing more. Removing the meal everybody ate
  leaves its leftovers where they were, and Undo puts the meal back with
  nothing moved.
- **Cooked** and the **cook day** are read off the live ticks every time
  (`cookDayOfCooking`): the earliest ticked day. An untick writes nothing.
  Untick everything and it reads not cooked: cooked on its next meal if one
  is still to come (`cook Thu`), never cooked otherwise. Food said by hand
  (`place` and `since`: *Add a leftover*, or a carried-over fridge row) is
  dated by `since`.
- **Bought** in the week of its earliest linked meal (`boughtIn`), for what
  it made; a linked meal in any other week buys nothing. A week's cook plan,
  shop and cost read that week's unlinked meals, the cookings it buys, and
  (as `CookPlan.eatenFromEarlier`) its meals of cookings bought earlier — one
  week, never a walk over weeks (`loadPlannedWeek`). Food said by hand is
  bought nowhere. Cook lists each meal eaten from an earlier cooking as one
  line (`earlierMealsOf`): `Beef Ragù · Thu · from the freezer` (or `from
  the fridge`), or `cook it` once nobody ticked the earlier meals and it has
  become the cook day; the week is not `nothing planned yet` for it.
- **No automatic cross-week sharing.** A meal shares a cooking only when it
  is picked from one: the picker's pot row, or **From leftovers** on the
  confirm sheet, which asks whenever the dish has a pot the day can eat from
  (planning's README). Picking from a cooking not cooked yet adds the meal's
  portions to what it makes: *Ragù Sat* picked for next Thursday is bought
  once, on Saturday's week, and Saturday's card says `freeze 2 by Tue for
  next Thu` (`freezeShareOf`), its meal sheet `cook it all · freeze 2 for
  next Thu` (`nextWeekShareLine`).
- **Cook fresh instead** clears a meal's link: it is cooked and bought in its
  own week again. A move (Ask's included) keeps the link; a copy of last week
  does not.

## The cook day, by the ticks

`cookDayOf` reads a session's cook day off its meals' ticks on a day, with
the same rule as a cooking's: the earliest ticked day, whatever order the
ticks came in; with no tick, the first of its meals not yet behind us; with
every meal behind and none ticked, null. `useByOf` is that day plus
`keeps_for_days` (7 when unknown), that day included, never stretched to a
later meal. `sessionByTicks` is a batch with that cook day in place of its
planned one: what the strips on Cook, its wide sheet and the meal's sheet
draw, live as ticks come in.

The Week reads the same rule (`cookMarkerFor` in `planning`): a meal before
the cook day says nothing, the cook day says `cooks Fri · batch of 6`
(`cooked Fri` once ticked; a one-meal cook says nothing until it is cooked,
then `cooked Fri` too), and a later meal of a cooking already cooked
wears the `leftover` tag, blue past the fridge date; a meal of a cooking
bought in an earlier week wears it too, until it becomes that cooking's cook
day. A meal from food said by hand wears it always (`eatsFromAPot`).

## The fridge and the freezer

`readCookings` is the one seam (pure) that says what the household has on a
day, and judges every meal linked to a cooking (`LeftoverShelves`: the rows,
and the meals by `plan_entry` id). It reads every live cooking with its live
linked meals, their ticks and its change rows in one flat query
(`loadCookingInputs`); a cooking said gone off is read only while a meal
from it is still to come, which it warns, or while a freezer part of it
could still be in date. Beside them, the planned meals from today on that
no cooking holds yet (`loadUnbornMeals`, one flat read by date) are the
**pots not born yet** (`plannedPots`, `LeftoverShelves.pots`): each week's
meals of a recipe grouped as a birth would group them, under the first
meal's id, not cooked (`Leftover.cooked`).

- **What a meal takes:** a meal behind today, its ticked shares, capped at
  its portions (a tick counts even if its member was since taken off the
  meal); today's or a later meal, its planned portions in full (spoken for).
- **Where it takes from:** on or before the fridge date (cook day plus
  fridge life), the fridge, and the freezer's spare when the fridge has not
  got it (as after a Freeze). After it, of a dish that freezes and within its
  freezer life, it is a **freezer meal**: its portions go in the freezer by
  the fridge date with no write (what the freezer has spare already covers
  that much), as far as the fridge has them: only what is there is frozen,
  and the rest warns. It takes from the freezer. Otherwise the fridge, `past
  its date`. A meal removed after it was ticked takes its ticked shares.
- **Counts**, per shelf and unclamped, so an untick reverses exactly: the
  fridge is made (or, said by hand, on its `place`) plus its change rows,
  less what its meals take and less what freezer meals move out; the freezer
  is its change rows plus what they move in, less what it gives. Until the
  fridge date passes, a freezer meal's portions are shown in the fridge
  (`freeze by Mon for Wed`). Each shelf is a `Leftover` row: `inBox` is the
  box clamped at nothing (the `N left` the page and Cook print), `planned`
  what meals still to come take, `portions` what is free to plan (the
  picker's). A row shows while its box holds anything or a meal still to
  come takes from it.
- **A dish counts as a whole** (`readDishes`): what a meal's own cooking
  cannot give comes from the household's other cookings of its recipe,
  cooked ones only, fridge before freezer, soonest to go off first, each
  from a shelf in date on the meal's day and only what is free once its own
  meals are served. The giver lists the share (`LeftoverMeal.lent`, `2 for
  next Tue`); the meal warns only for what is still short. Every write reads
  the cooking with its whole dish (`readCookingIn`).
- **Warnings, never edits:** a meal from today on that the shelves cannot
  cover is `notEnoughLeft` (`Sat needs 3 · 2 left`); one past every date is
  `pastItsDate`; every meal of a cooking never cooked, and every meal still
  to come of one said gone, is `notEnoughLeft`. The Week prints either in
  amber on the meal's tag.
- **Dates:** a fridge row is good until the cook day plus `keeps_for_days`
  (7 when unknown), a freezer row until the cook day plus `freezer_days` (no
  limit when null). Food in words keeps a week in the fridge; in the freezer
  it has no date, only an age. Dates read the recipe live. Every screen
  prints them through `leftover_format.dart`, one rule (`weekdayFrom`):
  `today`; a day of today's week by its weekday; `next Tue`; `last Sat`;
  else `17 Nov`; the freezer `till Jan` past six days; `cooks Sat` for a pot
  not cooked yet; an age `added today`, `2 wk`. Two rows of one dish say
  `cooked Sun`.
- **The picker** (`leftoverOfferOn`) judges a row on the day being planned: a
  fridge row in date then, from the fridge; one that would need freezing by
  then, under Freezer as `freeze by Mon`; a freezer row in date then. A row
  past its date today, food in words, and a cooked row with nothing free are
  never offered. A pot not cooked yet is offered from its cook day for as
  long as it would keep, whatever it has free, once (`leftoversGoodOn`); a
  pot not born yet only to a later week than its own. A day behind us is
  judged the same way, on that day.


### The writes

Every write names a `Leftover` (one shelf of one cooking) as the page drew
it, and reads the cooking again inside its transaction
(`LeftoverRepository`). Local tables are views, so each is a SELECT then an
INSERT or UPDATE.

- **The stepper** writes one `cooking_change` with the difference between
  what was set and the shelf's box: later ticks and unticks still move it,
  and two phones correcting offline both apply.
- **Freeze** and **Froze it** write one change moving the fridge box to the
  freezer (−n, +n). Dates still count from the cook day. A row with nothing
  in its box offers neither.
- **The whole batch** (`setWholeBatch`) writes, or soft-deletes, the
  cooking's one whole-batch change row; it moves no portions.
- **Remove gone off** sets `gone_at`, by the household's clock: the
  cooking's fridge part is gone for good, and its freezer part too unless
  it is still in date that day (`readCooking`). Final: an untick after it
  never brings either back, since the fridge part is never read again and
  the freezer line moves only with the cook day, by days against months. A
  freezer part gone off beside a fridge part still in date (only a freezer
  life shorter than the fridge's) is counted to nothing by a change.
- **Undo** (`undoLeftovers`) soft-deletes the change rows a write made, and
  puts back the `gone_at` each cooking had before.
- **Add a leftover** inserts a cooking said by hand: a recipe or the
  household's words, its `place`, `since` from the chip (today, 7 or 14 days
  back) and `made`.
- A refused upload names the cooking by its dish or words and opens
  `/leftovers` (`shared/dropped_write_subject.dart`).

### The carry-over

The last release stored fridge rows (`leftover`), pointers (`leftover_of`,
`from_leftover`) and answers (`batch_leftover`). They stay read-only for
this release and go with the next. Migration 0061 copies each `leftover` row
to a cooking of the same id (said by hand: its count, place and date) and
each pointer to a link. Once per launch, after the launch's first download,
`carryOverCookings` births a cooking for every group ticked in the last 28
days that none covers, links a group the old rows name to the cooking it
became (with one change keeping the count the row said), and turns an old
*binned* or *eaten* answer into a change that takes its cooking to nothing.
Its ids are deterministic, so it is idempotent on both phones.
`test/structure/leftover_meal_seam_test.dart` holds that nothing else reads
the old tables, and nothing writes them.

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
