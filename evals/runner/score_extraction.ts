// Extraction scorer (charter 0018 deliverable): PROGRAMMATIC scorers over the
// blessed gold, a never-invent / force-fit LEDGER (the disqualifying dimension),
// confidence CALIBRATION, and an LLM-judge seam for prose fidelity only. Reports
// per-stage (D1 transcribe / D2 sanitize-on-gold-text / D3 e2e) and per-path
// (jsonld / page_text / photo).
//
// It is a CALIBRATION TOOL, not a merge gate (evals/AGENTS.md): it runs on
// demand + nightly and reports numbers, it does not fail a PR.
//
// Keyless: `deno run --allow-read --allow-env score_extraction.ts` scores D2 on
// the gold with the mock adapter (an oracle row + a deliberately-degraded row so
// every scorer and the ledger are exercised) — green with no provider key.

import type {
  ExtractAdapter,
  ExtractionResult,
  RawBlob,
  RawLineItem,
  Step,
  TimeField,
} from "../../supabase/functions/_shared/types.ts";
import {
  ExtractionParseError,
  flattenLines,
} from "../../supabase/functions/_shared/adapters/schema.ts";
import { normalize } from "../../supabase/functions/_shared/normalize.ts";
import {
  fixedMock,
  MockAdapter,
} from "../../supabase/functions/_shared/adapters/mock.ts";
import {
  type GoldCase,
  type GoldRecipe,
  goldToBlob,
  loadGold,
  UNIT_HINTS,
} from "./fixtures.ts";

// --- number / field equality -------------------------------------------------

/**
 * Absolute slack, so a rounded fraction passes: gold `⅓ → 0.33` vs a model's
 * `0.3333` differs by 0.0033. Two decimal places of rounding on any vulgar
 * fraction stays inside 0.005, so 0.006 covers the family with a hair to spare.
 */
const NUM_TOL_ABS = 0.006;
/**
 * Relative slack for large magnitudes (seconds, grams) — deliberately TINY.
 * The old rule was 2% relative, which passed 400 g vs 395 g and 30 min vs
 * 29 min: a transcription error scored as a hit. 0.2% only absorbs float noise.
 */
const NUM_TOL_REL = 0.002;

/**
 * Numeric equality: absolute slack OR a very small relative slack, whichever is
 * larger. `⅓ → 0.333` vs `0.33` passes; `400` vs `395` fails.
 */
export function numEq(a: number | null, b: number | null): boolean {
  if (a === null && b === null) return true;
  if (a === null || b === null) return false;
  const tol = Math.max(
    NUM_TOL_ABS,
    NUM_TOL_REL * Math.max(
      Math.abs(a),
      Math.abs(b),
    ),
  );
  return Math.abs(a - b) <= tol;
}

function timeEq(a: TimeField, b: TimeField): boolean {
  const norm = (t: TimeField): [number, number] | null => {
    if (t === null) return null;
    if (typeof t === "number") return [t, t];
    return [t.low_seconds, t.high_seconds];
  };
  const na = norm(a), nb = norm(b);
  if (na === null && nb === null) return true;
  if (na === null || nb === null) return false;
  return numEq(na[0], nb[0]) && numEq(na[1], nb[1]);
}

/** A line's amount "shape": single value, a range, or none (imprecise/absent). */
export function amountShape(li: RawLineItem): "single" | "range" | "none" {
  if (li.qty_low !== null || li.qty_high !== null) return "range";
  if (li.qty !== null) return "single";
  return "none";
}

export function qtyMatch(gold: RawLineItem, got: RawLineItem): boolean {
  const sg = amountShape(gold), st = amountShape(got);
  if (sg !== st) return false;
  if (sg === "none") return true;
  if (sg === "single") return numEq(gold.qty, got.qty);
  return numEq(gold.qty_low, got.qty_low) && numEq(gold.qty_high, got.qty_high);
}

/**
 * The generic count-measure nouns (`_SCHEMA.md` "count-measure nouns are
 * mappable", mirrored from `_shared/unit_hints.ts`) plus the canonical `piece`.
 */
const COUNT_MEASURE_NOUNS = new Set([
  "clove",
  "head",
  "sprig",
  "loaf",
  "block",
  "slice",
  "can",
  "bunch",
  "stalk",
]);

/** Case-folds, singularizes a known measure noun, and folds `tin` → `can`. */
export function normUnit(u: string | null): string {
  let s = (u ?? "").trim().toLowerCase().replace(/\s+/gu, "_");
  if (s === "tin" || s === "tins") return "can";
  if (s.endsWith("es") && COUNT_MEASURE_NOUNS.has(s.slice(0, -2))) {
    s = s.slice(0, -2);
  } else if (s.endsWith("s") && COUNT_MEASURE_NOUNS.has(s.slice(0, -1))) {
    s = s.slice(0, -1);
  } else if (s === "pieces") s = "piece";
  return s;
}

