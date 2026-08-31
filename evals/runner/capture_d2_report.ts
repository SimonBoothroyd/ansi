// Per-recipe "what each model got right vs wrong" capture + side-by-side
// comparison for the extraction benchmark (D2 · page_text · TEXT input).
//
// ONE cheap pass over the 11 gold recipes for BOTH providers:
//   - claude-haiku-4-5  (ClaudeHaikuAdapter)
//   - gpt-5.4-mini      (GptMiniAdapter)
// => 22 text calls, no images. Scored with the SAME per-line + dangerous-ledger
// logic as score_extraction.ts (imported, not rewritten), then rendered to a
// self-contained, theme-aware HTML report that puts both providers' output side
// by side against the gold, line by line, clearly attributed.
//
// Run from evals/ (source ../.env.local first so the keys are set):
//   deno run --config ../supabase/functions/deno.json \
//     --allow-read --allow-env --allow-net runner/capture_d2_report.ts
//
// Writes evals/reports/extraction-d2-compare.html (+ a .json data dump).

import type {
  ExtractAdapter,
  ExtractionResult,
  RawLineItem,
} from "../../supabase/functions/_shared/types.ts";
import {
  ClaudeHaikuAdapter,
  GptMiniAdapter,
} from "../../supabase/functions/_shared/adapters/mod.ts";
import { flattenLines } from "../../supabase/functions/_shared/adapters/schema.ts";
import { normalize } from "../../supabase/functions/_shared/normalize.ts";
import {
  type GoldCase,
  type GoldRecipe,
  goldToBlob,
  loadGold,
  UNIT_HINTS,
} from "./fixtures.ts";
import {
  alignLines,
  amountShape,
  type CaseScore,
  EMPTY_RESULT,
  ledgerTotal,
  notesAgree,
  qtyMatch,
  scoreExtraction,
  unitMatch,
} from "./score_extraction.ts";

const PROVIDERS = ["claude", "gpt"] as const;
type ProviderKey = typeof PROVIDERS[number];
const PROVIDER_LABEL: Record<ProviderKey, string> = {
  claude: "claude-haiku-4-5",
  gpt: "gpt-5.4-mini",
};

// --- captured shapes ---------------------------------------------------------

interface LineView {
  raw_amount: string;
  ingredient: string;
  notes: string | null;
  optional: boolean;
  unit: string | null;
  unit_mappable: boolean;
  shape: "single" | "range" | "none";
}

/** One provider's take on a single GOLD line (aligned, or missed). */
interface ProvCell {
  present: boolean; // aligned to this gold line
  got: LineView | null;
  ingredientExact: boolean;
  qtyOk: boolean | null;
  unitOk: boolean | null;
  notesOk: boolean | null;
  danger: string[]; // per-line dangerous events on this pair
  correct: boolean; // present && qtyOk && unitOk (headline "line right")
}

interface GoldRow {
  gold: LineView;
  cells: Record<ProviderKey, ProvCell>;
  diverge: boolean; // providers disagree on correctness
}

/** A provider's hallucinated (extra) line — no gold anchor. */
interface ExtraRow {
  provider: ProviderKey;
  got: LineView;
}

interface ProvScore {
  line_p: number;
  line_r: number;
  line_f1: number;
  qty_acc: number;
  unit_acc: number;
  notes_acc: number;
  aligned: number;
  got_lines: number;
  title_match: boolean;
  servings_match: boolean;
  title_got: string;
  servings_got: string;
  ledger: CaseScore["ledger"];
  ledger_total: number;
  recipe_danger: string[];
  error: string | null;
}

interface RecipeReport {
  id: string;
  title_gold: string;
  servings_gold: string;
  gold_lines: number;
  rows: GoldRow[];
  extras: ExtraRow[];
  score: Record<ProviderKey, ProvScore>;
  review: string[];
}

function toView(li: RawLineItem): LineView {
  return {
    raw_amount: li.raw_amount,
    ingredient: li.ingredient_text,
    notes: li.notes,
    optional: li.optional,
    unit: li.unit,
    unit_mappable: li.unit_mappable,
    shape: amountShape(li),
  };
}

function servingsText(
  r: { servings_base: number | null; servings_raw: string | null },
): string {
  const parts: string[] = [];
  parts.push(
    r.servings_base === null ? "base=null" : `base=${r.servings_base}`,
  );
  if (r.servings_raw) parts.push(`"${r.servings_raw}"`);
  return parts.join(" ");
}

