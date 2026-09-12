// The structured-output JSON Schema every provider adapter targets, plus the
// coercion + never-invent validation that turns a provider's raw JSON into the
// frozen `ExtractionResult` (types.ts §4.4).
//
// One schema, three providers. Each provider's *native* structured-output mode
// (Anthropic `output_config.format`, OpenAI `response_format: json_schema`,
// Gemini `responseSchema`) consumes `EXTRACTION_JSON_SCHEMA`; each adapter then
// runs `coerceExtractionResult` (portability normalisation) and
// `validateExtractionResult` (structural never-invent checks). Keeping this in
// one place is what makes the providers comparable in the eval harness.
//
// Two deliberate simplifications make the schema portable across all three
// structured-output dialects (which disagree on unions):
//   1. Recipe-level times are always emitted as `{low_seconds, high_seconds}`
//      or null — never a bare number. Coercion collapses low === high back to
//      the `number` form of the frozen `TimeField`.
//   2. A step token is one flat object with a `t` discriminator and every other
//      field optional, rather than a tagged union. Coercion re-narrows it.

import type {
  ExtractionResult,
  ImageQuality,
  MentionKind,
  RawGroup,
  RawLineItem,
  RefPortion,
  Step,
  StepToken,
  TimeField,
  TimeRange,
} from "../types.ts";

// --- The wire schema ---------------------------------------------------------
// A JSON Schema (draft-2020-12 flavoured, kept to the common subset the three
// providers accept). `additionalProperties: false` everywhere so a provider
// cannot smuggle an un-modelled field past us. Adapters may down-convert this
// to a provider-specific dialect (see gemini.ts) but the shape is the contract.

const timeObject = {
  type: ["object", "null"],
  additionalProperties: false,
  required: ["low_seconds", "high_seconds"],
  properties: {
    low_seconds: { type: "number" },
    high_seconds: { type: "number" },
  },
} as const;

const lineItemSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "key",
    "qty",
    "qty_low",
    "qty_high",
    "unit",
    "unit_mappable",
    "ingredient_text",
    "notes",
    "raw_amount",
    "optional",
    "confidence",
  ],
  properties: {
    // The line's model-minted reference slug: step refs COPY these instead of
    // counting flattened positions (LLMs echo strings reliably and mis-count
    // arrays — the off-by-one chips observed live). Resolved to a flattened
    // index at coerce time; never leaves the adapter.
    key: { type: "string" },
    qty: { type: ["number", "null"] },
    qty_low: { type: ["number", "null"] },
    qty_high: { type: ["number", "null"] },
    unit: { type: ["string", "null"] },
    unit_mappable: { type: "boolean" },
    ingredient_text: { type: "string" },
    notes: { type: ["string", "null"] },
    raw_amount: { type: "string" },
    optional: { type: "boolean" },
    confidence: { type: "number" },
  },
} as const;

const portionSchema = {
  type: ["object", "null"],
  additionalProperties: false,
  required: ["qty", "qty_low", "qty_high", "unit", "qualifier"],
  properties: {
    qty: { type: ["number", "null"] },
    qty_low: { type: ["number", "null"] },
    qty_high: { type: ["number", "null"] },
    unit: { type: ["string", "null"] },
    qualifier: { type: ["string", "null"] },
  },
} as const;

const tokenSchema = {
  type: "object",
  additionalProperties: false,
  required: ["t"],
  properties: {
    t: { type: "string", enum: ["text", "ref", "timer"] },
    // text
    s: { type: "string" },
    // ref — entries are line KEYS (the slugs minted on line_items). Integers
    // are the legacy positional form, still accepted by coercion so committed
    // runs replay, but the schema steers new output to keys only.
    refs: { type: "array", items: { type: "string" } },
    label: { type: "string" },
    mention: { type: "string", enum: ["new", "rementioned", "fraction"] },
    portion: portionSchema,
    // timer
    low_seconds: { type: "number" },
    high_seconds: { type: "number" },
  },
} as const;

export const EXTRACTION_JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "title",
    "servings_base",
    "servings_raw",
    "yield_raw",
    "total_time_seconds",
    "cook_time_seconds",
    "truncated",
    "image_quality",
    "parse_warnings",
    "groups",
    "steps",
  ],
  properties: {
    title: { type: "string" },
    servings_base: { type: ["integer", "null"] },
    servings_raw: { type: ["string", "null"] },
    yield_raw: { type: ["string", "null"] },
    total_time_seconds: timeObject,
    cook_time_seconds: timeObject,
    truncated: { type: "boolean" },
    image_quality: { type: "string", enum: ["ok", "degraded", "poor"] },
    parse_warnings: { type: "array", items: { type: "string" } },
    groups: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["name", "line_items"],
        properties: {
          name: { type: ["string", "null"] },
          line_items: { type: "array", items: lineItemSchema },
        },
      },
    },
    steps: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["tokens"],
        properties: {
          tokens: { type: "array", items: tokenSchema },
        },
      },
    },
  },
} as const;

