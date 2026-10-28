# Exec plan: foods, not ingredients

- **Status:** draft — the inventory is taken; the owner rules each row before any string changes
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

## The proposed rule (not yet the ruling)

The brief proposed this contexts rule. The owner has asked to rule each row
in the table below themselves, so it is recorded here as the proposal the
table was read against, not as the ruling.

- **Says "food":** the vocabulary manager (the shelf that opens it, its title,
  its empty state, its add door), the detail page and form of one row, a
  planned bare item, the pickers (search, "add as a new …", "can't find it?"),
  the barcode, USDA and label lookups, the shop's "add as a new …", Ask Ansi's
  user-facing text, settings.
- **Stays "ingredient":** anything about a recipe's own lines: "Add
  ingredient" in the recipe editor, a recipe's ingredient list or tab, "Match
  an ingredient" on an import review line, "ingredient removed · pick again"
  on a recipe line, "add ingredients to a recipe".
- **On the boundary:** is this about a line of a recipe? Yes: "ingredient".
  No: "food". Plurals and capitals follow the original ("Ingredients" →
  "Foods", "ingredient" → "food").

## Acceptance criteria

- [ ] Every row in the inventory has the owner's ruling in its **New** column.
- [ ] The ruled strings are changed in `app/lib`, and nothing else is renamed.
- [ ] Every test in `app/test` and `app/integration_test` that quotes a
      changed string quotes the new one.
- [ ] `docs/product-specs/product-spec.md` and `import-and-matching.md` name
      the screens and actions as the app prints them.
- [ ] The board frames that print a changed string are redrawn, and each
      view's date is bumped only after reading it against `app/lib`.
- [ ] The copy rules of [plan 0057](./0057-copy-pass.md) hold for every new
      string: fragments, no em dashes, no semicolons, no explanations.
- [ ] `make analyze` clean, the full `flutter test` green.

## The inventory

Taken 2026-10-28 on `9cf6915`, from every `ingredient`, `ingredients`,
`Ingredient`, `Ingredients` and `INGREDIENTS` printed by `app/lib`. Left out:
identifiers, routes, SQL, table and column names, `StateError`,
`ArgumentError` and `assert` text (none reaches a screen:
`describeFailure` never prints an exception's message), and doc comments.

`{x}` is an interpolated value. **pending** waits for the owner's ruling. The
context column ends with what the proposed rule would say, for the owner to
accept or overrule. Paths are under `app/lib/`.

### The manager and its shelf

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 1 | `features/books/presentation/library_view.dart:895` | INGREDIENTS | pending | The Library's shelf after the books, the only door to the manager (phone ledger and wide ledger alike). No nav tab, rail or sidebar item names the vocabulary. Rule: food. |
| 2 | `features/books/presentation/library_view.dart:865` | {n} ingredient(s) | pending | The shelf's count line, beside `{n} stubs`. Rule: food. |
| 3 | `features/ingredients/presentation/ingredient_list_view.dart:185` | Ingredients | pending | The manager's header title. Rule: food. |
| 4 | `features/ingredients/presentation/ingredient_list_view.dart:313` | No ingredients yet | pending | The manager's empty state. Rule: food. |
| 5 | `features/ingredients/presentation/ingredient_list_view.dart:357` | add an ingredient | pending | The manager's add door. Rule: food. |
| 6 | `features/ingredients/presentation/ingredient_list_view.dart:541` | Pick an ingredient | pending | The empty detail pane at expanded width. Rule: food. |

### The detail page and form of one row

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 7 | `features/ingredients/presentation/ingredient_detail_view.dart:183` | Ingredient | pending | The header title of the form (new and edit) on a pushed page. Rule: food. |
| 8 | `features/ingredients/presentation/ingredient_detail_view.dart:1357` | Delete ingredient | pending | The `⋯` menu item on the detail page. Rule: food. |
| 9 | `features/ingredients/domain/name_namespace.dart:21` | Already an ingredient: {name} | pending | The form's note under the name field, and the save's refusal. Rule: food. |
| 10 | `features/ingredients/presentation/quantity_unit_sheet.dart:220` | this ingredient’s measures | pending | The quantity sheet's error state (`Couldn’t load this ingredient’s measures.`). The sheet opens from a recipe line, a week line, the shop and a bare meal. Boundary: it is the row's measures, not the line's. Rule: food. |

The barcode, USDA and label lookups print no `ingredient` today (`USDA · for
“{name}”`, `Read a label`, `Filled from a barcode · …`). Nothing to rule.

### The pickers

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 11 | `features/ingredients/presentation/ingredient_picker.dart:126` | Search ingredients | pending | The vocabulary picker's field. Opened from the receipt review (`What is this line?`, a receipt line's match and its add-a-line door). Rule: food. |
| 12 | `features/ingredients/presentation/ingredient_picker.dart:37` | Add an ingredient | pending | The vocabulary picker's default title. Both callers pass their own title, so it is never seen today. Rule: food. |
| 13 | `features/ingredients/presentation/ingredient_picker.dart:199` | INGREDIENTS | pending | The section header over the vocabulary hits when a second section (recipes) follows. Drawn in the recipe editor's line picker (#16). Boundary: the hits are foods, the pick becomes a line. Rule: food. |
| 14 | `features/ingredients/presentation/ingredient_picker.dart:235` | No ingredients yet. | pending | Every picker's empty list. Rule: food. |
| 15 | `features/ingredients/presentation/ingredient_picker.dart:467` | can’t find it? add "{name}" as a new ingredient | pending | The add-new row at a picker's foot: the receipt picker, the recipe editor's and week mode's line picker. Rule: food. |
| 16 | `features/recipes/presentation/line_target_picker.dart:67` and `recipe_editor_view.dart:602` | Add an ingredient | pending | The line picker's title. Opened from the recipe editor's Add ingredient, the import review's `＋ ingredient`, the method editor's `＋ ingredient` (a line to chip) and week mode's Add ingredient. Boundary: what is added is a line of the recipe. Rule: ingredient. |
| 17 | `features/recipes/presentation/line_target_picker.dart:184` | Search ingredients | pending | The same picker's field. It searches the vocabulary and the recipes. Boundary: it searches foods, to add a line. Rule: unclear, either reading holds. |
| 18 | `features/import/presentation/recon_resolver.dart:440` | Search ingredients | pending | The import review's match picker (`Match "{line}"`). Searches the vocabulary for one review line. Boundary as #17. |
| 19 | `features/import/presentation/recon_resolver.dart:463` | create "{name}" as a new ingredient | pending | The match picker's add-new row. It makes a vocabulary row. Rule: food. |
| 20 | `features/import/presentation/recon_resolver.dart:161` | Find or create ingredient | pending | The button on an unmatched review line that opens #18 when there are no candidates. Boundary: it finds a food for a recipe line. |

