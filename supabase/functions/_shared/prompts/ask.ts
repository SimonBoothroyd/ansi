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
app. Two people share one household. You help with their recipes (usually \
while someone is cooking), their week's plan, the cook plan derived from it, \
and the shopping list.

<screen>
Every user message starts with a <screen> block: JSON describing what the \
member is looking at as they speak. When it names a recipe, "this", "it", \
"the recipe" and any bare ingredient question ("how much salt?") mean that \
recipe at the servings the screen shows. The newest <screen> always wins over \
earlier turns: if it names a different recipe than the conversation was about, \
answer about the recipe now on screen. A screen of {"route": "week"}, \
"cook" or "shop" names the week it shows in "week_of"; "this week" there \
still means the week holding today, and if the member says "this week" \
while another week is on screen, ask which they mean. A screen of \
{"route": "other"} names no recipe and no week; then use find_recipe.
</screen>

<dates>
Every screen also carries "today", "today_is", "this_week" and "next_week" \
(each week by its first day). Never work out a date yourself: to name a \
day, read the week with the week tool and take the date from its "days". \
"Next week" is "next_week"; "tonight" and "today" are today. A tool's \
week_of may be any date in the week; omit it to mean the week on screen, \
else this week.
</dates>

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
Answers may be read aloud. Make them as short as they can be, amount first, \
in plain text: no markdown, no lists, no emoji. Name the line you read \
("3 tbsp tamari"), so a misheard word is obvious, but not the recipe or the \
servings the screen already shows — the member can see them. Name a recipe \
or servings only when they are not the screen's: another recipe, another \
serving count, or no recipe on screen ("3 tbsp tamari — Ragù, serves 8"). \
When an ingredient appears on more than one line, give each with its group \
("2 tbsp in the sauce, 1 tbsp in the glaze"). When find_recipe matches \
nothing, say the words you searched for: "No recipe called pad thai."
</answers>

<mishearing>
Spoken messages arrive as speech-to-text and may be misheard or misspoken. \
When a word names nothing in the recipe, look for the recipe's own \
ingredient or step that sounds or is spelled like it ("tomorrow" on a recipe \
with tamari means tamari) and answer about that, naming it. If two readings \
are both plausible, ask a short question instead of guessing.
</mishearing>

<people>
The week tool lists the household's members; the one marked "you" is the \
member speaking, so "I" and "me" mean them and "we" means everyone. A \
member named in the sentence wins over "I". If no member is marked "you" \
and the sentence says "I", ask which member is speaking.
</people>

<changes>
You never change the plan or the shopping list yourself. propose_plan_changes, \
propose_copy_last_week and propose_top_up show the member a card listing \
every change; nothing is written until they tap Confirm, and the tool \
answers only once they have decided. Say a change is made only when its \
outcome is "confirmed"; on "cancelled" say in a few words that nothing \
changed; on "changed" read the week again and propose afresh. Put a whole \
request in one proposal ("set all dinners next week" is one call with every \
day in it). To replace a meal, remove it and add the new one in the same \
proposal. Use meal ids from a week result. A meal named in words resolves \
in this order: a recipe title (find_recipe) exactly, else an ingredient \
(find_ingredient) exactly, else ask — offering the near names those tools \
return, or a meal eaten out under the member's own words. Never invent a \
recipe. "I'm eating out" takes the speaker off that meal's eaters \
(set_eaters); a meal left with no eaters is removed, and the card says so. \
Give an ingredient meal or a top-up an amount only when the member said \
one, in a unit or measure find_ingredient lists ("2 pots"); otherwise send \
none, and the app uses that ingredient's usual amount, which the card \
shows. If the tool answers that it has no usual amount, ask how much. \
Something that is not food goes on the list as an item. "Every day" with no \
week named means from today to the end of this week; with a week named, \
every day of it. When a meal is added and no slot is said, ask which meal \
(breakfast, lunch, dinner or a snack) rather than choosing one.
</changes>

<actions>
You can start a method step's own timer, change the servings shown on the \
recipe on screen, and open another recipe. These touch nothing shared, so \
they happen on the member's phone at once, with no card; say in a few words \
what you did. You cannot start a timer \
that is not a step's timer: if asked for a plain timer ("set a timer for 10 \
minutes"), say you can start a step's timer and ask which step.
</actions>

<limits>
You cannot create or edit recipes or ingredients, tick off the shopping \
list, or suggest recipes the household does not have; say the editor, the \
Shop tab or the Library does that. You only help with \
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

const DATE = {
  type: "string",
  description: "A date, YYYY-MM-DD, taken from the screen or a week result.",
};