/**
 * The phase-2 schema of the two-phase sanitize: steps only. The line list is
 * INPUT to that call (already extracted by phase 1), so the response carries
 * nothing but the tokenized method — same step/token shapes as the one-shot
 * schema, refs by line key.
 */
export const STEPS_JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["steps"],
  properties: {
    steps: EXTRACTION_JSON_SCHEMA.properties.steps,
  },
} as const;

/** Thrown when a provider returns JSON we cannot read as an ExtractionResult. */
export class ExtractionParseError extends Error {
  constructor(message: string, readonly raw?: unknown) {
    super(message);
    this.name = "ExtractionParseError";
  }
}

// --- Coercion: provider JSON → frozen ExtractionResult -----------------------

// Length caps on every coerced string. A provider under a bad prompt (or a page
// that fed it a megabyte of junk) can emit an arbitrarily long "title" or
// "notes", and those strings go on to be stored, synced to every device, and
// rendered. Generous — several times the longest real value — but bounded.
export const CAPS = {
  title: 300,
  servings_raw: 120,
  yield_raw: 200,
  group_name: 200,
  ingredient_text: 300,
  notes: 500,
  raw_amount: 300,
  unit: 60,
  qualifier: 120,
  label: 300,
  step_text: 5_000,
  parse_warning: 500,
} as const;

/** Max entries kept in `parse_warnings` (a per-line warning storm is bounded). */
export const MAX_PARSE_WARNINGS = 100;

/** Truncates to `max` chars. Never pads, never invents — only ever removes. */
function cap(s: string, max: number): string {
  return s.length <= max ? s : s.slice(0, max);
}

/**
 * Words a title leaves lower-case unless they open or close it.
 *
 * `à` and `la` are here for *Chicken à la King*, which a shouting cookbook
 * page prints as CHICKEN A LA KING.
 */
const SMALL_WORDS = new Set([
  "a",
  "an",
  "and",
  "as",
  "at",
  "but",
  "by",
  "for",
  "in",
  "of",
  "on",
  "or",
  "the",
  "to",
  "with",
  "à",
  "la",
]);

const isLetter = (c: string) => c.toLowerCase() !== c.toUpperCase();

/**
 * Title-cases a title that carries **no case information of its own**.
 *
 * A photographed page shouts: PEANUT TOFU NOODLES, and a scraped one sometimes
 * whispers. Neither is a decision the page made about capitalisation — it is
 * the absence of one — so we supply the ordinary one. A title that already
 * carries MIXED case is left exactly alone: the page that prints *PIZZA alla
 * Norma* meant it, and second-guessing that is inventing.
 *
 * The words, their order and their punctuation are the page's throughout.
 * Casing is not inventing; nothing else here is touched.
 *
 * A word that begins with a digit is left as it is — `400g` is a measurement,
 * not a word to capitalise. A hyphenated compound is ONE word, so a shouted
 * SLOW-COOKED becomes *Slow-cooked*.
 *
 * This is deliberately code rather than a line in the extraction prompt: a
 * model instruction is a probabilistic fix for a deterministic problem, and it
 * costs a re-scored eval every time it is tuned.
 */
export function titleCaseIfUncased(title: string): string {
  const letters = [...title].filter(isLetter);
  if (letters.length === 0) return title;
  const upper = letters.every((c) => c === c.toUpperCase());
  const lower = letters.every((c) => c === c.toLowerCase());
  if (!upper && !lower) return title;

  // The capture group keeps the runs of whitespace, so the joined result is
  // spaced exactly as the page spaced it.
  const parts = title.split(/(\s+)/);
  const words: number[] = [];
  parts.forEach((p, i) => {
    if (p.trim() !== "") words.push(i);
  });
  const first = words[0];
  const last = words[words.length - 1];
  return parts
    .map((part, i) =>
      i !== first && i !== last && SMALL_WORDS.has(part.toLowerCase())
        ? part.toLowerCase()
        : capitaliseWord(part)
    )
    .join("");
}

