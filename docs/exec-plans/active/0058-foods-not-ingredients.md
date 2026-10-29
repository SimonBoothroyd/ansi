# Exec plan: foods, not ingredients

- **Status:** active — built and on `main` 2026-10-29, Ask redeployed (deploy-supabase 40836577803); owes `make test-sim`
- **Owner:** Simon (rulings), agent (inventory and build)
- **Roadmap step:** none — the backlog row [*Foods, not ingredients*](../backlog.md)
- **Created:** 2026-10-28

## Goal

The word the app prints for a vocabulary row (a protein bar, a yoghurt pot,
flour) fits all of them. Where the word means *a thing you eat or buy* it reads
**food**. A recipe's line stays an **ingredient of that recipe**.

It is copy only. The `ingredient` table and its columns, the Dart types and
identifiers, the routes (`/ingredients/...`) and the file names keep their
names.

The owner, 2026-10-21, designing [plan 0054](./0054-eaten-vs-planned.md):

> *"Ingredient is also becoming a bit of a misnomer because a protein bar is
> added as an 'ingredient' same with a yoghurt pot."*

## The ruling

The owner ruled each row of the inventory on 2026-10-28 (see the decision
log). In short:

- **Says "food":** the manager and the Library shelf that opens it, the
  detail page and form of one row, the vocabulary picker (opened from
  receipts), a receipt line, a planned bare item and its picker, the shop's
  add-new row and its rows, the barcode, USDA and label lookups and anything
  else that fills in a row's own facts, the sync banner, and Ask wherever it
  means a vocabulary row.
- **Stays "ingredient":** a recipe's lines (the recipe page's tab and column,
  the editor's section and Add ingredient, week mode, the method, the share
  page), the line picker the recipe editor, week mode, the method editor and
  the import review open, and the import review with its match picker.
- **One string, two places, split:** the shop's removed note says *food* for a
  planned bare item and *ingredient* for a recipe line.
- **Plurals and capitals follow the original** ("Ingredients" → "Foods",
  "INGREDIENTS" → "FOODS").

## Acceptance criteria

- [x] Every row in the inventory has the owner's ruling in its **New** column.
- [x] The ruled strings are changed in `app/lib`, and nothing else is renamed.
- [x] Every test in `app/test` and `app/integration_test` that quotes a
      changed string quotes the new one.
- [x] `docs/product-specs/product-spec.md` and `import-and-matching.md` name
      the screens and actions as the app prints them.
- [x] The board frames that print a changed string are redrawn, and each
      view's date is bumped only after reading it against `app/lib`.
- [x] The copy rules of [plan 0057](./0057-copy-pass.md) hold for every new
      string: fragments, no em dashes, no semicolons, no explanations.
- [x] `make analyze` clean, the full `flutter test` green.

## The inventory