export type UnitVerdict = "exact" | "family" | "mismatch";

/**
 * Unit agreement in three grades.
 *
 * - `exact`   — same normalized unit word AND the same `unit_mappable`.
 * - `family`  — one side is the GENERIC count unit `piece` and the other is a
 *   specific count-measure noun (`clove`, `sprig`, `can`…), with `unit_mappable`
 *   agreeing. "2 garlic cloves" read as `2 piece` is a labelling choice inside
 *   one family, not a transcription error, and the old exact-string rule was
 *   the single largest source of the residual unit-accuracy gap (tech-debt
 *   2026-08-31). Two DIFFERENT specific nouns (`clove` vs `can`) stay a
 *   mismatch — that is a real error.
 * - `mismatch` — everything else, including any `unit_mappable` disagreement
 *   (a forced mapping is a ledger event, never a near-miss).
 */
export function unitVerdict(gold: RawLineItem, got: RawLineItem): UnitVerdict {
  if (gold.unit_mappable !== got.unit_mappable) return "mismatch";
  const g = normUnit(gold.unit), t = normUnit(got.unit);
  if (g === t) return "exact";
  const generic = (u: string) => u === "piece";
  const specific = (u: string) => COUNT_MEASURE_NOUNS.has(u);
  if ((generic(g) && specific(t)) || (specific(g) && generic(t))) {
    return "family";
  }
  return "mismatch";
}

/** Headline unit agreement — exact OR count-family equivalent. */
export function unitMatch(gold: RawLineItem, got: RawLineItem): boolean {
  return unitVerdict(gold, got) !== "mismatch";
}

/** The strict, string-equality reading, reported alongside the headline. */
export function unitExactMatch(gold: RawLineItem, got: RawLineItem): boolean {
  return unitVerdict(gold, got) === "exact";
}

// --- notes agreement ---------------------------------------------------------

/**
 * Filler words dropped before comparing `notes`. The question the metric asks is
 * "did the cook-prep survive into the note slot", not "did the model reproduce
 * the connective tissue".
 */
const NOTES_STOPWORDS = new Set([
  "a",
  "an",
  "the",
  "of",
  "and",
  "or",
  "to",
  "into",
  "with",
  "if",
  "then",
  "in",
  "on",
  "at",
  "is",
  "it",
]);

function notesTokens(s: string | null): Set<string> {
  return new Set(
    (s ?? "")
      .toLowerCase()
      .split(/[^\p{L}\p{N}]+/u)
      .filter(Boolean)
      .filter((w) => !NOTES_STOPWORDS.has(w)),
  );
}

/** Jaccard threshold for {@link notesAgree}. */
export const NOTES_AGREE_THRESHOLD = 0.6;

/**
 * Fuzzy `notes` agreement over an aligned pair.
 *
 * Rule (documented in EXTRACTION.md): lowercase, split on non-alphanumerics,
 * drop the stopword list above, then compare the two token SETS by Jaccard.
 * Both empty ⇒ agree (the gold says there is no cook-prep and the model agreed).
 * Exactly one empty ⇒ disagree. Otherwise agree when Jaccard ≥ 0.6, which
 * tolerates word order and light rewording ("chopped, for garnish" vs
 * "for garnish, chopped") but not a dropped qualifier ("finely diced" vs
 * "diced" scores 0.5 and fails).
 */
export function notesAgree(
  gold: RawLineItem,
  got: RawLineItem,
): boolean {
  const a = notesTokens(gold.notes), b = notesTokens(got.notes);
  if (a.size === 0 && b.size === 0) return true;
  if (a.size === 0 || b.size === 0) return false;
  let inter = 0;
  for (const w of a) if (b.has(w)) inter++;
  return inter / (a.size + b.size - inter) >= NOTES_AGREE_THRESHOLD;
}

// --- fuzzy line alignment ----------------------------------------------------

function words(text: string): Set<string> {
  return new Set(
    normalize(text).split(/\s+/).map((w) => w.trim()).filter(Boolean),
  );
}

function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 && b.size === 0) return 1;
  let inter = 0;
  for (const x of a) if (b.has(x)) inter++;
  return inter / (a.size + b.size - inter);
}

const ALIGN_THRESHOLD = 0.34;

export interface LinePair {
  goldIdx: number;
  gotIdx: number;
  sim: number;
}

export interface Alignment {
  pairs: LinePair[];
  missedGold: number[]; // gold lines with no got match (recall loss / omissions)
  extraGot: number[]; // got lines with no gold match (hallucinated lines)
}

