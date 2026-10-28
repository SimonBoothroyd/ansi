# Exec plan: a copy pass — fewer, plainer words

- **Status:** draft — the table below waits on the owner's ruling
- **Owner:** agent
- **Roadmap step:** none — the backlog row [*A copy pass*](../backlog.md)
- **Created:** 2026-10-28

## Goal

Every screen prints only what a person needs to act. What is left reads as if
a person wrote it. Errors, refusals and the honest-number words (`incomplete`,
`at least`, `not counted`) stay, said shorter.

## The rules the table applies

1. **Drop first.** If the layout, the title or the button already says it, the
   string goes.
2. **A fragment, not a sentence.** `No ingredients yet`, not `A cost arrives
   once this recipe has ingredients.`
3. **No em dashes, no semicolons, no "X, so Y".** One thought per string. If a
   second one is needed, it is a second short sentence.
4. **No why.** Say the state or the fix, never the reasoning behind it.
5. **No words from the code.** *row*, *door*, *basis*, *denomination*, *family*.
6. **No tap hints or reassurance.** "tap to include", "nothing is saved until
   you tap Save".

## The table

`{x}` is an interpolated value. **drop** means the string goes and nothing
replaces it. Strings not listed stay as they are.

### App-wide

| # | Where | Old | New |
|---|---|---|---|
| 1 | `shared/sync_banner.dart:37` | {n} changes have been waiting since {time}. Ansi keeps trying. | {n} changes not synced since {time} |
| 2 | `shared/sync_banner.dart:61` | A {thing} was refused and won’t sync. It’s still on this phone. | A {thing} didn’t sync. It’s only on this phone. |
| 3 | `shared/sync_banner.dart:62` | The oldest was a {thing}. They’re still on this phone. | They’re only on this phone. |
| 4 | `shared/sync_banner.dart:101` | The server refused these writes outright, so Ansi stopped trying rather than wedge everything behind them. They are still on this phone, and they are not on the other one. Re-saving what they changed is what puts them back. | Save them again to retry. |
| 5 | `shared/describe_failure.dart:26` | the local database didn’t answer — this is on the phone, not the network | phone storage error |
| 6 | `shared/describe_failure.dart:28` | the data came back in a shape Ansi didn’t expect | unexpected reply from the server |
| 7 | `shared/incomplete_macros.dart:123` | Imprecise and optional lines are left out by rule, not by failure. | **drop** |

### Shop

| # | Where | Old | New |
|---|---|---|---|
| 8 | `shopping_view.dart:460` | nothing to trace — an item you added by hand | added by hand |
| 9 | `shopping_view.dart:1491` | nothing to sum yet — {week} has meals, but their recipes list no ingredients | these recipes have no ingredients |
| 10 | `shopping_view.dart:1493` | nothing to buy for {week} yet — the list is summed from the cook plan | nothing to buy yet |
| 11 | `shopping_view.dart:1543` | This non-food item will be removed from the list. | **drop** |
| 12 | `shopping_view.dart:1544` | This removes {item} and your top-up from the list. | Your top-up goes too. |
| 13 | `shop_add_field.dart:231` | no amount · it just gets ticked | no amount |
| 14 | `shop_add_field.dart:245` | opens the ingredient form, then its amount | **drop** |
| 15 | `shopping/domain/shopping.dart:565–797` | not counted (measure beside non-count unit "{unit}") | not counted (bad unit) |

### Week

