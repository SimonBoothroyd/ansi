import { assertEquals } from "@std/assert";
import { pinnedSampling } from "./sampling.ts";

Deno.test("pinnedSampling — Haiku 4.5 is pinned to 0; the 5.x models get nothing", () => {
  assertEquals(pinnedSampling("claude-haiku-4-5"), { temperature: 0 });
  assertEquals(pinnedSampling("claude-haiku-5-5"), {});
  assertEquals(pinnedSampling("claude-sonnet-5"), {});
  assertEquals(pinnedSampling("claude-opus-5"), {});
});
