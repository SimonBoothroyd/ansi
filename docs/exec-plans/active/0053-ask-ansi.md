# Exec plan: Ask Ansi — a chat and voice assistant

- **Status:** active — slice 1 shipped in `v0.30.0` and waits only on its phone run; slice 2 is built on a branch and waits on its deploy, its paid eval and its phone run (see *Handover*)
- **Owner:** Simon (rulings), agents in lanes
- **Roadmap step:** none — slice 1 is the `v0.30.0` row of the roadmap's Shipped table
- **Created:** 2026-10-18

## Handover

**Where it stands.** Slice 1 — questions about the recipe on screen, typed or
spoken, with three on-phone actions — is on `main`, drawn on the board,
deployed (`ask`, deploy 39187852214) and released in `v0.30.0` (release
39188275832). Its paid eval passed 28/28 first moves and 17/17 answers (see
*Decision log*). What is left is the phone checklist below.

Slice 2 — the week, the cook plan and the list, and every change behind a
card — is built (*Slice 2 — what was built*) and needs no migration. Before it
is tagged: redeploy the `ask` function (its prompt and tool list changed; an
app with the new tools against the old function gets no week tools, and the
old app against the new function is unaffected), run the paid eval
(`run_ask_live.ts`, now 36 cases), then the phone checklist's slice-2 rows.

**Read first, in this order:**

1. This plan's *Rulings* and *Slice 1 — what was built* (below).
2. [`app/lib/features/ask/README.md`](../../../app/lib/features/ask/README.md)
   — the loop, the tools, the voice, every file.
3. [`supabase/functions/ask/README.md`](../../../supabase/functions/ask/README.md)
   — the relay's contract and its pin.
4. [`evals/AGENTS.md`](../../../evals/AGENTS.md) — the *Ask Ansi* dimension.
5. The board: [`recipe-page.html`](../../product-specs/board/recipe-page.html),
   frames *Ask Ansi* and *An answer, and an action*.

**Check it locally:**

```
make analyze                                  # flutter analyze + custom_lint
cd app && flutter test test/features/ask      # the 79 ask tests
cd app && flutter test test/features/planning/planning_repository_test.dart
make test-fns                                 # the function, adapter, timeout ladder
cd evals && ./runner/run.sh                   # the keyless scorers + the dataset's validity
```

**Owed by the owner:** a monthly spend cap in the Anthropic console, if there
is none — it is the fence the function does not hold itself.

**The phone checklist (not yet done):**

- [ ] The first mic tap asks for the microphone; refusing it shows the toast.
- [ ] *how much …?* on a recipe answers at the stepper's servings and names it.
- [ ] A spoken question sends on a pause, and its answer is read aloud.
- [ ] A spoken question Ansi asks back about (*set a timer for 10 minutes*)
      opens the mic once the question is read; the reply sends on a pause.
- [ ] *start the simmer timer* starts the step's chip and its dock row.
- [ ] *make it 8 servings* moves the stepper behind the sheet.
- [ ] *open the aioli* closes the sheet and opens the recipe.
- [ ] Airplane mode: a question fails with a sentence, and works again after.

Slice 2:

- [ ] The speech bubble is in the Library, Week, Cook and Shop bars, and the
      chip names the tab and its week.
- [ ] *what's for dinner tonight?* on the Week names today's dinner.
- [ ] *set all dinners next week to …* shows one card with every day dated;
      Cancel writes nothing; Confirm writes all of it and the Week shows it.
- [ ] *I'm eating out Friday* takes the speaker (and only them) off Friday's
      meals — the check that "I" is read from the account's name.
- [ ] A card confirmed after the other phone edited one of its meals is
      refused, and Ansi re-reads the week.
- [ ] *add milk to the list* asks how much; *add paper towels* lands as an
      item on the Shop tab.
- [ ] *copy last week* on an empty week copies it and the Week names the
      variants left behind.

iOS: the two new plugins need `pod install` on a Mac at the next Xcode build;
the usage strings are already in `Info.plist`.

## Goal

From anywhere in the app, a member can ask a question or give an instruction
in words — typed or spoken — and Ansi answers from the household's own data or
proposes a change the member confirms with one tap:

- *"How much tamari do I need?"* on a recipe page answers at the page's
  servings, and names the line it read.