| # | Where | Old | New |
|---|---|---|---|
| 16 | `copy_last_week.dart:137–139` | {n} recipes' this-week changes were left behind — {named}. Last week's meals came over; last week's changes did not. Open one and edit for this week if you want it again. | This-week edits not copied: {named} |
| 17 | `household_section.dart:126` | Every week you have planned moves to match. A {day} meal joins the week that starts on it, and the rest of the week keeps its days. Nothing is deleted. | Your planned weeks will shift to match. |
| 18 | `household_section.dart:197` | needs a connection · it moves weeks on both phones at once | needs a connection |
| 19 | `household_section.dart:199` | the week you plan, cook and shop — a {day} shop covers that {day}’s dinner | **drop** |
| 20 | `household_section.dart:214` | a meal for {who} counts as {n} — the cook plan, the shop and the macro lens all read it that way | {who} eats {n} |
| 21 | `meal_fields.dart:336` | left empty — the meal fills its slot, and the day says it was not counted | optional |
| 22 | `meal_fields.dart:340` | kcal, protein, carb and fat are one panel — a partial one is not stated, and will not be saved | fill in all four or none |
| 23 | `meal_fields.dart:343` | counted in the day and the week, as stated | **drop** |
| 24 | `meal_fields.dart:484` | defaults to eaters — bump up for big appetites | **drop** |
| 25 | `meal_fields.dart:573` | {recipe} already cooks {day}; {target} is past the fridge window ({n} days), but it freezes — a share goes to the freezer, so it still joins {day}’s batch instead of a second cook. | Cooked {day}, then frozen. |
| 26 | `meal_fields.dart:578` | {recipe} already cooks {target} — this meal joins that batch instead of a second cook. | Cooked with {target}’s batch. |
| 27 | `meal_fields.dart:580` | {recipe} already cooks {day} and keeps {n} days — {target} is inside that window, so this joins {day}’s batch instead of a second cook. | Cooked with {day}’s batch. |
| 28 | `recipe_picker_sheet.dart:303` | new recipe — build it from scratch | new recipe |
| 29 | `recipe_picker_sheet.dart:406` | Already this week — cook it in the same batch | Already this week |
| 30 | `week_macro_widgets.dart:449` | avg {kcal} kcal/day over the {n} days that counted | avg {kcal} kcal/day ({n} days) |
| 31 | `week_macro_widgets.dart:494` | no meals yet — nothing to add up | no meals yet |
| 32 | `week_macro_widgets.dart:544` | This is the sum of what is planned, not a daily target — a week that only plans dinners averages a dinner. | **drop** |
| 33 | `week_variant_format.dart:21–22` | a change covers every day this week[ — {named}] | every day this week |
| 34 | `week_variant_format.dart:34` | {week} · every day that plans it cooks these lines | {week} · every day |
| 35 | `week_variant_format.dart:35` | {week} · {named} both cook these lines | {week} · {named} |
| 36 | `week_variant_format.dart:85` | from the recipe · not edited here: serves {n} · … | from the recipe: serves {n} · … |
| 37 | `week_variant_editor.dart:225` | The recipe is not changed. | **drop** |
| 38 | `week_variant_editor.dart:547` + `ingredient_line.dart:447–448` (screen reader) | optional · tap to include this week / included this week · tap to leave it out | optional / included |

### Cook

| # | Where | Old | New |
|---|---|---|---|
| 39 | `cook_view.dart:148` | grouped by recipe · split by shelf life | **drop** |
| 40 | `cook_view.dart:736` | nothing planned for {week} yet — the batches are worked out from the meals you put on the week | nothing planned yet |
| 41 | `cook_format.dart:34` | cook ×{f} instead — covers {n} · {m} left over · shopping still buys ×{r} | cook ×{f} · {m} spare |
| 42 | `cook_format.dart:134` | A batch makes {x} and {day} needs {y} — the rest is yours. Nothing here tracks the leftover. | Makes {x}. {day} needs {y}. |
| 43 | `cook_format.dart:202` | Set its yield and this session gets a scale. Until then there is no honest number to put here. | Set its yield. |
| 44 | `cook_format.dart:205` | The line is in {volume} and the yield only says {weight}. State a second denomination in that family — two stated facts, not an invented bridge. | Add a {volume} yield. |
| 45 | `cook_format.dart:210` | Set an amount on that line and this session gets a scale. Until then there is no honest number to put here. | Add an amount to that line. |
| 46 | `cook_format.dart:213` | The number is kept; what it counted is not. Say that line’s amount again, in a measure {recipe} still has. | Pick another measure for that line. |
| 47 | `cook_format.dart:216` | A recipe cannot be built from itself. Change one of the links and the plan can derive it again. | Remove one of the links. |
| 48 | `cook_format.dart:231` | A later meal falls past the {n} window — cook it again, fresh. | Too far apart. Cooked twice. |
| 49 | `cook_format.dart:390` | showing the whole batch — tap for the honest ×{f} | whole batch · tap for ×{f} |

### Recipe page and editor