### Planned bare items

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 21 | `features/planning/presentation/recipe_picker_sheet.dart:223` | Search recipes and ingredients | pending | The Add a meal / Had instead picker. A pick from the vocabulary plans a bare item. Rule: food. |
| 22 | `features/planning/presentation/recipe_picker_sheet.dart:177` | INGREDIENTS | pending | The same picker's section header over the vocabulary hits. Rule: food. |
| 23 | `features/planning/domain/planning.dart:270` | (deleted ingredient) | pending | A bare meal whose row is gone: the Week, the week's cost and macros, Health, and Ask's cards and tool results. Rule: food. |

### Shop

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 24 | `features/shopping/presentation/shop_add_field.dart:242` | "{words}" as a new ingredient | pending | The shop's add field, add-new row. Rule: food. |
| 25 | `features/shopping/domain/shopping.dart:901` | (unknown ingredient) | pending | A shop row whose vocabulary row is missing. Rule: food. |
| 26 | `features/shopping/presentation/shopping_view.dart:758` | {name} · ingredient removed · pick again in the {recipe/plan} | pending | The shop's note on a retired row. One string for two sites: a recipe line (`recipe`) and a planned bare item (`plan`). Rule: ingredient for `recipe`, food for `plan`, so the string would split. |
| 27 | `features/shopping/presentation/shopping_view.dart:1495` | add ingredients to a recipe | pending | The empty list's link when the week's recipes have no lines. Rule: ingredient (named in the brief). |