/** Greedy best-first alignment of got line items onto gold line items. */
export function alignLines(
  gold: RawLineItem[],
  got: RawLineItem[],
): Alignment {
  const goldW = gold.map((li) => words(li.ingredient_text));
  const gotW = got.map((li) => words(li.ingredient_text));
  const cands: LinePair[] = [];
  for (let g = 0; g < gold.length; g++) {
    for (let t = 0; t < got.length; t++) {
      const sim = jaccard(goldW[g], gotW[t]);
      if (sim >= ALIGN_THRESHOLD) cands.push({ goldIdx: g, gotIdx: t, sim });
    }
  }
  cands.sort((a, b) => b.sim - a.sim);
  const usedGold = new Set<number>(), usedGot = new Set<number>();
  const pairs: LinePair[] = [];
  for (const c of cands) {
    if (usedGold.has(c.goldIdx) || usedGot.has(c.gotIdx)) continue;
    usedGold.add(c.goldIdx);
    usedGot.add(c.gotIdx);
    pairs.push(c);
  }
  const missedGold = gold.map((_, i) => i).filter((i) => !usedGold.has(i));
  const extraGot = got.map((_, i) => i).filter((i) => !usedGot.has(i));
  return { pairs, missedGold, extraGot };
}

// --- step scoring ------------------------------------------------------------

interface PR {
  matched: number;
  gold: number;
  got: number;
}

function prF1(pr: PR): { p: number; r: number; f1: number } {
  const p = pr.got === 0 ? (pr.gold === 0 ? 1 : 0) : pr.matched / pr.got;
  const r = pr.gold === 0 ? 1 : pr.matched / pr.gold;
  const f1 = p + r === 0 ? 0 : (2 * p * r) / (p + r);
  return { p, r, f1 };
}

function refKeys(steps: Step[], remap: (i: number) => number | null): string[] {
  const keys: string[] = [];
  for (const step of steps) {
    for (const tok of step.tokens) {
      if (tok.t !== "ref") continue;
      const mapped = tok.refs
        .map(remap)
        .filter((n): n is number => n !== null)
        .sort((a, b) => a - b);
      keys.push(mapped.join(","));
    }
  }
  return keys;
}

function timerKeys(steps: Step[]): string[] {
  const keys: string[] = [];
  for (const step of steps) {
    for (const tok of step.tokens) {
      if (tok.t === "timer") {
        keys.push(`${tok.low_seconds}-${tok.high_seconds}`);
      }
    }
  }
  return keys;
}

function multisetMatch(gold: string[], got: string[]): PR {
  const pool = new Map<string, number>();
  for (const k of got) pool.set(k, (pool.get(k) ?? 0) + 1);
  let matched = 0;
  for (const k of gold) {
    const n = pool.get(k) ?? 0;
    if (n > 0) {
      matched++;
      pool.set(k, n - 1);
    }
  }
  return { matched, gold: gold.length, got: got.length };
}

// --- the ledger (never-invent / force-fit; dangerous failures) ---------------

export interface Ledger {
  invented_lines: number; // a got line matching no gold line
  omitted_lines: number; // a gold line the model dropped
  invented_qty: number; // gold had no amount, model put a number
  collapsed_range: number; // gold was a range, model force-fit one number
  forced_unit: number; // gold unmappable amount, model mapped it to a unit
  invented_time: number; // gold time null, model emitted a time
  invented_servings: number; // gold servings null, model emitted a number
  invented_timers: number; // more timer tokens than the source has
  structural_flags: number; // adapter's own structural parse_warnings
}

function emptyLedger(): Ledger {
  return {
    invented_lines: 0,
    omitted_lines: 0,
    invented_qty: 0,
    collapsed_range: 0,
    forced_unit: 0,
    invented_time: 0,
    invented_servings: 0,
    invented_timers: 0,
    structural_flags: 0,
  };
}

function addLedger(a: Ledger, b: Ledger): Ledger {
  const out = emptyLedger();
  for (const k of Object.keys(out) as (keyof Ledger)[]) out[k] = a[k] + b[k];
  return out;
}

export function ledgerTotal(l: Ledger): number {
  return l.invented_lines + l.invented_qty + l.collapsed_range +
    l.forced_unit + l.invented_time + l.invented_servings + l.invented_timers;
}

// --- per-case score ----------------------------------------------------------

export interface CalibrationSample {
  confidence: number;
  correct: boolean;
  /** Where the sample came from — exposed so ECE's composition is auditable. */
  kind: "aligned" | "invented" | "omitted";
}

/** Raw per-field counts, so the aggregate can be line-weighted, not just macro. */
export interface FieldCounts {
  qty_ok: number;
  unit_ok: number;
  unit_exact_ok: number;
  normalize_ok: number;
  notes_ok: number;
  /** Aligned pairs — the denominator of the "aligned-only" reading. */
  aligned: number;
  /** Gold line count — the denominator of the HONEST headline reading. */
  gold_lines: number;
  got_lines: number;
}