// Per-line dangerous-ledger events on an aligned pair — mirrors the exact
// conditions in score_extraction.ts's scoreExtraction (reusing amountShape).
function pairDanger(g: RawLineItem, t: RawLineItem): string[] {
  const out: string[] = [];
  if (amountShape(g) === "none" && amountShape(t) !== "none") {
    out.push("invented_qty");
  }
  if (amountShape(g) === "range" && amountShape(t) === "single") {
    out.push("collapsed_range");
  }
  if (!g.unit_mappable && t.unit_mappable) out.push("forced_unit");
  return out;
}

async function runProvider(
  adapter: ExtractAdapter,
  gold: GoldRecipe,
  id: string,
): Promise<{ got: ExtractionResult; error: string | null }> {
  try {
    const got = await adapter.sanitize(goldToBlob(gold), UNIT_HINTS);
    return { got, error: null };
  } catch (e) {
    const error = e instanceof Error ? e.message : String(e);
    console.error(`  ! ${adapter.name}/${id}: ${error}`);
    return { got: EMPTY_RESULT, error };
  }
}

function provScore(
  id: string,
  gold: GoldRecipe,
  got: ExtractionResult,
  error: string | null,
): ProvScore {
  const s = scoreExtraction(id, gold, got, error === null);
  const recipeDanger: string[] = [];
  if (s.ledger.invented_time > 0) {
    recipeDanger.push(`invented_time ×${s.ledger.invented_time}`);
  }
  if (s.ledger.invented_servings > 0) {
    recipeDanger.push(`invented_servings ×${s.ledger.invented_servings}`);
  }
  if (s.ledger.invented_timers > 0) {
    recipeDanger.push(`invented_timers ×${s.ledger.invented_timers}`);
  }
  if (s.ledger.structural_flags > 0) {
    recipeDanger.push(`structural_flags ×${s.ledger.structural_flags}`);
  }
  return {
    line_p: s.line.p,
    line_r: s.line.r,
    line_f1: s.line.f1,
    // Gold-denominator readings (an omitted line counts as wrong) — the same
    // headline score_extraction.ts reports.
    qty_acc: s.qty_acc,
    unit_acc: s.unit_acc,
    notes_acc: s.notes_agree,
    aligned: s.aligned,
    got_lines: flattenLines(got).length,
    title_match: s.title_match,
    servings_match: s.servings_correct,
    title_got: got.title,
    servings_got: servingsText(got),
    ledger: s.ledger,
    ledger_total: ledgerTotal(s.ledger),
    recipe_danger: recipeDanger,
    error,
  };
}

