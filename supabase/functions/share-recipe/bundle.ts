// The compiled renderer, evaluated, and its source for browsers.
//
// The bundle is a classic script that sets `globalThis.ansiSharePage` when it
// is evaluated; importing it for its effect is how it is evaluated here, and
// how the deploy finds it to ship. The same source, as a string module
// (`share_page_source.ts`, generated beside it), is what browsers are served
// at `r/share.js` — a deployed function is modules, not files to read.

import "./share_page.js";
import { SHARE_BUNDLE } from "./share_page_source.ts";
import type { RenderPage } from "./index.ts";

export { SHARE_BUNDLE };

/** The renderer the bundle exported when it was evaluated. */
export function bundledRenderer(): RenderPage {
  const render = (globalThis as Record<string, unknown>).ansiSharePage;
  if (typeof render !== "function") {
    throw new Error("share_page.js did not export ansiSharePage");
  }
  return render as RenderPage;
}

/** The first twelve hex characters of [text]'s SHA-256. */
export async function shortHash(text: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 12);
}