export interface CaseScore {
  id: string;
  json_valid: boolean;
  title_match: boolean;
  servings_correct: boolean;
  total_time_correct: boolean;
  cook_time_correct: boolean;
  line: { p: number; r: number; f1: number };
  /**
   * HEADLINE field accuracies — over the GOLD denominator: an omitted line is a
   * line the model got wrong, so it counts against qty/unit/normalize/notes.
   * Scoring these over aligned pairs alone (as this scorer used to) let a model
   * raise its accuracy by dropping the lines it was unsure of.
   */
  qty_acc: number;
  unit_acc: number;
  unit_exact_acc: number;
  normalize_agree: number;
  notes_agree: number;
  /** The same four over aligned pairs only — "when it did emit a line, was it right". */
  qty_acc_aligned: number;
  unit_acc_aligned: number;
  normalize_agree_aligned: number;
  notes_agree_aligned: number;
  counts: FieldCounts;
  step_ref: { p: number; r: number; f1: number };
  timer: { p: number; r: number; f1: number };
  /**
   * Whether the recipe has anything to say about step-refs / timers at all. A
   * recipe with no timers in the gold AND none in the output used to score a
   * free 1.0 F1 that inflated the macro average; those cases are now excluded
   * from the metric and reported as reduced coverage instead.
   */
  step_ref_applicable: boolean;
  timer_applicable: boolean;
  aligned: number;
  ledger: Ledger;
  calibration: CalibrationSample[];
}

/**
 * The result a case is scored against when the adapter throws — a total miss.
 * Exported because `capture_d2_report.ts` needs the identical shape (it used to
 * re-declare its own copy, which could drift from this one).
 */
export const EMPTY_RESULT: ExtractionResult = {
  title: "",
  servings_base: null,
  servings_raw: null,
  yield_raw: null,
  total_time_seconds: null,
  cook_time_seconds: null,
  truncated: false,
  image_quality: "poor",
  parse_warnings: [],
  groups: [],
  steps: [],
};

export function scoreExtraction(
  id: string,
  gold: GoldRecipe,
  got: ExtractionResult,
  jsonValid: boolean,
): CaseScore {
  const goldLines = flattenLines(gold);
  const gotLines = flattenLines(got);
  const align = alignLines(goldLines, gotLines);

  const ledger = emptyLedger();
  ledger.invented_lines = align.extraGot.length;
  ledger.omitted_lines = align.missedGold.length;
  ledger.structural_flags =
    got.parse_warnings.filter((w) => w.startsWith("structural-review:")).length;

  let qtyOk = 0, unitOk = 0, unitExactOk = 0, normOk = 0, notesOk = 0;
  const calibration: CalibrationSample[] = [];
  for (const pair of align.pairs) {
    const g = goldLines[pair.goldIdx];
    const t = gotLines[pair.gotIdx];
    const qm = qtyMatch(g, t);
    const um = unitMatch(g, t);
    if (qm) qtyOk++;
    if (um) unitOk++;
    if (unitExactMatch(g, t)) unitExactOk++;
    if (normalize(g.ingredient_text) === normalize(t.ingredient_text)) normOk++;
    if (notesAgree(g, t)) notesOk++;

    // ledger: force-fit / invention detectable on an aligned pair
    if (amountShape(g) === "none" && amountShape(t) !== "none") {
      ledger.invented_qty++;
    }
    if (amountShape(g) === "range" && amountShape(t) === "single") {
      ledger.collapsed_range++;
    }
    if (!g.unit_mappable && t.unit_mappable) ledger.forced_unit++;

    calibration.push({
      confidence: t.confidence,
      correct: qm && um,
      kind: "aligned",
    });
  }
  // Calibration over the WHOLE gold, not just the lines that aligned. A line the
  // model invented is a confident claim that was wrong; a line it dropped is a
  // gold line it did not get right. Counting only aligned pairs meant the two
  // dangerous failure modes contributed nothing to ECE at all.
  for (const gi of align.extraGot) {
    calibration.push({
      confidence: gotLines[gi].confidence,
      correct: false,
      kind: "invented",
    });
  }
  for (const _ of align.missedGold) {
    // An omission carries no model confidence — it is binned at 0 so it enters
    // the sample count (ECE is over the gold denominator) without a fabricated
    // confidence. It therefore barely moves ECE: the honest headline for
    // omissions is `ledger.omitted_lines` and the gold-denominator accuracies.
    calibration.push({ confidence: 0, correct: false, kind: "omitted" });
  }
  const nPairs = align.pairs.length || 1;
  const nGold = goldLines.length || 1;

  // recipe-level invention
  if (gold.total_time_seconds === null && got.total_time_seconds !== null) {
    ledger.invented_time++;
  }
  if (gold.cook_time_seconds === null && got.cook_time_seconds !== null) {
    ledger.invented_time++;
  }
  if (gold.servings_base === null && got.servings_base !== null) {
    ledger.invented_servings++;
  }

  // steps: map got flattened index → gold flattened index via the alignment
  const gotToGold = new Map<number, number>();
  for (const p of align.pairs) gotToGold.set(p.gotIdx, p.goldIdx);
  const stepRefPR = multisetMatch(
    refKeys(gold.steps, (i) => i),
    refKeys(got.steps, (i) => gotToGold.get(i) ?? null),
  );
  const goldTimers = timerKeys(gold.steps);
  const gotTimers = timerKeys(got.steps);
  const timerPR = multisetMatch(goldTimers, gotTimers);
  if (gotTimers.length > goldTimers.length) {
    ledger.invented_timers += gotTimers.length - goldTimers.length;
  }

  return {
    id,
    json_valid: jsonValid,
    title_match: normalize(gold.title) === normalize(got.title),
    servings_correct: gold.servings_base === got.servings_base,
    total_time_correct: timeEq(gold.total_time_seconds, got.total_time_seconds),
    cook_time_correct: timeEq(gold.cook_time_seconds, got.cook_time_seconds),
    line: prF1({
      matched: align.pairs.length,
      gold: goldLines.length,
      got: gotLines.length,
    }),
    qty_acc: qtyOk / nGold,
    unit_acc: unitOk / nGold,
    unit_exact_acc: unitExactOk / nGold,
    normalize_agree: normOk / nGold,
    notes_agree: notesOk / nGold,
    qty_acc_aligned: qtyOk / nPairs,
    unit_acc_aligned: unitOk / nPairs,
    normalize_agree_aligned: normOk / nPairs,
    notes_agree_aligned: notesOk / nPairs,
    counts: {
      qty_ok: qtyOk,
      unit_ok: unitOk,
      unit_exact_ok: unitExactOk,
      normalize_ok: normOk,
      notes_ok: notesOk,
      aligned: align.pairs.length,
      gold_lines: goldLines.length,
      got_lines: gotLines.length,
    },
    step_ref: prF1(stepRefPR),
    timer: prF1(timerPR),
    step_ref_applicable: stepRefPR.gold > 0 || stepRefPR.got > 0,
    timer_applicable: timerPR.gold > 0 || timerPR.got > 0,
    aligned: align.pairs.length,
    ledger,
    calibration,
  };
}