| # | Where | Old | New |
|---|---|---|---|
| 50 | `recipe_cost_panel.dart:156` | A cost arrives once this recipe has ingredients. | No ingredients yet |
| 51 | `recipe_cost_panel.dart:159` | Every line is imprecise or optional, so there is nothing to price — a figure here would be a fabrication. | Nothing to price |
| 52 | `recipe_cost_panel.dart:167` | What the priced lines come to, at prices from {month} — a floor, not the cost: the lines named below can only add to it. | Some lines have no price |
| 53 | `recipe_cost_panel.dart:170` | Left out until every line has a price — a figure short of one of them would not be this recipe. | Some lines have no price |
| 54 | `recipe_macro_panel.dart:392` | Macros arrive once this recipe has ingredients. | No ingredients yet |
| 55 | `recipe_macro_panel.dart:394` | Every line is imprecise, so nothing was weighed — a total here would be a fabrication, not a number. | Every line is imprecise |
| 56 | `recipe_macro_panel.dart:396` | Left out of the total until every line resolves — a partial number would not be this recipe. | Some lines can’t be counted |
| 57 | `recipe_view.dart:871` | This removes it from your recipes. | **drop** |
| 58 | `recipe_header_form.dart:196` | · optional · what you call one of these | · optional |
| 59 | `recipe_header_form.dart:226` | hands-on and on the heat | **drop** |
| 60 | `recipe_header_form.dart:337` | the second slot only offers the other families — two ways of saying one batch, never two numbers in one family | **drop** |
| 61 | `recipe_header_form.dart:552` | Drives the batch cook plan — how far apart the same dish can be planned before it becomes two things to cook. | **drop** |
| 62 | `recipe_measures_editor.dart:172` | No measures yet — a component line can still say “0.5 batch”. | No measures yet |
| 63 | `recipe_measures_editor.dart:233` | one of them, weighed — another recipe can then say “3 blob” of this one | e.g. 1 blob = 30 g |
| 64 | `recipe_editor_view.dart:163` | That Save didn’t land | Couldn’t save |
| 65 | `recipe_editor_view.dart:1173` | Remove those chips too? Their words stay in the sentences — only the links go. | Remove their chips too? |
| 66 | `method_chip_sheet.dart:153` | The first time a step calls for something, its chip shows the amount. After that it’s the same stuff, so the chip just names it. | **drop** |
| 67 | `method_editor.dart:677` | {n} ingredient chips and {m} timers become ordinary words. Every sentence reads exactly the same — only the links go. | Removes {n} chips and {m} timers. |
| 68 | `method_editor.dart:682–684` | This can’t be undone here / Chips are written at import, or added one at a time from a selection. Nothing on the phone can re-chip a method — matching is online-only, and only at import. | Can’t be undone. |
| 69 | `method_editor.dart:733` | Their chips now read {new}. The words around them may need a look — we don’t rewrite your sentences. | Chips renamed to {new}. |
| 70 | `method_line_picker.dart:87` | A chip can only point at a line this recipe already has. | **drop** |
| 71 | `method_line_picker.dart:109` | Nothing in this recipe matches “{q}”. Add it below, or pick a line. | No match for “{q}” |
| 72 | `component_format.dart:103` | nothing to be a share of · MAKES states no {weight} yield | needs a {weight} yield |
| 73 | `component_format.dart:115` | {words} have nothing left to be a share of after this. Nothing is deleted — but every line saying them goes unresolved until MAKES says what a batch comes to in the same kind of unit again. | Lines using {words} will stop working. |
| 74 | `recipe_measure_delete.dart:58` | Change {lines} first — a measure that goes leaves every line saying it unresolved for good. | Change {lines} first. |
| 75 | `recipe_measure_delete.dart:127` + `measure_delete.dart:108` | {n} weeks say it in their own amount — that is not a recipe, so there is no page to send you to | Also used in {n} weeks. |
| 76 | `component_quantity_sheet.dart:351` + `quantity_unit_sheet.dart:460` | left out of macros and the shop list, and named where it left | not counted |
| 77 | `component_quantity_sheet.dart:401` | Say how many — a measure counts something. | How many? |
| 78 | `component_quantity_sheet.dart:406` | This line’s measure is gone from that recipe — pick a chip to say it again. | Measure deleted. Pick another. |
| 79 | `line_card.dart:365–366` (screen reader) | optional · tap to make it required / not optional · tap to mark it optional | optional / required |
| 80 | `recipe_measure_authoring.dart:161` | A measure is a share of a batch. Say what a batch makes first, under MAKES. | Set what a batch makes first. |
| 81 | `recipe_measure_authoring.dart:166` | A measure needs a name — what you call one of these. | Needs a name. |
| 82 | `recipe_measure_authoring.dart:170` | “{label}” is already a unit. Call the measure something else, like “blob”. | “{label}” is already a unit. |
| 83 | `recipe_measure_authoring.dart:174` | “{label}” is already a measure here, at {x}. Re-state that one instead. | “{label}” already exists. |
| 84 | `recipe_measure_authoring.dart:179` | Say what one “{label}” comes to — a number above zero. | Must be above zero. |
| 85 | `recipe_measure_authoring.dart:186` | {fact}. Say what one “{label}” comes to as a weight, a volume or a count. | Use a weight, volume or count. |
| 86 | `recipe_measure_authoring.dart:197` | This recipe makes {x}, and a recipe has no density to say “{label}” in {unit}. Add what a batch makes in {unit} under MAKES. | Add a {unit} yield first. |

