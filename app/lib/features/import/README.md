# Feature: import

Paste a recipe URL or photograph a page; the server extracts and matches; you
review the result on one editable screen; Save writes a real recipe with chipped
method steps. **The client never matches** — extraction and the match cascade
are the `import-recipe` edge function
([ADR-0004](../../../../docs/decisions/0004-matching-is-online-only.md)). This
feature sends the source, renders the answer, and owns the human decisions and
the commit. Behaviour is specified in
[import-and-matching.md](../../../../docs/product-specs/import-and-matching.md).

## The flow

```
ImportView (intake)          paste a URL · shoot or pick photos, crop each
      ▼  ImportController.startImport(ImportSource)
ImportRepository.startImport POST import-recipe {url} | {images}
      ▼
ReconciliationPayload        title · servings · times · warnings
                             groups[ lines[ raw, band, candidates ] ]
                             steps[ tokens ] — refs by FLATTENED LINE INDEX
      ▼
ReconciliationBody           one card per line; validity gates Save;
                             sections are the human's (review_groups.dart)
      ▼  ImportController.commit() → buildCommit(...)
SqliteImportRepository.commit — ONE local transaction:
  recipe (default book) · ingredient_group · recipe_line_item
  · correction aliases · step refs remapped line_index → line_item_id
```

## Files

```
import/
  domain/         PURE DART (no package:flutter)
    reconciliation_payload.dart  the server contract, mirrored
    commit_payload.dart          what the commit writes
    line_resolution.dart         one line's decision, buildCommit,
                                 landOnWholeMeasure
    line_validation.dart         per-line issues and the Save gate
    review_groups.dart           the review's sections, over flat line indexes
    work_queue.dart              outstanding lines grouped by what each wants
    amount_text.dart             what the amount slot may say
    learnable_alias.dart         which corrected phrases may become an alias
    preview_recipe.dart          payload → the Recipe the method renders
    method_draft_bridge.dart     method drafts ↔ the payload's line indexes
    header_draft.dart            payload → the header draft the form edits
    yield_prefill.dart           yield_raw → the MAKES prefill (parseYieldRaw)
    import_stage.dart            the reading stages and their wording
    import_repository.dart       ImportRepository + ImportSource
  data/
    import_repository_impl.dart   SqliteImportRepository — the commit
    remote_import_repository.dart EdgeImportRepository — the edge function
    sse.dart                      the text/event-stream reader
    sample_payloads.dart          the canned payload (below)
    photo_intake.dart             shoot/pick → crop → "another page?"
    import_providers.dart         importRepositoryProvider (keepAlive)
  presentation/
    import_view.dart             intake
    photo_doors.dart             the two photo doors (shared with receipts)
    import_stage_rows.dart       the reading checklist (shared with receipts)
    reconciliation_view.dart     the review screen
    wide_review_view.dart        the review at ≥ 1024: page · lines · open card
    recon_line_card.dart         a line's card, in the shared LineCard
    recon_amount.dart            the amount label and its sheets
    recon_resolver.dart          the identity cell and the seeded search sheet
    import_view_models.dart      ImportController and the ImportState machine
    import_method_editing.dart   the step cards' host over the review's draft
```

## Rules

- **Band ≠ validity.** The match band (`auto`/`suggest`/`none`) only decides
  how a line starts. `line_validation.dart` decides whether it is done:
  matched, any printed range resolved, and a unit the ingredient admits
  ([ADR-0008](../../../../docs/decisions/0008-unit-admission-model.md)).
  Save stays disabled until every line clears, and `buildCommit` re-asserts it
  and throws.
- **A counted line with no unit is validated as `piece`**
  ([ADR-0015](../../../../docs/decisions/0015-piece-weight-is-a-row-fact.md)).
  Nothing enters a piece weight here; the fix is the ingredient's own form.
- **A counted line lands on the row's whole measure**
  ([ADR-0016](../../../../docs/decisions/0016-a-measure-that-weighs-a-piece-is-its-word.md)):
  `landOnWholeMeasure` runs as the payload arrives and again on a re-match. A
  unit somebody chose, or a word the page printed, is never overruled.
- **Never-invent is a UI obligation.** Warnings, a printed range and
  `raw_amount` are shown; the source line sits under every open card, and a
  line the review added says *added here — not on the page*.
- **A unit the row cannot carry empties the amount slot** (`amountSlotLabel`)
  and flags the line; the parsed quantity is kept, so one chip tap resolves it.
- **The structure is the human's; the payload is the server's.** Sections ride
  `ImportReconciling.sections` as `(id, name, [flat line indexes])`, and
  `buildCommit` and `buildPreviewRecipe` walk those. Deleting a heading moves
  its lines up. A dragged line (`moveReviewLine`) changes position and keeps
  its index, which resolutions and step chips are keyed by. An added line's
  index is taken past the payload's last, so nothing renumbers.
- **A re-match carries its chips.** An identity change runs the editor's
  `relabelRefs` over the method draft, and the step cards show the relabel and
  *keep the old word*.
- **A recipe is offered, never auto-linked.** `recipe_candidates` render beside
  the ingredient candidates. Tapping one makes a component line
  (`sub_recipe_id`, no ingredient, no `measure_id`), gated on its amount alone.
- **The commit creates no ingredient.** *Create new* runs the ingredient form
  before the line resolves. Correction aliases are written through
  `normalizeMatchText`, and only for phrases `learnable_alias.dart` admits.
- **The header is the editor's.** The review renders the recipes feature's
  `RecipeHeaderForm` with `ImportController` as its `RecipeHeaderHost`. Prefill
  is attempt-then-flag; nothing in the header gates Save.
  `test/structure/recipe_insert_columns_test` pins the import's and the
  editor's `INSERT INTO recipe` column lists equal.
- **The reading checklist is the server's.** The function answers as
  `text/event-stream` and names each stage as it completes. The ids are the
  wire contract; the wording is in `import_stage.dart`. The arithmetic
  (`stageChecklist`, `PipelineStage`) and the rows are shared with receipts.
- **Title casing is server code, not a prompt** (`titleCaseIfUncased` in
  `supabase/functions/_shared/adapters/schema.ts`): only a title with no case
  of its own is changed.

## Traps

- **Writes are view-safe.** Local PowerSync tables are views, so every
  statement is a plain INSERT — a view rejects `ON CONFLICT`.
- **Filing into the default book is load-bearing.** The Library skips book-less
  recipes, so a null `book_id` saves a recipe nothing shows.

## The canned fallback

`importRepositoryProvider` always commits through `SqliteImportRepository`;
only `startImport` varies. With Supabase configured (`Env.isConfigured`) it is
`EdgeImportRepository`. Otherwise — dev, offline and all tests — it is the
canned payload from `sample_payloads.dart`, whose placeholder candidate ids are
re-pointed at the local vocabulary (a line whose candidates all miss degrades
to `none`), so bands, did-you-mean chips and create-new all run for real.

## Tests

`test/features/import/` mirrors the files above. Two are contracts:
`golden_payload_contract_test` parses the server's committed fixture
(`supabase/functions/import-recipe/__fixtures__/`), so a TS shape change fails
in Dart; `import_repository_test` runs the commit on a real `PowerSyncDatabase`.
