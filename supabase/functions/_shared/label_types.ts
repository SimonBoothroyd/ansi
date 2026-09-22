// What one photographed nutrition label says, and the seam the reader is
// injected through. Mirrored in Dart (`app/lib/features/ingredients/domain`),
// so a change here is a change to a contract two languages hold.
//
// Every field is what the label PRINTED. Nothing is derived: a figure the
// label does not print, or that could not be read, is null and names itself in
// `notes`.

/** The five macros a label is read for, per column. Null where not printed. */
export interface LabelMacros {
  kcal: number | null;
  protein_g: number | null;
  carbohydrate_g: number | null;
  fat_g: number | null;
  fibre_g: number | null;
}

/** The serving size as the label prints it. */
export interface LabelServing {
  /** The amount a person would type ("55" of "2/3 cup (55g)"). */
  amount: number | null;
  /** Its unit in the label's own words ("g", "ml", "cup"). */
  unit_printed: string | null;
  /** The whole serving line, verbatim, for the person to check against. */
  text_printed: string | null;
}

/**
 * A per-100 column, and which 100 it is. Present ONLY when the label prints
 * such a column — most EU labels do, most US ones do not. Never computed.
 */
export interface LabelPer100 extends LabelMacros {
  basis: "g" | "ml";
}

/** One label, read. */
export interface LabelReading {
  serving: LabelServing;
  per_serving: LabelMacros;
  per_100: LabelPer100 | null;
  /** What could not be read, in plain words. Empty when it read cleanly. */
  notes: string[];
}

/** The model seam: one image in, one reading out. Faked in tests. */
export interface LabelAdapter {
  readonly name: string;
  read(image: Uint8Array): Promise<LabelReading>;
}
