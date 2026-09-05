# Exec plan: import review — the line list becomes editable

- **Status:** built — fronts A–F land; A-D5 (drag) is plan 0035's, and the sim
  leg is still to run
- **Owner:** Simon (rulings) · agent lane (build)
- **Roadmap step:** 8.14 — field test, round five
- **Created:** 2026-09-04

## Goal

The review screen stops being read-only about **structure**. On a photo import
the cook can rename or delete a section, add a line the page forgot, and see
each card say what its line *is now* rather than what the page printed — and a
re-match carries its method chips with it instead of leaving them naming a food
the recipe no longer contains.

Done, in observable terms, on the wild-garlic page: delete a section heading;
add a line for something the page omitted; re-match `wild garlic` → `Kale` and
watch the method chip say *Kale* (revertibly); correct an amount without the
page scrolling back to the title; and a photographed `WILD GARLIC PASTA` title
arrives as `Wild Garlic Pasta`.

## What is true today

Read this before proposing anything — every line is checked against the code.

| Finding | Where |
|---|---|
| The review renders a group name as a plain `Text`. There is no rename, no delete, no add-section — the editor has all three (`setGroupName`, `removeGroup`, `addGroup`). | `app/lib/features/import/presentation/reconciliation_view.dart:88` vs `app/lib/features/recipes/presentation/recipe_editor_view.dart:151,259` |
| The review mints no lines *by design*: `canAddLine` is false and all three add-doors throw `UnsupportedError`, because `buildCommit` walks the payload's flat indexes and a new line has none. | `app/lib/features/import/presentation/import_method_editing.dart:250-300` |
| The **expanded** card heads with `line.raw.ingredientText` — the source text. The **collapsed** row heads with `resolution.chosenName ?? raw.ingredientText`. So opening a re-matched line shows the old words back. | `app/lib/features/import/presentation/recon_line_card.dart:405` vs `:141,232` |
| A chip's word never follows a re-match here: `relabels()` returns `const []` and `substitution()` returns null, on the argument that a re-match re-points by line index so no chip can be *orphaned*. True about the ref, silent about the word. | `app/lib/features/import/presentation/import_method_editing.dart:56-61` |
| The editor already has the machinery: `relabelRefs` rewrites every chip pointing at a line and returns each previous word, and the step card draws *was “sausage” · keep the old word*. | `app/lib/features/recipes/domain/method_draft.dart:497`, `app/lib/features/recipes/presentation/recipe_view_models.dart:342-392` |
| Typing over a chip's own characters deletes the chip: `applyEdit` keeps a span only when it lies wholly before or after the changed range. The word survives, the link does not, and nothing says so. | `app/lib/features/recipes/domain/method_draft.dart:353-360` |
| Nothing in the extraction contract says anything about title CASE. The transcriber copies the page ("same words"), the sanitizer caps the length and stores it verbatim. | `supabase/functions/_shared/prompts/extraction.ts`, `.../adapters/schema.ts:417` |

## Fronts

Every ruling below is settled.

### Front A — sections are editable

