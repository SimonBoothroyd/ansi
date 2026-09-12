# Feature: import

**Roadmap:** Step 8 — AI/deterministic import (done; the client lane is
`docs/exec-plans/completed/0017-import-client.md`, the frozen contracts are
`.../completed/0014-import-foundation.md`, the integration tail
`.../completed/0019-import-integration.md`).

Paste a recipe URL or pick photos of a page → the server extracts and matches →
you review and fix the result on one editable screen → Save writes a real
recipe with chipped method steps.

**The client never matches.** Extraction and the match cascade are a server-side
edge function (ADR-0004); this feature sends a URL or images, renders what comes
back, and owns the human decisions and the commit.

## The flow

```
ImportView (intake)                   presentation/import_view.dart
  paste a URL  ·  pick photos → crop/rotate each page
      │
      ▼  ImportController.startImport(ImportSource)
ImportRepository.startImport                 ← the seam that varies (below)
      │            POST import-recipe {url} | {images: [b64…]}
      ▼
ReconciliationPayload                 domain/reconciliation_payload.dart
  title · servings · times · warnings
  groups[ lines[ raw, band, candidates ] ]
  steps[ tokens ]   ← refs are by FLATTENED LINE INDEX, not ids yet
      │
      ▼
ReconciliationBody — "Review recipe"  presentation/reconciliation_view.dart
  one card per line (ReviewLineCard), compact → expands in place
  band seeds the card's starting state; VALIDITY is what gates Save
  SECTIONS are the human's (review_groups.dart), not the payload's
      │
      ▼  ImportController.commit() → buildCommit(...)
CommitPayload                         domain/commit_payload.dart
      │
      ▼  SqliteImportRepository.commit — ONE local transaction
recipe (filed into the default book) · ingredient_group · recipe_line_item
  · create-new stubs · correction aliases
  · step refs remapped line_index → line_item_id
```

## Layout

```
import/
  domain/         PURE DART (no package:flutter)
    reconciliation_payload.dart  the server contract, mirrored (Freezed/json)
    commit_payload.dart          what the commit writes
    line_resolution.dart         one line's decision + buildCommit()
    line_validation.dart         per-line issues + the Save gate
    review_groups.dart           the review's SECTIONS, over flat line indexes
    preview_recipe.dart          payload → the Recipe the method fold renders
    header_draft.dart            payload → the header draft the form edits (0025)
    yield_prefill.dart           yield_raw → the MAKES prefill (8.6)
    import_stage.dart            the stages the reading screen ticks off,
                                 named on the wire by the server
    import_repository.dart       ImportRepository + ImportSource
  data/
    import_repository_impl.dart  SqliteImportRepository — the REAL commit
    remote_import_repository.dart EdgeImportRepository — functions.invoke
    sse.dart                     the text/event-stream reader behind it
    sample_payloads.dart          the canned/offline payload (see below)
    photo_intake.dart            pick → crop/rotate, behind injectable seams
    import_providers.dart        importRepositoryProvider (keepAlive)
  presentation/
    import_view.dart             intake screen
    reconciliation_view.dart     the merged Review recipe screen
    recon_line_card.dart         the review's contents in the shared LineCard
                                 (recipes/presentation/line_card.dart)
    recon_amount.dart            the amount label + the two amount sheets
    recon_resolver.dart          the identity cell + the seeded search sheet
    import_view_models.dart      ImportController + the ImportState machine
    import_method_editing.dart   the step cards' host over the review's draft
```

## Model notes

- **The reading screen is a checklist the server fills in, not a guess.** The
  edge function answers as a `text/event-stream` and names each stage as it
  completes, so the list of rows comes from the server's first event and every
  finished row carries the server's own elapsed time. A photo import makes two
  model calls before matching and a URL import one, which is why the stage list
  is sent rather than assumed. The ids are the wire contract; the wording lives
  in `import_stage.dart`, because copy belongs where the screen is. A run that
  fails says so on the row it reached instead of stalling there.
