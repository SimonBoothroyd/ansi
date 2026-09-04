# ADR-0011 — One save, one write: the flesh-out form defers

- **Status:** proposed (2026-09-03, Simon + agent — exec plan 0029)
- **Refines:** [ADR-0008](./0008-unit-admission-model.md) §2 (density is one
  stored fact, enterable two equivalent ways) — the *ways* become two picks in
  one sentence rather than two controls, and both now land through the form's
  Save rather than immediately. Nothing about the stored fact changes.
  [ADR-0010](./0010-piece-is-an-admission-fact.md)'s one question is unchanged
  in substance; only *when* its answer is written moves.

## Context

The ingredient flesh-out form has two persistence models at once. Its `Save`
writes seven scalar fields through `saveEdit`. Fourteen other call sites write
the moment you tap them: aliases, measures, the density, "Counts as", the
`piece` question, the USDA decline and pick, confirm and un-confirm, delete.
Nothing on screen says which is which, and on a row whose density and measures
editors are both open there are three green buttons reading **Save**, each
saving something different.

The owner, driving it:

> *"the whole write on edit seems bizarre, rather than write on save?"*

It is not anyone's decision — it is a consequence. `DensityEntry` and
`MeasuresEditor` were extracted so the flesh-out form and the quantity sheet
could share one editor each. The quantity sheet has **no Save**: you are
managing the vocabulary in the middle of picking a unit for a recipe line, and
an immediate write is right there. The form inherited that behaviour rather
than choosing it, and the rest followed the precedent.

Three things fall out of the mixture:

1. **"Back" is a lie.** Leaving the form discards the seven scalar fields and
   keeps everything else. There is no way to abandon an edit.
2. **A guard that looks transactional isn't.** The New-ingredient sheet's
   `create()` runs `createStub` → `addMeasure` → `applyUsdaProbe`/enrich inside
   one `ref.write`, commented as *"one act to the person who tapped Create"*.
   `ref.write` is an error boundary, not a transaction: a failure after the row
   is made leaves a row without its pack measure and one message implying
   neither happened.
3. **The New-ingredient sheet cannot dissolve.** It exists because it is the
   stage where *nothing has been written yet* — dismiss it and no row exists.
   The form cannot take that over while half of it needs a row id to write to,
   so the app keeps two front doors for creating an ingredient, one of which
   (plan 0028's design pass) the owner called cluttered and daunting.

## Decision

**The flesh-out form writes once, on Save, in one transaction. Nothing on it
writes on tap.**

Three rules make that possible without a mode flag:

1. **The shared editors report intent; the host commits.** `DensityEntry` and
   `MeasuresEditor` stop calling repositories. They hand the host what the
   person asked for — a density, a cleared density, an added or removed
   measure, the `piece` answer — and the host decides when it lands. The
   quantity sheet's host commits immediately, because it has no Save and that
   is correct there. The form's host defers to its Save. **This is not a
   boolean on the widget**: two behaviours behind a flag is how the present
   confusion was built. It is a commit function the host supplies.

2. **One transaction, across both repositories.** `SqliteMeasureRepository` and
   `SqliteIngredientRepository` already wrap the *same* `SqliteConnection`, so
   this is an API shape, not a distributed write. A `saveForm` door takes the
   whole intent — row fields, alias set, measures added and removed, density,
   default measure — and applies it in one `writeTransaction`. Partial success
   stops being representable.

3. **A draft distinguishes "unloaded" from "empty".** The form must hold the
   measures it will write back, and D6's rule is that an errored measures
   stream rendered as `const []` hides rows that exist. The draft type carries
   the difference explicitly; a save is refused while any collection is
   unloaded rather than writing a narrowed set.

**Consequence, and the reason to do it: the form becomes the create surface.**
With nothing written until Save, a form with no row id is coherent — children
are held in memory and the first Save writes row and children together. The
New-ingredient sheet's remaining job (capture a name before a row exists)
disappears, and with it the last duplicate of the barcode and USDA legs the
form already has.

**Confirm and delete stay immediate.** They are not field edits: `Mark
complete` is a statement about a row that already exists, and delete ends it.
Both keep their own buttons and their own writes.

## Consequences

- **`Back` becomes honest**: it discards. That is the whole point, and it is
  also the risk — a person who edited a measure and backed out now loses it,
  where before it had already landed. The form is a pushed page with a visible
  dock; this is the standard bargain, and the alternative is the present one
  where nothing is discardable.
- **The M-D2 serving offer simplifies**: it already defers to Save by writing
  through `setDensity` inside the save. It stops being the exception.
- **The USDA pick stops writing.** It fills the draft; Save lands it. The
  "an explicit pick outranks a half-typed panel" reconciliation added in
  `5eb10cd` is deleted rather than extended — with one write model there is no
  row moving underneath a draft to reconcile against.
- **G1's re-seed narrows.** Its job was to make a row that filled *underneath*
  the form reach the fields. Only another device's sync can do that now.
- **Offline is unaffected.** PowerSync writes are local first; one transaction
  uploads as one batch. UPSERT stays illegal on the views (memory: local tables
  are views), so the compound save is explicit INSERT-or-UPDATE per row, which
  is how both repositories already work.

## Alternatives considered

- **Leave it.** Rejected: it is the reason the sheet cannot dissolve, and the
  owner has named the confusion directly.
- **A `commitImmediately` flag on the shared editors.** Rejected: two
  behaviours in one widget is the shape of the present bug.
- **Go the other way — everything writes immediately, and Save disappears.**
  Genuinely coherent, and cheaper. Rejected because it makes the sheet
  permanent: a create surface *requires* a stage where nothing has been
  written. It also forces rename-on-blur, and a rename rewrites `match_text`
  and re-fires the server probe.
