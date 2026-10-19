# Feature: ask

**Plan:** [0053 — Ask Ansi](../../../../docs/exec-plans/active/0053-ask-ansi.md).

Ask Ansi about the recipe on screen, typed or spoken: *how much tamari?*,
*what's step 3?*, *start the simmer timer*, *make it 8 servings*, *open the
aioli*. This first slice answers questions and acts on the phone; it changes
no shared data. Planning and the shopping list are the next slice.

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
  the steps struck off. It is the chip above the field; the chip's ✕ asks from
  nowhere. The newest screen wins over the thread.
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

## Voice

`data/ask_voice.dart`: the phone's own recogniser (`speech_to_text`) and speech
engine (`flutter_tts`). A spoken question is sent when the member pauses for
two seconds; the answer to a spoken question is read aloud, a typed one is not,
and the speaker in the sheet cycles *match the question* · *always* · *never*.
No audio reaches Ansi's servers.

## Files

```
ask/
  domain/         PURE DART
    ask_screen.dart       what is on screen, as the <screen> block and the chip
    ask_thread.dart       the wire turns, the exchanges shown, idle, trim, tail removal
    ask_tools.dart        what each tool answers, written by the app's own Dart
    ask_tool_runner.dart  which recipe, which servings, which week — data injected
    ask_read_aloud.dart   when an answer is read aloud
    ask_repository.dart   the relay's contract
  data/
    remote_ask_repository.dart  the `ask` edge function; waits 60 s
    ask_providers.dart          the relay, or a refusal when unconfigured
    ask_voice.dart              mic and speaker, and the read-aloud setting
  presentation/
    ask_controller.dart   the loop: question → model → tools → … → answer
    ask_wiring.dart       the runner over a captured container's repositories
    ask_sheet.dart        the chip, the conversation, the field and the mic
```

The door is the recipe page's speech-bubble icon (`_AskDoor` in
`recipes/presentation/recipe_view.dart`). The page's servings live in
`recipeServingsProvider` so Ansi can read and move them.