- **A-D1** Each group heading becomes a row: the name as an editable field
  (the editor's own `Group name (optional)` control) plus a `🗑`.
- **A-D2** **Ruled (owner, 2026-09-04): deleting a heading never deletes its
  lines.** They move into the group above it — the first group when it is the
  first — keeping their order and every resolution. Dropping food is what the
  per-line `🗑` already does; a delete that silently took four ingredients with
  it is not on offer. No confirm is needed for a delete that loses nothing.
- **A-D3** A `＋ section` at the end of the list, mirroring the editor. A new
  section starts empty and is filled by dragging lines into it (A-D5).
- **A-D4** Group edits ride the review state (`ImportReconciling`), not the
  payload: a `groupEdits` list of `(name, droppedInto)` keyed by the payload's
  group index, plus appended groups. `buildCommit` reads it, so the payload
  stays the server's word and the review's edits stay the human's.
- **A-D5** **A line moves by drag** — within its group and onto another
  heading, including a heading just added. The gesture, its handle and its
  drop behaviour are specified once in
  [plan 0035](./0035-line-ergonomics.md) and this screen is one of its two
  hosts; nothing about dragging is designed twice.

### Front B — a line can be added at review

- **B-D1** The line list gets the editor's one door: `showLineTargetPicker`
  (ingredients *and* "Your recipes"), then the quantity sheet, then a new
  line at the end of the group it was added from.
- **B-D2** A new line's index is minted past the payload's last flat index.
  This is the commit-contract change the backlog row named: `LineResolution`
  gains lines with no `raw`, `buildCommit` writes them like any other, and the
  never-renumber rule still holds (a dropped index simply stays unused).
- **B-D3** With B-D2 landed, `ImportMethodEditing.canAddLine` becomes true and
  the three `UnsupportedError` doors open — the method's chip picker gets its
  `＋ Add an ingredient to this recipe` for real, retiring
  [backlog: *A new line from the review's method editor*](../backlog.md).
- **B-D4** A review-minted line has no `from source:` line, and says so where
  the others print one: *added here — not on the page*. The honesty rule cuts
  both ways.

### Front C — the card says what the line is

- **C-D1** The expanded card heads with `resolution.chosenName ?? linkedRecipeTitle ?? raw.ingredientText` — the same rule the collapsed row already uses. The source text keeps its place in the `from source:` line directly under it, which is where the page's words belong.
- **C-D2** Widget test: re-match a line, expand it, assert the heading is the new name and that `from source:` still prints the old.

### Front D — a re-match carries its chips

- **D-D1** `ImportController` gains the editor's `_setIdentity` behaviour: on
  an identity change (not on a quantity, unit, measure or note edit), run
  `relabelRefs` over the method draft for `previewLineId(index)` and keep the
  returned `ChipRelabel`s and the `Substitution` for the sitting.
- **D-D2** `ImportMethodEditing.relabels()` / `substitution()` / `keepOldWord`
  stop being stubs and read that state, so the shipped banner — *was “wild
  garlic” · keep the old word* — appears at review with no new UI.
- **D-D3** **Ruled (owner, 2026-09-04): typing over a chip's word in the
  sentence deletes the chip, and that is fine** — a chip is a span; editing its
  characters really does end it. No notice, no undo, nothing to build.
- **D-D3b** **The real bug is the chip sheet's Word field**, and it is not the
  same thing: renaming an existing chip *there* deletes the chip and leaves the
  typed text as prose. The sanctioned rename path destroys what it renames.
  The mechanism, traced:
  1. the sheet's `onChanged` fires a cascade —
     `repointChip · renameChip · setChipAmountRule`
     (`method_editor.dart:429`);
  2. `renameChip` → `respan` rewrites the step's **text**
     (`method_draft.dart:421`);
  3. the card's `MethodSpanController.sync` assigns `value =
     TextEditingValue(text: next.text …)`
     (`method_span_controller.dart:34`), which notifies its listeners;
  4. Forui registers the field's `onChange` as **a plain controller listener**,
     so that assignment comes straight back as
     `notifier.editStep(step.id, v.text)`;
  5. `applyEdit` diffs the incoming text against the draft it can see and
     **drops every span overlapping the changed range**
     (`method_draft.dart:353-360`) — the chip, in other words. It survives only
     while the echo happens to arrive after the rename has landed in state; any
     ordering where it does not is exactly the reported bug.
  The class is already known here: `ImportMethodEditing._mapStep` carries a
  no-op guard with the comment *"a no-op edit must not re-enter state: it would
  round-trip forever"*. The guard is on the wrong side of the loop — it
  compares the resulting draft, which genuinely differs, rather than refusing
  the echo.
- **D-D3c** The fix is to close the loop, not to patch `applyEdit`: the
  controller knows it wrote that text itself, so `sync` suppresses the
  listener round-trip (a `_syncing` flag, or the host ignoring an `editStep`
  whose text is the text it last pushed). One place, both hosts.
- **D-D3d** The test that would have caught it, on both hosts: open the chip
  sheet on a chip, change the Word field, assert the span **still exists**, its
  refs are unchanged, and the sentence reads with the new word.
- **D-D4** Regression test: on the wild-garlic fixture, re-match line 0 and
  assert the chip's word changed, its refs did not, and `keepOldWord` puts the
  printed word back.

### Front E — the page stops jumping to the title

- **E-D1** Reproduce first: the review is one `ListView`; the title is an
  `FTextField` that keeps focus after `setTitle`, and the focused editable's
  scroll-into-view is the prime suspect once a sheet closes or the keyboard
  metrics change. The fix is only correct once a widget test fails without it.
- **E-D2** Expected shape: the review drops focus before opening any sheet
  (amount, identity, measures) and on a list scroll, so nothing off-screen is
  still asking to be shown.

### Front F — the title arrives cased like a title

**Ruled (owner, 2026-09-04): do it in code, not in the prompt.** A model
instruction is a probabilistic fix for a deterministic problem, and it costs a
re-scored eval every time it is tuned.

- **F-D1** One pure function, applied to the title **after** extraction
  returns, in the sanitizer beside the existing `cap()` — the single choke
  point every import passes through, URL and photo alike
  (`supabase/functions/_shared/adapters/schema.ts:417`).
- **F-D2** The rule, so it is testable rather than tasteful: a title with **no
  case information** — all upper, or all lower — is title-cased word by word,
  with a small-word list (`a an and as at but by for in of on or the to with`,
  plus `à la`) left lower except as the first or last word. A title that
  already carries mixed case is **left exactly alone** — the page that prints
  *PIZZA alla Norma* meant it.
- **F-D3** Nothing else is touched: the words, the order and the punctuation
  are the page's. Casing is not inventing.
- **F-D4** Vectors in the TS test: `WILD GARLIC PASTA` → `Wild Garlic Pasta`,
  `wild garlic pasta` → `Wild Garlic Pasta`, `SOUP OF THE DAY` → `Soup of the
  Day`, `PIZZA alla Norma` → unchanged, `mac & cheese` → `Mac & Cheese`.
- **F-D5** Gold/fixture check: `golden_payload_contract_test` and the TS golden
  keep parsing; any fixture title that changes case is re-committed with the
  new value rather than special-cased.

## Acceptance criteria

- [x] A section can be renamed, added, and deleted **without losing a line**.
- [x] A line can be added at review, commits with a real `line_item_id`, and is
      chippable from the method — the backlog row retires.
- [x] An expanded card heads with the line's current identity; `from source:`
      still shows the page's words.
- [x] A re-match relabels its chips and offers *keep the old word*.
- [x] **Renaming a chip in the chip sheet keeps the chip** — asserted on both
      hosts (D-D3d). Typing over a chip in the sentence still deletes it, by
      design.
- [x] Correcting a line after editing the title does not scroll the page.
- [x] A shouted or lower-cased title arrives title-cased from the function; a
      mixed-case title is untouched (F-D4's vectors, in the TS test).
- [x] Tests: `line_resolution_test` (sections + minted lines in `buildCommit`),
      `review_groups_test` (the pure section rules), `import_repository_test`
      (a minted line's insert and its `line_index` remap), `recon_line_card_test`
      (C-D2), `review_sections_test` (A and B on the real screen),
      `import_method_editing_test` (D-D4 and D-D3d), `review_scroll_test`
      (E's repro), and the casing vectors in `schema.test.ts`. The sim leg in
      `test_sim/import_test.dart` is still to write.
- [x] Docs: `app/lib/features/import/README.md` (the claim that the review can
      never mint a line is gone; the sections, the relabel and the casing are
      described), the board's `import-review.html` (both proposed frames are
      built now, with a `differs:` line for 0035's drag grip). The extraction
      *contract* did not change for F-D1 — the casing is a sanitizer pass over
      the same field — so `import-and-matching.md` needs nothing.

## Approach

1. Front C, then E — one-liner and one bug, both in the way of everything else.
2. Front D — pure wiring of shipped machinery; no contract change.
3. Front A — state shape first (`groupEdits`), then the UI.
4. Front B — the commit contract, tested at the repository before any UI.
5. Front F — prompt + fallback, last, because it needs a live import to judge.

## Decision log

- 2026-09-04 — Filed from the owner's round-five field notes. Six of the
  fifteen notes are this screen.
- 2026-09-04 — Owner rulings: **A-D2** a deleted heading keeps its lines;
  **A-D3/A-D5** new headings are addable and lines are **dragged** between
  them; **F** is a code-side casing pass, not a prompt rule.
- 2026-09-04 — **D-D3 corrected by the owner.** Typing over a chip in the
  sentence is fine as it is; the bug is the chip sheet's own Word field, which
  deletes the chip it renames. Traced to the controller-echo loop in D-D3b —
  a different defect, on a path that is supposed to be safe, and now the
  highest-value item in this plan.
- 2026-09-04 — **D-D3b's mechanism confirmed, and it has a second half the
  trace did not name.** The echo loop is exactly as written, and it fires on
  the REVIEW host only: the editor's `RecipeEditor.methodDraft()` re-derives
  from `_current.methodSteps`, which the rename has already updated by the
  time the echo arrives, so `applyEdit` sees identical text and the guard in
  `_mapStep` swallows it. `ImportMethodEditing` captured its `ImportReconciling`
  at build time, so the echo diffed against a draft the rename was *not* in and
  `applyEdit` dropped the span. Both halves are fixed: `MethodSpanController`
  exposes `isSyncing` and the card refuses an `onChange` raised inside `sync`
  (D-D3c, one place, both hosts), and the review host now reads
  `controller.reconciling()` rather than the state it captured — which also
  stops the chip sheet's `repointChip · renameChip · setChipAmountRule` cascade
  from having each call start from the draft before the previous one.
  `applyEdit` is untouched, and typing over a chip in the sentence still ends
  it.
- 2026-09-04 — **Front E reproduced before it was fixed, and the mechanism is
  the one E-D1 suspected.** A failing widget test (`review_scroll_test`) types
  the title, drags the list to 400, then moves the view insets: the list snapped
  back to 19 — the title caret's offset. Two halves, each pinned by its own
  failing test: `showAnsiSheet` drops focus (a sheet takes the screen, so the
  field behind it stops asking to be shown — one door, every caller), and the
  review's `ListView` takes `keyboardDismissBehavior: onDrag`. Removing either
  one puts the jump back.
- 2026-09-04 — **A-D4's shape, decided in the build.** A `groupEdits` diff keyed
  by payload group index turned out to need a second concept the moment front B
  landed (where does a minted line file?), so the review holds the whole
  section list instead: `ReviewGroup(id, name, [flat line indexes])` in
  `domain/review_groups.dart`, with `buildCommit` and `buildPreviewRecipe`
  taking it as an optional argument that defaults to the payload's own groups.
  Same rule — the payload is never edited — one concept rather than two, and an
  untouched import commits byte-identically.
- 2026-09-04 — **A-D2's edge case.** The last section standing cannot be
  removed, because its lines would have nowhere to go; it loses its heading
  instead, which is all the reader asked for. A single UNNAMED section shows no
  heading row at all — an empty field over the first line is furniture — and
  `＋ section` is the way out of it.
- 2026-09-04 — **F's known limit, stated rather than invented.** The rule is
  word by word over whitespace, so a shouted `SLOW-COOKED BEEF` arrives as
  *Slow-cooked Beef*. Capitalising after a hyphen was not ruled on, and
  inventing it here is exactly the accretion this plan is trying to avoid; if it
  matters it is a one-line change and a sixth vector.
- 2026-09-04 — **F-D5 cost one fixture.** `index_vocab.test.ts` asserted the
  gold's title passes through unchanged, and that gold (`gumbo z'fungi`) is all
  lower-case. The assertion now names the sanitizer's own function and adds a
  case-insensitive equality beside it, which is the property that actually
  matters: the words, the order and the punctuation are the page's. The
  committed golden payload's title is mixed-case and is untouched.

## Notes / open questions

- Front B is the only front that changes what a commit may contain. Everything
  else is client-side and reversible.
- The tracker's `import/ui` polish-remainder row (measure-chip fold, the duped
  source line, raw-line amounts) is *not* in this plan; it stays a debt row
  until it is worth a pass of its own.

## Step-done checklist

- [ ] Roadmap row updated.
- [ ] `ARCHITECTURE.md` standing table matches for `features/import`.
- [ ] `app/AGENTS.md` current focus still true.
- [ ] `make test-sim` on a booted simulator, result recorded here.
- [ ] Tech-debt rows added for corners cut; the backlog row retired.
- [ ] No migration expected — say so explicitly in the roadmap row.
- [ ] `make ci` green.
