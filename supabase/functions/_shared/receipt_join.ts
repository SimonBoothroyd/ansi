// Joining the photos of one receipt by position, never by identity.
//
//   The seam between photo n and photo n+1 is the longest run of identical
//   consecutive lines shared by the end of photo n and the start of photo n+1.
//
// A line is never dropped for looking like another: a receipt prints an item
// twice when two were bought. With no run found, the photos are concatenated
// and a note says so; the reconcile figure (`receipt_assemble.ts`) then shows
// the lines not adding up.

import type { ReceiptSeam } from "./receipt_types.ts";

/** The joined strip, plus everything the payload needs to explain it. */
export interface JoinedTranscript {
  /** Every line of the joined strip, verbatim, in printed order. */
  lines: string[];
  /** Which photo `lines[i]` came from. A seam line is the earlier photo's. */
  photoOfLine: number[];
  /** One entry per join, in order. Empty for a single photo. */
  seams: ReceiptSeam[];
  /** "What we could not read", in the review's voice. */
  notes: string[];
  /** The joined strip as one document, given to the structuring call. */
  text: string;
}

/**
 * The comparison form: case and inner whitespace folded away, for the
 * comparison only. Every kept line is kept verbatim.
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
 * end of `head` and the start of `tail`, or 0. Compared through
 * {@link joinKey}. A run of 1 counts; the reconcile catches a coincidence.
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

/** "the second", "the third": the review names photos in words. */
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
 * Joins consecutive photo transcriptions, in top-to-bottom order, into one
 * strip. A single photo comes back as itself.
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
    // The end of the previous photo only: a run may not reach back past one.
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
    // The overlap's lines are already in `lines`, from the earlier photo.
    for (const l of photoLines.slice(overlap)) {
      lines.push(l);
      photoOfLine.push(photo);
    }
  });

  return { lines, photoOfLine, seams, notes, text: lines.join("\n") };
}
