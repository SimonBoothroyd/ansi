// The sampling params a Claude model takes. Haiku 4.5 still accepts
// `temperature`, and a pinned 0 keeps one page's extraction from wandering
// between runs; the 5.x models reject it ("`temperature` is deprecated for
// this model", HTTP 400), so for them nothing is sent. One rule for every
// adapter: matching "haiku" alone sent it to Haiku 5.5 and broke every call.

/** The models known to take `temperature`. */
const TAKES_TEMPERATURE = /^claude-(?:3|haiku-4|sonnet-4|opus-4)/;

/** `{ temperature: 0 }` where [model] takes it, otherwise nothing. */
export function pinnedSampling(model: string): { temperature?: number } {
  return TAKES_TEMPERATURE.test(model) ? { temperature: 0 } : {};
}
