# Exec plan: a copy pass — fewer, plainer words

- **Status:** draft — the table below waits on the owner's ruling
- **Owner:** agent
- **Roadmap step:** none — the backlog row [*A copy pass*](../backlog.md)
- **Created:** 2026-10-28

## Goal

Every screen prints only what a person needs to act. A sentence that explains
the app's internals, repeats what the layout already shows, or reassures
("nothing is saved until…") is cut. What is left reads as if a person wrote it.
Errors, refusals and the honest-number reasons (`incomplete`, `at least`, `not
counted`) stay, said shorter.

## The rules the table applies

1. **Drop the why.** "— a figure here would be a fabrication", "— that is the
   row's fact, so the door goes to the row". The user needs the state, not the
   argument for it.
2. **Drop words that name the code.** *row*, *door*, *basis*, *denomination*,
   *family*, *derive*, *the one map*. Say *ingredient*, *recipe*, *weight*.
3. **Drop the reassurance.** "Nothing is saved until you tap Save." The Save
   button says that.
4. **Drop the tap hint.** "· tap to include this week" — the control is a
   button; a screen reader already says so.
5. **Keep the refusal, shorten it.** "Enter all four macros, or none." still
   says why Save is off.

## The table

`{x}` is an interpolated value. **drop** means the string goes and nothing
replaces it. Rows are ordered by screen, then by file. Strings not listed stay
as they are.

### App-wide (sync banner, errors, macro and cost notes)

| # | Where | Old | New |
|---|---|---|---|
| 1 | `shared/sync_banner.dart:37` | {n} changes have been waiting since {time}. Ansi keeps trying. | {n} changes waiting since {time}. |
| 2 | `shared/sync_banner.dart:61` | A {thing} was refused and won’t sync. It’s still on this phone. | A {thing} was refused. It’s only on this phone. |
| 3 | `shared/sync_banner.dart:62` | The oldest was a {thing}. They’re still on this phone. | Oldest: a {thing}. They’re only on this phone. |
| 4 | `shared/sync_banner.dart:101` | The server refused these writes outright, so Ansi stopped trying rather than wedge everything behind them. They are still on this phone, and they are not on the other one. Re-saving what they changed is what puts them back. | The server refused these. They’re only on this phone — save them again to retry. |
| 5 | `shared/describe_failure.dart:26` | the local database didn’t answer — this is on the phone, not the network | the phone’s database didn’t answer |
| 6 | `shared/describe_failure.dart:28` | the data came back in a shape Ansi didn’t expect | the server sent something unexpected |
| 7 | `shared/incomplete_macros.dart:123` | Imprecise and optional lines are left out by rule, not by failure. | Imprecise and optional lines aren’t counted. |

### Shop

| # | Where | Old | New |
|---|---|---|---|
| 8 | `shopping_view.dart:460` | nothing to trace — an item you added by hand | added by hand |
| 9 | `shopping_view.dart:1491` | nothing to sum yet — {week} has meals, but their recipes list no ingredients | {week}’s recipes have no ingredients yet |
| 10 | `shopping_view.dart:1493` | nothing to buy for {week} yet — the list is summed from the cook plan | nothing to buy for {week} yet |
| 11 | `shopping_view.dart:1543` | This non-food item will be removed from the list. | **drop** (title already asks “Remove {item}?”) |
| 12 | `shopping_view.dart:1544` | This removes {item} and your top-up from the list. | Your top-up goes too. |
| 13 | `shop_add_field.dart:231` | no amount · it just gets ticked | no amount |
| 14 | `shop_add_field.dart:245` | opens the ingredient form, then its amount | **drop** |
| 15 | `shopping/domain/shopping.dart:565–797` | not counted (measure beside non-count unit "{unit}") | not counted (bad unit “{unit}”) |

### Week