- **One screen, not three.** 0014/0017 designed triage → preview → commit. It
  merged during live review into a single always-editable surface: warnings at
  the top, a card per line, the read-only method fold below (rendering the same
  `Recipe` a save would write), Save at the bottom.
- **Band ≠ validity.** The match band (`auto`/`suggest`/`none`) only decides how
  a line *starts*. Whether it's **done** is recomputed by `line_validation.dart`:
  matched, any printed range has a picked number, and the unit is one the matched
  ingredient admits (ADR-0008 `allowed_units` + its measures + the always-admitted
  imprecise words). So an auto-matched line can still be flagged, and Save stays
  disabled until every line clears. `buildCommit` re-asserts this and throws —
  a partial import can never reach PowerSync.
- **A counted line with no printed unit is validated as `piece`**
  ([ADR-0015](../../../../docs/decisions/0015-piece-weight-is-a-row-fact.md)):
  "2 dragon fruit" meets the same admission gate as every other unit, clean on a
  row that admits `piece` (a `piece` default carrying a piece weight) and
  `unitNotAllowed` on one that does not. **Nothing enters a weight here** —
  what one of a thing weighs is the ingredient's property, and the fix for an
  unweighed row is its own form, opened from the chosen-ingredient row on the
  card, or another unit or measure chip.
- **A counted line lands on the row's whole measure**
  ([ADR-0016](../../../../docs/decisions/0016-a-measure-that-weighs-a-piece-is-its-word.md)):
  a printed `piece`, or a number with no unit word, on a row that carries a
  measure weighing what a piece weighs (`wholeMeasureOf`, within 1 %) becomes
  that measure's label at the moment the match resolves — `landOnWholeMeasure`,
  run over the payload as it arrives and again by the controller's
  `resolveLine` on a re-match, which takes the machine's earlier word back
  first. It is exactly a tapped chip: unflagged, printed as `1 lime, whole` in
  the amount slot, committed to the measure's id. A weighed row with no whole
  measure keeps `piece`; an unweighed row keeps the gate above; a unit somebody
  chose or a word the page printed is never overruled. The extraction still
  prints `piece` — the review decides — and the landing's reads are
  best-effort, so a local failure leaves the lines as they arrived and is
  named by the review's own check rather than by a lost import.
- **Never-invent is a UI obligation too.** Parse warnings, a degraded image, a
  truncated source, a printed range, and `raw_amount` are all *shown*. The source
  line sits under every open card ("from source: …") — from a photo you would
  otherwise have no way to check what the page said. It cuts both ways: a line
  the review MINTED has no source, and says so in that same slot — *added here
  — not on the page*.
- **A unit the matched row cannot carry empties the AMOUNT SLOT**
  (`amountSlotLabel`). "1 whole" or "1 can" in the slot reads as *filled*, which
  is the one thing the line is not: `whole` is no unit and a `can` on a row
  measured in `400 g can` is a word the picker could never hand back. The slot
  shows its unset state, the flag says "Pick a supported unit", and the source
  line rides the compact row too so the page's own words stay on screen either
  way. The parsed quantity stays on the resolution — the sheet opens on it and
  the inline unit chips write onto a line that keeps its number, so one tap
  still resolves it.
