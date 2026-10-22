// Scorers for the ask door (plan 0053). Pure functions over one model turn,
// keyless, self-tested in `score_ask.test.ts`.
//
// Two things are graded, matching the door's two rules:
//
//   1. **The model points.** Its first move on a question is the right tool
//      with the right ids — or, for a refusal case, no action tool at all.
//   2. **The app counts.** Every number in a final answer appears in what
//      the model was given (the tool results and the question); a number
//      found nowhere is invented, and an invented number fails the case
//      whatever else it got right.

/** One eval case, a line of `datasets/ask/cases.jsonl`. */
export interface AskCase {
  id: string;
  /** What the case is checking, in a sentence. */
  why: string;
  /** The `<screen>` JSON the app would send. */
  screen: Record<string, unknown>;
  /** What the member said (or what speech-to-text heard). */
  question: string;
  /** The first tool call expected, or null for "answer or ask without one". */
  expect_tool: string | null;
  /** Input keys the call must carry, compared loosely (see `inputMatches`). */
  expect_input?: Record<string, unknown>;
  /** A tool the model must NOT call (the refusal cases). */
  forbid_tool?: string;
  /** The canned result fed back for the expected call, when the case goes on
   *  to grade the answer. */
  result?: string;
  /** Strings the final answer must contain (case-insensitive). */
  answer_includes?: string[];
  /** Strings the final answer must not contain (case-insensitive): what the
   *  screen already shows, which a concise answer leaves out. */
  answer_excludes?: string[];
  /** The model's next move once [result] is fed back: a tool it must call,
   *  or null for "no proposal" (it answers, asks, or reads on). Graded
   *  instead of the answer. */
  then_tool?: string | null;
  /** Keys one change in that call's `changes` must carry, compared like
   *  `expect_input` — the change a proposal must hold. */
  then_change?: Record<string, unknown>;
}

/** A tool call as the API returns it. */
export interface ToolCall {
  name: string;
  input: Record<string, unknown>;
}

/** The tool names, as the function declares them. */
export const ASK_TOOL_NAMES = [
  "find_recipe",
  "recipe_lines",
  "method_step",
  "start_step_timer",
  "set_servings",
  "open_recipe",
  "week",
  "cook_sessions",
  "shopping",
  "find_ingredient",
  "nutrition",
  "cost",
  "prices",
  "propose_plan_changes",
  "propose_copy_last_week",
  "propose_top_up",
];

/**
 * Whether [actual] carries every expected key. Strings compare
 * case-insensitively and by containment (the model may send "Tamari" or
 * "tamari sauce" for "tamari"); everything else compares exactly.
 */
export function inputMatches(
  actual: Record<string, unknown>,
  expected: Record<string, unknown>,
): boolean {
  for (const [key, want] of Object.entries(expected)) {
    const got = actual[key];
    if (typeof want === "string") {
      if (typeof got !== "string") return false;
      if (!got.toLowerCase().includes(want.toLowerCase())) return false;
    } else if (got !== want) {
      return false;
    }
  }
  return true;
}

/** Grades the model's first move against the case. */
export function scoreFirstMove(
  c: AskCase,
  call: ToolCall | null,
): { pass: boolean; why: string } {
  if (c.forbid_tool && call?.name === c.forbid_tool) {
    return { pass: false, why: `called ${c.forbid_tool}, which it must not` };
  }
  if (c.expect_tool === null) {
    return { pass: true, why: call ? `called ${call.name}` : "no tool" };
  }
  if (!call) return { pass: false, why: `no tool; expected ${c.expect_tool}` };
  if (call.name !== c.expect_tool) {
    return {
      pass: false,
      why: `called ${call.name}; expected ${c.expect_tool}`,
    };
  }
  if (c.expect_input && !inputMatches(call.input, c.expect_input)) {
    return {
      pass: false,
      why: `${call.name} with ${JSON.stringify(call.input)}; expected ` +
        JSON.stringify(c.expect_input),
    };
  }
  return { pass: true, why: call.name };
}