### Import review

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 28 | `features/import/presentation/recon_line_card.dart:217` and `domain/work_queue.dart:20` | Match an ingredient | pending | A review line's attention label and the work queue's group. Rule: ingredient (named in the brief). |
| 29 | `features/import/presentation/recon_line_card.dart:216` | Match an ingredient — or link your recipe | pending | The same label when a recipe is on offer. Carries an em dash the copy pass left. Rule: ingredient. |
| 30 | `features/import/presentation/recon_line_card.dart:527` | Match an ingredient first | pending | Under the notes field of an unmatched line. Rule: ingredient. |
| 31 | `features/import/presentation/recon_line_card.dart:189` | {name} has no piece weight yet — set it on the ingredient, or pick a unit below. | pending | A matched line counted in pieces whose row has no piece weight. "The ingredient" here is the vocabulary row, not the line. Carries an em dash. Rule: food. |
| 32 | `features/import/presentation/reconciliation_view.dart:123` and `wide_review_view.dart:613` | Ingredients | pending | The review's section header over the lines (phone and wide). Rule: ingredient. |
| 33 | `features/import/presentation/reconciliation_view.dart:321` | ingredient | pending | The `＋ ingredient` button that adds a line to the reviewed recipe. Rule: ingredient. |
| 34 | `features/import/domain/import_stage.dart:56–57` | Matching ingredients… / Ingredients matched | pending | The import's progress stages. It matches the recipe's lines against the vocabulary. Boundary. |

### Receipts

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 35 | `features/receipts/domain/receipt_review.dart:44` | Match an ingredient | pending | A receipt line's attention label. A receipt line is a thing bought, not a line of a recipe. Rule: food. |