Taken 2026-10-28 on `9cf6915`, from every `ingredient`, `ingredients`,
`Ingredient`, `Ingredients` and `INGREDIENTS` printed by `app/lib`. Left out:
identifiers, routes, SQL, table and column names, `StateError`,
`ArgumentError` and `assert` text (none reaches a screen:
`describeFailure` never prints an exception's message), and doc comments.

`{x}` is an interpolated value. **New** is the owner's ruling; **stays**
means the string is unchanged. The context column ends with what the brief's
first proposed rule said, which the ruling mostly kept. Line numbers are as
of `9cf6915`. Paths are under `app/lib/`.

### The manager and its shelf

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 1 | `features/books/presentation/library_view.dart:895` | INGREDIENTS | FOODS | The Library's shelf after the books, the only door to the manager (phone ledger and wide ledger alike). No nav tab, rail or sidebar item names the vocabulary. Rule: food. |
| 2 | `features/books/presentation/library_view.dart:865` | {n} ingredient(s) | {n} food(s) | The shelf's count line, beside `{n} stubs`. Rule: food. |
| 3 | `features/ingredients/presentation/ingredient_list_view.dart:185` | Ingredients | Foods | The manager's header title. Rule: food. |
| 4 | `features/ingredients/presentation/ingredient_list_view.dart:313` | No ingredients yet | No foods yet | The manager's empty state. Rule: food. |
| 5 | `features/ingredients/presentation/ingredient_list_view.dart:357` | add an ingredient | add a food | The manager's add door. Rule: food. |
| 6 | `features/ingredients/presentation/ingredient_list_view.dart:541` | Pick an ingredient | Pick a food | The empty detail pane at expanded width. Rule: food. |

### The detail page and form of one row

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 7 | `features/ingredients/presentation/ingredient_detail_view.dart:183` | Ingredient | Food | The header title of the form (new and edit) on a pushed page. Rule: food. |
| 8 | `features/ingredients/presentation/ingredient_detail_view.dart:1357` | Delete ingredient | Delete food | The `⋯` menu item on the detail page. Rule: food. |
| 9 | `features/ingredients/domain/name_namespace.dart:21` | Already an ingredient: {name} | Already a food: {name} | The form's note under the name field, and the save's refusal. Rule: food. |
| 10 | `features/ingredients/presentation/quantity_unit_sheet.dart:220` | this ingredient’s measures | this food’s measures | The quantity sheet's error state (`Couldn’t load this ingredient’s measures.`). The sheet opens from a recipe line, a week line, the shop and a bare meal. Boundary: it is the row's measures, not the line's. Rule: food. |

The barcode, USDA and label lookups print no `ingredient` today (`USDA · for
“{name}”`, `Read a label`, `Filled from a barcode · …`). Nothing to rule.

### The pickers

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 11 | `features/ingredients/presentation/ingredient_picker.dart:126` | Search ingredients | Search foods | The vocabulary picker's field. Opened from the receipt review (`What is this line?`, a receipt line's match and its add-a-line door). Rule: food. |
| 12 | `features/ingredients/presentation/ingredient_picker.dart:37` | Add an ingredient | Add a food | The vocabulary picker's default title. Both callers pass their own title, so it is never seen today. Rule: food. |
| 13 | `features/ingredients/presentation/ingredient_picker.dart:199` | INGREDIENTS | **stays** | The section header over the vocabulary hits when a second section (recipes) follows. Drawn in the recipe editor's line picker (#16). Boundary: the hits are foods, the pick becomes a line. Rule: food. |
| 14 | `features/ingredients/presentation/ingredient_picker.dart:235` | No ingredients yet. | No foods yet. (the line picker: **stays**) | Every picker's empty list. Rule: food, and ingredient in the line picker (#16). |
| 15 | `features/ingredients/presentation/ingredient_picker.dart:467` | can’t find it? add "{name}" as a new ingredient | can’t find it? add "{name}" as a new food (the line picker: **stays**) | The add-new row at a picker's foot: the receipt picker, the recipe editor's and week mode's line picker. Rule: food, and ingredient in the line picker (#16). |
| 16 | `features/recipes/presentation/line_target_picker.dart:67` and `recipe_editor_view.dart:602` | Add an ingredient | **stays** | The line picker's title. Opened from the recipe editor's Add ingredient, the import review's `＋ ingredient`, the method editor's `＋ ingredient` (a line to chip) and week mode's Add ingredient. Boundary: what is added is a line of the recipe. Rule: ingredient. |
| 17 | `features/recipes/presentation/line_target_picker.dart:184` | Search ingredients | **stays** | The same picker's field. It searches the vocabulary and the recipes. Boundary: it searches foods, to add a line. Rule: unclear, either reading holds. |
| 18 | `features/import/presentation/recon_resolver.dart:440` | Search ingredients | **stays** | The import review's match picker (`Match "{line}"`). Searches the vocabulary for one review line. Boundary as #17. |
| 19 | `features/import/presentation/recon_resolver.dart:463` | create "{name}" as a new ingredient | **stays** | The match picker's add-new row. It makes a vocabulary row. Rule: food. |
| 20 | `features/import/presentation/recon_resolver.dart:161` | Find or create ingredient | **stays** | The button on an unmatched review line that opens #18 when there are no candidates. Boundary: it finds a food for a recipe line. |

### Planned bare items

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 21 | `features/planning/presentation/recipe_picker_sheet.dart:223` | Search recipes and ingredients | Search recipes and foods | The Add a meal / Had instead picker. A pick from the vocabulary plans a bare item. Rule: food. |
| 22 | `features/planning/presentation/recipe_picker_sheet.dart:177` | INGREDIENTS | FOODS | The same picker's section header over the vocabulary hits. Rule: food. |
| 23 | `features/planning/domain/planning.dart:270` | (deleted ingredient) | (deleted food) | A bare meal whose row is gone: the Week, the week's cost and macros, Health, and Ask's cards and tool results. Rule: food. |