- *"Set all dinners next week to Hamburger Helper"* shows the seven changes as
  a card; **Confirm** writes them; nothing is written before that.

This file is the spec first: what can be said, what Ansi knows when it is
said, and what it may do. The build approach at the foot is a sketch for the
rulings to reshape.

## The rules it inherits

Nothing here is a new principle. Each is an existing rule applied to a new
door.

1. **The model points; the app counts.** The model chooses *which* recipe,
   line, meal or week a sentence means. Every number in an answer — an amount,
   a scale, a cost, a macro — is computed by the app's own Dart from the
   rows, exactly as import chips work
   ([import-and-matching.md](../../product-specs/import-and-matching.md)). The
   worst failure is pointing at the wrong thing, and the answer always names
   what it pointed at.
2. **Honest numbers** (invariant 3). A stub line, an unconvertible line or a
   meal out without macros is named as missing, never estimated. *"About
   2 tbsp, I think"* is not an answer Ansi gives.
3. **Machine proposes, a human confirms.** A change to shared data is a
   proposal card until a member taps Confirm. Confirm is one write through
   the existing repositories ([ADR-0011](../../decisions/0011-one-save-one-write.md)),
   synced like any other edit.
4. **Online-only, like import** ([ADR-0004](../../decisions/0004-matching-is-online-only.md)).
   Offline, the button says so instead of opening.

## What Ansi knows when you speak

A question like *"how much of x?"* only makes sense with a place. Ansi works
from three layers of context, and only the first is new state.

### 1. The screen (sent with every message)

The app sends a small, typed description of what is on screen. It is shown
to the member as a chip above the input — **On: Ragù · serves 6** — and
tapping the chip's ✕ drops it, so a question can be asked "from nowhere".

| Route | What the screen context carries |
|---|---|
| `/recipes/:id` | recipe id and title, the **servings the stepper shows now**, `?week=` when opened from a week that plans it, the focused method step, struck lines and steps |
| `/recipes/:id/edit` | recipe id only; answers come from the **saved** recipe and say so (*"from the saved version"*), never from the unsaved draft |
| `/week` | the viewed week, the open day (wide layout) |
| `/cook` | the viewed week |
| `/shop` | the viewed week |
| `/books/:id`, `/` | the book on screen, if any |
| `/ingredients/:id` | ingredient id and name |
| `/receipts/:id` | receipt id |
| anything else | the route name only |

**One code change this forces:** the recipe page's servings are hook state
inside `RecipeView` (`useState(recipe.servingsBase)`). To be sent, they have to
move to a provider keyed by recipe that the assistant can read. The scaling
itself stays a view concern.

### 2. The conversation (this device, this sitting)

A thread lives on the device in memory, so a follow-up works:

> *How much tamari?* → **3 tbsp** (Ragù, serves 6) · *And garlic?* → **6 cloves**
> · *Make it 8 servings* → the stepper moves · *Garlic now?* → **8 cloves**

- The thread is **not synced and not stored**. Closing the sheet keeps it for
  that session; it is cleared when the app restarts, or after 30 minutes with
  no message.
- **The screen wins over the thread.** If the member navigates to another
  recipe, the next message carries the new screen, and *"how much salt?"*
  means the new recipe.
- The thread is resent whole with each message (the server keeps nothing).
  It is capped at the last ~20 turns.

### 3. The household's data (fetched by tools, never sent wholesale)

The model sees nothing of the household until it calls a tool. A tool
returns the few rows it was asked for. See **Tools** below.

## The conversations

Grouped by area. **Slice 1** is recipe questions and device-only actions —
nothing a member says can change shared data. **Slice 2** adds the week and
the shopping list, every write behind a proposal card. **Later** is spec'd so
the tool shapes allow it, but not scheduled. Each row is the canonical
example; the evals hold the variants.

### A. On a recipe (read-only, plus device-only actions)

