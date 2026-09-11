// Building an Anthropic message STREAM for the tests, frame by frame.
//
// A test-only writer, and the mirror of what `anthropicAssembler` reads. It
// exists so a test can say what the provider sends — including the awkward
// cases: a delta at a time, a pause between them, a stream that stops before
// `message_stop`. Nothing in the deployed function imports it.

/** One SSE frame, in the wire format the Messages API uses. */
export function sseFrame(event: string, data: unknown): string {
  return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
}

export interface AnthropicStreamOptions {
  /** Text deltas, in order. Each becomes one `content_block_delta`. */
  deltas: string[];
  /** `stop_reason` on the closing `message_delta` (default `end_turn`). */
  stopReason?: string | null;
  /** Usage as `message_start` reports it (input + cache counts). */
  inputUsage?: Record<string, number>;
  /** Usage as `message_delta` reports it (the final output count). */
  outputUsage?: Record<string, number>;
  /** Omit `message_stop` — a stream that died mid-answer. */
  unterminated?: boolean;
  /** Model id echoed back in `message_start` (default `test-model`). */
  model?: string;
}

/** The frames a complete (or deliberately incomplete) message is made of. */
export function anthropicFrames(opts: AnthropicStreamOptions): string[] {
  const frames = [
    sseFrame("message_start", {
      type: "message_start",
      message: {
        id: "msg_test",
        type: "message",
        role: "assistant",
        model: opts.model ?? "test-model",
        content: [],
        stop_reason: null,
        usage: opts.inputUsage ?? { input_tokens: 10 },
      },
    }),
    sseFrame("content_block_start", {
      type: "content_block_start",
      index: 0,
      content_block: { type: "text", text: "" },
    }),
  ];
  for (const text of opts.deltas) {
    frames.push(sseFrame("content_block_delta", {
      type: "content_block_delta",
      index: 0,
      delta: { type: "text_delta", text },
    }));
  }
  frames.push(sseFrame("content_block_stop", {
    type: "content_block_stop",
    index: 0,
  }));
  frames.push(sseFrame("message_delta", {
    type: "message_delta",
    delta: { stop_reason: opts.stopReason ?? "end_turn", stop_sequence: null },
    usage: opts.outputUsage ?? { output_tokens: 20 },
  }));
  if (!opts.unterminated) {
    frames.push(sseFrame("message_stop", { type: "message_stop" }));
  }
  return frames;
}

export interface SseResponseInit {
  /** Delay BEFORE each frame (one number, or one per frame). */
  pauseMs?: number | number[];
  status?: number;
  /**
   * Go quiet after the last frame instead of closing — a provider that stopped
   * answering without hanging up. It ends only when `signal` aborts, which is
   * how a test tells SILENCE from a slow answer.
   */
  stall?: boolean;
  /**
   * The caller's abort signal. A real `fetch` fails its body read on abort;
   * a stub has to be told to, or a test's idle timer fires into nothing.
   */
  signal?: AbortSignal | null;
}

/** A `text/event-stream` Response over `frames`. */
export function sseResponse(
  frames: string[],
  init: SseResponseInit = {},
): Response {
  const encoder = new TextEncoder();
  const pauseFor = (i: number): number =>
    Array.isArray(init.pauseMs) ? init.pauseMs[i] ?? 0 : init.pauseMs ?? 0;
  let i = 0;
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      const signal = init.signal;
      if (!signal) return;
      const fail = () =>
        controller.error(
          new DOMException("The signal has been aborted", "AbortError"),
        );
      if (signal.aborted) fail();
      else signal.addEventListener("abort", fail, { once: true });
    },
    async pull(controller) {
      if (i >= frames.length) {
        // Never resolves — no timer to leak, and the abort above is what ends
        // it. A `return` here would close the stream, which is a different
        // failure entirely (a stream that stopped mid-message).
        if (init.stall) return await new Promise<void>(() => {});
        controller.close();
        return;
      }
      const wait = pauseFor(i);
      if (wait > 0) await new Promise((r) => setTimeout(r, wait));
      controller.enqueue(encoder.encode(frames[i++]));
    },
  });
  return new Response(body, {
    status: init.status ?? 200,
    headers: { "content-type": "text/event-stream" },
  });
}

/** The whole of one message as a streamed Response — the common case. */
export function anthropicStream(
  opts: AnthropicStreamOptions,
  init: SseResponseInit = {},
): Response {
  return sseResponse(anthropicFrames(opts), init);
}

/** One text response, split into `parts` deltas — the shortest useful stub. */
export function anthropicText(text: string, parts = 2): Response {
  const size = Math.max(1, Math.ceil(text.length / parts));
  const deltas: string[] = [];
  for (let i = 0; i < text.length; i += size) {
    deltas.push(text.slice(i, i + size));
  }
  return anthropicStream({ deltas: deltas.length > 0 ? deltas : [""] });
}