| # | Where | Old | New |
|---|---|---|---|
| 16 | `copy_last_week.dart:137–139` | {n} recipes' this-week changes were left behind / {named}. Last week's meals came over; last week's changes did not. Open one and edit for this week if you want it again. | This-week edits weren’t copied / {named} |
| 17 | `household_section.dart:126` | Every week you have planned moves to match. A {day} meal joins the week that starts on it, and the rest of the week keeps its days. Nothing is deleted. | Planned weeks move to match. Nothing is deleted. |
| 18 | `household_section.dart:197` | needs a connection · it moves weeks on both phones at once | needs a connection |
| 19 | `household_section.dart:199` | the week you plan, cook and shop — a {day} shop covers that {day}’s dinner | **drop** |
| 20 | `household_section.dart:214` | a meal for {who} counts as {n} — the cook plan, the shop and the macro lens all read it that way | a meal for {who} counts as {n} |
| 21 | `meal_fields.dart:336` | left empty — the meal fills its slot, and the day says it was not counted | optional — not counted if empty |
| 22 | `meal_fields.dart:340` | kcal, protein, carb and fat are one panel — a partial one is not stated, and will not be saved | fill in all four, or none |
| 23 | `meal_fields.dart:343` | counted in the day and the week, as stated | **drop** |
| 24 | `meal_fields.dart:484` | defaults to eaters — bump up for big appetites | from who’s eating |
| 25 | `meal_fields.dart:573` | {recipe} already cooks {day}; {target} is past the fridge window ({n} days), but it freezes — a share goes to the freezer, so it still joins {day}’s batch instead of a second cook. | Joins {day}’s batch — frozen, as {target} is past {n} days. |
| 26 | `meal_fields.dart:578` | {recipe} already cooks {target} — this meal joins that batch instead of a second cook. | Joins {target}’s batch. |
| 27 | `meal_fields.dart:580` | {recipe} already cooks {day} and keeps {n} days — {target} is inside that window, so this joins {day}’s batch instead of a second cook. | Joins {day}’s batch (keeps {n} days). |
| 28 | `recipe_picker_sheet.dart:303` | new recipe — build it from scratch | new recipe |
| 29 | `recipe_picker_sheet.dart:406` | Already this week — cook it in the same batch | Already this week |
| 30 | `week_macro_widgets.dart:449` | avg {kcal} kcal/day over the {n} days that counted | avg {kcal} kcal/day · {n} days |
| 31 | `week_macro_widgets.dart:494` | no meals yet — nothing to add up | no meals yet |
| 32 | `week_macro_widgets.dart:544` | This is the sum of what is planned, not a daily target — a week that only plans dinners averages a dinner. | **drop** |
| 33 | `week_variant_format.dart:21–22` | a change covers every day this week[ — {named}] | applies to every day this week[ — {named}] |
| 34 | `week_variant_format.dart:34` | {week} · every day that plans it cooks these lines | {week} · every day |
| 35 | `week_variant_format.dart:35` | {week} · {named} both cook these lines | {week} · {named} |
| 36 | `week_variant_format.dart:85` | from the recipe · not edited here: serves {n} · … | from the recipe: serves {n} · … |
| 37 | `week_variant_editor.dart:225` | The recipe is not changed. | **drop** (“for this week only” already says it) |
| 38 | `week_variant_editor.dart:547` + `ingredient_line.dart:447–448` (screen-reader labels) | optional · tap to include this week / included this week · tap to leave it out | optional / included this week |

### Cook

| # | Where | Old | New |
|---|---|---|---|
| 39 | `cook_view.dart:148` | grouped by recipe · split by shelf life | **drop** |
| 40 | `cook_view.dart:736` | nothing planned for {week} yet — the batches are worked out from the meals you put on the week | nothing planned for {week} yet |
| 41 | `cook_format.dart:34` | cook ×{f} instead — covers {n} · {m} left over · shopping still buys ×{r} | cook ×{f} — {n}, {m} spare · shop buys ×{r} |
| 42 | `cook_format.dart:134` | A batch makes {x} and {day} needs {y} — the rest is yours. Nothing here tracks the leftover. | A batch makes {x}; {day} needs {y}. The rest is spare. |
| 43 | `cook_format.dart:202` | Set its yield and this session gets a scale. Until then there is no honest number to put here. | Set its yield to get a scale. |
| 44 | `cook_format.dart:205` | The line is in {volume} and the yield only says {weight}. State a second denomination in that family — two stated facts, not an invented bridge. | The line is in {volume}; the yield is in {weight}. Add a {volume} yield. |
| 45 | `cook_format.dart:210` | Set an amount on that line and this session gets a scale. Until then there is no honest number to put here. | Set an amount on that line to get a scale. |
| 46 | `cook_format.dart:213` | The number is kept; what it counted is not. Say that line’s amount again, in a measure {recipe} still has. | Re-enter that line’s amount in a measure {recipe} still has. |
| 47 | `cook_format.dart:216` | A recipe cannot be built from itself. Change one of the links and the plan can derive it again. | A recipe can’t contain itself. Change one of the links. |
| 48 | `cook_format.dart:231` | A later meal falls past the {n} window — cook it again, fresh. | A later meal is past {n} — cook again. |
| 49 | `cook_format.dart:390` | showing the whole batch — tap for the honest ×{f} | whole batch · tap for ×{f} |