| Say | Ansi does | Slice |
|---|---|---|
| *How much tamari do I need?* | The line's amount **at the stepper's servings**, its unit as written, and the line named: *"3 tbsp tamari — Ragù, serves 6."* Two lines with the same ingredient are listed with their group (*"2 tbsp in the sauce, 1 tbsp in the glaze"*). | 1 |
| *How much tamari for this week?* | With `?week=` (or the recipe planned that week), the amount for the week's planned portions, read through `effectiveLines` so this week's variant counts. | 1 |
| *How much tamari in grams?* | Converted by the unit system when the ingredient's density allows; otherwise says it can't and why (a stub, no density). Never a guessed conversion. | 1 |
| *What's in the sauce?* | The lines of that group, scaled. | 1 |
| *What's step 3? / What's next?* | Reads the step; *next* is the step after the focused one. | 1 |
| *Start the simmer timer* | Starts the step's own timer chip. Device-only: done at once and shown in the timer dock, no Confirm. | 1 |
| *Set a timer for 10 minutes* | **Refused:** a timer belongs to a step. *"I can start a step's timer — which step?"*; with no step to name, the phone's clock app is the answer. | — |
| *Make it 8 servings* | Moves the stepper. Device-only, no Confirm. | 1 |
| *What can I use instead of tamari?* | General cooking knowledge, not household data. Allowed, and **labelled as general advice**. It never changes the recipe and never states an amount as if it were on the page. | later |
| *Add a note: use less salt* | A recipe edit. Out of scope — the editor is the one place a recipe changes. | later |

### B. The week (writes, via a proposal card)

| Say | Proposal card | Slice |
|---|---|---|
| *Set all dinners next week to Hamburger Helper* | Seven rows, Mon–Sun: *Dinner · Hamburger Helper · replaces Ragù*, or *· new*. Eaters default to the household. Confirm writes all seven or none. | 2 |
| *What's for dinner tonight?* | Read-only: today's Dinner entries with their eaters. | 2 |
| *Move Tuesday's curry to Thursday* | One row: *Tue Dinner → Thu Dinner*. | 2 |
| *Add yoghurt to breakfast every weekday* | Five ingredient entries, one portion each, unit from the ingredient's default. | 2 |
| *I'm eating out Friday* | Takes the speaker off Friday's eaters (the signed-in member); if that leaves a meal with no eaters, the card says it will be removed. | 2 |
| *Copy last week* | The existing copy-last-week, behind the same card, with its existing note about variants it did not carry. | 2 |
| *Clear the snacks* | Removes Snack entries for the viewed week, listed. | 2 |
| *Plan something with chicken on Wednesday* | Suggests 2–3 of the household's own recipes; the member picks one, then the card. Never invents a recipe. | later |

**What a named meal becomes.** A plan entry is one of three things
([planning README](../../../app/lib/features/planning/README.md)), and a name
resolves in this order:

1. **An exact recipe** (title, case-insensitive) → that recipe, no question.
2. **Otherwise an exact ingredient** (name or alias) → a bare-ingredient
   entry, no question.
3. **Otherwise Ansi asks**, on the card: the near-named recipes and
   ingredients `searchRank` offers as *"did you mean"*, or a **meal out**
   with the words as its label. Ansi never invents a recipe.

### C. Cook and shop

| Say | Ansi does | Slice |
|---|---|---|
| *What am I cooking on Sunday?* | Read-only: the cook plan's sessions that day, portions per recipe, from the derived plan. | 2 |
| *Add milk to the list* | A manual top-up, proposed and confirmed. One item — the card is a single row with Confirm. | 2 |
| *Do we need tamari?* | Whether tamari is on this week's list, how much, and **which meals ask for it** (the list's provenance). | 2 |
| *What's left to buy?* | The unchecked rows, grouped by aisle, read out briefly. | 2 |
| *Tick off the milk* | Check state is a list overlay; proposed and confirmed like a top-up. | later |

### D. Numbers about the week

| Say | Ansi does | Slice |
|---|---|---|
| *How much protein this week?* | The week band's own figure, with its exclusions named (*"two meals out don't state macros"*). | later |
| *What will this week cost?* | The week's cost to cook, from unit prices ([ADR-0017](../../decisions/0017-a-cost-is-a-unit-price-never-an-allocation.md)), with the lines it couldn't price. | later |
| *When did we last buy tamari, and for how much?* | The latest receipt line for the ingredient. | later |

### E. Finding things

| Say | Ansi does | Slice |
|---|---|---|
| *Open the aioli* | Navigates. Device-only, no Confirm. | 1 |
| *Find the chicken one with lime* | Searches the library by title. Searching by *ingredients* is the backlog's "Recipes with almonds" row and waits on its ruling. | later |

