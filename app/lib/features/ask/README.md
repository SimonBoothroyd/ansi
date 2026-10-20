# Feature: ask

**Plan:** [0053 — Ask Ansi](../../../../docs/exec-plans/active/0053-ask-ansi.md).

Ask Ansi, typed or spoken, from the recipe page or the Library, Week, Cook
and Shop tabs: *how much tamari?*, *what's step 3?*, *start the simmer
timer*, *make it 8 servings*, *open the aioli*, *what's for dinner tonight?*,
*do we need tamari?*, *set all dinners next week to Hamburger Helper*, *I'm
eating out Friday*, *add milk to the list*. Questions and on-phone actions
happen at once; a change to the plan or the list is a card the member
confirms.

## How a question runs

```
the sheet ──question + <screen>──▶ AskController ──conversation──▶ `ask` function ──▶ Claude
                                       ▲    │                                        │
                                       │    └── tool calls run HERE (AskToolRunner) ◀┘
                                       └──────────── the answer, after ≤ 6 rounds
```

- **The model points; the app counts.** The `ask` function relays the
  conversation and declares six tools; it reads no table. Every tool runs on
  the phone, over the same rows and Dart the recipe page uses, so every amount
  Ansi says was written by `scaleLineItem` and `amountOfLine`
  (`domain/ask_tools.dart`). The model never multiplies.
- **The screen is sent with every question** (`domain/ask_screen.dart`): the
  recipe, the servings the stepper shows, the week the page was opened from,
  the steps struck off — or the tab and the week it shows — and always today,
  this week and next by their first days (`AskToday`). It is the chip above
  the field; the chip's ✕ asks from nowhere. The newest screen wins over the
  thread.
- **Dates are the app's.** A tool takes `week_of` (any date in the week) and
  answers with every day dated through the household's `WeekShape`, so the
  model copies *Thu 29 Oct* rather than counting to it.
- **A proposal is a card, and only Confirm writes** (`domain/ask_proposal.dart`,
  `presentation/ask_card.dart`). A `propose_*` call is checked against the
  household's rows — the meals by id in the weeks read, the recipe, the
  ingredient and its allowed units, the members — and drawn as rows (*Mon 26
  Oct · Dinner · Hamburger Helper · replaces Ragù*). The runner waits on the
  controller (`awaitDecision`) until the member taps Confirm or Cancel, or
  closes the sheet (a Cancel), and the model reads the outcome. Confirm is one
  `ref.write`: a plan card goes through `PlanningRepository.applyPlanChanges`,
  one transaction that re-reads every meal it touches and refuses the whole
  set when one changed (`PlanChangedError`, told to the model as `changed`).
- **An amount not said is the usual one.** An ingredient meal or a top-up
  takes the amount said ("2 pots" names a measure), else the one its sheet
  would open on (`defaultAmountFor`: last time at that door, else one of its
  word for one, else one piece), and the card says which. With neither, the
  call is refused with a sentence telling the model to ask how much.
- **Figures are the screens' own.** `nutrition` and `cost` call the same
  summations the recipe panel, the Week band and the Shop do
  (`sumPlannedMacros`, `sumPlannedCost`, `tripCostCents`) and write them with
  the same words (`incompleteNote`, `excludedLine`, `weekCostLine`,
  `costFloor`), so an answer cannot disagree with a screen. A day or a week
  is the speaker's unless `everyone` or a member is named; money and macros
  never share a result.
- **"I" is the member signed in**, matched by the account's own name or email
  as onboarding named the member (`askMe`); when no one or two match, the week
  marks no one "you" and Ansi asks.
- **The thread is the API's own turns, verbatim** (`domain/ask_thread.dart`),
  held in a kept-alive controller on this device only — never stored or
  synced. It is append-only, because a thinking block the model returned is
  valid only while everything before it is unchanged. It clears after 30 idle
  minutes or on restart; past 20 questions the oldest go, and every thinking
  block left is stripped with them.
- **A failed or refused question is taken off the tail** and the exchange says
  why; nothing earlier is touched.

## The tools

