// The privacy policy's page: the repository's `PRIVACY.md`, rendered to HTML.
//
// The Markdown is imported as text, so `wrangler` bundles the file as it
// stands in the checkout it deploys from and Deno's tests read the same file:
// there is no copy to fall behind. The renderer knows only what the policy
// uses — `#` headings, paragraphs, `-` lists, bold, italic, inline code and
// links — and escapes everything else, so anything new shows as the text it
// is rather than as markup.

import policy from "../../PRIVACY.md" with { type: "text" };

/** The Markdown the page is made from, as bundled. */
export const PRIVACY_MD: string = policy;

const ESCAPES: Record<string, string> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
};

export function escapeHtml(text: string): string {
  return text.replace(/[&<>"']/g, (c) => ESCAPES[c]);
}

/** Only addresses a reader can follow safely; anything else stays text. */
const SAFE_HREF = /^(https:\/\/|http:\/\/|mailto:)/i;

const INLINE =
  /`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)|\*\*(.+?)\*\*|\*([^*\s][^*]*?)\*|(?<![A-Za-z0-9])_([^_\s][^_]*?)_(?![A-Za-z0-9])/g;

/** One line's inline Markdown, as escaped HTML. */
export function renderInline(text: string): string {
  let out = "";
  let last = 0;
  for (const m of text.matchAll(INLINE)) {
    out += escapeHtml(text.slice(last, m.index));
    last = m.index + m[0].length;
    const [whole, code, label, href, strong, em, em2] = m;
    if (code !== undefined) {
      out += `<code>${escapeHtml(code)}</code>`;
    } else if (label !== undefined) {
      out += SAFE_HREF.test(href)
        ? `<a href="${escapeHtml(href)}">${renderInline(label)}</a>`
        : escapeHtml(whole);
    } else if (strong !== undefined) {
      out += `<strong>${renderInline(strong)}</strong>`;
    } else {
      out += `<em>${renderInline(em ?? em2)}</em>`;
    }
  }
  return out + escapeHtml(text.slice(last));
}

/** The policy's Markdown as body HTML, and its first heading as the title. */
export function renderMarkdown(md: string): { title: string; body: string } {
  const blocks: string[] = [];
  let title = "";
  let paragraph: string[] = [];
  let items: string[][] = [];

  const flush = () => {
    if (paragraph.length) {
      blocks.push(`<p>${renderInline(paragraph.join(" "))}</p>`);
      paragraph = [];
    }
    if (items.length) {
      const lis = items.map((i) => `<li>${renderInline(i.join(" "))}</li>`);
      blocks.push(`<ul>\n${lis.join("\n")}\n</ul>`);
      items = [];
    }
  };

  for (const raw of md.replace(/\r\n?/g, "\n").split("\n")) {
    const line = raw.trimEnd();
    const heading = line.match(/^(#{1,6})\s+(.*)$/);
    const item = line.match(/^[-*]\s+(.*)$/);
    if (line.trim() === "") {
      flush();
    } else if (heading) {
      flush();
      const level = heading[1].length;
      const text = heading[2].replace(/\s+#+$/, "");
      if (!title) title = text;
      blocks.push(`<h${level}>${renderInline(text)}</h${level}>`);
    } else if (item) {
      if (paragraph.length) flush();
      items.push([item[1]]);
    } else if (items.length && /^\s/.test(line)) {
      items[items.length - 1].push(line.trim());
    } else {
      if (items.length) flush();
      paragraph.push(line.trim());
    }
  }
  flush();
  return { title, body: blocks.join("\n") };
}

const STYLE = `
:root { color-scheme: light dark; }
body {
  margin: 0; padding: 1.5rem 1rem 3rem;
  font: 1.0625rem/1.6 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  background: Canvas; color: CanvasText;
}
main { max-width: 40rem; margin: 0 auto; overflow-wrap: break-word; }
h1 { font-size: 1.6rem; line-height: 1.25; margin: 0 0 1rem; }
h2 { font-size: 1.2rem; line-height: 1.3; margin: 2rem 0 0.5rem; }
ul { padding-left: 1.25rem; }
li + li { margin-top: 0.5rem; }
code { font-family: ui-monospace, Menlo, monospace; font-size: 0.9em; }
a { color: LinkText; }
`.trim();

/** The whole page for [md]. */
export function privacyPage(md: string): string {
  const { title, body } = renderMarkdown(md);
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>${escapeHtml(title || "Privacy policy")}</title>
<style>
${STYLE}
</style>
</head>
<body>
<main>
${body}
</main>
</body>
</html>
`;
}

/** The page as the Worker serves it, rendered once per isolate. */
export const PRIVACY_PAGE: string = privacyPage(PRIVACY_MD);