/**
 * Grades the move after the first tool's result: the expected tool, with a
 * change that matches [AskCase.then_change] — or, for `then_tool: null`, no
 * `propose_*` tool at all.
 */
export function scoreThenMove(
  c: AskCase,
  call: ToolCall | null,
): { pass: boolean; why: string } {
  if (c.then_tool === null) {
    return call?.name.startsWith("propose_")
      ? { pass: false, why: `proposed with ${call.name}, which it must not` }
      : { pass: true, why: call ? `then ${call.name}` : "then no tool" };
  }
  if (!call) {
    return { pass: false, why: `then no tool; expected ${c.then_tool}` };
  }
  if (call.name !== c.then_tool) {
    return { pass: false, why: `then ${call.name}; expected ${c.then_tool}` };
  }
  if (c.then_change) {
    const changes = Array.isArray(call.input.changes)
      ? call.input.changes as Record<string, unknown>[]
      : [];
    if (!changes.some((ch) => inputMatches(ch, c.then_change!))) {
      return {
        pass: false,
        why: `then ${call.name} with ${JSON.stringify(call.input)}; ` +
          `expected a change ${JSON.stringify(c.then_change)}`,
      };
    }
  }
  return { pass: true, why: `then ${call.name}` };
}

/** The vulgar fractions the app prints (`formatAmount`). */
const FRACTIONS = "½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞";

/** Every number written in [text]: `3`, `1.5`, `1½`, `½`, `20–25`'s two. */
export function numbersIn(text: string): string[] {
  const re = new RegExp(`\\d+(?:[.,]\\d+)?[${FRACTIONS}]?|[${FRACTIONS}]`, "g");
  return text.match(re) ?? [];
}

/**
 * The numbers in [answer] that appear in none of [given] — what the model
 * made up. Step and servings numbers count as given when the question or a
 * result says them.
 */
export function inventedNumbers(answer: string, given: string[]): string[] {
  const pool = given.join("\n");
  return numbersIn(answer).filter((n) => !pool.includes(n));
}

/** Grades a final answer: required words present, no number invented. */
export function scoreAnswer(
  c: AskCase,
  answer: string,
  given: string[],
): { pass: boolean; why: string } {
  const invented = inventedNumbers(answer, given);
  if (invented.length > 0) {
    return { pass: false, why: `invented ${invented.join(", ")}` };
  }
  const lower = answer.toLowerCase();
  const missing = (c.answer_includes ?? []).filter((w) =>
    !lower.includes(w.toLowerCase())
  );
  if (missing.length > 0) {
    return { pass: false, why: `missing ${missing.join(", ")}` };
  }
  const repeated = (c.answer_excludes ?? []).filter((w) =>
    lower.includes(w.toLowerCase())
  );
  if (repeated.length > 0) {
    return { pass: false, why: `repeats ${repeated.join(", ")}` };
  }
  return { pass: true, why: "ok" };
}

/** Parses the dataset, refusing a case that names an unknown tool. */
export function parseCases(jsonl: string): AskCase[] {
  const cases: AskCase[] = [];
  for (const [i, line] of jsonl.split("\n").entries()) {
    if (line.trim() === "") continue;
    const c = JSON.parse(line) as AskCase;
    for (const name of [c.expect_tool, c.forbid_tool]) {
      if (name && !ASK_TOOL_NAMES.includes(name)) {
        throw new Error(`line ${i + 1} (${c.id}) names unknown tool ${name}`);
      }
    }
    if (c.result !== undefined && c.expect_tool === null) {
      throw new Error(`line ${i + 1} (${c.id}) has a result but no tool`);
    }
    if (c.then_tool !== undefined && c.result === undefined) {
      throw new Error(`line ${i + 1} (${c.id}) has a then_tool but no result`);
    }
    if (c.then_tool && !ASK_TOOL_NAMES.includes(c.then_tool)) {
      throw new Error(
        `line ${i + 1} (${c.id}) names unknown tool ${c.then_tool}`,
      );
    }
    cases.push(c);
  }
  return cases;
}
