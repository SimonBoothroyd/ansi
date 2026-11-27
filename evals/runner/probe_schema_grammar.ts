// Whether each Claude model compiles the extraction schema for strict output.
// The limit is tighter on Haiku 5.5 than 4.5 ("The compiled grammar is too
// large", HTTP 400): an optional field on the step token, or one more field in
// its portion, is enough to tip it. This sends each schema with a one-line
// recipe and a one-token output cap, so a refusal costs nothing and an
// acceptance a fraction of a cent. Run it after any schema change.
//
//   source ../.env.local   # ANTHROPIC_API_KEY
//   deno run --allow-env --allow-net --allow-read runner/probe_schema_grammar.ts

import { EXTRACTION_JSON_SCHEMA } from "../../supabase/functions/_shared/adapters/schema.ts";

type Json = Record<string, unknown>;

const base = EXTRACTION_JSON_SCHEMA as unknown as Json;

const VARIANTS: Record<string, Json> = {
  // The schema production sends. Every model in MODELS must accept it; a
  // candidate shape goes here beside it while one is being sized.
  "production schema": base,
};

const MODELS = ["claude-haiku-4-5", "claude-haiku-5-5"];
const key = Deno.env.get("ANTHROPIC_API_KEY");
if (!key) throw new Error("ANTHROPIC_API_KEY is not set");

async function compiles(model: string, schema: Json): Promise<string> {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": key!,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model,
      max_tokens: 1,
      messages: [{ role: "user", content: "Toast: 1 slice bread. Toast it." }],
      output_config: { format: { type: "json_schema", schema } },
    }),
  });
  if (res.ok) return "ACCEPTED";
  const text = await res.text();
  return text.includes("grammar is too large")
    ? "REFUSED (grammar too large)"
    : `REFUSED (${res.status}: ${text.slice(0, 160)})`;
}

for (const [name, schema] of Object.entries(VARIANTS)) {
  for (const model of MODELS) {
    console.log(
      `${name.padEnd(38)} ${model.padEnd(18)} ${await compiles(model, schema)}`,
    );
  }
}