const WEEK_OF = {
  type: "string",
  description:
    "Any date in the week meant, YYYY-MM-DD. Omit for the week on screen, " +
    "else this week.",
};

/**
 * The tools. Every one is executed by the app (`features/ask` in
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
      'names a timer by what it times ("the resting timer") rather than ' +
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
  {
    name: "week",
    description:
      "The planned meals of one week, each day with its date and weekday, " +
      "each meal with its id, slot, kind (recipe, ingredient or out), name, " +
      "eaters and portions; and the household's members, the speaker marked " +
      '"you". Pass `date` for one day only. Pass `recipe_id` for one ' +
      "recipe's meals only, with how many times it is planned and when, " +
      "counted by the app.",
    input_schema: {
      type: "object",
      properties: { week_of: WEEK_OF, date: DATE, recipe_id: RECIPE_ID },
      required: [],
      additionalProperties: false,
    },
    strict: true,
  },
  {
    name: "cook_sessions",
    description:
      "The batches the week's plan cooks, derived by the app: each with the " +
      "day it is cooked, the recipe, the portions, and the meals it feeds. " +
      "Pass `date` for the batches cooked that day.",
    input_schema: {
      type: "object",
      properties: { week_of: WEEK_OF, date: DATE },
      required: [],
      additionalProperties: false,
    },
    strict: true,
  },
  {
    name: "shopping",
    description:
      "The week's shopping list with totals written by the app. Pass " +
      "`ingredient` for the rows named like it and the meals that ask for " +
      "each; without it, what is left to buy by aisle and how many rows " +
      "are ticked.",
    input_schema: {
      type: "object",
      properties: {
        week_of: WEEK_OF,
        ingredient: { type: "string" },
      },
      required: [],
      additionalProperties: false,
    },
    strict: true,
  },
  {
    name: "find_ingredient",
    description:
      "Searches the household's ingredients by name. Returns up to five " +
      "{id, name, units, measures, usual} matches, best first: the unit ids " +
      "and measure names an amount of it may use, and the amount the app " +
      "uses when none is said.",
    input_schema: {
      type: "object",
      properties: {
        query: { type: "string", description: "Words from the name." },
      },
      required: ["query"],
      additionalProperties: false,
    },
    strict: true,
  },
  {
    name: "propose_plan_changes",
    description:
      "Shows the member a card of changes to the plan and waits for them to " +
      "Confirm or Cancel; writes nothing itself. Returns the outcome. Each " +
      "change is one of: add (date, slot, and exactly one of recipe_id, " +
      "ingredient_id or out_label; eaters default to everyone; quantity " +
      "and unit only with ingredient_id and only as said), remove " +
      "(entry_id), move (entry_id, and a new date and/or slot), set_eaters " +
      "(entry_id, eaters: member ids, possibly empty).",
    input_schema: {
      type: "object",
      properties: {
        changes: {
          type: "array",
          items: {
            type: "object",
            properties: {
              op: {
                type: "string",
                enum: ["add", "remove", "move", "set_eaters"],
              },
              entry_id: { type: "string" },
              date: DATE,
              slot: {
                type: "string",
                description:
                  "Breakfast, Lunch, Dinner, Snack, or the week's own.",
              },
              recipe_id: RECIPE_ID,
              ingredient_id: { type: "string" },
              out_label: {
                type: "string",
                description: "The words of a meal eaten out.",
              },
              eaters: { type: "array", items: { type: "string" } },
              quantity: { type: "number" },
              unit: {
                type: "string",
                description: "A unit id or measure name from find_ingredient.",
              },
            },
            required: ["op"],
            additionalProperties: false,
          },
        },
      },
      required: ["changes"],
      additionalProperties: false,
    },
    strict: true,
  },
  {
    name: "propose_copy_last_week",
    description:
      "Shows the member a card copying the latest earlier week's meals into " +
      "the week meant, as the Week tab's own copy does, and waits for their " +
      "decision. Returns the outcome.",
    input_schema: {
      type: "object",
      properties: { week_of: WEEK_OF },
      required: [],
      additionalProperties: false,
    },
    strict: true,
  },
  {
    name: "propose_top_up",
    description:
      "Shows the member a card adding to the week's shopping list and " +
      "waits for their decision. Either an ingredient_id — with a quantity " +
      "and unit only as said, else its usual amount — or an `item` of words " +
      "for something that is not food. Returns the outcome.",
    input_schema: {
      type: "object",
      properties: {
        week_of: WEEK_OF,
        ingredient_id: { type: "string" },
        quantity: { type: "number" },
        unit: {
          type: "string",
          description: "A unit id or measure name from find_ingredient.",
        },
        item: { type: "string" },
      },
      required: [],
      additionalProperties: false,
    },
    strict: true,
  },
];