### Shop

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 24 | `features/shopping/presentation/shop_add_field.dart:242` | "{words}" as a new ingredient | "{words}" as a new food | The shop's add field, add-new row. Rule: food. |
| 25 | `features/shopping/domain/shopping.dart:901` | (unknown ingredient) | (unknown food) | A shop row whose vocabulary row is missing. Rule: food. |
| 26 | `features/shopping/presentation/shopping_view.dart:758` | {name} · ingredient removed · pick again in the {recipe/plan} | recipe: {name} · ingredient removed · pick again in the recipe; plan: {name} · food removed · pick again in the plan | The shop's note on a retired row. One string for two sites: a recipe line (`recipe`) and a planned bare item (`plan`). Rule: ingredient for `recipe`, food for `plan`, so the string would split. |
| 27 | `features/shopping/presentation/shopping_view.dart:1495` | add ingredients to a recipe | **stays** | The empty list's link when the week's recipes have no lines. Rule: ingredient (named in the brief). |

### Import review

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 28 | `features/import/presentation/recon_line_card.dart:217` and `domain/work_queue.dart:20` | Match an ingredient | **stays** | A review line's attention label and the work queue's group. Rule: ingredient (named in the brief). |
| 29 | `features/import/presentation/recon_line_card.dart:216` | Match an ingredient — or link your recipe | Match an ingredient or link your recipe | The same label when a recipe is on offer. Carries an em dash the copy pass left. Rule: ingredient. |
| 30 | `features/import/presentation/recon_line_card.dart:527` | Match an ingredient first | **stays** | Under the notes field of an unmatched line. Rule: ingredient. |
| 31 | `features/import/presentation/recon_line_card.dart:189` | {name} has no piece weight yet — set it on the ingredient, or pick a unit below. | {name} has no piece weight yet. Set it on the food, or pick a unit below. | A matched line counted in pieces whose row has no piece weight. "The ingredient" here is the vocabulary row, not the line. Carries an em dash. Rule: food. |
| 32 | `features/import/presentation/reconciliation_view.dart:123` and `wide_review_view.dart:613` | Ingredients | **stays** | The review's section header over the lines (phone and wide). Rule: ingredient. |
| 33 | `features/import/presentation/reconciliation_view.dart:321` | ingredient | **stays** | The `＋ ingredient` button that adds a line to the reviewed recipe. Rule: ingredient. |
| 34 | `features/import/domain/import_stage.dart:56–57` | Matching ingredients… / Ingredients matched | **stays** | The import's progress stages. It matches the recipe's lines against the vocabulary. Boundary. |

### Receipts

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 35 | `features/receipts/domain/receipt_review.dart:44` | Match an ingredient | Match a food | A receipt line's attention label. A receipt line is a thing bought, not a line of a recipe. Rule: food. |

