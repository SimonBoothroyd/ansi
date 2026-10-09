// Runs the compiled share-page bundle the way the edge function will — a
// classic script evaluated into a Deno isolate with no document — and checks
// the page it renders from the shared payload fixture.
//
//   deno run --allow-read scripts/share_bundle_smoke.ts <bundle.js> <payload.json>

const [bundlePath, payloadPath] = Deno.args;
if (!bundlePath || !payloadPath) {
  throw new Error("usage: share_bundle_smoke.ts <bundle.js> <payload.json>");
}

// Indirect eval: the bundle is a classic script and sets a global.
(0, eval)(await Deno.readTextFile(bundlePath));
const render = (globalThis as Record<string, unknown>).ansiSharePage;
if (typeof render !== "function") {
  throw new Error("the bundle did not export ansiSharePage");
}

const html = (render as (p: string, u: string, b: string) => string)(
  await Deno.readTextFile(payloadPath),
  "https://getansi.app/r/smoke",
  "/r/share_page.js",
);

const expected = [
  "<title>Miso Noodles &lt;spicy&gt;</title>",
  '<script type="application/ld+json">',
  '<span class="amt">2 blob (30 g)</span>',
  "<dt>kcal</dt><dd>346</dd>",
  'data-seconds="270"',
];
const missing = expected.filter((s) => !html.includes(s));
if (missing.length > 0) {
  throw new Error(`the rendered page is missing:\n  ${missing.join("\n  ")}`);
}
const size = (await Deno.stat(bundlePath)).size;
console.log(
  `  ✓ share bundle renders the fixture (${
    Math.round(size / 1024)
  } KB, ${html.length} chars of HTML)`,
);