### Recipe page and editor

| # | Where | Old | New |
|---|---|---|---|
| 50 | `recipe_cost_panel.dart:156` | A cost arrives once this recipe has ingredients. | No ingredients yet. |
| 51 | `recipe_cost_panel.dart:159` | Every line is imprecise or optional, so there is nothing to price — a figure here would be a fabrication. | Nothing to price — every line is imprecise or optional. |
| 52 | `recipe_cost_panel.dart:167` | What the priced lines come to, at prices from {month} — a floor, not the cost: the lines named below can only add to it. | Priced lines only ({month} prices). The lines below add to it. |
| 53 | `recipe_cost_panel.dart:170` | Left out until every line has a price — a figure short of one of them would not be this recipe. | Shown once every line has a price. |
| 54 | `recipe_macro_panel.dart:392` | Macros arrive once this recipe has ingredients. | No ingredients yet. |
| 55 | `recipe_macro_panel.dart:394` | Every line is imprecise, so nothing was weighed — a total here would be a fabrication, not a number. | Every line is imprecise — nothing to count. |
| 56 | `recipe_macro_panel.dart:396` | Left out of the total until every line resolves — a partial number would not be this recipe. | Shown once every line resolves. |
| 57 | `recipe_view.dart:871` | This removes it from your recipes. | **drop** (title says “Delete recipe?”) |
| 58 | `recipe_header_form.dart:196` | · optional · what you call one of these | · optional |
| 59 | `recipe_header_form.dart:226` | hands-on and on the heat | **drop** |
| 60 | `recipe_header_form.dart:337` | the second slot only offers the other families — two ways of saying one batch, never two numbers in one family | **drop** |
| 61 | `recipe_header_form.dart:552` | Drives the batch cook plan — how far apart the same dish can be planned before it becomes two things to cook. | Meals further apart are cooked twice. |
| 62 | `recipe_measures_editor.dart:172` | No measures yet — a component line can still say “0.5 batch”. | No measures yet. |
| 63 | `recipe_measures_editor.dart:233` | one of them, weighed — another recipe can then say “3 blob” of this one | e.g. 1 blob = 30 g |
| 64 | `recipe_editor_view.dart:163` | That Save didn’t land | Couldn’t save |
| 65 | `recipe_editor_view.dart:1173` | Remove those chips too? Their words stay in the sentences — only the links go. | Remove those chips too? The words stay. |
| 66 | `method_chip_sheet.dart:153` | The first time a step calls for something, its chip shows the amount. After that it’s the same stuff, so the chip just names it. | **drop** |
| 67 | `method_editor.dart:677` | {n} ingredient chips and {m} timers become ordinary words. Every sentence reads exactly the same — only the links go. | {n} chips and {m} timers become plain text. |
| 68 | `method_editor.dart:684` | Chips are written at import, or added one at a time from a selection. Nothing on the phone can re-chip a method — matching is online-only, and only at import. | **drop** (“This can’t be undone here” stays, as “This can’t be undone.”) |
| 69 | `method_editor.dart:733` | Their chips now read {new}. The words around them may need a look — we don’t rewrite your sentences. | Their chips now read {new}. Check the wording around them. |
| 70 | `method_line_picker.dart:87` | A chip can only point at a line this recipe already has. | **drop** |
| 71 | `method_line_picker.dart:109` | Nothing in this recipe matches “{q}”. Add it below, or pick a line. | No line matches “{q}”. |
| 72 | `component_format.dart:103` | nothing to be a share of · MAKES states no {weight} yield | needs a {weight} yield under MAKES |
| 73 | `component_format.dart:115` | {words} have nothing left to be a share of after this. Nothing is deleted — but every line saying them goes unresolved until MAKES says what a batch comes to in the same kind of unit again. | Lines using {words} stop resolving until MAKES has a {weight} yield again. |
| 74 | `recipe_measure_delete.dart:58` | Change {lines} first — a measure that goes leaves every line saying it unresolved for good. | Change {lines} first. |
| 75 | `recipe_measure_delete.dart:127` + `measure_delete.dart:108` | {n} weeks say it in their own amount — that is not a recipe, so there is no page to send you to | {n} weeks use it too. |
| 76 | `component_quantity_sheet.dart:351` + `quantity_unit_sheet.dart:460` | left out of macros and the shop list, and named where it left | not counted in macros or the shop list |
| 77 | `component_quantity_sheet.dart:401` | Say how many — a measure counts something. | Enter how many. |
| 78 | `component_quantity_sheet.dart:406` | This line’s measure is gone from that recipe — pick a chip to say it again. | That measure was deleted — pick another. |
| 79 | `line_card.dart:365–366` (screen-reader label) | optional · tap to make it required / not optional · tap to mark it optional | optional / required |
| 80 | `recipe_measure_authoring.dart:161` | A measure is a share of a batch. Say what a batch makes first, under MAKES. | Set what a batch makes (MAKES) first. |
| 81 | `recipe_measure_authoring.dart:166` | A measure needs a name — what you call one of these. | Give the measure a name. |
| 82 | `recipe_measure_authoring.dart:170` | “{label}” is already a unit. Call the measure something else, like “blob”. | “{label}” is already a unit — pick another name. |
| 83 | `recipe_measure_authoring.dart:174` | “{label}” is already a measure here, at {x}. Re-state that one instead. | “{label}” already exists ({x}). Edit that one. |
| 84 | `recipe_measure_authoring.dart:179` | Say what one “{label}” comes to — a number above zero. | Enter how much one “{label}” is. |
| 85 | `recipe_measure_authoring.dart:186` | {fact}. Say what one “{label}” comes to as a weight, a volume or a count. | {fact}. Use a weight, volume or count. |
| 86 | `recipe_measure_authoring.dart:197` | This recipe makes {x}, and a recipe has no density to say “{label}” in {unit}. Add what a batch makes in {unit} under MAKES. | This recipe makes {x}. Add a {unit} yield under MAKES to use {unit}. |

