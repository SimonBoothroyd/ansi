# Product backlog

Unbuilt product ideas — things the app could do and does not. This is not the
[tech-debt tracker](./tech-debt-tracker.md): a tracker row is a corner cut in
something that exists, a backlog row is something that does not exist yet. The
roadmap's **Next** list draws from here, and the design board's
designed-not-built appendix links the row that explains a frame.

A row marked **not planned** is a recorded refusal. It is here so nobody
re-proposes it blind, not because it is queued.

| Idea | One line | Origin | Trigger |
|---|---|---|---|
| Cook mode (+ the Notes tab) | A hands-free cooking view over the recipe's steps, and the notes tab beside it. | The design board's step-2 frames; `app/lib/features/recipes/README.md` calls it deferred | The input shape is ready — every recipe saves `methodSteps` with structured timers and derived step keys — so this is its own slice off the board's frame whenever cooking from the phone is wanted. |
| Recipe photos | A photo on the recipe hero, held in Supabase Storage rather than the database. | Deferred from step 2 as blocked on Storage + auth; unblocked by [step 7](./completed/0008-sync-layer.md) | Wanted the first time a recipe is hard to pick out of a list. |
| Per-book detail screen | A book gets a page of its own: a cover or colour (`book.color`, one migration), notes, per-book search. | Deferred from step 3, when all books rendered inline | A book wants something of its **own** — not because the list got long, which Library v2's fold already fixed. |
| Clear list / new trip | Reset the check-state and soft-delete manual top-ups so a shop starts fresh. | Deferred from step 6 to step 7, which did not ship it | Check-state and top-ups accumulate forever; wanted the first time a second trip in one week is annoying. |
| "Recipes with almonds" | Library search over a recipe's *ingredients*, transitively through `sub_recipe_id`, with a `matched: almonds` line explaining the hit. | Library v2 D2, said out loud on the board | Searching by what is in the fridge currently returns nothing rather than saying it is unsupported. Needs a ruling on whether a component's ingredients count. |
| Method-step sub-recipe chips | A step token carrying a `recipe_id`, rendered with the shipped `RecipeChip`, so "the aioli" in a method navigates. | Designed in [plan 0014](./completed/0014-import-foundation.md); nested recipes v1 links ingredient lines only | Its natural moment is cook mode, the other consumer of a step's tokens. |
| Collapse and duplicate a method step | An unfocused step card folds to its first line; a step can be duplicated beside `▲ ▼ 🗑`. | Plan 0022 D7, flagged not built | Watch a real twelve-step import first — editing step 11 means scrolling past ten cards nobody is touching. |
| The stub queue at its source | "3 new ingredients need details" on the import that made them, and at the macro lens — then the global count on the Ingredients shelf retires. | Plan 0028 E5 re-homed the counter; the objection is that a count is still a scoreboard | A permanent number you can only clear by doing chores reads as a nag. Build it with the next import pass. |
| Typo tolerance in the import cascade | The server cascade surfaces ~6 % of single-word typos (0 `auto`, 31 `suggest`, 446 `none` over 477 generated one-edit typos); the phone's rule would surface 84 %. | Search & matching v1 D4 — **stated, not scheduled**: the cascade *commits* where the phone only *offers*, and its bands are calibrated | Revisit only if the evals show import lines genuinely arriving mistyped. OCR from photos is the plausible source. |
| A week that is not a position | **Not planned:** a calendar or month view (refused by spec §4 — it invites the per-day planning this app does not do), week templates (`copy last week` covers the real case), and a week archive or lock (every rule about *when* a week would lock is wrong for someone catching up on a Tuesday). | Week v2's recorded refusals | Real demand only. If jumping to an arbitrary week is ever needed, the honest answer is a date entry in the switcher menu, not a calendar. `week_plan.label` exists, is always null, and is where a user-named week would live — do not delete it. |
| The 400 ms tap latch | **Not planned:** a timed lock-out after a navigating tap. | A Navigation v2 frame, never built | The shipped guard is a same-location dedupe in `pushOnce` ([navigation.md](../design-docs/navigation.md)), which stops the double-tap without a timer. |
| The dirty-new-row prompt | **Not planned:** a prompt when leaving the flesh-out form with unsaved edits. | Plan 0029 R1; dropped by the owner — it guards against a rare case that loses little time | Nothing tracks dirty state and there is no `PopScope` outside the shell. Revisit only if losing a draft actually bites. |
