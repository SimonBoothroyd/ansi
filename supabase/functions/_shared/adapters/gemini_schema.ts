// Gemini's `responseSchema` speaks an OpenAPI-3 subset, not JSON Schema: types
// are uppercase enums, nullability is `nullable: true`, and
// `additionalProperties` is unsupported. So EXTRACTION_JSON_SCHEMA
// (adapters/schema.ts) is hand-mirrored here in Gemini's dialect; coercion
// tolerates either shape.

interface GSchema {
  type: string;
  nullable?: boolean;
  description?: string;
  enum?: string[];
  format?: string;
  items?: GSchema;
  properties?: Record<string, GSchema>;
  required?: string[];
  propertyOrdering?: string[];
}

const gTime: GSchema = {
  type: "OBJECT",
  nullable: true,
  properties: {
    low_seconds: { type: "NUMBER" },
    high_seconds: { type: "NUMBER" },
  },
  required: ["low_seconds", "high_seconds"],
  propertyOrdering: ["low_seconds", "high_seconds"],
};

const gLineItem: GSchema = {
  type: "OBJECT",
  properties: {
    key: { type: "STRING" },
    qty: { type: "NUMBER", nullable: true },
    qty_low: { type: "NUMBER", nullable: true },
    qty_high: { type: "NUMBER", nullable: true },
    unit: { type: "STRING", nullable: true },
    unit_mappable: { type: "BOOLEAN" },
    ingredient_text: { type: "STRING" },
    notes: { type: "STRING", nullable: true },
    raw_amount: { type: "STRING" },
    optional: { type: "BOOLEAN" },
    confidence: { type: "NUMBER" },
  },
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
  propertyOrdering: [
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
};

const gPortion: GSchema = {
  type: "OBJECT",
  nullable: true,
  properties: {
    qty: { type: "NUMBER", nullable: true },
    qty_low: { type: "NUMBER", nullable: true },
    qty_high: { type: "NUMBER", nullable: true },
    unit: { type: "STRING", nullable: true },
    qualifier: { type: "STRING", nullable: true },
  },
  required: ["qty", "qty_low", "qty_high", "unit", "qualifier"],
};

const gToken: GSchema = {
  type: "OBJECT",
  properties: {
    t: { type: "STRING", enum: ["text", "ref", "timer"] },
    s: { type: "STRING", nullable: true },
    refs: { type: "ARRAY", nullable: true, items: { type: "STRING" } },
    label: { type: "STRING", nullable: true },
    mention: {
      type: "STRING",
      nullable: true,
      enum: ["new", "rementioned", "fraction"],
    },
    portion: gPortion,
    low_seconds: { type: "NUMBER", nullable: true },
    high_seconds: { type: "NUMBER", nullable: true },
  },
  required: ["t"],
};

/** The extraction schema in Gemini's responseSchema dialect. */
export function toGeminiSchema(): GSchema {
  return {
    type: "OBJECT",
    properties: {
      title: { type: "STRING" },
      servings_base: { type: "INTEGER", nullable: true },
      servings_raw: { type: "STRING", nullable: true },
      yield_raw: { type: "STRING", nullable: true },
      total_time_seconds: gTime,
      cook_time_seconds: gTime,
      truncated: { type: "BOOLEAN" },
      image_quality: { type: "STRING", enum: ["ok", "degraded", "poor"] },
      parse_warnings: { type: "ARRAY", items: { type: "STRING" } },
      groups: {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          properties: {
            name: { type: "STRING", nullable: true },
            line_items: { type: "ARRAY", items: gLineItem },
          },
          required: ["name", "line_items"],
        },
      },
      steps: {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          properties: { tokens: { type: "ARRAY", items: gToken } },
          required: ["tokens"],
        },
      },
    },
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
  };
}