/** Lower-cases a word and raises its first letter, if a letter opens it. */
function capitaliseWord(word: string): string {
  const lower = word.toLowerCase();
  for (let i = 0; i < lower.length; i++) {
    const c = lower[i];
    if (isLetter(c)) {
      return lower.slice(0, i) + c.toUpperCase() + lower.slice(i + 1);
    }
    // A digit before any letter means this is an amount, not a word.
    if (c >= "0" && c <= "9") return lower;
  }
  return lower;
}

function asRecord(v: unknown): Record<string, unknown> {
  if (v === null || typeof v !== "object" || Array.isArray(v)) {
    throw new ExtractionParseError("expected an object", v);
  }
  return v as Record<string, unknown>;
}

function numOrNull(v: unknown): number | null {
  if (v === null || v === undefined) return null;
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string" && v.trim() !== "" && Number.isFinite(Number(v))) {
    return Number(v);
  }
  return null;
}

function strOrNull(v: unknown, max: number): string | null {
  if (v === null || v === undefined) return null;
  return cap(String(v), max);
}

function boolOr(v: unknown, fallback: boolean): boolean {
  return typeof v === "boolean" ? v : fallback;
}

function coerceTime(v: unknown): TimeField {
  if (v === null || v === undefined) return null;
  // A bare number is accepted even though the schema asks for the object form.
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  const o = v as Record<string, unknown>;
  const low = numOrNull(o.low_seconds);
  const high = numOrNull(o.high_seconds);
  if (low === null && high === null) return null;
  const lo = low ?? high ?? 0;
  const hi = high ?? low ?? 0;
  if (lo === hi) return lo; // collapse single printed time to the number form
  return { low_seconds: lo, high_seconds: hi } satisfies TimeRange;
}

function coerceImageQuality(v: unknown): ImageQuality {
  return v === "degraded" || v === "poor" ? v : "ok";
}

function coerceLineItem(v: unknown): RawLineItem {
  const o = asRecord(v);
  return {
    qty: numOrNull(o.qty),
    qty_low: numOrNull(o.qty_low),
    qty_high: numOrNull(o.qty_high),
    unit: strOrNull(o.unit, CAPS.unit),
    unit_mappable: boolOr(o.unit_mappable, false),
    ingredient_text: cap(String(o.ingredient_text ?? ""), CAPS.ingredient_text),
    notes: strOrNull(o.notes, CAPS.notes),
    raw_amount: o.raw_amount === null || o.raw_amount === undefined
      ? ""
      : cap(String(o.raw_amount), CAPS.raw_amount),
    optional: boolOr(o.optional, false),
    confidence: numOrNull(o.confidence) ?? 0,
  };
}

/**
 * A leading determiner on a chip label ("the kale") belongs to the sentence,
 * not the food's name — but it must never be DELETED, or the step loses a
 * word. Relocate it: append it to the preceding text token (inserting one when
 * the ref opens the step), and keep the label as the bare name. The prompt
 * asks for this split up front; this guard makes the sentence read back intact
 * whenever the model includes the article anyway.
 */
const LEADING_DETERMINER = /^(?:the|a|an|some)\s+/i;

function relocateLeadingDeterminers(tokens: StepToken[]): StepToken[] {
  const out: StepToken[] = [];
  for (const tok of tokens) {
    if (tok.t === "ref") {
      const m = tok.label.match(LEADING_DETERMINER);
      if (m) {
        const prev = out[out.length - 1];
        if (prev && prev.t === "text") {
          out[out.length - 1] = { t: "text", s: prev.s + m[0] };
        } else {
          out.push({ t: "text", s: m[0] });
        }
        out.push({ ...tok, label: tok.label.slice(m[0].length) });
        continue;
      }
    }
    out.push(tok);
  }
  return out;
}

function coerceMention(v: unknown): MentionKind {
  return v === "rementioned" || v === "fraction" ? v : "new";
}

function coercePortion(v: unknown): RefPortion | null {
  if (v === null || v === undefined) return null;
  const o = asRecord(v);
  return {
    qty: numOrNull(o.qty),
    qty_low: numOrNull(o.qty_low),
    qty_high: numOrNull(o.qty_high),
    unit: strOrNull(o.unit, CAPS.unit),
    qualifier: strOrNull(o.qualifier, CAPS.qualifier),
  };
}

/**
 * One ref entry → a flattened line index. A number is the legacy positional
 * form (committed runs replay through here) and passes straight through; a
 * string is a line KEY, resolved via the minted-key map — an unknown key
 * resolves to -1 ON PURPOSE, which the existing out-of-range machinery then
 * reports (`ref_out_of_range`) and demotes (`dropOutOfRangeRefs`), so a bad
 * key degrades exactly like a bad index always has.
 */
type RefResolver = (r: unknown) => number | null;

