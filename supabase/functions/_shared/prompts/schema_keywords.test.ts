// Claude's structured outputs refuse a schema that uses these keywords, and the
// refusal only shows against the live API — so the schemas are checked here.
import { assertEquals } from "@std/assert";
import * as receipt from "./receipt.ts";
import * as label from "./label.ts";
import * as extraction from "./extraction.ts";
import * as recipe from "../adapters/schema.ts";

const UNSUPPORTED = new Set([
  "minimum",
  "maximum",
  "exclusiveMinimum",
  "exclusiveMaximum",
  "multipleOf",
  "minLength",
  "maxLength",
  "pattern",
  "maxItems",
  "uniqueItems",
  "minProperties",
  "maxProperties",
]);

function offenders(node: unknown, path: string, out: string[]): void {
  if (Array.isArray(node)) {
    node.forEach((child, i) => offenders(child, `${path}[${i}]`, out));
    return;
  }
  if (node === null || typeof node !== "object") return;
  const record = node as Record<string, unknown>;
  const isPropertyMap = path.endsWith(".properties");
  for (const [key, value] of Object.entries(record)) {
    if (!isPropertyMap && UNSUPPORTED.has(key)) out.push(`${path}.${key}`);
    if (!isPropertyMap && key === "minItems" && value !== 0 && value !== 1) {
      out.push(`${path}.${key}`);
    }
    offenders(value, `${path}.${key}`, out);
  }
}

Deno.test("no prompt schema uses a keyword structured outputs refuse", () => {
  const found: string[] = [];
  const modules = { receipt, label, extraction, recipe };
  for (const [file, mod] of Object.entries(modules)) {
    for (const [name, value] of Object.entries(mod)) {
      if (name.endsWith("_SCHEMA")) offenders(value, `${file}.${name}`, found);
    }
  }
  assertEquals(found, []);
});