- **The STRUCTURE is the human's, the payload is the server's.** The review
  renames, deletes and adds sections, and can add a line the page never
  printed. None of it touches `ReconciliationPayload`, which stays the server's
  word about the page so `from source:` cannot start lying. It rides
  `ImportReconciling.sections` (`domain/review_groups.dart`) as a list of
  `(id, name, [flat line indexes])`, which `buildCommit` and
  `buildPreviewRecipe` both walk instead of the payload's groups.
  - **Deleting a heading never deletes its lines.** They move into the section
    above — into the one that becomes first, when the first goes — keeping
    their order and every resolution. Dropping food is what the line's own bin
    does, so the delete needs no confirm: nothing is lost. The last section
    standing loses its heading rather than being removed.
  - **A line MOVES by being dragged**, on the same flat list of heading rows
    and line rows the editor uses (`recipes/domain/line_reorder.dart`, wrapped
    here as `moveReviewLine`). Dropping a line under a heading files it there,
    so reordering and moving between sections are one gesture. **Order and
    identity stop being the same number**: a moved line keeps its flat INDEX —
    what resolutions are keyed by and what every step chip points at through
    `previewLineId` — and changes only its POSITION, which is what the commit
    walks and the repository writes as `sort_order`. A section emptied by a
    move keeps its heading (and, as ever, commits no group at all).
  - **A minted line's index is taken past the payload's last**, so nothing
    renumbers and every step chip already written keeps pointing where it did.
    `LineResolution.added` has no `raw` behind it; the card is handed a
    stand-in `ReconLine` carrying its name and nothing else. That is what
    opened the chip picker's *＋ Add an ingredient to this recipe* here.
- **A re-match carries its chips.** An identity change on a line (a re-match, a
  recipe link, an unlink — not a quantity, unit, measure or note edit) runs the
  editor's own `relabelRefs` over the method draft for `previewLineId(index)`.
  The controller keeps the returned `ChipRelabel`s and `Substitution` for the
  sitting, and `ImportMethodEditing` hands them to the shipped step cards, so
  *2 steps mentioned coriander* and *was "coriander" · keep the old word*
  appear here with no new UI. **A chip never names something the recipe does
  not contain** — that is the invariant, and the ref is untouched throughout.
- **Amount editing reuses the 7.7 sheet.** `showQuantityUnitSheet` is the single
  entry surface for quantities app-wide; reconciliation is just another caller,
  seeded from the raw line. A picked measure rides on the line as its **label**
  and is resolved back to an `ingredient_measure.id` at commit.
- **Stubs are created client-side, in the commit transaction**, keyed by a
  coalescing key so identical no-match lines share one new ingredient. The USDA
  enrichment leg is server-side and **now wired**: migrations `0014`/`0015` fire
  a trigger as the stub arrives (and on a later rename), copying density + macros
  from `usda_food` onto a bare stub — the row stays `stub` until a human confirms
  it in the ingredients manager. One gap left: this commit still writes
  `match_text` with the character-level normalizer rather than the phrase
  normalizer the ingredients feature ported (tracker).