function coerceToken(v: unknown, resolveRef: RefResolver): StepToken | null {
  const o = asRecord(v);
  const t = o.t;
  if (t === "text") {
    return { t: "text", s: cap(String(o.s ?? ""), CAPS.step_text) };
  }
  if (t === "timer") {
    const low = numOrNull(o.low_seconds) ?? numOrNull(o.high_seconds) ?? 0;
    const high = numOrNull(o.high_seconds) ?? low;
    return { t: "timer", low_seconds: low, high_seconds: high };
  }
  if (t === "ref") {
    const refs = Array.isArray(o.refs)
      ? o.refs.map((r) => resolveRef(r)).filter((n): n is number => n !== null)
      : [];
    return {
      t: "ref",
      refs,
      // The chip words. `label` is the documented field, but the token schema
      // is one loose shape for all three kinds, and models reliably put the
      // words in `s` (the text-token field) instead — observed across runs;
      // reading only `label` blanked every chip and the UI fell back to
      // canonical names. Accept either; both are the model's own words.
      label: cap(String(o.label ?? o.s ?? ""), CAPS.label),
      mention: coerceMention(o.mention),
      portion: coercePortion(o.portion),
    };
  }
  return null; // unknown token kind — dropped (never invented into the stream)
}

/**
 * Normalises a provider's raw JSON into the frozen ExtractionResult. Missing
 * optional fields default the honest way (null / empty / false); a genuinely
 * unreadable payload throws `ExtractionParseError` (⇒ the scorer's JSON-invalid
 * bucket). Coercion never *adds* content — it only re-shapes what the model
 * emitted.
 */
export function coerceExtractionResult(raw: unknown): ExtractionResult {
  const o = asRecord(raw);
  // Line keys are read alongside the coercion and resolved to FLATTENED
  // indices here — the key never leaves the adapter, so the payload contract
  // (positional refs) is unchanged. First occurrence wins on a duplicate key.
  const keyToIndex = new Map<string, number>();
  let flat = 0;
  const groups: RawGroup[] = Array.isArray(o.groups)
    ? o.groups.map((g) => {
      const gr = asRecord(g);
      const rawItems = Array.isArray(gr.line_items) ? gr.line_items : [];
      for (const li of rawItems) {
        const key = String(asRecord(li).key ?? "").trim();
        if (key !== "" && !keyToIndex.has(key)) keyToIndex.set(key, flat);
        flat++;
      }
      return {
        name: strOrNull(gr.name, CAPS.group_name),
        line_items: rawItems.map(coerceLineItem),
      };
    })
    : [];
  const resolveRef: RefResolver = (r) => {
    if (typeof r === "string") return keyToIndex.get(r.trim()) ?? -1;
    return numOrNull(r);
  };
  const steps: Step[] = Array.isArray(o.steps)
    ? o.steps.map((s) => {
      const st = asRecord(s);
      const tokens = Array.isArray(st.tokens)
        ? st.tokens.map((t) => coerceToken(t, resolveRef)).filter((
          x,
        ): x is StepToken => x !== null)
        : [];
      return { tokens: relocateLeadingDeterminers(tokens) };
    })
    : [];
  const servings = numOrNull(o.servings_base);
  return {
    // The single choke point every import passes through, URL and photo
    // alike — so a shouted page arrives cased like a title wherever it came
    // from, and only ever from here.
    title: titleCaseIfUncased(cap(String(o.title ?? ""), CAPS.title)),
    servings_base: servings === null ? null : Math.round(servings),
    servings_raw: strOrNull(o.servings_raw, CAPS.servings_raw),
    yield_raw: strOrNull(o.yield_raw, CAPS.yield_raw),
    total_time_seconds: coerceTime(o.total_time_seconds),
    cook_time_seconds: coerceTime(o.cook_time_seconds),
    truncated: boolOr(o.truncated, false),
    image_quality: coerceImageQuality(o.image_quality),
    parse_warnings: Array.isArray(o.parse_warnings)
      ? o.parse_warnings.slice(0, MAX_PARSE_WARNINGS).map((w) =>
        cap(String(w), CAPS.parse_warning)
      )
      : [],
    groups,
    steps,
  };
}

// --- Structural never-invent validation --------------------------------------
// The scorer owns *content* hallucination (got vs gold). Here we catch the
// invariant violations that are detectable from the payload ALONE — the
// self-inconsistencies a faithful extractor should never produce — and fold
// them into parse_warnings so a comparison run can count them.
//
// Reporting is the rule; ONE issue is also repaired. An out-of-range step ref
// is not merely inconsistent, it mis-points at a real ingredient, so
// `validateExtractionResult` drops it rather than shipping it behind a warning.
// Everything else is surfaced honestly and left for the human at reconciliation.