### F. What Ansi refuses, and how

Each refusal is one short line saying why, never a silent no:

- **Creating or editing a recipe or an ingredient.** *"Recipes are edited in
  the editor — want me to open it?"* Import stays the door for new recipes.
- **A number it can't stand behind.** Macros for a stub, a conversion
  without a density, a price with no receipt: *"Tamari has no density yet, so
  I can't give grams."*
- **Anything outside the household's food.** Ansi is not a general chatbot.
- **Offline.** *"Ask Ansi needs a connection."*

## Actions: three tiers

| Tier | Examples | Behaviour |
|---|---|---|
| **Answer** | amounts, steps, what's for dinner, what's left to buy | Text, read aloud if voice is on. Each answer names its source, which can be tapped to open it. |
| **Device-only** | timer, servings stepper, navigate | Done at once; nothing synced changes, so no Confirm. A toast says what was done. |
| **Proposal** | plan entries, top-ups, check state | A card listing every change (day · slot · before → after). **Confirm** writes them in one transaction through the existing repository; **Cancel** discards. The card is the whole change: nothing hidden behind "and 3 more". |

A proposal against a week someone else edits meanwhile is re-checked at
Confirm. If any listed row changed under it, the card says so and offers to
redo, rather than overwriting.

## How words resolve

- **Relative dates resolve against today**, not the week on screen: *next
  week* is the Monday after this one. The card always prints the dates, so a
  wrong reading is visible before Confirm. *"This week"* while viewing
  another week is ambiguous; Ansi asks.
- **Slots** match `kDefaultMealSlots` case-insensitively, and custom slots by
  their label.
- **Recipes and ingredients** resolve through the household's own rows. Ansi
  asks when two match equally (*"Ragù or Ragù bianco?"*), and offers *did you
  mean* when none match exactly, as the search boxes do.
- **"I" is the signed-in member; "we" is the household.** A sentence that
  names a member (*"Emma's eating out"*) wins over the account.
- **A spoken message may be misheard.** Voice is sent on a pause, so the
  prompt treats a transcript as possibly wrong: a word that names nothing is
  matched against the household's own recipe and ingredient names by sound
  and spelling (*"tomorrow"* on a recipe with tamari is tamari). An answer
  names what it resolved to, so a mishearing is visible; when two readings
  are both plausible, Ansi asks. A misheard *change* is caught by the card,
  which lists every row before Confirm.

## Voice

- **In:** a mic button in the input uses Android's built-in speech recogniser
  (`speech_to_text`; on-device where the phone supports it). Keyboard
  dictation works with no extra code. A spoken message is **sent on a pause**,
  hands-free; the transcript stays in the thread, so a mishearing shows (see
  *How words resolve*). When Ansi answers a spoken question with a question
  of its own, the mic opens for the reply once it has been read.
- **Out:** through Android's text-to-speech engine (`flutter_tts`). **An
  answer is spoken when the question was spoken**, and text only when it was
  typed; a speaker toggle in the sheet overrides that. Answers are written to
  be heard: short, amount first. Proposal cards are always shown on screen,
  never only spoken.
- **No wake word.** The sheet is opened by a tap (or later a launcher
  shortcut). "Hey Google" integration through Android AppFunctions is behind
  Google's private preview. The on-device tools below are deliberately the
  shape AppFunctions would expose, if that opens up.

## Where it sits

A single **Ask** button reachable from every screen, opening a bottom sheet
(a side pane at the wide layout) with the context chip, the thread, the
input and the mic. Drawn on the board as `proposed` before it is built.

## Tools

The derivations Ansi needs — scaling, `effectiveLines`, the cook plan's
clustering, the shopping list's sums, macros, cost — are pure Dart on the
phone. So **the tools run on the phone**, against the local PowerSync
database, and the edge function is a thin, stateless relay:

```
phone ──(thread + screen + tool results)──▶ ask (edge fn: key, allowlist, prompt)
  ▲                                                │
  └──────────── tool calls / answer ◀── Claude ◀───┘
```

