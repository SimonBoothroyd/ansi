// The keyless replay switch, and the locks that keep it out of a deployed
// environment. See `replay.ts`.

import { assert, assertEquals, assertThrows } from "@std/assert";
import {
  REPLAY_FIXTURE_ENV,
  replayAdapter,
  replayAdapterFromEnv,
} from "./replay.ts";
import { deriveUnitHints } from "../_shared/unit_hints.ts";

// The corpus's largest case, from a saved Haiku run that read every line of it.
const RUN_CASE =
  "../../../evals/runs/2026-09-02-var-v5-r3/claude-haiku/dirty-rice.json";

const savedCase = (): unknown =>
  JSON.parse(
    Deno.readTextFileSync(new URL(RUN_CASE, import.meta.url).pathname),
  );

/** Sets the env for one case and restores whatever was there. */
function withEnv(vars: Record<string, string | null>, run: () => void): void {
  const before = Object.keys(vars).map(
    (k) => [k, Deno.env.get(k) ?? null] as const,
  );
  try {
    for (const [k, v] of Object.entries(vars)) {
      if (v === null) Deno.env.delete(k);
      else Deno.env.set(k, v);
    }
    run();
  } finally {
    for (const [k, v] of before) {
      if (v === null) Deno.env.delete(k);
      else Deno.env.set(k, v);
    }
  }
}

Deno.test("replay — a saved run case extracts the recipe it recorded, with no key", async () => {
  const adapter = replayAdapter(savedCase(), "dirty-rice");
  assert(adapter.transcribe, "the photo path needs a transcribe tier");
  const blob = await adapter.transcribe!([new Uint8Array([1, 2, 3])]);
  assertEquals(blob.source, "transcription");
  assert((blob.text ?? "").length > 0, "the recorded source text is replayed");

  const result = await adapter.sanitize(blob, deriveUnitHints());
  // The largest case in the corpus: three groups, thirty-five lines. It is the
  // size that matters here — it is what makes the cascade's fan-out visible.
  assertEquals(result.groups.length, 3);
  assertEquals(
    result.groups.reduce((n, g) => n + g.line_items.length, 0),
    35,
  );
});

Deno.test("replay — refuses a fixture recorded from another provider", () => {
  assertThrows(
    () => replayAdapter({ provider: "gpt-5-mini", raw: {} }, "x"),
    Error,
    "replay decodes Claude responses",
  );
});

Deno.test("replay — a file that is not a run case fails at wiring, not as an empty recipe", () => {
  assertThrows(
    () => replayAdapter({ title: "Dirty Rice" }, "x"),
    Error,
    "not an eval run case file",
  );
});

Deno.test("replay — off unless the env var names something", () => {
  withEnv({ [REPLAY_FIXTURE_ENV]: null, ANTHROPIC_API_KEY: null }, () => {
    assertEquals(replayAdapterFromEnv(), null);
  });
  withEnv({ [REPLAY_FIXTURE_ENV]: "   ", ANTHROPIC_API_KEY: null }, () => {
    assertEquals(replayAdapterFromEnv(), null);
  });
});

Deno.test("replay — REFUSES to load where a real key can extract", () => {
  // The lock that matters: a deployed environment always has the key, so even
  // if the switch were somehow set there it can never serve a canned recipe.
  withEnv(
    { [REPLAY_FIXTURE_ENV]: "/does/not/matter", ANTHROPIC_API_KEY: "sk-ant-x" },
    () => {
      assertThrows(
        replayAdapterFromEnv,
        Error,
        "refusing to serve a saved recipe",
      );
    },
  );
});