/** Flatten line items across groups, in the order steps index into. */
export function flattenLines(r: ExtractionResult): RawLineItem[] {
  return r.groups.flatMap((g) => g.line_items);
}

export interface StructuralIssue {
  kind:
    | "range_with_single_qty" // qty AND qty_low/high both set
    | "empty_ingredient_text" // a line with no identity
    | "ref_out_of_range" // a step ref points at a non-existent line (dropped)
    | "portion_qty_and_range" // portion has qty AND qty_low/high
    | "negative_or_nan_number";
  where: string;
}

/**
 * Returns the structural never-invent issues in `r` (does not mutate). Adapters
 * append a summary to `parse_warnings`; the scorer counts them into the ledger.
 */
export function structuralIssues(r: ExtractionResult): StructuralIssue[] {
  const issues: StructuralIssue[] = [];
  const lines = flattenLines(r);
  lines.forEach((li, i) => {
    if (li.qty !== null && (li.qty_low !== null || li.qty_high !== null)) {
      issues.push({ kind: "range_with_single_qty", where: `line ${i}` });
    }
    if (li.ingredient_text.trim() === "") {
      issues.push({ kind: "empty_ingredient_text", where: `line ${i}` });
    }
    for (
      const [k, v] of Object.entries({
        qty: li.qty,
        low: li.qty_low,
        high: li.qty_high,
      })
    ) {
      if (v !== null && !Number.isFinite(v)) {
        issues.push({
          kind: "negative_or_nan_number",
          where: `line ${i}.${k}`,
        });
      }
    }
  });
  const n = lines.length;
  r.steps.forEach((step, si) => {
    step.tokens.forEach((tok, ti) => {
      if (tok.t === "ref") {
        for (const ref of tok.refs) {
          if (ref < 0 || ref >= n || !Number.isInteger(ref)) {
            issues.push({
              kind: "ref_out_of_range",
              where: `step ${si} token ${ti}`,
            });
          }
        }
        if (
          tok.portion &&
          tok.portion.qty !== null &&
          (tok.portion.qty_low !== null || tok.portion.qty_high !== null)
        ) {
          issues.push({
            kind: "portion_qty_and_range",
            where: `step ${si} token ${ti}`,
          });
        }
      }
    });
  });
  return issues;
}

/**
 * Removes step refs that point outside the flattened line space, since a ref
 * that cannot resolve is the one structural issue that is actively DANGEROUS
 * downstream: `line_index` is positional, so a stale index does not fail — it
 * silently chips the wrong ingredient (or, once the app remaps to
 * line_item_ids, throws in the client). A ref token left with no valid refs is
 * demoted to the plain text of its label, which is what it would have been had
 * the model not tried to link it; an unlabelled one is dropped entirely.
 *
 * This is the one place the pipeline REMOVES model output. It is still
 * never-invent: nothing is added or guessed, and the drop is recorded in
 * parse_warnings by the caller.
 */
function dropOutOfRangeRefs(r: ExtractionResult): ExtractionResult {
  const n = flattenLines(r).length;
  const valid = (ref: number) => Number.isInteger(ref) && ref >= 0 && ref < n;
  return {
    ...r,
    steps: r.steps.map((step) => ({
      tokens: step.tokens.flatMap((tok): StepToken[] => {
        if (tok.t !== "ref") return [tok];
        const refs = tok.refs.filter(valid);
        if (refs.length === tok.refs.length) return [tok];
        if (refs.length > 0) return [{ ...tok, refs }];
        return tok.label.trim() === "" ? [] : [{ t: "text", s: tok.label }];
      }),
    })),
  };
}

/**
 * Runs coercion + structural validation. Appends a single `parse_warnings`
 * summary when structural issues are found (so downstream sees the flag without
 * the adapter silently "fixing" the data — honest numbers), and DROPS the
 * unresolvable step refs (see {@link dropOutOfRangeRefs}). Returns the result.
 */
export function validateExtractionResult(
  r: ExtractionResult,
): ExtractionResult {
  const issues = structuralIssues(r);
  if (issues.length === 0) return r;
  const cleaned = issues.some((i) => i.kind === "ref_out_of_range")
    ? dropOutOfRangeRefs(r)
    : r;
  const summary = issues.map((i) => `${i.kind} @ ${i.where}`).join("; ");
  return {
    ...cleaned,
    parse_warnings: [
      ...cleaned.parse_warnings,
      `structural-review: ${summary}`,
    ],
  };
}