async function capture(): Promise<RecipeReport[]> {
  const cases: GoldCase[] = await loadGold();
  const adapters: Record<ProviderKey, ExtractAdapter> = {
    claude: new ClaudeHaikuAdapter(), // claude-haiku-4-5, ANTHROPIC_API_KEY
    gpt: new GptMiniAdapter(), // gpt-5.4-mini, OPENAI_API_KEY
  };
  const reports: RecipeReport[] = [];

  for (const c of cases) {
    const gold = c.gold as GoldRecipe;
    const goldLines = flattenLines(gold);

    const got: Record<ProviderKey, ExtractionResult> = {} as never;
    const score: Record<ProviderKey, ProvScore> = {} as never;
    const align: Record<ProviderKey, ReturnType<typeof alignLines>> =
      {} as never;
    const gotLines: Record<ProviderKey, RawLineItem[]> = {} as never;

    for (const p of PROVIDERS) {
      const { got: g, error } = await runProvider(adapters[p], gold, c.id);
      got[p] = g;
      gotLines[p] = flattenLines(g);
      align[p] = alignLines(goldLines, gotLines[p]);
      score[p] = provScore(c.id, gold, g, error);
      console.log(
        `  ${c.id.padEnd(30)} ${PROVIDER_LABEL[p].padEnd(16)} ` +
          `F1=${(score[p].line_f1 * 100).toFixed(0).padStart(3)}% ` +
          `qty=${(score[p].qty_acc * 100).toFixed(0).padStart(3)}% ` +
          `unit=${(score[p].unit_acc * 100).toFixed(0).padStart(3)}% ` +
          `notes=${(score[p].notes_acc * 100).toFixed(0).padStart(3)}% ` +
          `danger=${score[p].ledger_total}${error ? "  ERROR" : ""}`,
      );
    }

    // goldIdx -> gotIdx per provider
    const goldToGot: Record<ProviderKey, Map<number, number>> = {
      claude: new Map(),
      gpt: new Map(),
    };
    for (const p of PROVIDERS) {
      for (const pair of align[p].pairs) {
        goldToGot[p].set(pair.goldIdx, pair.gotIdx);
      }
    }

    const rows: GoldRow[] = goldLines.map((g, gi) => {
      const cells = {} as Record<ProviderKey, ProvCell>;
      for (const p of PROVIDERS) {
        const gotIdx = goldToGot[p].get(gi);
        if (gotIdx === undefined) {
          cells[p] = {
            present: false,
            got: null,
            ingredientExact: false,
            qtyOk: null,
            unitOk: null,
            notesOk: null,
            danger: [],
            correct: false,
          };
        } else {
          const t = gotLines[p][gotIdx];
          const qOk = qtyMatch(g, t);
          const uOk = unitMatch(g, t);
          cells[p] = {
            present: true,
            got: toView(t),
            ingredientExact:
              normalize(g.ingredient_text) === normalize(t.ingredient_text),
            qtyOk: qOk,
            unitOk: uOk,
            notesOk: notesAgree(g, t),
            danger: pairDanger(g, t),
            correct: qOk && uOk,
          };
        }
      }
      return {
        gold: toView(g),
        cells,
        diverge: cells.claude.correct !== cells.gpt.correct,
      };
    });

    const extras: ExtraRow[] = [];
    for (const p of PROVIDERS) {
      for (const ti of align[p].extraGot) {
        extras.push({ provider: p, got: toView(gotLines[p][ti]) });
      }
    }

    reports.push({
      id: c.id,
      title_gold: gold.title,
      servings_gold: servingsText(gold),
      gold_lines: goldLines.length,
      rows,
      extras,
      score,
      review: gold._review ?? [],
    });
  }
  return reports;
}

// --- HTML rendering ----------------------------------------------------------