// --- calibration -------------------------------------------------------------

export interface CalibrationBin {
  lo: number;
  hi: number;
  n: number;
  meanConf: number;
  accuracy: number;
}

export interface Calibration {
  bins: CalibrationBin[];
  ece: number; // expected calibration error
  n: number;
  /** Sample composition, so a low ECE can't hide a pile of omissions. */
  n_aligned: number;
  n_invented: number;
  n_omitted: number;
}

export function calibrate(samples: CalibrationSample[]): Calibration {
  const bins: CalibrationBin[] = [];
  for (let b = 0; b < 10; b++) {
    const lo = b / 10, hi = (b + 1) / 10;
    const inBin = samples.filter((s) =>
      s.confidence >= lo && (b === 9 ? s.confidence <= hi : s.confidence < hi)
    );
    const n = inBin.length;
    const meanConf = n === 0
      ? 0
      : inBin.reduce((a, s) => a + s.confidence, 0) / n;
    const accuracy = n === 0 ? 0 : inBin.filter((s) => s.correct).length / n;
    bins.push({ lo, hi, n, meanConf, accuracy });
  }
  const total = samples.length || 1;
  const ece = bins.reduce(
    (a, bin) => a + (bin.n / total) * Math.abs(bin.meanConf - bin.accuracy),
    0,
  );
  const count = (k: CalibrationSample["kind"]) =>
    samples.filter((s) => (s.kind ?? "aligned") === k).length;
  return {
    bins,
    ece,
    n: samples.length,
    n_aligned: count("aligned"),
    n_invented: count("invented"),
    n_omitted: count("omitted"),
  };
}

// --- prose judge seam (LLM-judge; prose fidelity only) -----------------------

export interface ProseVerdict {
  score: number | null; // 0..1, or null when not judged (keyless)
  note: string;
}

export interface ProseJudge {
  name: string;
  judge(gold: GoldRecipe, got: ExtractionResult): Promise<ProseVerdict>;
}

/** Keyless default — prose fidelity is only checkable with a judge model. */
export const NOOP_PROSE_JUDGE: ProseJudge = {
  name: "none",
  judge: () => Promise.resolve({ score: null, note: "no judge (keyless)" }),
};