### Import

| # | Where | Old | New |
|---|---|---|---|
| 87 | `import_view.dart:197` | Paste a recipe link, or import from photos. We read the ingredients and steps, then you confirm each match — nothing is guessed for you. | Paste a link, or add photos. |
| 88 | `photo_doors.dart:40` | In a browser the pages go up as they are — cropping and rotating is a phone job. Photograph the page there, or choose a file here. | No cropping in a browser. Photograph on the phone, or choose a file. |
| 89 | `reconciliation_view.dart:121` | the page didn’t say a number — set one, or leave it unset. Nothing is invented, and a yield-less recipe still saves, links and scales; only the derived numbers wait. | not on the page — optional |
| 90 | `reconciliation_view.dart:125` | the page didn’t say what this makes — set it, or leave it unset. Nothing is invented, and a yield-less recipe still saves, links and scales. | not on the page — optional |
| 91 | `recon_line_card.dart:149` | removed — this line will not be saved | removed |
| 92 | `recon_line_card.dart:527` | Match an ingredient first — then the amount and notes unlock. | Match an ingredient first. |
| 93 | `recon_line_card.dart:537` | linked — no ingredient match needed, no allowed-units gate. Valid for Save the moment its amount is set. | linked recipe — set an amount |
| 94 | `wide_review_view.dart:409` | the page’s own text did not come back with this import — the lines below are what we read out of it, and each one still carries the words it was read from. | Page text unavailable. |
| 95 | `wide_review_view.dart:513` | this line, as the page printed it | as printed |
| 96 | `wide_review_view.dart:802` | every item above is a flag already drawn on its row, read from the one map the header count and Save read | **drop** |
| 97 | `wide_review_view.dart:804` | nothing here is saved until Save, exactly as on the phone | **drop** |
| 98 | `wide_review_view.dart:869` | nothing is waiting on you — every line is matched, its amount is set and its unit is one the row can carry. | All lines ready. |
| 99 | `wide_review_view.dart:884` | {name} has no piece weight yet — that is the row’s fact, so the door goes to the row. Every other bare count of it clears with it. | {name} has no piece weight yet. Setting it fixes every line. |
| 100 | `wide_review_view.dart:904` | it saves as it stands and is out of the count — a stub is a real, plannable line with numbers it has not got yet. It surfaces in the Ingredients manager’s stub band. | Saves as a stub — fill it in later under Ingredients. |