| Tool | What the phone does |
|---|---|
| `find_recipe` | the household's recipe titles through `searchRank`, best tier only |
| `recipe_lines` | the lines, scaled to the screen's servings (or a stated number); `ingredient` filters, and a word that names nothing returns every line so a misheard name can be matched; `for_week` reads the week's variant and planned portions |
| `method_step` | one step as plain text, chip amounts scaled, with its timers |
| `start_step_timer` | starts a step's own timer chip — never a free timer |
| `set_servings` | moves the stepper of the recipe on screen, and only that one |
| `open_recipe` | closes the sheet and opens the recipe once the answer is in |
| `week` | a week's meals by day, each day dated, each meal with its id, kind, eaters and portions; the members, the speaker marked; with `recipe_id`, one recipe's meals and how many, counted here |
| `cook_sessions` | the derived batches by cook day, portions and the meals they feed |
| `shopping` | one ingredient's rows with the meals that ask for it, or what is left to buy by aisle; totals as the Shop prints them |
| `find_ingredient` | the vocabulary's best matches, each with the unit ids and measure names an amount may use and its usual amount |
| `nutrition` | a recipe's per-serving macros (and at the servings on screen), or a day's or a week's under a member's lens — the speaker's by default — with a week's per-day average; incomplete and left-out named |
| `cost` | a recipe per serving and whole, a day's or a week's cost to cook beside the week's receipts, or the Shop's trip estimate; a gap reads `at least` |
| `prices` | an ingredient's latest three purchases and the price its costs read |
| `propose_plan_changes` | add, remove, move, set eaters — checked, drawn as a card, written on Confirm |
| `propose_copy_last_week` | the Week's own copy, as a card |
| `propose_top_up` | an ingredient with an amount, or a free-text item, onto the week's list, as a card |

## Voice

`data/ask_voice.dart`: the phone's own recogniser (`speech_to_text`) and speech
engine (`flutter_tts`). A spoken question is sent when the member has been
quiet for two and a half seconds, a pause the app keeps itself
(`domain/ask_spoken_question.dart`): Android ends a listening session on its
own silence of about a second whatever it is asked for, so a session that
ends early is restarted and its words kept. The mic waits six seconds for a
first word and thirty for the whole question; the answer to a spoken question is read aloud, a typed one is not,
and the speaker in the sheet cycles *match the question* · *always* · *never*.
When the answer to a spoken question ends on a question of Ansi's own
(`asksBack`: *Tamari in the sauce or the glaze?*), the mic opens for the
reply once it has been read — `speak` completes only when the reading ends,
so the mic never hears Ansi. It stays shut if the member has already tapped
the mic, typed, started anew or closed the sheet.
No audio reaches Ansi's servers.

## Files

```
ask/
  domain/         PURE DART
    ask_screen.dart       what is on screen, as the <screen> block and the chip
    ask_thread.dart       the wire turns, the exchanges shown, idle, trim, tail removal
    ask_tools.dart        what each tool answers, written by the app's own Dart
    ask_tool_runner.dart  which recipe, which servings, which week — data injected
    ask_week_tools.dart   what the week, cook and shop tools answer; who "I" is
    ask_proposal.dart     a propose_* call checked and drawn as card rows
    ask_read_aloud.dart   when an answer is read aloud
    ask_spoken_question.dart  when a spoken question is over, across recogniser sessions
    ask_repository.dart   the relay's contract
  data/
    remote_ask_repository.dart  the `ask` edge function; waits 60 s
    ask_providers.dart          the relay, or a refusal when unconfigured
    ask_voice.dart              mic and speaker, and the read-aloud setting
  presentation/
    ask_controller.dart   the loop: question → model → tools → … → answer;
                          the card waiting on Confirm
    ask_card.dart         the card, and the one write Confirm makes
    ask_door.dart         the bar's door on the Library, Week, Cook and Shop
    ask_figures.dart      what nutrition, cost and prices answer, in the
                          panel's and the band's own words
    ask_figures_wiring.dart  those figures read for any recipe, day or week
    ask_wiring.dart       the runner over a captured container's repositories
    ask_sheet.dart        the chip, the conversation, the field and the mic
```

The doors are the recipe page's speech-bubble icon (`_AskDoor` in
`recipes/presentation/recipe_view.dart`) and `AskDoor` in the four tabs'
bars. The page's servings live in
`recipeServingsProvider` so Ansi can read and move them.
