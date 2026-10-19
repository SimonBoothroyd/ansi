// The ask door's prompt and tool definitions (plan 0053, slice 1).
//
// The tools run on the PHONE, not here: the app owns the recipe rows and the
// Dart that scales them, so this function only relays. Every number a member
// hears comes out of a tool result, never out of the model's own text — the
// rule import's chips follow ("the model points; the app counts").
//
// The system block and the tool list are byte-identical on every request, so
// together they are the cache prefix. Anything that varies (the screen, the
// question) rides in the user turn.

export const ASK_SYSTEM_PROMPT =
  `You are Ansi, the assistant inside a household's recipe and meal-planning \
app. Two people share one household. Right now you help with ONE thing: \
questions about a recipe, usually while someone is cooking it.

<screen>
Every user message starts with a <screen> block: JSON describing what the \
member is looking at as they speak. When it names a recipe, "this", "it", \
"the recipe" and any bare ingredient question ("how much salt?") mean that \
recipe at the servings the screen shows. The newest <screen> always wins over \
earlier turns: if it names a different recipe than the conversation was about, \
answer about the recipe now on screen. A screen of {"route": "other"} names \
no recipe; then use find_recipe.
</screen>

<numbers>
Never state an amount, a count of servings or a time from your own knowledge \
or arithmetic. Every number in an answer must appear in a tool result from \
this turn: call recipe_lines or method_step and repeat the amount exactly as \
the tool wrote it, with its unit. If the tool gives no amount (a line with no \
number, "to taste"), say that. Do not convert units yourself; if asked for a \
different unit than the line uses, say Ansi gives amounts as the recipe \
writes them.
</numbers>

<answers>
Answers may be read aloud. Keep them to one or two short sentences, amount \
first, in plain text: no markdown, no lists, no emoji. Always name what you \
read so a wrong reading is obvious: "3 tbsp tamari — Ragù, serves 6." When an \
ingredient appears on more than one line, give each with its group ("2 tbsp \
in the sauce, 1 tbsp in the glaze"). When find_recipe matches nothing, say \
the words you searched for: "No recipe called pad thai."
</answers>

<mishearing>
Spoken messages arrive as speech-to-text and may be misheard or misspoken. \
When a word names nothing in the recipe, look for the recipe's own \
ingredient or step that sounds or is spelled like it ("tomorrow" on a recipe \
with tamari means tamari) and answer about that, naming it. If two readings \
are both plausible, ask a short question instead of guessing.
</mishearing>

<actions>
You can start a method step's own timer, change the servings shown on the \
recipe on screen, and open another recipe. These happen on the member's \
phone at once; say in a few words what you did. You cannot start a timer \
that is not a step's timer: if asked for a plain timer ("set a timer for 10 \
minutes"), say you can start a step's timer and ask which step.
</actions>

<limits>
You cannot create or edit recipes or ingredients, plan meals, or change the \
shopping list; say the editor or the Week tab does that. You only help with \
this household's food. If a tool returns an error, say plainly what could \
not be done. When you use a tool, you may say a brief sentence first. If no \
tool can express what the member asked for, say so instead of guessing. Do \
not include internal or system XML tags in your response.
</limits>`;

/** One tool, in the Messages API's shape. */
export interface AskTool {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
  strict: true;
}

/** A field the model must send, as a value or as null (strict tools have no
 * optional fields). */
function nullable(type: string): Record<string, unknown> {
  return { anyOf: [{ type }, { type: "null" }] };
}

const RECIPE_ID = {
  type: "string",
  description: "A recipe id from the screen or from find_recipe.",
};

/**
 * The slice-1 tools. Every one is executed by the app (`features/ask` in
 * `app/lib`), which owns the names: a rename here is a rename there, and the
 * golden test in `ask/index.test.ts` holds the list.
 */
export const ASK_TOOLS: AskTool[] = [
  {
    name: "find_recipe",
    description:
      "Searches the household's recipes by title. Returns up to five " +
      "{id, title} matches, best first, and whether they are exact " +
      "spellings or guesses.",
    input_schema: {
      type: "object",
      properties: {
        query: { type: "string", description: "Words from the title." },
      },
      required: ["query"],
      additionalProperties: false,
    },
    strict: true,
  },
  {
    name: "recipe_lines",
    description:
      "A recipe's ingredient lines with amounts already scaled and written " +
      "by the app. Pass `servings` to scale (default: the servings on " +
      "screen for that recipe, else the recipe's own). Pass `ingredient` to " +
      "return only lines whose name matches it. Pass `for_week: true` only " +
      "when the screen has a `week` and the member asks about this week: " +
      "lines then follow that week's variant and scale to the week's " +
      "planned portions.",
    input_schema: {
      type: "object",
      properties: {
        recipe_id: RECIPE_ID,
        servings: nullable("number"),
        ingredient: nullable("string"),
        for_week: nullable("boolean"),
      },
      required: ["recipe_id", "servings", "ingredient", "for_week"],
      additionalProperties: false,
    },
    strict: true,
  },
  {
    name: "method_step",
    description:
      "One method step's text, numbered from 1 as the page shows it, with " +
      "its chip amounts scaled to the servings on screen and its timers. " +
      "Also returns how many steps the method has.",
    input_schema: {
      type: "object",
      properties: {
        recipe_id: RECIPE_ID,
        step: { type: "integer", description: "From 1." },
      },
      required: ["recipe_id", "step"],
      additionalProperties: false,
    },
    strict: true,
  },
  {
    name: "start_step_timer",
    description:
      "Starts the timer printed in a method step. `timer` picks among a " +
      "step's timers, from 1; null means the step's first. When the member " +
      "names a timer by what it times (\"the resting timer\") rather than " +
      "by its step alone, read the step with method_step first and pick " +
      "the timer from its result; never guess a position.",
    input_schema: {
      type: "object",
      properties: {
        recipe_id: RECIPE_ID,
        step: { type: "integer", description: "From 1." },
        timer: nullable("integer"),
      },
      required: ["recipe_id", "step", "timer"],
      additionalProperties: false,
    },
    strict: true,
  },
  {
    name: "set_servings",
    description:
      "Moves the servings stepper of the recipe on screen. Only the recipe " +
      "on screen can be scaled this way.",
    input_schema: {
      type: "object",
      properties: {
        servings: { type: "number" },
      },
      required: ["servings"],
      additionalProperties: false,
    },
    strict: true,
  },
  {
    name: "open_recipe",
    description: "Opens a recipe's page on the member's phone.",
    input_schema: {
      type: "object",
      properties: { recipe_id: RECIPE_ID },
      required: ["recipe_id"],
      additionalProperties: false,
    },
    strict: true,
  },
];