### Recipe lines

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 36 | `features/recipes/presentation/recipe_view.dart:184` and `:369` | Ingredients | pending | The recipe page's tab (phone) and column heading (wide). Rule: ingredient. |
| 37 | `features/recipes/presentation/recipe_editor_view.dart:346` | INGREDIENTS | pending | The editor's section head over the lines. Rule: ingredient. |
| 38 | `features/recipes/presentation/recipe_editor_view.dart:511` | Add ingredient | pending | The editor's add-a-line button. Rule: ingredient. |
| 39 | `features/planning/presentation/week_variant_editor.dart:160` | Add ingredient | pending | Week mode's add-a-line button (a this-week line of a recipe). Rule: ingredient. |
| 40 | `features/planning/presentation/meal_editor_sheet.dart:140` | Ingredients | pending | The meal editor's micro-label over the door into week mode, for a recipe meal. Rule: ingredient. |
| 41 | `features/recipes/presentation/ingredient_line.dart:507` and `shared/incomplete_macros.dart:62` | ingredient removed · pick again | pending | A recipe line whose row was deleted (tag on the line; the line's note in the macro panel). Rule: ingredient (named in the brief). `incompleteLineNote` is also drawn on a bare meal (#45). |
| 42 | `shared/incomplete_macros.dart:36` | {n} ingredient(s) removed | pending | A recipe's incomplete-macros note: lines whose row was deleted. Also on a recipe meal in the Week and the picker. Rule: ingredient. |
| 43 | `shared/incomplete_macros.dart:21`, `shared/cost_words.dart:121`, `recipe_macro_panel.dart:373`, `recipe_cost_panel.dart:155` | no ingredients yet / No ingredients yet | pending | A recipe with no lines: its macro and cost panels, and the notes on a recipe meal. Rule: ingredient. |
| 44 | `features/recipes/presentation/method_line_picker.dart:147` | Add an ingredient to this recipe | pending | The method chip sheet's door to add a line. Rule: ingredient. |
| 45 | `features/recipes/presentation/method_editor.dart:320` | ingredient | pending | The method toolbar's `＋ ingredient` (chips a line). Rule: ingredient. |
| 46 | `features/recipes/presentation/method_editor.dart:364` | To ingredient | pending | The text-selection menu item that turns words into a line's chip. Rule: ingredient. |
| 47 | `shared/method_step_text.dart:285` | ingredient | pending | A method chip whose line has no name. Rule: ingredient. |
| 48 | `features/recipes/domain/recipe_rows.dart:177` | (unknown ingredient) | pending | A recipe line whose row is missing. Rule: ingredient. |
| 49 | `features/share/page/share_page.dart:89` and `:99` | Ingredients | pending | The public share page's heading over a recipe's (and a component's) lines. Rule: ingredient (named in the brief). |
| 50 | `features/share/page/share_page.dart:253` | No nutrition total. Some ingredients have no data. | pending | The share page's macros section. Rule: ingredient. |

### Shared by recipe lines and bare items

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 51 | `shared/incomplete_macros.dart:59` | stub ingredient | pending | Why one line's macros are left out. Drawn on a recipe line (recipe page, macro panel), and on a bare meal (Week macros, meal editor). Boundary: a recipe line's row is a stub, or a planned food is. One string serves both. |
| 52 | `shared/incomplete_macros.dart:60` | not in your ingredients yet | pending | Same sites as #51. "Your ingredients" names the vocabulary (the manager), not the lines. Rule: food. |

### Ask

Ask's own card and sheet print no `ingredient`. It reaches the user through
#23 on a proposal card. The rest is model-facing, and the model's replies
borrow its words.

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 53 | `features/ask/presentation/ask_figures.dart:54`, `:57`, `:115` | (#41–#43, #51, #52) | pending | The `no_figure` reasons in Ask's tool results are the shared helpers above, so they follow those rulings. |
| 54 | `features/ask/domain/ask_proposal.dart:335`, `ask_tool_runner.dart:404`, `ask_figures_wiring.dart:201` | there is no ingredient with the id `{id}` | pending | A refused tool call, in words the model can repeat. Model-facing. |
| 55 | `features/ask/domain/ask_week_tools.dart:261` | no ingredient matches | pending | The `find_ingredient` tool's note. Model-facing. |
| 56 | `supabase/functions/_shared/prompts/ask.ts` (lines 21, 64, 77, 99, 110, 112, 144, 219–221, 306, 337, 354, 420) | ingredient, ingredients | pending | Ask's system prompt and tool descriptions, outside `app/lib`. The model's replies to the user follow this vocabulary. Tool names (`find_ingredient`) and parameter names are identifiers and stay. |

### Settings and other

| # | Where | Old | New | Context |
|---|---|---|---|---|
| 57 | `shared/dropped_write_subject.dart:94` | An ingredient | pending | The name a refused write's row shows in the sync banner's list when the row itself cannot be found. Rule: food. |
| 58 | `shared/dropped_write_subject.dart:77` | ingredient edit | pending | The kind line under each refused write in the sync banner's list (`ingredient edit · 14:02`). Rule: food. |

Settings (`features/account`) prints no `ingredient`. Nothing to rule.

## What the rulings will move

Once the **New** column is filled, the same change moves:

- **Tests.** Some forty files under `app/test` and `app/integration_test`
  quote one of these strings; the heaviest are
  `test/features/import/recon_line_card_test.dart`,
  `test/features/books/library_view_test.dart`,
  `integration_test/recipe_editor_test.dart` and
  `integration_test/support/editor.dart`. Each is found by its string after
  the ruling, not from this list.
- **Specs.** `docs/product-specs/product-spec.md` and
  `docs/product-specs/import-and-matching.md` where they name a screen or an
  action as the user sees it.
- **Board.** `ingredients-manager.html`, `ingredient-detail.html`,
  `ingredient-picker.html`, `library.html` (the shelf), `week.html` and
  `recipe-picker-confirm.html` (bare items), `cook-shop.html` (the shop's add
  field), `receipts.html`, `errors-sync.html`, and `import-review.html` if a
  boundary row there changes. `navigation.html` only if a rail or sidebar
  label changes; none names the vocabulary today.

## Approach

1. Inventory (done, above).
2. The owner rules each row's **New**.
3. Apply the ruled strings in `app/lib`. In `features/recipes` and
   `features/cook_plan` only string literals change.
4. Move the tests, the specs and the board in the same commits as the strings.
5. `make analyze`, then the full `flutter test` once.

## Decision log

- 2026-10-28 — The inventory is taken first and the owner rules each row,
  rather than an agent applying the proposed contexts rule. The rule is kept
  above as the proposal each row was read against.
- 2026-10-28 — Exception text (`StateError`, `ArgumentError`) is out of scope:
  `describeFailure` never prints it, so no user reads it.

## Notes / open questions

- Rows #17, #18, #20 and #34 search or match foods for a recipe's line. They
  are where the proposed rule is least clear.
- Rows #26 and #51 are one string serving a recipe line and a bare item. A
  split ruling splits the string.
- Rows #29 and #31 carry em dashes the copy pass left. A ruling that touches
  them is the moment to drop the dash.

## Step-done checklist

- [ ] Roadmap row updated: one line on what shipped.
- [ ] `ARCHITECTURE.md`'s standing table matches reality for every area touched.
- [ ] `app/AGENTS.md` "Current focus" and command list still true.
- [ ] `make test-sim` run on a booted simulator (the integration tests quote
      these strings), and the result recorded here.
- [ ] The backlog row *Foods, not ingredients* removed.
- [ ] `make ci` green.