### Import

| # | Where | Old | New |
|---|---|---|---|
| 87 | `import_view.dart:197` | Paste a recipe link, or import from photos. We read the ingredients and steps, then you confirm each match — nothing is guessed for you. | Paste a link or add photos. |
| 88 | `photo_doors.dart:40` | In a browser the pages go up as they are — cropping and rotating is a phone job. Photograph the page there, or choose a file here. | Cropping only works on the phone. |
| 89 | `reconciliation_view.dart:121` | the page didn’t say a number — set one, or leave it unset. Nothing is invented, and a yield-less recipe still saves, links and scales; only the derived numbers wait. | not on the page |
| 90 | `reconciliation_view.dart:125` | the page didn’t say what this makes — set it, or leave it unset. Nothing is invented, and a yield-less recipe still saves, links and scales. | not on the page |
| 91 | `recon_line_card.dart:149` | removed — this line will not be saved | removed |
| 92 | `recon_line_card.dart:527` | Match an ingredient first — then the amount and notes unlock. | Match an ingredient first |
| 93 | `recon_line_card.dart:537` | linked — no ingredient match needed, no allowed-units gate. Valid for Save the moment its amount is set. | linked recipe |
| 94 | `wide_review_view.dart:409` | the page’s own text did not come back with this import — the lines below are what we read out of it, and each one still carries the words it was read from. | No page text |
| 95 | `wide_review_view.dart:513` | this line, as the page printed it | as printed |
| 96 | `wide_review_view.dart:802` | every item above is a flag already drawn on its row, read from the one map the header count and Save read | **drop** |
| 97 | `wide_review_view.dart:804` | nothing here is saved until Save, exactly as on the phone | **drop** |
| 98 | `wide_review_view.dart:869` | nothing is waiting on you — every line is matched, its amount is set and its unit is one the row can carry. | All lines ready |
| 99 | `wide_review_view.dart:884` | {name} has no piece weight yet — that is the row’s fact, so the door goes to the row. Every other bare count of it clears with it. | {name} needs a piece weight |
| 100 | `wide_review_view.dart:904` | it saves as it stands and is out of the count — a stub is a real, plannable line with numbers it has not got yet. It surfaces in the Ingredients manager’s stub band. | Saves as a stub |

### Receipts

| # | Where | Old | New |
|---|---|---|---|
| 101 | `receipt_scan_view.dart:25` | Photograph the receipt. A long one goes in two or three shots, top to bottom, overlapping a few lines. | Photograph the receipt. Overlap shots for a long one. |
| 102 | `receipt_ledger_view.dart:95` | no receipts yet — a scanned shop files here by week; a price typed on an ingredient stays on the ingredient | no receipts yet |
| 103 | `receipt_ledger_view.dart:156` | in a browser there is no camera and no crop step — shoot the receipt on the phone, and review it anywhere | scan receipts on your phone |
| 104 | `receipt_pack_sheet.dart:228` | The pack carries over either way. Keep one you would say on a recipe or a shopping list, with its size in it: “can (14.5 oz)”. | e.g. “can (14.5 oz)” |
| 105 | `receipt_pack_sheet.dart:242` | this row already says “{word}” at this weight — the line will point at it | uses “{word}” |
| 106 | `receipt_pack_sheet.dart:278–279` | keeping the pack as a measure · tap to stop / not kept as a measure · tap to keep it | kept as a measure / not kept |
| 107 | `receipt_line_card.dart:224` | low confidence — check this one against the paper | check this |
| 108 | `receipt_review_body.dart:234` | the paper printed no date — this is the scan day | no date, using scan date |
| 109 | `receipt_review_body.dart:235` | the receipt’s own date, not the scan’s | **drop** |
| 110 | `receipt_review.dart:438` | ×{n} on this receipt — an answer here answers them all | ×{n} on this receipt |
| 111 | `receipt_review.dart:582` | {x} apart · Find the join — a line is missing, doubled or misread | {x} off. Check for a missing or doubled line. |