function esc(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function pct(x: number): string {
  // A dump written before a metric existed has no value for it — render an
  // honest dash rather than "NaN%".
  return Number.isFinite(x) ? (x * 100).toFixed(1) + "%" : "—";
}

function tick(ok: boolean | null | undefined): string {
  if (ok === null || ok === undefined) return `<span class="na">—</span>`;
  return ok
    ? `<span class="yes">&#10003;</span>`
    : `<span class="no">&#10007;</span>`;
}

function lineCell(v: LineView | null): string {
  if (!v) return `<span class="na">—</span>`;
  const rawAmt = v.raw_amount ?? ""; // gold "to taste" lines carry null here
  const amt = rawAmt.trim() === "" ? "∅" : esc(rawAmt);
  const notes: string[] = [];
  if (v.notes) notes.push(esc(v.notes));
  if (v.optional) notes.push("optional");
  if (v.unit) {
    notes.push(`unit=${esc(v.unit)}${v.unit_mappable ? "" : " (unmappable)"}`);
  }
  const noteHtml = notes.length
    ? `<div class="notes">${notes.join(" · ")}</div>`
    : "";
  return `<div class="amt">${amt}</div><div class="ing">${
    esc(v.ingredient)
  }</div>${noteHtml}`;
}

function dangerBadges(danger: string[]): string {
  if (danger.length === 0) return "";
  return `<div class="dwrap">${
    danger.map((d) => `<span class="dbadge">${esc(d)}</span>`).join(" ")
  }</div>`;
}

function provGotCell(cell: ProvCell): string {
  if (!cell.present) {
    return `<span class="no bold" title="gold line this provider omitted">MISSED</span>`;
  }
  const fuzzy = cell.ingredientExact
    ? ""
    : `<span class="fuzzy" title="aligned by fuzzy match; identity text differs from gold">~</span> `;
  return `${fuzzy}${lineCell(cell.got)}${dangerBadges(cell.danger)}`;
}

function recipeSection(r: RecipeReport): string {
  const rowsHtml = r.rows
    .map((row) => {
      const rowCls = row.diverge ? "row-diverge" : "";
      const cCls = row.cells.claude.present
        ? (row.cells.claude.correct && row.cells.claude.danger.length === 0
          ? "prov-ok"
          : "prov-warn")
        : "prov-missed";
      const gCls = row.cells.gpt.present
        ? (row.cells.gpt.correct && row.cells.gpt.danger.length === 0
          ? "prov-ok"
          : "prov-warn")
        : "prov-missed";
      return `<tr class="${rowCls}">
        <td class="c-gold">${lineCell(row.gold)}</td>
        <td class="c-prov ${cCls}">${provGotCell(row.cells.claude)}</td>
        <td class="c-f">${tick(row.cells.claude.qtyOk)}</td>
        <td class="c-f">${tick(row.cells.claude.unitOk)}</td>
        <td class="c-f">${tick(row.cells.claude.notesOk)}</td>
        <td class="c-prov ${gCls}">${provGotCell(row.cells.gpt)}</td>
        <td class="c-f">${tick(row.cells.gpt.qtyOk)}</td>
        <td class="c-f">${tick(row.cells.gpt.unitOk)}</td>
        <td class="c-f">${tick(row.cells.gpt.notesOk)}</td>
      </tr>`;
    })
    .join("\n");

  const extrasHtml = r.extras
    .map((ex) => {
      const isC = ex.provider === "claude";
      return `<tr class="row-extra">
        <td class="c-gold"><span class="na">— (no gold line)</span></td>
        <td class="c-prov prov-extra">${
        isC
          ? `<span class="no bold" title="hallucinated line">EXTRA</span> ${
            lineCell(ex.got)
          }`
          : `<span class="na">—</span>`
      }</td>
        <td class="c-f"><span class="na">—</span></td>
        <td class="c-f"><span class="na">—</span></td>
        <td class="c-f"><span class="na">—</span></td>
        <td class="c-prov prov-extra">${
        !isC
          ? `<span class="no bold" title="hallucinated line">EXTRA</span> ${
            lineCell(ex.got)
          }`
          : `<span class="na">—</span>`
      }</td>
        <td class="c-f"><span class="na">—</span></td>
        <td class="c-f"><span class="na">—</span></td>
        <td class="c-f"><span class="na">—</span></td>
      </tr>`;
    })
    .join("\n");

  const reviewHtml = r.review.length
    ? `<details class="review"><summary>gold reclassification notes (_review · ${r.review.length})</summary><ul>${
      r.review.map((x) => `<li>${esc(x)}</li>`).join("")
    }</ul></details>`
    : "";

  const provChips = (p: ProviderKey) => {
    const s = r.score[p];
    const name = p === "claude" ? "C" : "G";
    return `<span class="chip ${p}">${name} F1 ${pct(s.line_f1)}</span>` +
      `<span class="chip ${p}">${name} qty ${pct(s.qty_acc)}</span>` +
      `<span class="chip ${p}">${name} unit ${pct(s.unit_acc)}</span>` +
      `<span class="chip ${p}">${name} notes ${pct(s.notes_acc)}</span>` +
      `<span class="chip ${
        s.ledger_total === 0 ? "chip-good" : "chip-danger"
      }">${name} danger ${s.ledger_total}</span>`;
  };

  const errBanner = PROVIDERS
    .filter((p) => r.score[p].error)
    .map((p) =>
      `<div class="errbanner">${
        PROVIDER_LABEL[p]
      } error (scored as total miss): ${esc(r.score[p].error!)}</div>`
    )
    .join("");

  const divergeCount = r.rows.filter((x) => x.diverge).length;
  const divergeChip = divergeCount > 0
    ? `<span class="chip chip-diverge">${divergeCount} diverge</span>`
    : "";

  const metaRow = (
    label: string,
    gold: string,
    sel: (p: ProviderKey) => string,
  ) =>
    `<div><b>${label}</b> gold <code>${esc(gold)}</code> · C <code>${
      esc(sel("claude"))
    }</code> · G <code>${esc(sel("gpt"))}</code></div>`;

  return `<details class="recipe">
    <summary>
      <span class="rname">${esc(r.id)}</span>
      <span class="chips">${provChips("claude")}${
    provChips("gpt")
  }${divergeChip}</span>
    </summary>
    ${errBanner}
    <div class="meta">
      ${
    metaRow(
      "title",
      r.title_gold,
      (p) => r.score[p].title_got + (r.score[p].title_match ? " ✓" : " ✗"),
    )
  }
      ${
    metaRow(
      "servings",
      r.servings_gold,
      (p) =>
        r.score[p].servings_got + (r.score[p].servings_match ? " ✓" : " ✗"),
    )
  }
    </div>
    <div class="tablewrap">
    <table>
      <thead>
        <tr>
          <th class="c-gold" rowspan="2">gold (amount · ingredient · notes)</th>
          <th class="prov-h claude" colspan="4">claude-haiku-4-5</th>
          <th class="prov-h gpt" colspan="4">gpt-5.4-mini</th>
        </tr>
        <tr>
          <th class="c-prov">got</th><th class="c-f">qty</th><th class="c-f">unit</th><th class="c-f">note</th>
          <th class="c-prov">got</th><th class="c-f">qty</th><th class="c-f">unit</th><th class="c-f">note</th>
        </tr>
      </thead>
      <tbody>
${rowsHtml}
${extrasHtml}
      </tbody>
    </table>
    </div>
    ${reviewHtml}
  </details>`;
}

function renderHtml(reports: RecipeReport[]): string {
  const mean = (xs: number[]) =>
    xs.reduce((a, b) => a + b, 0) / (xs.length || 1);
  const agg = (p: ProviderKey) => ({
    line_f1: mean(reports.map((r) => r.score[p].line_f1)),
    qty: mean(reports.map((r) => r.score[p].qty_acc)),
    unit: mean(reports.map((r) => r.score[p].unit_acc)),
    notes: mean(reports.map((r) => r.score[p].notes_acc)),
    title: mean(reports.map((r) => (r.score[p].title_match ? 1 : 0))),
    servings: mean(reports.map((r) => (r.score[p].servings_match ? 1 : 0))),
    danger: reports.reduce((a, r) => a + r.score[p].ledger_total, 0),
    omitted: reports.reduce((a, r) => a + r.score[p].ledger.omitted_lines, 0),
    invented: reports.reduce((a, r) => a + r.score[p].ledger.invented_lines, 0),
  });
  const C = agg("claude"), G = agg("gpt");

  const cmpRow = (
    label: string,
    c: string,
    g: string,
    better?: "c" | "g" | null,
  ) =>
    `<tr>
      <td class="cmp-k">${label}</td>
      <td class="cmp-v ${better === "c" ? "win" : ""}">${c}</td>
      <td class="cmp-v ${better === "g" ? "win" : ""}">${g}</td>
    </tr>`;
  const win = (c: number, g: number, higher = true): "c" | "g" | null => {
    if (c === g) return null;
    return (higher ? c > g : c < g) ? "c" : "g";
  };

  // Divergence list — gold lines one provider got right and the other wrong.
  const diverge: { recipe: string; ing: string; right: ProviderKey }[] = [];
  for (const r of reports) {
    for (const row of r.rows) {
      if (!row.diverge) continue;
      diverge.push({
        recipe: r.id,
        ing: row.gold.ingredient,
        right: row.cells.claude.correct ? "claude" : "gpt",
      });
    }
  }
  const divergeHtml = diverge.length
    ? diverge.map((d) =>
      `<li><code>${esc(d.recipe)}</code> — <b>${esc(d.ing)}</b> → ${
        d.right === "claude"
          ? `<span class="claude-t">Claude ✓</span> / <span class="no">GPT ✗</span>`
          : `<span class="no">Claude ✗</span> / <span class="gpt-t">GPT ✓</span>`
      }</li>`
    ).join("")
    : `<li class="na">no line-level divergence — the two providers succeed and fail on the same lines</li>`;

  const cWins = diverge.filter((d) => d.right === "claude").length;
  const gWins = diverge.filter((d) => d.right === "gpt").length;

  const band = `
    <div class="cmpwrap">
      <table class="cmp">
        <thead><tr><th></th><th class="claude-t">claude-haiku-4-5</th><th class="gpt-t">gpt-5.4-mini</th></tr></thead>
        <tbody>
          ${
    cmpRow("line F1", pct(C.line_f1), pct(G.line_f1), win(C.line_f1, G.line_f1))
  }
          ${
    cmpRow("qty acc (gold denom)", pct(C.qty), pct(G.qty), win(C.qty, G.qty))
  }
          ${
    cmpRow(
      "unit acc (gold denom)",
      pct(C.unit),
      pct(G.unit),
      win(C.unit, G.unit),
    )
  }
          ${
    cmpRow(
      "notes agree (gold denom)",
      pct(C.notes),
      pct(G.notes),
      win(C.notes, G.notes),
    )
  }
          ${
    cmpRow("title acc", pct(C.title), pct(G.title), win(C.title, G.title))
  }
          ${
    cmpRow(
      "servings acc",
      pct(C.servings),
      pct(G.servings),
      win(C.servings, G.servings),
    )
  }
          ${
    cmpRow(
      "dangerous total",
      String(C.danger),
      String(G.danger),
      win(C.danger, G.danger, false),
    )
  }
          ${
    cmpRow(
      "omitted lines",
      String(C.omitted),
      String(G.omitted),
      win(C.omitted, G.omitted, false),
    )
  }
          ${
    cmpRow(
      "hallucinated lines",
      String(C.invented),
      String(G.invented),
      win(C.invented, G.invented, false),
    )
  }
        </tbody>
      </table>
      <div class="diverge">
        <div class="dhead">Where they diverge <span class="na">(${diverge.length} lines · Claude-only-right ${cWins} · GPT-only-right ${gWins})</span></div>
        <ul>${divergeHtml}</ul>
      </div>
    </div>`;

  const sections = reports.map(recipeSection).join("\n");

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Extraction D2 — Claude vs GPT</title>
<style>
  :root {
    --bg:#fff; --fg:#1a1a1a; --muted:#666; --card:#f7f7f8; --border:#e2e2e6;
    --code-bg:#eeeef1;
    --yes:#128a3a; --yes-bg:#e6f5ec; --no:#c02626; --no-bg:#fbe9e9;
    --warn:#a86500; --warn-bg:#fdf3e0;
    --missed-bg:#fbe9e9; --extra-bg:#fdf0f5; --diverge-bg:#eef2ff;
    --ok-bg:#eef8f0;
    --chip-bg:#ececf0; --chip-fg:#333; --good:#128a3a; --bad:#c02626;
    --claude:#c86a2a; --gpt:#2a7d6a; --accent:#3355cc;
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --bg:#16171a; --fg:#e8e8ea; --muted:#9a9aa2; --card:#1f2024; --border:#33343a;
      --code-bg:#26272c;
      --yes:#4ecb7a; --yes-bg:#16311f; --no:#f26a6a; --no-bg:#351a1a;
      --warn:#e0a53a; --warn-bg:#33280f;
      --missed-bg:#351a1a; --extra-bg:#331a26; --diverge-bg:#1c2138;
      --ok-bg:#16251b;
      --chip-bg:#2a2b31; --chip-fg:#d0d0d6; --good:#4ecb7a; --bad:#f26a6a;
      --claude:#e6944e; --gpt:#4fbfa5; --accent:#7f9bff;
    }
  }
  :root[data-theme="dark"] {
    --bg:#16171a; --fg:#e8e8ea; --muted:#9a9aa2; --card:#1f2024; --border:#33343a;
    --code-bg:#26272c;
    --yes:#4ecb7a; --yes-bg:#16311f; --no:#f26a6a; --no-bg:#351a1a;
    --warn:#e0a53a; --warn-bg:#33280f;
    --missed-bg:#351a1a; --extra-bg:#331a26; --diverge-bg:#1c2138;
    --ok-bg:#16251b;
    --chip-bg:#2a2b31; --chip-fg:#d0d0d6; --good:#4ecb7a; --bad:#f26a6a;
    --claude:#e6944e; --gpt:#4fbfa5; --accent:#7f9bff;
  }
  * { box-sizing:border-box; }
  body { margin:0; background:var(--bg); color:var(--fg);
    font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
    padding:24px 16px 80px; }
  .wrap { max-width:1180px; margin:0 auto; }
  h1 { font-size:22px; margin:0 0 4px; }
  .lede { color:var(--muted); margin:0 0 18px; font-size:14px; }
  code { background:var(--code-bg); padding:1px 5px; border-radius:4px;
    font:12.5px/1.4 ui-monospace,SFMono-Regular,Menlo,monospace; }
  .claude-t { color:var(--claude); font-weight:650; }
  .gpt-t { color:var(--gpt); font-weight:650; }
  .cmpwrap { display:flex; flex-wrap:wrap; gap:18px; margin:0 0 26px; }
  table.cmp { border-collapse:collapse; background:var(--card);
    border:1px solid var(--border); border-radius:10px; overflow:hidden;
    flex:0 0 auto; }
  table.cmp th, table.cmp td { padding:8px 16px; text-align:right;
    border-bottom:1px solid var(--border); font-size:13.5px; }
  table.cmp thead th { font-size:13px; }
  table.cmp th:first-child, .cmp-k { text-align:left; color:var(--muted); }
  .cmp-v.win { font-weight:700; color:var(--good); }
  .diverge { flex:1 1 380px; background:var(--card); border:1px solid var(--border);
    border-radius:10px; padding:12px 16px; min-width:320px; }
  .dhead { font-weight:650; margin-bottom:6px; }
  .diverge ul { margin:0; padding-left:18px; font-size:13px; }
  .diverge li { margin:3px 0; }
  details.recipe { border:1px solid var(--border); border-radius:10px;
    margin:0 0 12px; background:var(--card); overflow:hidden; }
  details.recipe > summary { cursor:pointer; padding:12px 16px; list-style:none;
    display:flex; flex-wrap:wrap; align-items:center; gap:8px 10px; }
  details.recipe > summary::-webkit-details-marker { display:none; }
  details.recipe > summary::before { content:"▶"; color:var(--muted);
    font-size:11px; transition:transform .15s; }
  details.recipe[open] > summary::before { transform:rotate(90deg); }
  .rname { font-weight:650; font-size:15.5px; }
  .chips { display:flex; flex-wrap:wrap; gap:5px; margin-left:auto; }
  .chip { background:var(--chip-bg); color:var(--chip-fg); border-radius:20px;
    padding:2px 9px; font-size:11.5px; white-space:nowrap; }
  .chip.claude { background:color-mix(in srgb, var(--claude) 16%, transparent); color:var(--claude); }
  .chip.gpt { background:color-mix(in srgb, var(--gpt) 16%, transparent); color:var(--gpt); }
  .chip-good { background:var(--yes-bg); color:var(--yes); }
  .chip-danger { background:var(--no-bg); color:var(--no); font-weight:600; }
  .chip-diverge { background:var(--diverge-bg); color:var(--accent); font-weight:600; }
  .meta { padding:4px 16px 10px; font-size:13px; }
  .meta > div { margin:3px 0; }
  .meta b { color:var(--muted); font-weight:600; margin-right:4px; }
  .errbanner { margin:8px 16px; padding:8px 12px; background:var(--no-bg);
    color:var(--no); border-radius:8px; font-size:13px; }
  .tablewrap { overflow-x:auto; padding:0 8px 8px; }
  table { border-collapse:collapse; width:100%; font-size:13px; min-width:860px; }
  th, td { text-align:left; padding:7px 10px; vertical-align:top;
    border-bottom:1px solid var(--border); }
  thead th { color:var(--muted); font-weight:600; font-size:12px; }
  .prov-h { text-align:center; border-left:2px solid var(--border); }
  .prov-h.claude { color:var(--claude); }
  .prov-h.gpt { color:var(--gpt); }
  .c-gold { width:30%; }
  .c-prov { width:24%; border-left:2px solid var(--border); }
  .c-f { width:34px; text-align:center; }
  td.c-f { text-align:center; }
  .amt { font-weight:600; }
  .notes { color:var(--muted); font-size:12px; margin-top:2px; }
  .yes { color:var(--yes); font-weight:700; }
  .no { color:var(--no); font-weight:700; }
  .bold { font-weight:700; }
  .fuzzy { color:var(--warn); font-weight:700; }
  .na { color:var(--muted); }
  .row-diverge { background:var(--diverge-bg); }
  .row-extra { background:var(--extra-bg); }
  .prov-ok { background:var(--ok-bg); }
  .prov-warn { background:var(--warn-bg); }
  .prov-missed { background:var(--missed-bg); }
  .prov-extra { background:var(--extra-bg); }
  .dwrap { margin-top:4px; }
  .dbadge { display:inline-block; background:var(--no-bg); color:var(--no);
    border-radius:5px; padding:1px 6px; font-size:11px; margin:1px 2px 0 0;
    font-family:ui-monospace,Menlo,monospace; }
  details.review { margin:4px 16px 14px; font-size:12.5px; color:var(--muted); }
  details.review summary { cursor:pointer; color:var(--accent); }
  details.review ul { margin:6px 0; padding-left:18px; }
  details.review li { margin:4px 0; }
  .legend { font-size:12.5px; color:var(--muted); margin:0 0 18px;
    display:flex; flex-wrap:wrap; gap:12px; }
  .legend span { display:inline-flex; align-items:center; gap:5px; }
  .sw { width:12px; height:12px; border-radius:3px; display:inline-block; }
</style>
</head>
<body>
<div class="wrap">
  <h1>Extraction D2 — Claude vs GPT, right vs wrong</h1>
  <p class="lede">Sanitize stage on reconstructed gold page-text (TEXT input, no images), 11 gold recipes. Each provider's line is aligned to the gold and scored per field. Headline accuracies use the GOLD denominator — a line the provider omitted counts as a line it got wrong. <span class="claude-t">Claude</span> and <span class="gpt-t">GPT</span> shown side by side; missed / hallucinated / dangerous rows highlighted.</p>
  <div class="legend">
    <span><span class="sw" style="background:var(--ok-bg)"></span> field-correct</span>
    <span><span class="sw" style="background:var(--warn-bg)"></span> wrong field / dangerous</span>
    <span><span class="sw" style="background:var(--missed-bg)"></span> missed (omitted)</span>
    <span><span class="sw" style="background:var(--extra-bg)"></span> hallucinated (extra)</span>
    <span><span class="sw" style="background:var(--diverge-bg)"></span> providers diverge</span>
    <span><span class="fuzzy">~</span> aligned but identity text differs</span>
  </div>
  ${band}
  ${sections}
</div>
</body>
</html>`;
}

// --- main --------------------------------------------------------------------

async function main(): Promise<void> {
  const outDir = new URL("../reports/", import.meta.url);
  const htmlUrl = new URL("extraction-d2-compare.html", outDir);
  const jsonUrl = new URL("extraction-d2-compare.json", outDir);

  // --render-only re-renders the HTML from the saved JSON dump WITHOUT making
  // any (paid) provider calls — used to iterate on the report layout for free.
  if (Deno.args.includes("--render-only")) {
    const reports = JSON.parse(
      await Deno.readTextFile(jsonUrl),
    ) as RecipeReport[];
    await Deno.writeTextFile(htmlUrl, renderHtml(reports));
    console.log(
      `re-rendered ${htmlUrl.pathname} from saved JSON (no API calls)`,
    );
    return;
  }

  console.log(
    "D2 capture · claude-haiku-4-5 + gpt-5.4-mini · 11 gold · page_text (text)\n",
  );
  const reports = await capture();

  const mean = (xs: number[]) =>
    xs.reduce((a, b) => a + b, 0) / (xs.length || 1);
  for (const p of PROVIDERS) {
    console.log(
      `\n  OVERALL ${PROVIDER_LABEL[p]}  ` +
        `lineF1=${pct(mean(reports.map((r) => r.score[p].line_f1)))} ` +
        `qty=${pct(mean(reports.map((r) => r.score[p].qty_acc)))} ` +
        `unit=${pct(mean(reports.map((r) => r.score[p].unit_acc)))} ` +
        `notes=${pct(mean(reports.map((r) => r.score[p].notes_acc)))} ` +
        `title=${
          pct(mean(reports.map((r) => (r.score[p].title_match ? 1 : 0))))
        } ` +
        `servings=${
          pct(mean(reports.map((r) => (r.score[p].servings_match ? 1 : 0))))
        } ` +
        `dangerous=${reports.reduce((a, r) => a + r.score[p].ledger_total, 0)}`,
    );
  }

  await Deno.mkdir(outDir, { recursive: true });
  await Deno.writeTextFile(jsonUrl, JSON.stringify(reports, null, 2));
  await Deno.writeTextFile(htmlUrl, renderHtml(reports));
  console.log(`\n  wrote ${htmlUrl.pathname}`);
  console.log(`  wrote ${jsonUrl.pathname}`);
}

if (import.meta.main) {
  await main();
}
