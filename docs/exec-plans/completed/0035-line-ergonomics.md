# Exec plan: line ergonomics — reorder and move, on both line lists

- **Status:** built on both screens; the sim leg is outstanding
- **Owner:** Simon (rulings) · agent lane (build)
- **Roadmap step:** 8.14 — field test, round five
- **Created:** 2026-09-04

## Goal

An ingredient line can be moved — within its group and between groups — on the
**recipe editor** and on the **import review**, without deleting and re-adding
it. Done means: on a fresh import whose extractor mis-ordered two lines, and on
a saved recipe, the cook can put the list in the order the recipe reads, and
every method chip still points where it did.

## What is true today

- Nothing anywhere reorders a line. The only fix is delete + re-add, which also
  re-points every chip that referenced it — the cost the backlog row named.
- The storage is ready: `recipe_line_item.sort_order` exists
  (`app/lib/core/sync/schema.dart:82`) and `saveRecipe` already persists a
  changed `group_id`, so moving a line between groups needs no migration.
- **Drag is buildable without Material.** `ReorderableList`,
  `SliverReorderableList` and `ReorderableDragStartListener` are exported from
  `package:flutter/widgets.dart` (verified in the pinned SDK:
  `packages/flutter/lib/widgets.dart:116`). Only `ReorderableListView` — the
  styled one — is Material, and it is not what this uses. The Forui-only rule
  holds.
- The backlog row said **buttons, not drag**. The owner has ruled the other
  way; this plan supersedes that line, and the row's reasoning is answered in
  A-D4 rather than ignored.

## Fronts

Every ruling below is settled.

### Front A — drag to reorder

- **A-D1** **Drag, ruled by the owner.** One flat reorderable list per recipe:
  group headings are items in it too, so a line dragged under a heading is
  filed under that heading — that is how "move to a section" and "reorder"
  become **one gesture** rather than two features.
- **A-D2** The handle is explicit — a grip glyph on the line, not
  long-press-anywhere. A list of tappable rows that also opens on hold is how
  a scroll becomes an accidental move.
- **A-D3** Headings do not drag in v1. Reordering *sections* is a second
  question (and the editor has no such control today either); a line moving
  between them is what was asked for.
- **A-D4** The backlog row's objection was that a drag target inside a
  scrolling list of **expandable cards** is a fight. So: a card that is open
  does not drag — the grip appears on collapsed rows only, and an open card
  collapses when a drag starts elsewhere. That keeps the drag surface a list of
  uniform rows, which is the shape drag is good at.
- **A-D5** Persistence is the existing save: `sort_order` from list position,
  `group_id` from the heading above. No new write path, no migration.

### Front B — what a move must not break

- **B-D1** A moved line keeps its id, so every method chip that pointed at it
  still does. Pinned by a test, because this is the whole reason the feature is
  worth building.
- **B-D2** An empty group left behind is kept, not swept: the heading is the
  human's, and a section that empties while you rearrange is not a bug to fix
  behind them. Deleting it is A-D1's `🗑` in
  [plan 0034](./0034-import-review-editable.md).
- **B-D3** **Ruled (owner, 2026-09-04): drag is the whole path.** No *Move to
  section…* on the `⋯`, no ▲▼. One gesture, one affordance, nothing to keep in
  sync. (If a two-person household ever needs a non-drag path, it is one menu
  row away — but it is not built on speculation.)

### Front D — one line layout, on every surface

**Ruled (owner, 2026-09-04):** *"on the recipe editor it's ingredient — unit,
we should pick one layout."* The two surfaces disagree today, and the drag
list needs uniform rows anyway.