// --- aggregation -------------------------------------------------------------

/** The four field accuracies under one denominator. */
export interface FieldAccuracies {
  qty: number;
  unit: number;
  unit_exact: number;
  normalize: number;
  notes: number;
}

export interface Summary {
  provider: string;
  n: number;
  json_valid_rate: number;
  servings_acc: number;
  total_time_acc: number;
  cook_time_acc: number;
  line_p: number;
  line_r: number;
  line_f1: number;
  /**
   * HEADLINE: per-recipe macro average of the GOLD-denominator accuracies —
   * every recipe counts once, and a dropped line counts as a wrong line.
   */
  qty_acc: number;
  unit_acc: number;
  unit_exact_acc: number;
  normalize_agree: number;
  notes_agree: number;
  /** Same metrics over aligned pairs only — "when it emitted a line, was it right". */
  aligned_only: FieldAccuracies;
  /** Line-WEIGHTED (micro) aggregate over the gold denominator — big recipes count more. */
  weighted: FieldAccuracies;
  gold_lines: number;
  got_lines: number;
  aligned_lines: number;
  step_ref_f1: number;
  timer_f1: number;
  /** Fraction of recipes that actually have step-refs / timers to score. */
  step_ref_coverage: number;
  timer_coverage: number;
  ledger: Ledger;
  ledger_total: number;
  calibration: Calibration;
}

function mean(xs: number[]): number {
  return xs.length === 0 ? 0 : xs.reduce((a, b) => a + b, 0) / xs.length;
}

function sum(xs: number[]): number {
  return xs.reduce((a, b) => a + b, 0);
}

/** Ratio with an explicit 0-denominator convention (no free 1.0). */
function ratio(num: number, den: number): number {
  return den === 0 ? 0 : num / den;
}

export function summarize(provider: string, scores: CaseScore[]): Summary {
  const ledger = scores.reduce((a, s) => addLedger(a, s.ledger), emptyLedger());
  const calibration = calibrate(scores.flatMap((s) => s.calibration));
  const c = scores.map((s) => s.counts);
  const goldLines = sum(c.map((x) => x.gold_lines));
  const alignedLines = sum(c.map((x) => x.aligned));
  // Empty-vs-empty recipes are EXCLUDED from these two macro averages rather
  // than scoring a free 1.0 (a recipe with no timers proved nothing about timer
  // extraction); `*_coverage` reports how much of the set the number covers.
  const refApplicable = scores.filter((s) => s.step_ref_applicable);
  const timerApplicable = scores.filter((s) => s.timer_applicable);
  return {
    provider,
    n: scores.length,
    json_valid_rate: mean(scores.map((s) => (s.json_valid ? 1 : 0))),
    servings_acc: mean(scores.map((s) => (s.servings_correct ? 1 : 0))),
    total_time_acc: mean(scores.map((s) => (s.total_time_correct ? 1 : 0))),
    cook_time_acc: mean(scores.map((s) => (s.cook_time_correct ? 1 : 0))),
    line_p: mean(scores.map((s) => s.line.p)),
    line_r: mean(scores.map((s) => s.line.r)),
    line_f1: mean(scores.map((s) => s.line.f1)),
    qty_acc: mean(scores.map((s) => s.qty_acc)),
    unit_acc: mean(scores.map((s) => s.unit_acc)),
    unit_exact_acc: mean(scores.map((s) => s.unit_exact_acc)),
    normalize_agree: mean(scores.map((s) => s.normalize_agree)),
    notes_agree: mean(scores.map((s) => s.notes_agree)),
    aligned_only: {
      qty: ratio(sum(c.map((x) => x.qty_ok)), alignedLines),
      unit: ratio(sum(c.map((x) => x.unit_ok)), alignedLines),
      unit_exact: ratio(sum(c.map((x) => x.unit_exact_ok)), alignedLines),
      normalize: ratio(sum(c.map((x) => x.normalize_ok)), alignedLines),
      notes: ratio(sum(c.map((x) => x.notes_ok)), alignedLines),
    },
    weighted: {
      qty: ratio(sum(c.map((x) => x.qty_ok)), goldLines),
      unit: ratio(sum(c.map((x) => x.unit_ok)), goldLines),
      unit_exact: ratio(sum(c.map((x) => x.unit_exact_ok)), goldLines),
      normalize: ratio(sum(c.map((x) => x.normalize_ok)), goldLines),
      notes: ratio(sum(c.map((x) => x.notes_ok)), goldLines),
    },
    gold_lines: goldLines,
    got_lines: sum(c.map((x) => x.got_lines)),
    aligned_lines: alignedLines,
    step_ref_f1: mean(refApplicable.map((s) => s.step_ref.f1)),
    timer_f1: mean(timerApplicable.map((s) => s.timer.f1)),
    step_ref_coverage: ratio(refApplicable.length, scores.length),
    timer_coverage: ratio(timerApplicable.length, scores.length),
    ledger,
    ledger_total: ledgerTotal(ledger),
    calibration,
  };
}

