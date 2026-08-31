// The structured-output JSON Schema every provider adapter targets, plus the
// coercion + never-invent validation that turns a provider's raw JSON into the
// frozen `ExtractionResult` (types.ts §4.4).
//
// One schema, three providers. Each provider's *native* structured-output mode
// (Anthropic `output_config.format`, OpenAI `response_format: json_schema`,
// Gemini `responseSchema`) consumes `EXTRACTION_JSON_SCHEMA`; each adapter then
// runs `coerceExtractionResult` (portability normalisation) and
// `validateExtractionResult` (structural never-invent checks). Keeping this in
// one place is what makes the providers comparable in lane D.
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
    // ref
    refs: { type: "array", items: { type: "integer" } },
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

/** Thrown when a provider returns JSON we cannot read as an ExtractionResult. */
export class ExtractionParseError extends Error {
  constructor(message: string, readonly raw?: unknown) {
    super(message);
    this.name = "ExtractionParseError";
  }
}

// --- Coercion: provider JSON → frozen ExtractionResult -----------------------

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

function strOrNull(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  return String(v);
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
    unit: strOrNull(o.unit),
    unit_mappable: boolOr(o.unit_mappable, false),
    ingredient_text: String(o.ingredient_text ?? ""),
    notes: strOrNull(o.notes),
    raw_amount: o.raw_amount === null || o.raw_amount === undefined
      ? ""
      : String(o.raw_amount),
    optional: boolOr(o.optional, false),
    confidence: numOrNull(o.confidence) ?? 0,
  };
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
    unit: strOrNull(o.unit),
    qualifier: strOrNull(o.qualifier),
  };
}

function coerceToken(v: unknown): StepToken | null {
  const o = asRecord(v);
  const t = o.t;
  if (t === "text") return { t: "text", s: String(o.s ?? "") };
  if (t === "timer") {
    const low = numOrNull(o.low_seconds) ?? numOrNull(o.high_seconds) ?? 0;
    const high = numOrNull(o.high_seconds) ?? low;
    return { t: "timer", low_seconds: low, high_seconds: high };
  }
  if (t === "ref") {
    const refs = Array.isArray(o.refs)
      ? o.refs.map((r) => numOrNull(r)).filter((n): n is number => n !== null)
      : [];
    return {
      t: "ref",
      refs,
      label: String(o.label ?? ""),
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
  const groups: RawGroup[] = Array.isArray(o.groups)
    ? o.groups.map((g) => {
      const gr = asRecord(g);
      return {
        name: strOrNull(gr.name),
        line_items: Array.isArray(gr.line_items)
          ? gr.line_items.map(coerceLineItem)
          : [],
      };
    })
    : [];
  const steps: Step[] = Array.isArray(o.steps)
    ? o.steps.map((s) => {
      const st = asRecord(s);
      const tokens = Array.isArray(st.tokens)
        ? st.tokens.map(coerceToken).filter((x): x is StepToken => x !== null)
        : [];
      return { tokens };
    })
    : [];
  const servings = numOrNull(o.servings_base);
  return {
    title: String(o.title ?? ""),
    servings_base: servings === null ? null : Math.round(servings),
    servings_raw: strOrNull(o.servings_raw),
    yield_raw: strOrNull(o.yield_raw),
    total_time_seconds: coerceTime(o.total_time_seconds),
    cook_time_seconds: coerceTime(o.cook_time_seconds),
    truncated: boolOr(o.truncated, false),
    image_quality: coerceImageQuality(o.image_quality),
    parse_warnings: Array.isArray(o.parse_warnings)
      ? o.parse_warnings.map((w) => String(w))
      : [],
    groups,
    steps,
  };
}

// --- Structural never-invent validation --------------------------------------
// The scorer owns *content* hallucination (got vs gold). Here we catch the
// invariant violations that are detectable from the payload ALONE, and fold
// them into parse_warnings so a comparison run can count them. These are the
// self-inconsistencies a faithful extractor should never produce.

/** Flatten line items across groups, in the order steps index into. */
export function flattenLines(r: ExtractionResult): RawLineItem[] {
  return r.groups.flatMap((g) => g.line_items);
}

export interface StructuralIssue {
  kind:
    | "range_with_single_qty" // qty AND qty_low/high both set
    | "empty_ingredient_text" // a line with no identity
    | "ref_out_of_range" // a step ref points at a non-existent line
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
 * Runs coercion + structural validation. Appends a single `parse_warnings`
 * summary when structural issues are found (so downstream sees the flag without
 * the adapter silently "fixing" the data — honest numbers). Returns the result.
 */
export function validateExtractionResult(
  r: ExtractionResult,
): ExtractionResult {
  const issues = structuralIssues(r);
  if (issues.length > 0) {
    const summary = issues.map((i) => `${i.kind} @ ${i.where}`).join("; ");
    return {
      ...r,
      parse_warnings: [
        ...r.parse_warnings,
        `structural-review: ${summary}`,
      ],
    };
  }
  return r;
}