### Receipts

| # | Where | Old | New |
|---|---|---|---|
| 101 | `receipt_scan_view.dart:25` | Photograph the receipt. A long one goes in two or three shots, top to bottom, overlapping a few lines. | Photograph the receipt. A long one: a few overlapping shots, top to bottom. |
| 102 | `receipt_ledger_view.dart:95` | no receipts yet — a scanned shop files here by week; a price typed on an ingredient stays on the ingredient | no receipts yet |
| 103 | `receipt_ledger_view.dart:156` | in a browser there is no camera and no crop step — shoot the receipt on the phone, and review it anywhere | scan receipts on the phone |
| 104 | `receipt_pack_sheet.dart:228` | The pack carries over either way. Keep one you would say on a recipe or a shopping list, with its size in it: “can (14.5 oz)”. | Keep it if you’d use it in a recipe or list, e.g. “can (14.5 oz)”. |
| 105 | `receipt_pack_sheet.dart:242` | this row already says “{word}” at this weight — the line will point at it | “{word}” already exists at this weight — using it |
| 106 | `receipt_pack_sheet.dart:278–279` | keeping the pack as a measure · tap to stop / not kept as a measure · tap to keep it | kept as a measure / not kept |
| 107 | `receipt_line_card.dart:224` | low confidence — check this one against the paper | check against the receipt |
| 108 | `receipt_review_body.dart:234` | the paper printed no date — this is the scan day | no date printed — scan day |
| 109 | `receipt_review_body.dart:235` | the receipt’s own date, not the scan’s | **drop** |
| 110 | `receipt_review.dart:438` | ×{n} on this receipt — an answer here answers them all | ×{n} on this receipt |
| 111 | `receipt_review.dart:582` | {x} apart · Find the join — a line is missing, doubled or misread | {x} off — a line is missing, doubled or misread |

### Ingredients