// --- benchmark driver --------------------------------------------------------

export type Stage = "D1" | "D2" | "D3";
export type Path = "jsonld" | "page_text" | "photo";

export interface BenchmarkOptions {
  provider: string;
  adapter: ExtractAdapter;
  cases: GoldCase[];
  stage: Stage;
  path: Path;
  /** Builds the RawBlob fed to sanitize for a case (default: gold source text). */
  blobFor?: (gold: GoldRecipe) => RawBlob;
  judge?: ProseJudge;
}

export interface BenchmarkReport {
  provider: string;
  stage: Stage;
  path: Path;
  scores: CaseScore[];
  summary: Summary;
  prose: { id: string; verdict: ProseVerdict }[];
}

export async function runBenchmark(
  opts: BenchmarkOptions,
): Promise<BenchmarkReport> {
  const blobFor = opts.blobFor ?? goldToBlob;
  const judge = opts.judge ?? NOOP_PROSE_JUDGE;
  const scores: CaseScore[] = [];
  const prose: { id: string; verdict: ProseVerdict }[] = [];
  for (const c of opts.cases) {
    let got: ExtractionResult = EMPTY_RESULT;
    let jsonValid = true;
    try {
      got = await opts.adapter.sanitize(blobFor(c.gold), UNIT_HINTS);
    } catch (e) {
      jsonValid = !(e instanceof ExtractionParseError);
      // Any adapter error → an empty result scored as a total miss for this case.
      got = EMPTY_RESULT;
      if (!(e instanceof ExtractionParseError)) {
        // Non-parse errors (e.g. missing key) are logged but still scored 0 so a
        // partial provider outage shows as a failure, not a crash.
        console.error(`  ! ${opts.provider}/${c.id}: ${(e as Error).message}`);
      }
    }
    scores.push(scoreExtraction(c.id, c.gold, got, jsonValid));
    if (judge !== NOOP_PROSE_JUDGE) {
      prose.push({ id: c.id, verdict: await judge.judge(c.gold, got) });
    }
  }
  return {
    provider: opts.provider,
    stage: opts.stage,
    path: opts.path,
    scores,
    summary: summarize(opts.provider, scores),
    prose,
  };
}

// --- perturbations (build the degraded keyless mock + feed the self-test) -----

/** Deep-clones an ExtractionResult (structured clone; all fields are JSON). */
function clone(r: ExtractionResult): ExtractionResult {
  return JSON.parse(JSON.stringify(r)) as ExtractionResult;
}

/**
 * A deterministic degradation of a gold recipe, so the keyless run exercises
 * every scorer AND every ledger row: it invents a line, drops a line, force-fits
 * a range to a single number, and maps an unmappable amount to a unit.
 */
export function degrade(gold: GoldRecipe): ExtractionResult {
  const r = clone(gold);
  // drop the last line of the last group first (an omission) — done before the
  // invention below so the two never cancel in a single-group recipe.
  const lastGroup = r.groups[r.groups.length - 1];
  if (lastGroup && lastGroup.line_items.length > 1) lastGroup.line_items.pop();
  if (r.groups.length > 0 && r.groups[0].line_items.length > 0) {
    // invent a line not in the source
    r.groups[0].line_items.push({
      qty: 1,
      qty_low: null,
      qty_high: null,
      unit: "tsp",
      unit_mappable: true,
      ingredient_text: "monosodium glutamate",
      notes: null,
      raw_amount: "1 tsp",
      optional: false,
      confidence: 0.4,
    });
    // force-fit any range to its low bound; map any unmappable amount to a unit;
    // invent a number onto the first amount-less line (an invented_qty).
    let inventedQty = false;
    for (const g of r.groups) {
      for (const li of g.line_items) {
        if (li.qty === null && li.qty_low !== null) {
          li.qty = li.qty_low;
          li.qty_low = null;
          li.qty_high = null;
        }
        if (!li.unit_mappable) {
          li.unit = "cup";
          li.unit_mappable = true;
        }
        if (
          !inventedQty && li.qty === null && li.qty_low === null &&
          li.qty_high === null && (li.raw_amount ?? "").trim() === ""
        ) {
          li.qty = 1;
          inventedQty = true;
        }
      }
    }
  }
  return r;
}

// --- CLI: keyless D2 on the gold with the mock adapter -----------------------

function pct(x: number): string {
  return (x * 100).toFixed(1).padStart(5) + "%";
}