The edge function holds the API key and the household allowlist, adds the
system prompt, and forwards. It reads no household data and stores nothing.
The phone runs each tool call and sends the result on the next request. This
costs a round trip per tool step, but it reuses the existing Dart rules,
reads exactly what the member sees (including unsynced edits), and needs no
second implementation in TypeScript.

The tool set. Slice 1 has the read tools and
the device-only actions; the `propose_*` tools arrive with slice 2:

| Tool | Returns / does |
|---|---|
| `find_recipe(query)` | up to 5 `{id, title}` by `searchRank` |
| `recipe_lines(recipe_id, servings?, week?, ingredient?)` | scaled lines with group, amount and unit computed by the app; `week` reads through `effectiveLines` |
| `method_step(recipe_id, n)` | a step's text and its timers |
| `week(week_start, day?, slot?)` | plan entries with kind, eaters, portions |
| `cook_sessions(week_start, day?)` | the derived sessions |
| `shopping(week_start, ingredient?)` | rows with amount, checked state and provenance |
| `find_ingredient(query)` | up to 5 `{id, name}` |
| `propose_plan_changes(changes[])` | validates, then renders the card; returns `confirmed` / `cancelled` |
| `propose_top_up(ingredient_id \| label, amount?)` | same, for the list |
| `start_step_timer(recipe_id, step, timer)`, `set_servings(servings)`, `open_recipe(recipe_id)` | device-only actions |

Every number that reaches the member comes out of a tool, never out of the
model's own text. The prompt says this, and the evals check that each amount
in an answer appears verbatim in a tool result of that turn.

## Privacy and cost

- **What leaves the phone:** the typed or transcribed text, the screen
  context, and the tool results for that turn — recipe lines, plan entries,
  list rows. No audio (speech-to-text runs on the phone or through Google's
  recogniser). Nothing is stored server-side by Ansi; the API provider's
  standard retention applies. [PRIVACY.md](../../../PRIVACY.md) gains a
  paragraph.
- **Model:** Claude Haiku 5.5 by default — the job is resolving references
  and filling tool calls, not reasoning. The model id is pinned in one
  constant, like `CLAUDE_HAIKU_MODEL`, and changed only by measurement.
- **Estimate:** about a tenth of a cent per question; under a dollar a month
  at twenty questions a day. Behind `IMPORT_ALLOWED_HOUSEHOLDS` (or its own
  allowlist), with a monthly spend cap set in the provider's console and a
  per-household rate limit in the function.

## Evals

A new `evals/ask/` set: utterance + screen context + a fixture household →
the expected tool calls and the expected proposal (or refusal). Graded
mechanically: right tool, right ids, right changes, every number in the
answer present in a tool result. An LLM judge is only for the tone of
refusals and clarifying questions. Run before choosing the model and again
on every prompt change.

## Rulings

Taken with the owner, 2026-10-18.

1. **Slice 1 is recipe questions only** (section A, plus *open* from E):
   amounts, steps, servings, step timers. Nothing said can change shared
   data. The week and the list are slice 2, once slice 1 shows it is used.
2. **A named meal resolves exact recipe → exact ingredient → ask.** No
   default to a meal out; a near match is only ever offered.
3. **Voice sends on a pause**, and the prompt allows for misspeaking and
   mishearing: it resolves a word against the household's own names and asks
   when two readings are plausible.
4. **Step timers only.** No free *"set a timer for 10 minutes"*.
5. **The thread clears on restart or after 30 minutes with no message.**
6. **Saved rows only.** In the editor, answers say they come from the saved
   recipe.
7. **"I" is the signed-in member**; a named member in the sentence wins.
8. **Read aloud matches how you asked**: spoken in, spoken out; typed in,
   text out; a toggle in the sheet overrides.

## Slice 1 — what was built

