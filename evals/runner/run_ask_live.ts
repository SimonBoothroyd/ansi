// The ask door's live eval (plan 0053): every case in `datasets/ask/cases.jsonl`
// through the real adapter and prompt. PAID — it needs ANTHROPIC_API_KEY and
// spends a fraction of a cent a case; it never runs in `run.sh`.
//
//   deno run --allow-read --allow-env --allow-net runner/run_ask_live.ts
//
// Per case: the question goes up with its screen; the first move is graded
// (`scoreFirstMove`). When the case carries a canned `result`, it is fed back
// as the expected call's result and the answer is graded (`scoreAnswer`):
// required words present, no number invented. A case with no tool expected
// grades the first answer directly. A case with a `then_tool` grades the move
// after the result instead (`scoreThenMove`): which proposal, holding which
// change — or none at all.

import {
  ClaudeAskAdapter,
} from "../../supabase/functions/_shared/adapters/claude_ask.ts";
import type {
  AskBlock,
  AskMessage,
} from "../../supabase/functions/_shared/ask_types.ts";
import type { ProviderCall } from "../../supabase/functions/_shared/types.ts";
import { PRICING } from "./pricing.ts";
import {
  type AskCase,
  parseCases,
  scoreAnswer,
  scoreFirstMove,
  scoreThenMove,
  type ToolCall,
} from "./score_ask.ts";

function firstCall(content: AskBlock[]): (ToolCall & { id: string }) | null {
  const b = content.find((x) => x.type === "tool_use");
  return b
    ? {
      id: String(b.id),
      name: String(b.name),
      input: (b.input ?? {}) as Record<string, unknown>,
    }
    : null;
}

function textOf(content: AskBlock[]): string {
  return content.filter((b) => b.type === "text").map((b) => String(b.text))
    .join("\n").trim();
}

async function runCase(adapter: ClaudeAskAdapter, c: AskCase) {
  const question = `<screen>${
    JSON.stringify(c.screen)
  }</screen>\n${c.question}`;
  const messages: AskMessage[] = [{
    role: "user",
    content: [{ type: "text", text: question }],
  }];
  const first = await adapter.turn(messages);
  const call = firstCall(first.content);
  const move = scoreFirstMove(c, call);
  let answer: { pass: boolean; why: string } | null = null;
  const given = [question];

  if (c.expect_tool === null && !call && c.answer_includes) {
    answer = scoreAnswer(c, textOf(first.content), given);
  } else if (
    c.then_tool !== undefined && c.result !== undefined && call &&
    move.pass
  ) {
    messages.push({ role: "assistant", content: first.content });
    messages.push({
      role: "user",
      content: [{
        type: "tool_result",
        tool_use_id: call.id,
        content: c.result,
      }],
    });
    const second = await adapter.turn(messages);
    answer = scoreThenMove(c, firstCall(second.content));
  } else if (c.result !== undefined && call && move.pass) {
    given.push(c.result);
    messages.push({ role: "assistant", content: first.content });
    messages.push({
      role: "user",
      content: [{
        type: "tool_result",
        tool_use_id: call.id,
        content: c.result,
      }],
    });
    const second = await adapter.turn(messages);
    answer = scoreAnswer(c, textOf(second.content), given);
  }
  return { move, answer };
}

async function main() {
  if (!Deno.env.get("ANTHROPIC_API_KEY")) {
    console.error("run_ask_live: set ANTHROPIC_API_KEY — this run is paid.");
    Deno.exit(2);
  }
  const cases = parseCases(
    await Deno.readTextFile(
      new URL("../datasets/ask/cases.jsonl", import.meta.url),
    ),
  );
  const calls: ProviderCall[] = [];
  const adapter = new ClaudeAskAdapter();
  adapter.onCall = (c) => calls.push(c);

  let moves = 0;
  let answers = 0;
  let graded = 0;
  for (const c of cases) {
    try {
      const { move, answer } = await runCase(adapter, c);
      if (move.pass) moves++;
      if (answer) {
        graded++;
        if (answer.pass) answers++;
      }
      console.log(
        `${move.pass && (answer?.pass ?? true) ? "PASS" : "FAIL"}  ${c.id}` +
          `  · move: ${move.why}` + (answer ? `  · answer: ${answer.why}` : ""),
      );
    } catch (e) {
      console.log(`ERROR ${c.id}  · ${e instanceof Error ? e.message : e}`);
    }
  }

  const price = PRICING[adapter.model];
  let usd = 0;
  for (const call of calls) {
    const u = call.usage;
    if (!u || !price) continue;
    usd += ((u.input_tokens ?? 0) * price.usd_per_mtok_input +
      (u.output_tokens ?? 0) * price.usd_per_mtok_output +
      (u.cache_read_tokens ?? 0) * (price.usd_per_mtok_cache_read ?? 0) +
      (u.cache_write_tokens ?? 0) * (price.usd_per_mtok_cache_write ?? 0)) /
      1e6;
  }
  console.log(
    `\n${adapter.model}: first moves ${moves}/${cases.length}, ` +
      `answers ${answers}/${graded}, ${calls.length} calls, ` +
      `$${usd.toFixed(4)}` + (price ? "" : " (no pricing row)"),
  );
}

if (import.meta.main) await main();
