// The ask door's contract (plan 0053). Zero imports, like the other `_types`
// files, so a test of the parse or the handler pulls in no adapter.
//
// The wire IS the Messages API's: the app keeps the conversation and sends it
// whole each turn, and this door relays it. Content blocks pass through
// verbatim, thinking blocks included — a thinking block must come back
// exactly as it was produced, so nothing here may rewrite one.

/** One content block, opaque past its `type`. */
export type AskBlock = Record<string, unknown> & { type: string };

/** One turn of the conversation, as the Messages API takes it. */
export interface AskMessage {
  role: "user" | "assistant";
  content: string | AskBlock[];
}

/** What one model call answered. */
export interface AskReply {
  /** The assistant's blocks: `thinking`, `redacted_thinking`, `text`,
   *  `tool_use`. Empty when the model declined (`stop_reason: "refusal"`). */
  content: AskBlock[];
  /** `end_turn`, `tool_use`, `max_tokens` or `refusal`. */
  stop_reason: string;
}

/** The model seam. The live one is `adapters/claude_ask.ts`. */
export interface AskAdapter {
  readonly model: string;
  turn(messages: AskMessage[]): Promise<AskReply>;
}
