// Joining the photos of one receipt — BY POSITION, never by identity.
//
// A till receipt is one strip. Photographed in parts, top to bottom, each photo
// overlaps the one before it by a few lines, and the whole job here is to find
// where. The rule, and it is the whole rule:
//
//   the seam between photo n and photo n+1 is the LONGEST RUN of identical
//   consecutive lines shared by the END of photo n and the START of photo n+1.
//
// Longest, consecutive, and anchored at those two ends. Nothing else is
// considered, and in particular **a line is never deduplicated because it looks
// like another line**. A receipt honestly prints the same item twice when two
// were bought, and a joiner that noticed "BANANAS 1.99" twice and kept one
// would delete a banana the household paid for. Every de-duplication this
// module performs is positional: it drops photo n+1's copy of a run that photo
// n already contributed, at the join, and nowhere else.
//
// When no run is found the photos are concatenated end to end and a note says
// so — in the review's voice, because it is the review that has to act on it.
// The reconcile figure (`receipt_assemble.ts`) is the backstop: a missed seam
// double-counts its overlap and a wrong one loses lines, and either way the
// lines stop adding up to the printed subtotal, which is exactly the flag the
// join card draws.
//
// Pure, and unit-tested against the four cases that matter: an overlap found,
// none found, the same item printed twice across a seam (kept twice), and three
// photos in a row.

import type { ReceiptSeam } from "./receipt_types.ts";

/** The joined strip, plus everything the payload needs to explain it. */
export interface JoinedTranscript {
  /** Every line of the joined strip, verbatim, in printed order. */
  lines: string[];
  /** `photoOfLine[i]` — which photo `lines[i]` came from. A seam line is the EARLIER photo's. */
  photoOfLine: number[];
  /** One entry per join, in order. Empty for a single photo. */
  seams: ReceiptSeam[];
  /** "What we could not read", in the review's voice. */
  notes: string[];
  /** The joined strip as one document — what the structuring call is given. */
  text: string;
}

/**
 * The comparison form. Case and inner whitespace are noise across two photos of
 * the same paper (one shot is brighter, one transcription spaces a column
 * differently), so they are folded away FOR THE COMPARISON ONLY — every line
 * kept is kept verbatim.
 */
export function joinKey(line: string): string {
  return line.trim().replace(/\s+/g, " ").toLowerCase();
}

/** A photo's transcription split into lines, blank ones dropped, each verbatim. */
export function transcriptLines(text: string): string[] {
  return text.split("\n").map((l) => l.replace(/\s+$/, "")).filter((l) =>
    l.trim() !== ""
  );
}

/**
 * The length of the longest run of identical consecutive lines shared by the
 * end of `head` and the start of `tail`, or 0 when there is none. Compared
 * through {@link joinKey}; a run of 1 is a real answer (a receipt's lines are
 * long and specific enough that one is rarely a coincidence, and the reconcile
 * catches it when it is).
 */
export function overlapLength(head: string[], tail: string[]): number {
  const max = Math.min(head.length, tail.length);
  for (let k = max; k >= 1; k--) {
    let same = true;
    for (let i = 0; i < k; i++) {
      if (joinKey(head[head.length - k + i]) !== joinKey(tail[i])) {
        same = false;
        break;
      }
    }
    if (same) return k;
  }
  return 0;
}

/** "the second", "the third" — the review speaks about photos in words, not indices. */
function ordinal(n: number): string {
  const words = [
    "first",
    "second",
    "third",
    "fourth",
    "fifth",
    "sixth",
    "seventh",
    "eighth",
  ];
  return words[n] ?? `${n + 1}th`;
}

/**
 * Joins consecutive photo transcriptions into one strip.
 *
 * `photos` are the segments IN ORDER, top to bottom — the order they were shot
 * in, which the camera door states and the transcription preserves. A single
 * photo joins to nothing and comes back as itself.
 */
export function joinPhotoTranscripts(photos: string[]): JoinedTranscript {
  const perPhoto = photos.map(transcriptLines);
  const lines: string[] = [];
  const photoOfLine: number[] = [];
  const seams: ReceiptSeam[] = [];
  const notes: string[] = [];

  perPhoto.forEach((photoLines, photo) => {
    if (photo === 0) {
      for (const l of photoLines) {
        lines.push(l);
        photoOfLine.push(0);
      }
      return;
    }
    // The end of the PREVIOUS photo, not the end of everything joined so far:
    // the rule is about two photos, and a run may not reach back past one.
    const previous = perPhoto[photo - 1];
    const previousKept = Math.min(previous.length, lines.length);
    const head = lines.slice(lines.length - previousKept);
    const overlap = overlapLength(head, photoLines);
    if (overlap === 0) {
      notes.push(
        `We could not find where the ${ordinal(photo - 1)} photo joins the ` +
          `${
            ordinal(photo)
          } — their lines are kept end to end, so a line may ` +
          `be missing or counted twice.`,
      );
    } else {
      seams.push({ from: photo - 1, to: photo, overlap_lines: overlap });
    }
    // The overlap's lines are already in `lines`, contributed by the earlier
    // photo — which is why a seam line's `photo` is the FIRST one it appeared in.
    for (const l of photoLines.slice(overlap)) {
      lines.push(l);
      photoOfLine.push(photo);
    }
  });

  return { lines, photoOfLine, seams, notes, text: lines.join("\n") };
}
