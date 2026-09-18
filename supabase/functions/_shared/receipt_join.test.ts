// The positional join — the four cases it has to get right, and the one it
// must never "helpfully" get wrong.

import { assertEquals } from "@std/assert";
import {
  joinKey,
  joinPhotoTranscripts,
  overlapLength,
  transcriptLines,
} from "./receipt_join.ts";

const strip = (...lines: string[]) => lines.join("\n");

Deno.test("join — a single photo joins to nothing and comes back as itself", () => {
  const t = joinPhotoTranscripts([strip("A 1.00", "B 2.00")]);
  assertEquals(t.lines, ["A 1.00", "B 2.00"]);
  assertEquals(t.photoOfLine, [0, 0]);
  assertEquals(t.seams, []);
  assertEquals(t.notes, []);
});

Deno.test("join — the overlap is found, and counted", () => {
  const t = joinPhotoTranscripts([
    strip("A 1.00", "B 2.00", "C 3.00"),
    strip("B 2.00", "C 3.00", "D 4.00"),
  ]);
  assertEquals(t.lines, ["A 1.00", "B 2.00", "C 3.00", "D 4.00"]);
  assertEquals(t.seams, [{ from: 0, to: 1, overlap_lines: 2 }]);
  assertEquals(t.notes, []);
  // A seam line belongs to the photo that CONTRIBUTED it — the earlier one.
  assertEquals(t.photoOfLine, [0, 0, 0, 1]);
});

Deno.test("join — case and inner spacing are noise across two shots of one paper", () => {
  const t = joinPhotoTranscripts([
    strip("A 1.00", "TJ  ORG   BANANAS 3.49"),
    strip("tj org bananas 3.49", "B 2.00"),
  ]);
  assertEquals(t.seams, [{ from: 0, to: 1, overlap_lines: 1 }]);
  // Kept VERBATIM: the fold is for the comparison only.
  assertEquals(t.lines, ["A 1.00", "TJ  ORG   BANANAS 3.49", "B 2.00"]);
});

Deno.test("join — the LONGEST run wins, not the first one found", () => {
  // "X 9.00" repeats inside the overlap; a shorter answer would lose a line.
  const t = joinPhotoTranscripts([
    strip("A", "X 9.00", "B", "X 9.00", "C"),
    strip("B", "X 9.00", "C", "D"),
  ]);
  assertEquals(t.seams, [{ from: 0, to: 1, overlap_lines: 3 }]);
  assertEquals(t.lines, ["A", "X 9.00", "B", "X 9.00", "C", "D"]);
});

Deno.test("join — no run: the photos are concatenated and the review is told", () => {
  const t = joinPhotoTranscripts([
    strip("A 1.00", "B 2.00"),
    strip("C 3.00", "D 4.00"),
  ]);
  assertEquals(t.lines, ["A 1.00", "B 2.00", "C 3.00", "D 4.00"]);
  assertEquals(t.seams, []);
  assertEquals(t.notes.length, 1);
  // Names the two photos in the words the review speaks, and says what the
  // consequence is rather than that an algorithm failed.
  assertEquals(
    t.notes[0],
    "We could not find where the first photo joins the second — their lines " +
      "are kept end to end, so a line may be missing or counted twice.",
  );
  assertEquals(t.photoOfLine, [0, 0, 1, 1]);
});

Deno.test("join — THE RULE: an item printed twice is kept twice", () => {
  // Two bunches of bananas, on ONE photo. Nothing about the join may notice
  // that two lines look alike; only position is ever consulted.
  const t = joinPhotoTranscripts([
    strip(
      "TJ ORG BANANAS 3.49",
      "MILK 2.99",
      "TJ ORG BANANAS 3.49",
      "EGGS 4.29",
    ),
    strip("TJ ORG BANANAS 3.49", "EGGS 4.29", "TOTAL 14.26"),
  ]);
  assertEquals(t.seams, [{ from: 0, to: 1, overlap_lines: 2 }]);
  assertEquals(t.lines, [
    "TJ ORG BANANAS 3.49",
    "MILK 2.99",
    "TJ ORG BANANAS 3.49",
    "EGGS 4.29",
    "TOTAL 14.26",
  ]);
  // Both bananas survive: the seam consumed the LAST two lines, which is where
  // they positionally overlapped, and left the first bunch alone.
  assertEquals(
    t.lines.filter((l) => l === "TJ ORG BANANAS 3.49").length,
    2,
  );
});

Deno.test("join — three photos, two seams, in order", () => {
  const t = joinPhotoTranscripts([
    strip("A", "B", "C"),
    strip("C", "D", "E"),
    strip("D", "E", "F"),
  ]);
  assertEquals(t.lines, ["A", "B", "C", "D", "E", "F"]);
  assertEquals(t.seams, [
    { from: 0, to: 1, overlap_lines: 1 },
    { from: 1, to: 2, overlap_lines: 2 },
  ]);
  assertEquals(t.photoOfLine, [0, 0, 0, 1, 1, 2]);
});

Deno.test("join — one seam missing among three does not take the other with it", () => {
  const t = joinPhotoTranscripts([
    strip("A", "B"),
    strip("C", "D"), // no run with A/B
    strip("D", "E"), // joins cleanly to the one before it
  ]);
  assertEquals(t.lines, ["A", "B", "C", "D", "E"]);
  assertEquals(t.seams, [{ from: 1, to: 2, overlap_lines: 1 }]);
  assertEquals(t.notes.length, 1);
});

Deno.test("join — a run may not reach back past the photo it belongs to", () => {
  // Photo 2 is a single line that also happens to end photo 0. Only photo 1's
  // own end is compared, so nothing splices photo 2 onto the wrong seam.
  const t = joinPhotoTranscripts([
    strip("A", "Z"),
    strip("Z", "B"),
    strip("Z"),
  ]);
  assertEquals(t.lines, ["A", "Z", "B", "Z"]);
  assertEquals(t.seams, [{ from: 0, to: 1, overlap_lines: 1 }]);
  assertEquals(t.notes.length, 1);
});

Deno.test("join — blank lines are dropped, trailing space never counted", () => {
  assertEquals(transcriptLines("A  \n\n  \nB\n"), ["A", "B"]);
  assertEquals(joinKey("  TJ   ORG  "), "tj org");
  assertEquals(overlapLength([], ["A"]), 0);
  assertEquals(overlapLength(["A"], []), 0);
});