| Step | What exists | Where |
|---|---|---|
| The relay | `ask` edge function: shared gate + allowlist, a parsed and capped conversation (120 turns, 256 KB), one Claude Haiku 5.5 call with the six tools, blocks back verbatim; no SQL (`no_write.test.ts`) | `supabase/functions/ask/`, `_shared/adapters/claude_ask.ts`, `_shared/prompts/ask.ts` |
| Screen context | `AskRecipeScreen` / `AskNoScreen`, sent as a `<screen>` block with each question; the recipe page's servings now live in `recipeServingsProvider` | `features/ask/domain/ask_screen.dart`, `recipes/presentation/recipe_view_models.dart` |
| The thread | the API's own turns kept append-only; 30-minute idle clear; trim past 20 questions strips thinking blocks; a failed or refused question comes off the tail | `features/ask/domain/ask_thread.dart`, `presentation/ask_controller.dart` |
| The tools | `find_recipe`, `recipe_lines` (with `for_week`), `method_step`, `start_step_timer`, `set_servings`, `open_recipe`, run on the phone with every amount written by the page's own Dart | `features/ask/domain/ask_tools.dart`, `ask_tool_runner.dart`, `presentation/ask_wiring.dart` |
| The sheet and the door | the speech-bubble icon in the recipe page's bar; the chip, the conversation, the field, the mic and the speaker | `features/ask/presentation/ask_sheet.dart`, `_AskDoor` in `recipe_view.dart` |
| Voice | `speech_to_text` (sent on a 2.5 s pause the app keeps itself, restarting a session Android ends early) and `flutter_tts` (read when asked aloud); `RECORD_AUDIO`, the two `<queries>` intents, the two iOS usage strings | `features/ask/data/ask_voice.dart`, `domain/ask_spoken_question.dart` |
| Evals | 28 hand-written cases; scorers for the first move and for invented numbers, self-tested keyless; a paid live runner | `evals/datasets/ask/`, `evals/runner/score_ask.ts`, `run_ask_live.ts` |

Tests: 20 Deno tests for the function and adapter (and one more rung in
`_shared/timeouts.test.ts`); 43 Flutter tests in `test/features/ask/`,
including six end to end on the real recipe page; 7 keyless eval tests.

The board draws the bar's Ask door on every recipe-page frame and the sheet
in two frames; the view's status row reads *ask: matches code*.

**Still open for slice 1:** the merge, the deploy, the paid eval and the phone
checklist — all in *Handover* above.

## Slice 2 — what was built