### Ingredients

| # | Where | Old | New |
|---|---|---|---|
| 112 | `ingredient_list_view.dart:314` | No ingredients yet — the vocabulary arrives with your household’s first sync. | No ingredients yet |
| 113 | `ingredient_list_view.dart:363` | add an ingredient — by hand, or scan a barcode | add an ingredient |
| 114 | `ingredient_list_view.dart:547` | Pick a row to read what it says. | Pick an ingredient |
| 115 | `ingredient_picker.dart:242` | Too few letters to guess from — try spelling it out. | Keep typing |
| 116 | `ingredient_detail_view.dart:401, 1249` | ALLOWED UNITS — what a line may say | ALLOWED UNITS (hint **drop**) |
| 117 | `ingredient_detail_view.dart:413, 1280` | MEASURES — count-like, in the basis | MEASURES (hint **drop**) |
| 118 | `ingredient_detail_view.dart:485–488` | Price — after the first save / A price is an event on a row, and this one does not exist yet. | Price / Save first to add a price. |
| 119 | `ingredient_detail_view.dart:505` | a price is written as you enter it; Save below is for the fields | prices save right away |
| 120 | `ingredient_detail_view.dart:549, 584` | what a recipe reads | used for costs |
| 121 | `ingredient_detail_view.dart:550` | read when no receipt prices it | used if no receipt |
| 122 | `ingredient_detail_view.dart:597` | a recipe reads the latest; the rest is what you paid, kept as paid | **drop** |
| 123 | `ingredient_detail_view.dart:742` | what the receipt door remembers — not words this row is also known as; fix one on its own receipt, where the latest answer wins | names seen on receipts |
| 124 | `ingredient_detail_view.dart:190` | This ingredient is gone — it was deleted on another device. | Deleted on another device. |
| 125 | `ingredient_detail_view.dart:929` | {name} is already in your ingredients. Nothing you have typed here is saved. | {name} already exists. |
| 126 | `ingredient_detail_view.dart:1124` | as the label reads · fibre optional | fibre optional |
| 127 | `ingredient_detail_view.dart:1557` | {fields} — the numbers on this row are no longer the source’s | {fields} edited |
| 128 | `ingredient_detail_view.dart:1583` | renaming this row will not refill it — you said no once | **drop** |
| 129 | `ingredient_detail_view.dart:1659` | read from a photo — check it against the label | check against the label |
| 130 | `ingredient_detail_view.dart:1762` | filled in, not saved — Save keeps it, and nothing counts until you confirm. | not saved yet |
| 131 | `ingredient_detail_view.dart:1764` | nothing to fill in — every field it could answer already had an answer. | nothing new |
| 132 | `ingredient_detail_view.dart:1778` | pack added below — rename it or bin it there. | pack added below |
| 133 | `ingredient_detail_view.dart:1850` | {unit} stays on — the row is bought in it | **drop** |
| 134 | `ingredient_detail_view.dart:2128` | That alias carries no identity word — it would match everything and nothing. | Too generic. |
| 135 | `ingredient_detail_view.dart:2473` | New — nothing is saved until you tap Save. | **drop** |
| 136 | `ingredient_detail_view.dart:2475` | Still a stub — left out of macro totals until confirmed. | Stub · not in macros |
| 137 | `ingredient_detail_view.dart:2476` | Complete — counts in conversions and macro totals. | **drop** |
| 138 | `ingredient_view_models.dart:44` | One serving is how much? The label’s figures become per 100 only once the serving amount is typed. | Enter the serving size. |
| 139 | `ingredient_view_models.dart:362` | A name is the one field an ingredient can’t go without. | Needs a name. |
| 140 | `ingredient_view_models.dart:370` | Which aisle is it in? Pick a category — an uncategorised row sorts ahead of every aisle, and words like pinch and handful are earned by one. | Pick a category. |
| 141 | `ingredient_view_models.dart:375` | Enter all four macros, or leave them all blank — a part of a panel isn’t a panel. | Enter all four macros or none. |
| 142 | `ingredient_view_models.dart:379` | Fibre is an extra figure on a panel, not a panel of its own — give it a number beside the four, or clear it. | Fibre needs the other four. |
| 143 | `ingredient_view_models.dart:389` | Macros per 100 {basis} and no density can’t have {unit} as the default unit — add a density below, or make it {fix}. | {unit} needs a density. Add one or use {fix}. |
| 144 | `ingredient_view_models.dart:395` | Piece can’t be the default unit with nothing weighing one — enter what one weighs below, or make it {fix}. | Piece needs a weight. Add one or use {fix}. |
| 145 | `ingredient_view_models.dart:413, 420` | saving it / completing it counts it in conversions and macro totals | **drop** |
| 146 | `ingredient_view_models.dart:1060` | Undone — the label’s figures are off the form, and nothing was saved. | Undone |
| 147 | `ingredient_view_models.dart:1170` | Filled from “{food}” — nothing is saved until you tap Save. | Filled from “{food}” |
| 148 | `ingredient_view_models.dart:1198` | Not this food — the pick is off the form, and nothing was saved. | Cleared |
| 149 | `ingredient_view_models.dart:1212` | Cleared — the USDA numbers are gone, and a rename will not bring them back. | Cleared |
| 150 | `ingredient_view_models.dart:1360` | Back to a stub — it stops counting until you complete it again. | Back to a stub |
| 151 | `ingredient_facts.dart:269` | this row has no density, so a volume pack cannot be weighed — set one on the ingredient, or say the pack in {unit} | no density. Use {unit}. |
| 152 | `ingredient_facts.dart:272` | this row does not say what one piece weighs — set a piece weight, or say the pack in {unit} | no piece weight. Use {unit}. |
| 153 | `ingredient_facts.dart:275` | an imprecise word cannot be priced — say the pack in {unit} | can’t price that. Use {unit}. |
| 154 | `density_entry.dart:181` | one side is a volume and the other a weight — “1 cup weighs 240 g”, or “30 ml weighs 1 oz” | e.g. 1 cup = 240 g |
| 155 | `density_entry.dart:183` + `piece_weight_entry.dart:76` + `measures_editor.dart:155, 405` | weigh it: {x} and what it weighs must both be positive / … must be a positive number | must be above zero |
| 156 | `density_entry.dart:323` | your serving, ready to use — type what that much weighs (the pack’s “(32 g)”) | e.g. 32 g |
| 157 | `density_entry.dart:326, 328` | both halves come from the pack’s serving line — check them against it / then tap {Save} | from the pack, check it |
| 158 | `density_entry.dart:430` + `piece_weight_entry.dart:241` | Remove it? Nothing about what a line may say changes. | Remove it? |
| 159 | `density_entry.dart:431` + `piece_weight_entry.dart:242` | Remove it? {units} lock again[, and a count of this stops joining totals]. | Remove it? {units} will stop working. |
| 160 | `piece_weight_entry.dart:89` + `measures_editor.dart:467` | this row has no density, so {unit} cannot become {base} — say it in {base}, or state a density first | needs a density. Use {base}. |
| 161 | `piece_weight_entry.dart:121` | none yet — what one of these weighs | none yet |
| 162 | `measures_editor.dart:148, 398` | “{name}” is a unit — that mapping is the density; enter it in the density section and the {unit} chip unlocks | “{name}” is a unit. Set a density instead. |
| 163 | `measures_editor.dart:277` | saved as yours — synced & editable | **drop** |
| 164 | `measure_delete.dart:49` | Change them to another unit first — deleting it now would quietly drop those lines out of every total. | Change them to another unit first. |
| 165 | `measure_authoring.dart:24` | “{label}” is already {x} on this row, and this pack is {y}. Put the size in the name, like “{label} ({y})”. | “{label}” is taken. Try “{label} ({y})”. |
| 166 | `price_sheet.dart:201` | A cost then reads only what a receipt says was paid. Receipts stay as they are. | Costs will use receipts only. |
| 167 | `serving_row.dart:171` | stored per 100 {g} — once the four are in | needs all four |
| 168 | `serving_row.dart:173` | stored per 100 {g}: needs the serving amount | needs the serving size |
| 169 | `serving_row.dart:197` | the pack printed it per serving? switch to per serving and type it as read | label per serving? switch above |
| 170 | `draft_card.dart:31` | Nothing came back for {code} — the name and the macros are all a barcode was going to fill in. Type them here. | Not found. Enter the name and macros. |
| 171 | `draft_card.dart:69` | panel read per 100 {g} — stored as the basis, not converted | per 100 {g} |
| 172 | `draft_card.dart:87` | No macros came with this product — fill them in on the next screen. | No macros found |
| 173 | `draft_card.dart:110` | panel read per serving{says} — type the serving weight and the row stores per 100 | per serving. Enter the serving weight. |
| 174 | `draft_card.dart:115` | panel read per serving of {x}{says} — stored per 100 {g} | per serving of {x} |
| 175 | `usda_pick_sheet.dart:76` | picking one fills density + macros from it and names it on the form — still a stub until you confirm | **drop** |
| 176 | `usda_pick_sheet.dart:123` | nothing came back for “{name}” — offline, or nothing close enough. The server runs the same lookup when the row syncs up. | No match |
| 177 | `label_photo_door.dart:28` | one photo of the nutrition panel — a screenshot counts | photo or screenshot of the label |