| # | Where | Old | New |
|---|---|---|---|
| 112 | `ingredient_list_view.dart:314` | No ingredients yet — the vocabulary arrives with your household’s first sync. | No ingredients yet. |
| 113 | `ingredient_list_view.dart:363` | add an ingredient — by hand, or scan a barcode | add an ingredient |
| 114 | `ingredient_list_view.dart:547` | Pick a row to read what it says. | Pick an ingredient. |
| 115 | `ingredient_picker.dart:242` | Too few letters to guess from — try spelling it out. | Type a bit more. |
| 116 | `ingredient_detail_view.dart:401, 1249` | ALLOWED UNITS — what a line may say | ALLOWED UNITS (hint **drop**) |
| 117 | `ingredient_detail_view.dart:413, 1280` | MEASURES — count-like, in the basis | MEASURES (hint **drop**) |
| 118 | `ingredient_detail_view.dart:485–488` | Price — after the first save / A price is an event on a row, and this one does not exist yet. | Price / Save the ingredient first. |
| 119 | `ingredient_detail_view.dart:505` | a price is written as you enter it; Save below is for the fields | prices save as you add them |
| 120 | `ingredient_detail_view.dart:549, 584` | what a recipe reads | used for costs |
| 121 | `ingredient_detail_view.dart:550` | read when no receipt prices it | used when no receipt has it |
| 122 | `ingredient_detail_view.dart:597` | a recipe reads the latest; the rest is what you paid, kept as paid | **drop** |
| 123 | `ingredient_detail_view.dart:742` | what the receipt door remembers — not words this row is also known as; fix one on its own receipt, where the latest answer wins | names matched on receipts — fix one on its receipt |
| 124 | `ingredient_detail_view.dart:190` | This ingredient is gone — it was deleted on another device. | Deleted on another device. |
| 125 | `ingredient_detail_view.dart:929` | {name} is already in your ingredients. Nothing you have typed here is saved. | {name} already exists. |
| 126 | `ingredient_detail_view.dart:1124` | as the label reads · fibre optional | fibre optional |
| 127 | `ingredient_detail_view.dart:1557` | {fields} — the numbers on this row are no longer the source’s | {fields} edited |
| 128 | `ingredient_detail_view.dart:1583` | renaming this row will not refill it — you said no once | **drop** |
| 129 | `ingredient_detail_view.dart:1659` | read from a photo — check it against the label | check against the label |
| 130 | `ingredient_detail_view.dart:1762` | filled in, not saved — Save keeps it, and nothing counts until you confirm. | filled in — not saved |
| 131 | `ingredient_detail_view.dart:1764` | nothing to fill in — every field it could answer already had an answer. | nothing new to fill in |
| 132 | `ingredient_detail_view.dart:1778` | pack added below — rename it or bin it there. | pack added below |
| 133 | `ingredient_detail_view.dart:1850` | {unit} stays on — the row is bought in it | {unit} stays on — it’s bought in it |
| 134 | `ingredient_detail_view.dart:2128` | That alias carries no identity word — it would match everything and nothing. | Too generic for an alias. |
| 135 | `ingredient_detail_view.dart:2473` | New — nothing is saved until you tap Save. | **drop** |
| 136 | `ingredient_detail_view.dart:2475` | Still a stub — left out of macro totals until confirmed. | Stub — not in macro totals |
| 137 | `ingredient_detail_view.dart:2476` | Complete — counts in conversions and macro totals. | **drop** |
| 138 | `ingredient_view_models.dart:44` | One serving is how much? The label’s figures become per 100 only once the serving amount is typed. | Enter the serving size. |
| 139 | `ingredient_view_models.dart:362` | A name is the one field an ingredient can’t go without. | Give it a name. |
| 140 | `ingredient_view_models.dart:370` | Which aisle is it in? Pick a category — an uncategorised row sorts ahead of every aisle, and words like pinch and handful are earned by one. | Pick a category. |
| 141 | `ingredient_view_models.dart:375` | Enter all four macros, or leave them all blank — a part of a panel isn’t a panel. | Enter all four macros, or none. |
| 142 | `ingredient_view_models.dart:379` | Fibre is an extra figure on a panel, not a panel of its own — give it a number beside the four, or clear it. | Fibre needs the other four macros. |
| 143 | `ingredient_view_models.dart:389` | Macros per 100 {basis} and no density can’t have {unit} as the default unit — add a density below, or make it {fix}. | No density, so {unit} can’t be the default — add one, or use {fix}. |
| 144 | `ingredient_view_models.dart:395` | Piece can’t be the default unit with nothing weighing one — enter what one weighs below, or make it {fix}. | Piece needs a piece weight to be the default — add one, or use {fix}. |
| 145 | `ingredient_view_models.dart:413, 420` | saving it / completing it counts it in conversions and macro totals | **drop** |
| 146 | `ingredient_view_models.dart:1060` | Undone — the label’s figures are off the form, and nothing was saved. | Undone. |
| 147 | `ingredient_view_models.dart:1170` | Filled from “{food}” — nothing is saved until you tap Save. | Filled from “{food}”. |
| 148 | `ingredient_view_models.dart:1198` | Not this food — the pick is off the form, and nothing was saved. | Cleared. |
| 149 | `ingredient_view_models.dart:1212` | Cleared — the USDA numbers are gone, and a rename will not bring them back. | USDA numbers cleared. |
| 150 | `ingredient_view_models.dart:1360` | Back to a stub — it stops counting until you complete it again. | Back to a stub. |
| 151 | `ingredient_facts.dart:269` | this row has no density, so a volume pack cannot be weighed — set one on the ingredient, or say the pack in {unit} | no density — give the pack in {unit} |
| 152 | `ingredient_facts.dart:272` | this row does not say what one piece weighs — set a piece weight, or say the pack in {unit} | no piece weight — give the pack in {unit} |
| 153 | `ingredient_facts.dart:275` | an imprecise word cannot be priced — say the pack in {unit} | can’t price that — give the pack in {unit} |
| 154 | `density_entry.dart:181` | one side is a volume and the other a weight — “1 cup weighs 240 g”, or “30 ml weighs 1 oz” | a volume and a weight, e.g. 1 cup = 240 g |
| 155 | `density_entry.dart:183` + `piece_weight_entry.dart:76` + `measures_editor.dart:155, 405` | weigh it: {x} and what it weighs must both be positive / … must be a positive number | must be above zero |
| 156 | `density_entry.dart:323` | your serving, ready to use — type what that much weighs (the pack’s “(32 g)”) | what one serving weighs, e.g. 32 g |
| 157 | `density_entry.dart:326, 328` | both halves come from the pack’s serving line — check them against it / then tap {Save} | from the pack — check it |
| 158 | `density_entry.dart:430` + `piece_weight_entry.dart:241` | Remove it? Nothing about what a line may say changes. | Remove it? |
| 159 | `density_entry.dart:431` + `piece_weight_entry.dart:242` | Remove it? {units} lock again[, and a count of this stops joining totals]. | Remove it? {units} won’t be usable. |
| 160 | `piece_weight_entry.dart:89` + `measures_editor.dart:467` | this row has no density, so {unit} cannot become {base} — say it in {base}, or state a density first | no density — use {base}, or add a density |
| 161 | `piece_weight_entry.dart:121` | none yet — what one of these weighs | none yet |
| 162 | `measures_editor.dart:148, 398` | “{name}” is a unit — that mapping is the density; enter it in the density section and the {unit} chip unlocks | “{name}” is a unit — set it as the density |
| 163 | `measures_editor.dart:277` | saved as yours — synced & editable | **drop** |
| 164 | `measure_delete.dart:49` | Change them to another unit first — deleting it now would quietly drop those lines out of every total. | Change them to another unit first. |
| 165 | `measure_authoring.dart:24` | “{label}” is already {x} on this row, and this pack is {y}. Put the size in the name, like “{label} ({y})”. | “{label}” is already {x}. Name this one “{label} ({y})”. |
| 166 | `price_sheet.dart:201` | A cost then reads only what a receipt says was paid. Receipts stay as they are. | Costs will use receipt prices only. |
| 167 | `serving_row.dart:171` | stored per 100 {g} — once the four are in | per 100 {g} — needs all four |
| 168 | `serving_row.dart:173` | stored per 100 {g}: needs the serving amount | per 100 {g} — needs the serving size |
| 169 | `serving_row.dart:197` | the pack printed it per serving? switch to per serving and type it as read | label per serving? switch to per serving |
| 170 | `draft_card.dart:31` | Nothing came back for {code} — the name and the macros are all a barcode was going to fill in. Type them here. | Nothing found for {code}. Type the name and macros. |
| 171 | `draft_card.dart:69` | panel read per 100 {g} — stored as the basis, not converted | per 100 {g} |
| 172 | `draft_card.dart:87` | No macros came with this product — fill them in on the next screen. | No macros for this product. |
| 173 | `draft_card.dart:110` | panel read per serving{says} — type the serving weight and the row stores per 100 | per serving{says} — enter the serving weight |
| 174 | `draft_card.dart:115` | panel read per serving of {x}{says} — stored per 100 {g} | per serving of {x}{says} |
| 175 | `usda_pick_sheet.dart:76` | picking one fills density + macros from it and names it on the form — still a stub until you confirm | fills density and macros |
| 176 | `usda_pick_sheet.dart:123` | nothing came back for “{name}” — offline, or nothing close enough. The server runs the same lookup when the row syncs up. | No match for “{name}” (or offline). |
| 177 | `label_photo_door.dart:28` | one photo of the nutrition panel — a screenshot counts | a photo or screenshot of the nutrition panel |