| Step | What exists | Where |
|---|---|---|
| The doors | the speech bubble in the Library, Week, Cook and Shop bars beside the recipe page's; the chip names the tab and its week | `features/ask/presentation/ask_door.dart`, the four tab views |
| Today, on every screen | `today`, `today_is`, `this_week`, `next_week`, `weeks_start_on` in each `<screen>` block, from the household's `WeekShape` | `AskToday` in `domain/ask_screen.dart` |
| The read tools | `week` (days dated, meals by id with eaters and portions, the members with the speaker marked), `cook_sessions`, `shopping` (one ingredient's rows with their meals, or what is left by aisle), `find_ingredient` (with the units an amount may use) | `domain/ask_week_tools.dart` |
| Who "I" is | the member whose name is the account's own name or email local part, as onboarding named them; none or two → Ansi asks | `askMe` |
| The proposals | `propose_plan_changes` (add, remove, move, set eaters), `propose_copy_last_week`, `propose_top_up`, each checked against the rows and drawn as card rows; ruling 2's order is the prompt's, and the check refuses a recipe, ingredient, unit or member that is not the household's | `domain/ask_proposal.dart`, the runner |
| The card | Confirm and Cancel in the sheet under the question; the runner waits on `AskController.awaitDecision`; closing the sheet is a Cancel; Confirm is one `ref.write` | `presentation/ask_card.dart`, `ask_controller.dart` |
| One transaction | `PlanningRepository.applyPlanChanges`: every change in one write, each touched meal re-read and compared with the card's, `PlanChangedError` refusing the whole set | `planning/domain/plan_change.dart`, `planning_repository_impl.dart` |
| The function | the prompt's `<dates>`, `<people>` and `<changes>`; seven new strict tools, inside the API's per-request limits (counted by `claude_ask.test.ts`) | `_shared/prompts/ask.ts` |
| Evals | two refusal cases turned into slice-2 first moves, eight new cases | `evals/datasets/ask/cases.jsonl` |

Tests: 79 Flutter tests in `test/features/ask/` (26 new, two of them end to
end on the recipe page: a card confirmed, a card cancelled), three repository
tests for the change set on a real database, and the function's 401.

**Not built, and why:**

- **The board does not draw slice 2.** The tab bars' new door and the card
  are not on `week.html` / `shop.html` yet; the recipe page's frames still
  hold. Owed with the phone run, when the card's look is settled.
- **Ticking the list off, week numbers (protein, cost), suggestions** stay
  *later*, as section C and D say.
- **No server-side "me".** The phone reads the account's name; a member
  renamed on the server would stop matching, and Ansi would ask.

## Decision log

- 2026-10-19 — Slice 2 built. Decisions taken while building it:
  - **The card waits inside the tool call.** A `propose_*` result is the
    member's decision, so the model's next turn knows whether the change
    happened; it is never told "done" before Confirm.
  - **"I" from the account's name, not a migration.** `auth_user_id` stays off
    the wire; the onboarding rule that named the member is applied again on
    the phone. It costs nothing to ship and fails safe (Ansi asks).
  - **An ingredient meal with no amount states none.** The card says *no
    amount — set it on the Week*; an invented portion would be a number nobody
    said. A top-up has no such state on the list, so it asks for one.
  - **Optional fields in the new tools.** Every slice-1 nullable field is a
    union type; the API allows 16 per request, so slice 2's tools leave fields
    out instead of sending null (21 optional of 24 allowed).
  - **The door is a header action on the four tabs**, not a floating button
    over the shell — the recipe page's door already set the place.

- 2026-10-18 — Drafted from a conversation with the owner: in-app chat with
  voice now; "Hey Google" waits on AppFunctions leaving Google's private
  preview. The tools run on the phone so the Dart derivations are not ported.
- 2026-10-18 — The eight open questions ruled (see Rulings).
- 2026-10-19 — Slice 1 built. Decisions taken while building it:
  - **The door is on the recipe page only.** Every slice-1 conversation is
    about a recipe, and *open the aioli* works from there too; the door on
    every screen comes with slice 2, which needs it for the week.
  - **Adaptive thinking at `effort: low`, kept append-only**, not thinking
    disabled. Claude Haiku 5.5 binds a thinking block to the history before
    it, so the app stores blocks verbatim and only ever removes at the tail;
    a trim past 20 questions strips every thinking block it keeps.
  - **No stream.** The import doors' stream assembler folds text only, and a
    turn here is a sentence or a tool call; `postJson` with a 30 s deadline
    under the app's 60 s wait (`timeouts.test.ts` caught a first draft's
    45 s wait sitting exactly on the server's worst case).
  - **Amounts as the recipe writes them.** *How much tamari in grams?* is
    answered in the recipe's own unit with a sentence; a converted amount
    needs the ingredient's density, which the line does not carry. Revisit
    with slice 2.
  - **No per-household rate limit in the function.** Edge isolates hold no
    state between calls, so an in-memory limit would limit nothing; the
    allowlist and a monthly spend cap in the Anthropic console are the
    fence.
  - **Offline is a failed question with a sentence**, not a disabled button:
    the app has no connectivity signal to read, and the failure says what to
    do.
- 2026-10-19 — The paid eval on `claude-haiku-5-5`: **first moves 28/28,
  answers 17/17, 42 calls, $0.0044**, nothing invented. The first run scored
  27/28 and 16/17; its two misses were fixed before the tag:
  - **A timer named by what it times is read before it is started.** The
    screen carries no timer list, so *the resting timer in step 2* cannot be
    picked by position; `start_step_timer`'s description says to read the
    step with `method_step` first, and the `rest-timer` case expects that
    read.
  - **A search that finds nothing says the words it searched**, so a
    misheard title is obvious when read back.

## Step-done checklist

The code landing is not the step landing. Tick these before setting Status to
done and moving this file to `completed/`.

- [ ] Roadmap row updated: status flipped, one line on what shipped and what was
      deliberately deferred.
- [ ] `ARCHITECTURE.md`'s standing table matches reality for every area touched.
- [ ] `app/AGENTS.md` "Current focus" and command list still true.
- [ ] Feature steps: `make test-sim` run on a booted simulator (the UI paths CI
      can't reach), and the result recorded here.
- [ ] Tech-debt rows **added** for corners knowingly cut, and **retired** (or
      narrowed) for debt this step paid off.
- [ ] New migrations or seed changes? Say in the roadmap row whether they have
      reached **cloud** yet, and append a `docs/cloud-setup.md` ledger entry
      when they do.
- [ ] `make ci` green.
