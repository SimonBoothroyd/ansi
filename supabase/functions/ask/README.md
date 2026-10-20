# `ask` — Ansi's relay

The fourth model door
([plan 0053](../../../docs/exec-plans/active/0053-ask-ansi.md)). The app sends
the whole conversation; this function adds the prompt and the tool list, makes
one model call, and hands the assistant's blocks back. The app runs every tool
and sends the next turn.

It shares `read-label`'s household gate and allowlist
(`IMPORT_ALLOWED_HOUSEHOLDS`) and failure shapes. What is its own:

- **It reads and writes nothing.** The household's rows reach the model only as
  the tool results the app chose to send. There is no Postgres seam, and
  `no_write.test.ts` refuses a statement verb, the driver or the connection
  string's name in any file this door owns.
- **Its own model pin**, `CLAUDE_ASK_MODEL = "claude-haiku-5-5"`
  (`_shared/adapters/claude_ask.ts`), chosen by its own eval
  (`evals/runner/run_ask_live.ts`), not the import doors' extraction evals.
  Claude Haiku 5.5 takes no sampling parameters and no prefill, so the request
  sends neither; it runs adaptive thinking at `effort: low`.
- **Blocks pass through verbatim.** A thinking block is valid only as it was
  produced and only while the history before it is unchanged, so the parse
  checks each block's `type` and nothing else, and the app keeps the
  conversation append-only.
- **No stream.** A turn is a sentence or a tool call; the 30 s budget
  (`ASK_DEADLINE_MS`) sits under the app's 60 s wait, which
  `_shared/timeouts.test.ts` asserts.

## The contract

```
POST { messages: [ {role, content}, … ] }      turns alternate from the member,
                                                and end on the member's turn
200  { content: [blocks], stop_reason }         refusal → content [] and the
                                                app takes the question back
400  a malformed conversation · 403 not this household · 422 nothing usable
504  out of time (safe to retry) · 500 anything else, detail in the log only
```

Caps: 120 messages and 256 KB per request. The prompt and the sixteen tools are
in `_shared/prompts/ask.ts`; the app's side is `app/lib/features/ask/`. Slice
1's six tools are strict, inside the API's per-request limits for strict schemas
(20 tools, 24 optional parameters, 16 with a union type), which
`claude_ask.test.ts` counts. The other ten are not: a strict schema is compiled
into a grammar on first use, and theirs — mostly optional fields and a nested
list of changes — took the first questions after their deploy past the 30 s
budget. The app checks every input they send and answers a bad one with a
sentence.

Two cache breakpoints: one on the system block (the prompt and tools, which
never vary) and the API's automatic one on the growing thread, so a question's
tool rounds and a follow-up within five minutes read the thread back at a tenth
of the input price rather than resending it.

Each turn logs one line — model, input, output and cache-read tokens — so the
spend can be read off the function log.