### Recipe lines

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 36 | `features/recipes/presentation/recipe_view.dart:184` and `:369` | Ingredients | **stays** | The recipe page's tab (phone) and column heading (wide). Rule: ingredient. |
| 37 | `features/recipes/presentation/recipe_editor_view.dart:346` | INGREDIENTS | **stays** | The editor's section head over the lines. Rule: ingredient. |
| 38 | `features/recipes/presentation/recipe_editor_view.dart:511` | Add ingredient | **stays** | The editor's add-a-line button. Rule: ingredient. |
| 39 | `features/planning/presentation/week_variant_editor.dart:160` | Add ingredient | **stays** | Week mode's add-a-line button (a this-week line of a recipe). Rule: ingredient. |
| 40 | `features/planning/presentation/meal_editor_sheet.dart:140` | Ingredients | **stays** | The meal editor's micro-label over the door into week mode, for a recipe meal. Rule: ingredient. |
| 41 | `features/recipes/presentation/ingredient_line.dart:507` and `shared/incomplete_macros.dart:62` | ingredient removed · pick again | **stays** | A recipe line whose row was deleted (tag on the line; the line's note in the macro panel). Rule: ingredient (named in the brief). `incompleteLineNote` is also drawn on a bare meal (#45). |
| 42 | `shared/incomplete_macros.dart:36` | {n} ingredient(s) removed | **stays** | A recipe's incomplete-macros note: lines whose row was deleted. Also on a recipe meal in the Week and the picker. Rule: ingredient. |
| 43 | `shared/incomplete_macros.dart:21`, `shared/cost_words.dart:121`, `recipe_macro_panel.dart:373`, `recipe_cost_panel.dart:155` | no ingredients yet / No ingredients yet | **stays** | A recipe with no lines: its macro and cost panels, and the notes on a recipe meal. Rule: ingredient. |
| 44 | `features/recipes/presentation/method_line_picker.dart:147` | Add an ingredient to this recipe | **stays** | The method chip sheet's door to add a line. Rule: ingredient. |
| 45 | `features/recipes/presentation/method_editor.dart:320` | ingredient | **stays** | The method toolbar's `＋ ingredient` (chips a line). Rule: ingredient. |
| 46 | `features/recipes/presentation/method_editor.dart:364` | To ingredient | **stays** | The text-selection menu item that turns words into a line's chip. Rule: ingredient. |
| 47 | `shared/method_step_text.dart:285` | ingredient | **stays** | A method chip whose line has no name. Rule: ingredient. |
| 48 | `features/recipes/domain/recipe_rows.dart:177` | (unknown ingredient) | **stays** | A recipe line whose row is missing. Rule: ingredient. |
| 49 | `features/share/page/share_page.dart:89` and `:99` | Ingredients | **stays** | The public share page's heading over a recipe's (and a component's) lines. Rule: ingredient (named in the brief). |
| 50 | `features/share/page/share_page.dart:253` | No nutrition total. Some ingredients have no data. | **stays** | The share page's macros section. Rule: ingredient. |

### Shared by recipe lines and bare items

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 51 | `shared/incomplete_macros.dart:59` | stub ingredient | stub | Why one line's macros are left out. Drawn on a recipe line (recipe page, macro panel), and on a bare meal (Week macros, meal editor). Boundary: a recipe line's row is a stub, or a planned food is. One string serves both. |
| 52 | `shared/incomplete_macros.dart:60` | not in your ingredients yet | not in your foods yet | Same sites as #51. "Your ingredients" names the vocabulary (the manager), not the lines. Rule: food. |

### Ask

Ask's own card and sheet print no `ingredient`. It reaches the user through
#23 on a proposal card. The rest is model-facing, and the model's replies
borrow its words.

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 53 | `features/ask/presentation/ask_figures.dart:54`, `:57`, `:115` | (#41–#43, #51, #52) | follows #41–#43, #51, #52 | The `no_figure` reasons in Ask's tool results are the shared helpers above, so they follow those rulings. |
| 54 | `features/ask/domain/ask_proposal.dart:335`, `ask_tool_runner.dart:404`, `ask_figures_wiring.dart:201` | there is no ingredient with the id `{id}` | there is no food with the id `{id}` | A refused tool call, in words the model can repeat. Model-facing. |
| 55 | `features/ask/domain/ask_week_tools.dart:261` | no ingredient matches | no food matches | The `find_ingredient` tool's note. Model-facing. |
| 56 | `supabase/functions/_shared/prompts/ask.ts` (lines 21, 64, 77, 99, 110, 112, 144, 219–221, 306, 337, 354, 420) | ingredient, ingredients | food for the vocabulary, ingredient for a recipe's lines (see below) | Ask's system prompt and tool descriptions, outside `app/lib`. The model's replies to the user follow this vocabulary. Tool names (`find_ingredient`) and parameter names are identifiers and stay. |

### Settings and other

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 57 | `shared/dropped_write_subject.dart:94` | An ingredient | A food | The name a refused write's row shows in the sync banner's list when the row itself cannot be found. Rule: food. |
| 58 | `shared/dropped_write_subject.dart:77` | ingredient edit | food edit | The kind line under each refused write in the sync banner's list (`ingredient edit · 14:02`). Rule: food. |

Settings (`features/account`) prints no `ingredient`. Nothing to rule.

## What moved with the strings

- **The Ask prompt.** `supabase/functions/_shared/prompts/ask.ts` says *food*
  where it means a vocabulary row: the meal-resolution order (*else a food*), a
  meal of one food and its usual amount, *recipes or foods* in the limits, the
  `week` tool's kind list, `find_ingredient` (*the household's foods*) and
  `prices` (*a food's latest purchases*). A recipe's lines, a bare ingredient
  question about the recipe on screen, and every tool, parameter and stored
  value name (`find_ingredient`, `ingredient_id`, `ingredient`, kind
  `ingredient`) stay. No test or eval fixture pins the prose. The function
  needs a redeploy for the model to see it.
- **Tests.** 21 files under `app/test` and one under `app/integration_test`
  (`support/library.dart`, the shelf finder) quote a new string. The
  integration tests' other quotes (the editor's *Add an ingredient*, the
  review's *Match an ingredient* and *INGREDIENTS*, the match picker's *as a
  new ingredient*) are on strings that stay.
- **The share page's bundle** compiles `shared/incomplete_macros.dart` in,
  but none of its changed strings: a fresh `dart compile js` is
  byte-identical to the committed `share_page.js`, so nothing is rebuilt.
- **Specs and READMEs.** `product-spec.md` gains one bullet under *Ingredient*
  saying which word each place uses, and names the Foods manager, the Foods
  shelf, the picker's FOODS section, the shop's add-new row, the name refusal,
  the stub note and the split removed note in their new words.
  `features/ingredients`, `features/books` and `features/shopping` READMEs
  follow. `import-and-matching.md` names the review's strings, which stay.
- **Board.** Frames redrawn in `library.html`, `ingredients-manager.html`
  (now *Foods manager*), `ingredient-detail.html` (now *Food detail*),
  `ingredient-picker.html` and `recipe-editor.html` (the line picker's add-new
  row), `recipe-picker-confirm.html`, `cook-shop.html`, `receipts.html`,
  `recipe-page.html` and `week.html` (the stub note), `import-review.html`
  (the two em dashes) and `not-built.html` (the receipt columns' tag).
  `navigation.html` is unchanged: no tab, rail or sidebar names the
  vocabulary. No view's date was bumped: the views dated 2026-10-28 were
  already read today, and the older ones (`library`, `recipe-page`,
  `recipe-editor`, `ingredient-picker`, the Week's planned part) were not
  re-read whole, so their dates stay as they were.

## Approach

1. Inventory (done, above).
2. The owner rules each row's **New** (done, 2026-10-28).
3. Apply the ruled strings in `app/lib`, on top of the session branch's deep
   links in `features/recipes` and `features/cook_plan`.
4. Move the tests, the specs, the READMEs, the board and the Ask prompt.
5. `make analyze`, then the full `flutter test` once.

## Decision log

- 2026-10-28 — The inventory is taken first and the owner rules each row,
  rather than an agent applying the proposed contexts rule.
- 2026-10-28 — Exception text (`StateError`, `ArgumentError`) is out of scope:
  `describeFailure` never prints it, so no user reads it.
- 2026-10-28 — **The owner's rulings, made interactively** (the **New**
  column). *Food* for the manager and its shelf, the detail page and form, the
  vocabulary picker, a receipt line ("it's a purchase"), a planned bare item,
  the shop's add-new row and rows, the lookups, the sync banner, and Ask's
  vocabulary. *Ingredient* for a recipe's lines, the line picker, and the
  import review with its match picker. The shop's removed note splits by
  where the row came from. `stub ingredient` becomes plain `stub`, and `not in
  your ingredients yet` becomes `not in your foods yet`. The import review's
  piece-weight hint says *the food*, because the row it means is the food. The
  two em dashes the copy pass left (#29, #31) go by the copy rules.
- 2026-10-28 — **The shared picker footer and empty list say *food*
  everywhere.** `AddNewIngredientRow`'s default (`can’t find it? add "{name}"
  as a new food`) and the result list's `No foods yet.` were ruled with the
  vocabulary picker, and the line picker uses both defaults, so the line
  picker reads *Add an ingredient* / *Search ingredients* over a footer that
  makes a new food. That is literally true (the footer makes a vocabulary
  row), and a per-host wording would have been new code for no ruling. The
  import match picker keeps its own `create "{name}" as a new ingredient`, as
  ruled.
- 2026-10-28 — `Match an ingredient — or link your recipe` becomes `Match an
  ingredient or link your recipe`: one thought with two answers reads better
  as one fragment than as two sentences.
- 2026-10-28 — The line picker's footer and empty state stay ingredient, as
  ruled.

## Notes / open questions

- Line numbers in the inventory are as of `9cf6915`; the session branch moved
  some lines in `features/recipes` since.
- The detail board's frames draw no title over the form, where the app prints
  `Food`. That gap predates this plan and is left as it was.

## Verification

2026-10-28, on the worktree branch over the session branch's deep links:

- `make analyze`: clean (`dart analyze` and `custom_lint`).
- `cd app && flutter test`: all 4404 passed, 18 skipped.
- `make docs-check`: OK (the warnings are older plans' dates and the
  backlog's date density, none from this plan).
- Not run: `make test-sim` (no simulator here), and the edge-function tests
  (`deno` is not installed). No edge test pins the prompt prose.

## Step-done checklist

- [ ] Roadmap row updated: one line on what shipped.
- [ ] `ARCHITECTURE.md`'s standing table matches reality for every area touched.
- [ ] `app/AGENTS.md` "Current focus" and command list still true.
- [ ] `make test-sim` run on a booted simulator (the integration tests quote
      these strings), and the result recorded here.
- [x] The Ask function redeployed, so the model reads the new prompt (deploy-supabase 40836577803, 2026-10-29).
- [x] The backlog row *Foods, not ingredients* removed.
- [ ] `make ci` green.