### Barcode scan

| # | Where | Old | New |
|---|---|---|---|
| 178 | `barcode_scan_sheet.dart:139` | a barcode is 8 to 14 digits — the small ones printed beside the bars count too | 8 to 14 digits |
| 179 | `barcode_scan_sheet.dart:317` | Camera access is turned off for Ansi. Turn it on in Settings, or type the barcode below — both end in the same place. | Camera access is off. Turn it on in Settings or type the barcode. |
| 180 | `barcode_scan_sheet.dart:320` | No camera is available here. Type the barcode below — it ends in the same place. | No camera. Type the barcode. |
| 181 | `barcode_scan_sheet.dart:386` | Nobody has added this product yet. Add it by hand — the name and macros are the only parts a barcode was going to fill in anyway. | Add it by hand. |
| 182 | `barcode_scan_sheet.dart:391` | The lookup needs a connection. Everything else on the form works offline and syncs when you're back. | You’re offline. Add it by hand or try again. |
| 183 | `barcode_scan_sheet.dart:395–396` | Open Food Facts turned us away / It limits how often it will answer. Wait a moment and try again, or fill the form in by hand. | Open Food Facts is busy / Try again soon or add it by hand. |
| 184 | `barcode_scan_sheet.dart:401` | This isn't a missing product — the answer came back in a shape we do not understand. Try again, or fill the form in by hand. | Try again or add it by hand. |
| 185 | `ingredient_draft.dart:39` | Open Food Facts holds this panel per serving, not per 100 — type the serving weight from the pack and the row stores per 100. | Enter the serving weight from the pack. |