export function printSummary(s: Summary): void {
  console.log(`\n  ${s.provider}  (n=${s.n})`);
  console.log(`    json-valid      ${pct(s.json_valid_rate)}`);
  console.log(
    `    line P/R/F1     ${pct(s.line_p)} / ${pct(s.line_r)} / ${
      pct(s.line_f1)
    }`,
  );
  console.log(
    `    lines           gold=${s.gold_lines} got=${s.got_lines} aligned=${s.aligned_lines}`,
  );
  console.log(
    `    -- field accuracy: recipe-macro over the GOLD denominator (omissions count as wrong)`,
  );
  console.log(`    qty accuracy    ${pct(s.qty_acc)}`);
  console.log(
    `    unit accuracy   ${pct(s.unit_acc)}   (exact-string ${
      pct(s.unit_exact_acc)
    })`,
  );
  console.log(`    §7 normalize    ${pct(s.normalize_agree)}`);
  console.log(`    notes agree     ${pct(s.notes_agree)}`);
  console.log(
    `    -- same four, line-weighted (micro) / aligned-pairs-only`,
  );
  console.log(
    `    qty             ${pct(s.weighted.qty)} / ${pct(s.aligned_only.qty)}`,
  );
  console.log(
    `    unit            ${pct(s.weighted.unit)} / ${pct(s.aligned_only.unit)}`,
  );
  console.log(
    `    §7 normalize    ${pct(s.weighted.normalize)} / ${
      pct(s.aligned_only.normalize)
    }`,
  );
  console.log(
    `    notes           ${pct(s.weighted.notes)} / ${
      pct(s.aligned_only.notes)
    }`,
  );
  console.log(`    servings        ${pct(s.servings_acc)}`);
  console.log(
    `    time total/cook ${pct(s.total_time_acc)} / ${pct(s.cook_time_acc)}`,
  );
  console.log(
    `    step-ref F1     ${pct(s.step_ref_f1)} (over ${
      pct(s.step_ref_coverage)
    } of recipes — n/a cases excluded)`,
  );
  console.log(
    `    timer F1        ${pct(s.timer_f1)} (over ${
      pct(s.timer_coverage)
    } of recipes — n/a cases excluded)`,
  );
  console.log(
    `    calibration ECE ${
      s.calibration.ece.toFixed(3)
    } (n=${s.calibration.n}: ` +
      `${s.calibration.n_aligned} aligned, ${s.calibration.n_invented} invented, ` +
      `${s.calibration.n_omitted} omitted)`,
  );
  const l = s.ledger;
  console.log(
    `    LEDGER  invented_lines=${l.invented_lines} invented_qty=${l.invented_qty} ` +
      `collapsed_range=${l.collapsed_range} forced_unit=${l.forced_unit} ` +
      `invented_time=${l.invented_time} invented_servings=${l.invented_servings} ` +
      `invented_timers=${l.invented_timers}  (omitted_lines=${l.omitted_lines}, ` +
      `dangerous_total=${s.ledger_total})`,
  );
}

export async function main(): Promise<void> {
  const cases = await loadGold();
  console.log(
    `extraction eval — D2 (sanitize on reconstructed gold text), path=page_text`,
  );
  console.log(
    `${cases.length} gold recipes · MOCK adapter (keyless plumbing + scorer check)`,
  );

  // Oracle: returns the gold exactly → the scorer's "perfect" reference row.
  const oracleReports: BenchmarkReport[] = [];
  for (const c of cases) {
    const adapter: MockAdapter = fixedMock(c.gold);
    oracleReports.push(
      await runBenchmark({
        provider: "mock-oracle",
        adapter,
        cases: [c],
        stage: "D2",
        path: "page_text",
      }),
    );
  }
  const oracleScores = oracleReports.flatMap((r) => r.scores);
  printSummary(summarize("mock-oracle", oracleScores));

  // Degraded: a fixed corruption → exercises every scorer and every ledger row.
  const degradedScores: CaseScore[] = [];
  for (const c of cases) {
    const adapter = new MockAdapter({
      name: "mock-degraded",
      sanitizeWith: () => degrade(c.gold),
    });
    const report = await runBenchmark({
      provider: "mock-degraded",
      adapter,
      cases: [c],
      stage: "D2",
      path: "page_text",
    });
    degradedScores.push(...report.scores);
  }
  printSummary(summarize("mock-degraded", degradedScores));

  console.log(
    "\n  NOTE: mock rows prove the harness + scorer are wired and keyless.",
  );
  console.log(
    "  Real Gemini-Flash / GPT-5-Mini / Claude-Haiku rows need provider keys",
  );
  console.log(
    "  (ANTHROPIC_API_KEY / OPENAI_API_KEY / GEMINI_API_KEY) — see runner/EXTRACTION.md.",
  );
}

if (import.meta.main) {
  await main();
}