### Barcode scan

| # | Where | Old | New |
|---|---|---|---|
| 178 | `barcode_scan_sheet.dart:139` | a barcode is 8 to 14 digits — the small ones printed beside the bars count too | 8 to 14 digits |
| 179 | `barcode_scan_sheet.dart:317` | Camera access is turned off for Ansi. Turn it on in Settings, or type the barcode below — both end in the same place. | Camera access is off. Turn it on in Settings, or type the barcode. |
| 180 | `barcode_scan_sheet.dart:320` | No camera is available here. Type the barcode below — it ends in the same place. | No camera here. Type the barcode. |
| 181 | `barcode_scan_sheet.dart:386` | Nobody has added this product yet. Add it by hand — the name and macros are the only parts a barcode was going to fill in anyway. | Add it by hand. |
| 182 | `barcode_scan_sheet.dart:391` | The lookup needs a connection. Everything else on the form works offline and syncs when you're back. | Needs a connection. Try again, or add it by hand. |
| 183 | `barcode_scan_sheet.dart:395–396` | Open Food Facts turned us away / It limits how often it will answer. Wait a moment and try again, or fill the form in by hand. | Open Food Facts is busy / Try again in a moment, or add it by hand. |
| 184 | `barcode_scan_sheet.dart:401` | This isn't a missing product — the answer came back in a shape we do not understand. Try again, or fill the form in by hand. | Try again, or add it by hand. |
| 185 | `ingredient_draft.dart:39` | Open Food Facts holds this panel per serving, not per 100 — type the serving weight from the pack and the row stores per 100. | Per serving only — enter the serving weight from the pack. |