### Library, settings, Ask, share

| # | Where | Old | New |
|---|---|---|---|
| 186 | `library_view.dart:940` | A book is a shelf — name it whatever you call it out loud. | **drop** |
| 187 | `book_rows.dart:221` | This is your only book — every recipe needs a shelf. | Can’t delete your only book. |
| 188 | `book_rows.dart:266` | The shelf is empty, so nothing goes with it. | **drop** |
| 189 | `book_pick_sheet.dart:73` | Pick a shelf. Their sections stay behind. | **drop** |
| 190 | `account_view.dart:106` | This removes the synced data from this device. It stays in your household and comes back when you sign in again. | Your data comes back when you sign in. |
| 191 | `ask_controller.dart:167` | Ansi took too many steps over that — try asking it more simply. | Too complicated. Try a simpler question. |
| 192 | `ask_sheet.dart:184` | Asking about nothing on screen | **drop** |
| 193 | `share_actions.dart:65` | Anyone who opens the link will find nothing there. Sharing again makes a new link. | The link will stop working. |
| 194 | `share_page.dart:253` | No nutrition total: some ingredients in this recipe have no nutrition data yet, and a partial sum would mislead. | No nutrition total. Some ingredients have no data. |

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
- 2026-10-28 — The owner: the first draft's replacements *"still sound a
  little AI"*. Rewritten under rules 1–3: drop first, fragments over
  sentences, no em dashes or semicolons. 30 rows and two labels’ hints are now drops.