- **A recipe is OFFERED, never auto-linked** (8.6 / D6, board frame e). The
  server may attach `recipe_candidates` to a line — household recipes whose
  *title* the line seems to name. The card renders them in the existing
  did-you-mean row ("↪ your recipe · Romesco Aioli"), **beside** the ingredient
  candidates, and nothing links itself at any score. Tapping makes the line a
  **component** line: `sub_recipe_id` set, no ingredient, no `measure_id`
  (migration 0017's XOR + measure fence). Its Save gate is its amount alone —
  no ingredient match, and **no `allowed_units` admission**, because admission
  is an ingredient concept; the unit meets the target's yield family later, at
  derive time (D2), which is why "¼ cup of a yield-less aioli" surfaces on the
  cook plan rather than here. Unlink (or match an ingredient) puts the line
  back; a line nobody taps commits byte-identically to before the field
  existed, which `line_resolution_test` pins against the gold specimens.
- **The header is the editor's** (plan 0025 #4, board frame b). The review
  holds a header draft `Recipe` (`domain/header_draft.dart`) from the moment
  the page arrives and renders the recipes feature's `RecipeHeaderForm` over
  it, with `ImportController` as its `RecipeHeaderHost` — title, serves, makes
  in both denominations, cook/total times, shelf life and filing, one widget
  shared with the editor so a section added there cannot miss the review.
  Prefill is attempt-then-flag over the whole header: servings and the times
  as printed, the yield **only** from a plain amount + unit (`parseYieldRaw`:
  "MAKES: 8 SLIDERS" → `8 piece`), shelf life unset, filed into the default
  book. What only the review knows rides the form's note slot — *not printed
  — set it* beside SERVES, *from source: …* under MAKES — and the source-notes
  strip sits above the form. Nothing in the header gates Save; `buildCommit`
  reads every column off the draft and the INSERT writes the same list the
  editor's save does (a structural test pins the two equal).
- **The title arrives cased like a title.** A photographed page shouts and a
  scraped one sometimes whispers; neither is a decision the page made about
  capitalisation. `titleCaseIfUncased` in the server's sanitizer
  (`supabase/functions/_shared/adapters/schema.ts`, beside `cap()`) title-cases
  a title carrying **no case of its own** — all upper, or all lower — with a
  small-word list left lower except at either end. A title that already carries
  mixed case is left exactly alone: the page that prints *PIZZA alla Norma*
  meant it. The words, their order and their punctuation are the page's
  throughout; casing is not inventing. Code, not a prompt line: a model
  instruction is a probabilistic fix for a deterministic problem, and it costs a
  re-scored eval every time it is tuned.
- **Writes are view-safe**: local PowerSync tables are SQLite views, so every
  statement is a plain INSERT — a view rejects `ON CONFLICT`.
- **Filing into the default book is load-bearing.** The Library renders books and
  skips book-less recipes, so a commit that left `book_id` null saved the recipe
  somewhere nothing showed it.

## The canned / offline fallback

`importRepositoryProvider` always commits through `SqliteImportRepository`. Only
the extract→match step varies:

| Supabase configured (`Env.isConfigured`) | `startImport` runs |
|---|---|
| yes | `EdgeImportRepository` — the real `import-recipe` edge function, auth-scoped (the signed-in user's token carries the `household_id` claim that scopes matching) |
| no — dev, offline, and **all tests** | `SqliteImportRepository.startImport` — the canned payload from `sample_payloads.dart` |

The canned path is not a stub that returns a fixture verbatim: it re-points the
fixture's placeholder candidate ids at whatever the **local vocab** actually
holds (exact canonical-name hit, else the same token-subset search the picker
uses), and degrades a line whose candidates all miss to `none`. So the offline
flow exercises real bands, real "did you mean" chips, and the real create-new
path — which is what makes it useful for tests and for driving the UI without a
backend.

## Tests

- Domain: `line_resolution_test` (incl. the sections riding the commit and a
  minted line's index), `line_validation_test`, `preview_recipe_test`,
  `review_groups_test` (a deleted heading loses no line; nothing renumbers; a
  moved line changes position and keeps its index),
  `yield_prefill_test` (the parser's whole table — the refusals especially).
- VM: `import_controller_test` (state machine, resolution edits, commit gate).
- Repo: `import_repository_test` on a **real `PowerSyncDatabase`** — the
  `line_index` → `line_item_id` remap (a minted index included), stub
  coalescing, `measure_id` resolution, default-book filing.
- Contract: `golden_payload_contract_test` parses the *server's* committed
  fixture (`supabase/functions/import-recipe/__fixtures__/…golden.json`), so a
  TS-side shape change fails on the Dart side too.
- Widget: `recon_line_card_test` (incl. the 8.6 offer → link → unlink path and
  the component quantity sheet), `recon_resolver_test` (the did-you-mean pills
  and the create-new chain), `recon_amount_test` (what the amount slot
  prints), `review_header_test` (the shared header on
  the review: notes strip above, the two host notes, prefill, the whole
  header riding the commit), `review_sections_test` (rename · delete · add a
  section · add a line, on the real screen), `import_method_editing_test`
  (a re-match relabels its chips, `keep the old word` puts one back, and the
  chip sheet's Word field KEEPS the chip it renames), `review_scroll_test`
  (the page does not jump to the title), `review_reorder_test` (a line dragged
  under another heading; an open card has no grip and closes when a drag
  starts). Intake seams: `photo_intake_test`.
- Seam: `test/features/recipes/recipe_header_form_test` renders every
  section of `kRecipeHeaderSections` under BOTH hosts and round-trips every
  setter; `test/structure/recipe_insert_columns_test` pins the import's and
  the editor's `INSERT INTO recipe` column lists equal.