### Library, settings, Ask, share

| # | Where | Old | New |
|---|---|---|---|
| 186 | `library_view.dart:940` | A book is a shelf — name it whatever you call it out loud. | **drop** |
| 187 | `book_rows.dart:221` | This is your only book — every recipe needs a shelf. | You can’t delete your only book. |
| 188 | `book_rows.dart:266` | The shelf is empty, so nothing goes with it. | It’s empty. |
| 189 | `book_pick_sheet.dart:73` | Pick a shelf. Their sections stay behind. | Sections aren’t moved. |
| 190 | `account_view.dart:106` | This removes the synced data from this device. It stays in your household and comes back when you sign in again. | Your data stays in the household and returns when you sign in. |
| 191 | `ask_controller.dart:167` | Ansi took too many steps over that — try asking it more simply. | That took too many steps — try a simpler question. |
| 192 | `ask_sheet.dart:184` | Asking about nothing on screen | **drop** |
| 193 | `share_actions.dart:65` | Anyone who opens the link will find nothing there. Sharing again makes a new link. | The link will stop working. |
| 194 | `share_page.dart:253` | No nutrition total: some ingredients in this recipe have no nutrition data yet, and a partial sum would mislead. | No nutrition total — some ingredients have no data. |

## Out of scope

- **Ask Ansi's tool results** (`features/ask/domain/`) — read by the model, not
  printed, so their wording is tuned for it.
- **Developer-facing messages** — asserts, `StateError`s, `toString`s.
- **The word *ingredient*** — that is the backlog's *Foods, not ingredients*,
  which this pass runs ahead of.

## Approach

1. The owner rules on the table: keep, change the wording, or overrule a drop.
2. Apply it screen by screen, one commit per section. Each string's widget and
   structural tests move with it (`find.text` matches the exact string).
3. Read the board's frames for the same strings; a frame that quotes an old
   string is redrawn, and its status date bumped only after re-verifying.
4. `make analyze` + `make test` + `make docs-check` once, then `make test-sim`
   before landing.

## Decision log

- 2026-10-28 — Table drafted from every user-visible string of seven or more
  words under `app/lib`, plus the short hints beside them. Ask's tool results
  and developer messages are excluded (see *Out of scope*).