- **D-D1** The editor stacks its line — identity on top, then *used in N
  steps*, then the amount control below
  (`recipe_editor_view.dart:380-402`). The review card and the recipe page
  print the **three-part inline line**: amount · identity · note
  (`line_display.dart`, the review's `l3` row).
- **D-D2** **The inline line wins**, because it is what the recipe page — the
  screen a cook actually reads — already prints, and it is the one both other
  surfaces share. The editor adopts it: `[amount] [name] [note]` on one line,
  the amount cell opening the quantity sheet and the name cell opening the
  identity picker, exactly the two doors it has now.
- **D-D3** *used in N steps* moves to a second muted line under the name, and
  only when N > 0 — it is a fact about the line, not a control.
- **D-D4** The payoff is structural, not cosmetic: uniform single-line rows are
  the shape drag is good at (A-D4), and the editor stops teaching a layout the
  rest of the app contradicts.

### Front C — the same on the review

- **C-D1** The review's line cards get the same list over the review's own
  state (a `LineResolution` order, not the payload's), and `buildCommit` writes
  `sort_order` from that order rather than from the flat index.
- **C-D2** The never-renumber rule is unchanged: a moved line keeps its
  **index** (its identity for chips and refs) and changes only its position.
  Order and identity stop being the same number — the one structural change in
  this plan, and the thing to test hardest.

## Acceptance criteria

- [x] A line can be dragged to a new position inside its group, on both screens.
- [x] A line can be dragged under another heading — including one just added at
      review — keeping its id.
- [x] Nothing Material is imported: the drag comes from `package:flutter/widgets.dart`.
- [x] The editor's line renders as the inline three-part line, matching the
      review and the recipe page — one layout, asserted by a shared widget test.
- [x] Method chips survive both moves — asserted, not assumed.
- [x] `sort_order` round-trips: reopen the recipe and the order is what was left.
- [x] Tests: `line_reorder_test` (the shared rule), `recipe_line_move_test`
      (editor moves + the drag itself), `line_layout_test` (one layout, both
      surfaces), `review_groups_test` + `line_resolution_test` +
      `review_reorder_test` (review moves, C-D2's index/position split),
      `recipe_repository_test` (sort_order persistence).
- [ ] A sim leg that reorders and re-reads (the orchestrator schedules the one
      simulator).
- [x] Docs: `recipe-editor.html` and `import-review.html` re-drawn;
      `app/lib/features/recipes/README.md` and `.../import/README.md`.

## Approach

1. Editor first (Fronts A and B) — it owns the save path and the chip rules,
   and it is where the drag surface is proved.
2. Review second (Front C), hosting the same list widget; the index/position
   split is designed and tested before the UI is wired.

## Decision log

- 2026-09-04 — Filed from the owner's round-five note ("Both import and edit,
  can't reorder ingredients"), promoting the backlog row that predicted it.
- 2026-09-04 — Owner: **"prefer drag"**. The backlog row's *buttons, not drag*
  is superseded; its objection is answered by A-D4 (a grip on collapsed rows
  only) rather than dropped. Reorder and *move to a section* collapse into one
  gesture, which is also what [plan 0034](./0034-import-review-editable.md)
  A-D5 needs for a newly added heading.
- 2026-09-04 — Built. **One rule, two surfaces**: the move is
  `features/recipes/domain/line_reorder.dart`, written over `List<List<T>>` so
  the editor's `LineItem`s and the review's flat indexes drag by the same
  arithmetic — a rule one screen could learn without the other is the shape
  this feature must not take. `review_groups.moveReviewLine` is the review's
  one-line wrapper over it.
- 2026-09-04 — Both screens became a `CustomScrollView`: leading `SliverList`,
  one `SliverReorderableList` for the ingredient list, trailing `SliverList`.
  `SliverList` rather than `SliverToBoxAdapter` deliberately — a box adapter
  builds its whole subtree the moment the sliver is reached, which would build
  every step card to show the top of the page (and did, until a scroll-to-Save
  test found it).
- 2026-09-04 — `onReorderItem`, not `onReorder`: the newer callback hands back
  an index already adjusted for the removed row, so no caller carries the
  `if (newIndex > oldIndex) newIndex -= 1` folklore. `onReorder` is deprecated
  in the pinned SDK.
- 2026-09-04 — **The editor's group card became a heading row.** Front A asks
  for one flat list, and a bordered card per group is not a row in one. Every
  door it held survives: the name field and `🗑` are the heading; *Add
  ingredient* and *Add group* are two doors under the list, exactly the review's
  pair, and a line added lands in the last group for the drag to place.
- 2026-09-04 — A-D4 needed the review card's expansion state to be reachable
  from the list. It stays the card's own (`useState`), with the list passing a
  `collapseEpoch` it bumps on `onReorderStart` — one integer rather than
  hoisting every card's state onto the screen, and the card still opens and
  closes on its own everywhere else.
- 2026-09-04 — C-D1 wanted `buildCommit` to write `sort_order` from position
  rather than the flat index. It already did: the repository counts down
  `group.lines`, so the section's ORDER was always what landed. What was
  missing was anything that could change that order — which is what
  `moveReviewLine` now is. The commit code needed no change, and the test that
  proves the split (`a MOVED line commits at its new position, carrying its old
  index`) is the whole of C-D2.
- 2026-09-05 — The simulator leg ran over the merged round and found a **real
  clipping bug no widget test could see**: the method card's *was "…" · keep
  the old word* notice (`_KeepTheOldWord`) is a `Row` whose old word carried no
  flex, so a genuine page's *"the sauce and cheese"* overflowed it by 4.7px and
  pushed the revert off the card. The word now yields and ellipsizes while the
  action keeps its width — which is what the board had drawn all along. It
  surfaced only here because the notice reaches the review's narrower card, and
  because a host test renders in a square test font whose metrics are not the
  device's.
- 2026-09-05 — Two smoke expectations changed because **behaviour changed, not
  because a test was loosened**; both now assert the new rule by name. The
  editor's `＋ ingredient → onion` lands on the row's stated default measure
  (`onion, medium`) rather than a bare `piece`, so the assertion reads that
  measure's label instead of expecting no measure at all. And a COUNT line's
  amount cell prints the recipe page's bare number (`1`, never `1 piece`) —
  D-D2 arriving on the editor. The cell gained a `Semantics(label: 'Amount')`
  with it: a bare digit is not an accessible name, and it is the handle the
  smoke now finds the door by.
- 2026-09-05 — The same runs exposed **two latent sync races in the smoke
  harness** — nobody's feature and everybody's problem. Both are the same
  mistake: driving the app before the household has finished arriving.
  - **auth** waited for *Our Cookbook* and then asserted on synced rows, but
    that book is a LOCAL write the session controller makes, so the Library
    renders before one row has come down. It now waits for the rows, then says
    what they must be; the waits ask only whether the table is populated, so
    which members, in which order and how much vocabulary stay the
    assertions' claims.
  - **the review's search** (`searchAndPickForLine`) typed a query and
    asserted on the first frame. The picker reads the local vocabulary, still
    syncing down on a cold household — and waiting alone would not help,
    because a search that has already answered is not re-run by rows landing
    after it. It now asks again, a bounded number of times; the assertion
    itself is untouched.
- 2026-09-05 — **There was no rebuild loop; the slowness is the machine.** One
  `FILE=wild_garlic` run took 18:00 and the very next identical
  `FILE=wild_garlic` run took 0:30 — like for like, the same single file — and
  over the full suite the lost minutes land on a different file each time
  (`auth` in one run, `ingredients` in the next, both passing). Nothing in
  `lib/` repeats an animation, the sync-health tick is 20 seconds, and the slow
  run carried *less* sync traffic than the fast one. Orphaned processes on the
  host (two `flutter_test`ers about four days old and a `dartvm` about five)
  are the likely thief. If a run of this suite ever crawls, suspect the machine
  before the widget tree.

## Notes / open questions

- Nothing is open. Front D arrived with the drag ruling and belongs here: the
  same rows, in one shape.

## Step-done checklist

- [ ] Roadmap row updated.
- [ ] `ARCHITECTURE.md` standing table matches for `features/recipes` + `import`.
- [ ] `app/AGENTS.md` current focus still true.
- [x] `make test-sim` over the merged round: **9 tests, 7 files, all green**
      (13:41), after the overflow fix, the two changed-behaviour
      expectations and the two harness sync races above.
- [ ] Backlog row retired; tech-debt rows added for anything cut.
- [ ] No migration — say so in the roadmap row.
- [ ] `make ci` green.
