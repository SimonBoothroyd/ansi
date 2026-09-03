# Exec plan: Library · v3 — the menus dissolve

- **Status:** active
- **Owner:** Simon (board signed off 2026-09-03)
- **Roadmap step:** 8.12 — Library v3
- **Created:** 2026-09-03

## Goal

The Library header becomes a search field and one link. Creation moves onto the
rows that already carry controls, filed all the way from the tap. Every
duplicate door found on the way is deleted rather than relocated. Board section:
**"Library · v3"** (locked 2026-09-03), decisions E1–E9.

Observable when done: no popover menu exists in the Library header; an expanded
book card has no dashed rows; `book_reorder_sheet.dart` is gone; a recipe made
from a section's `＋` opens already filed into that section; a recipe can be
re-shelved without entering the editor; `/account` exists.

**Zero migrations.** Nothing in this plan touches the schema.

## Acceptance criteria

- [ ] E1 — Library header is the pinned search field plus one `FLucideIcons.users`
      control that **navigates** to `/account`. No screen name, no `＋`, no `⋯`.
- [ ] E2 — every section label (including the synthetic `Unsectioned`) carries a
      `＋` opening New recipe · Import a recipe; both carry
      `?book=…&section=…` and the editor seeds its filing from them.
- [ ] E3 — the dashed `＋ new section` row is gone (the book `⋯` already has it).
- [ ] E4 — `book_reorder_sheet.dart` deleted, "Reorder books" gone, the
      `books.length >= 2` conditional gone. Book order still changes from the
      book `⋯`'s Move up / Move down.
- [ ] E5 — Ingredients renders as a card at the end of the library
      (`308 ingredients · 3 stubs`, `›`); the stub **dot** is deleted.
- [x] E6 — `/account` route: household members + usual portions (today's sheet),
      sync health's quiet line, Sign out with its confirm.
- [ ] E7 — the dashed `＋ new book` footer row exists at last.
- [ ] E8 — a `⋯` on the recipe row with **Move to…** and the favourite toggle;
      re-filing writes through a narrow `setFiling(id, bookId, sectionId)`,
      never `saveRecipe`. The target sheet says what it will do before it acts.
- [ ] E9 — the editor's FILE UNDER is one breadcrumb line (`BOOK · SECTION`,
      `change ›`) opening the shipped picker.
- [ ] Every test that drives a removed affordance is moved **by the slice that
      removes it** — see "Test moves", below. No slice lands red.
- [ ] Tests cover the new logic (the narrow write, the query-param seeding, the
      filing shown on the editor line).
- [ ] Docs updated: `docs/QUALITY.md` (books, recipes), `product-spec.md`
      Library section rewritten to v3, board tag flipped to `shipped`.
- [ ] `make test-sim` on a booted simulator for **all three affected files** —
      `library`, `week` (the usual-portion leg reaches Household through the
      header) and `ingredients` (its whole entry path is that menu) — one
      simulator, serially; results recorded here.
- [ ] `make ci` green.

## Approach

**Order changed 2026-09-03:** lane D goes first (see below), then A, then B/C.
Lane A owns `library_view.dart` and must land before B/C touch it.

1. **Lane A — the Library screen** (E1, E2, E3, E5, E7 + the deletions).
   Slices, each its own commit: header (field + `users` link, `_AddMenu` and
   `_OverflowMenu` deleted, `book_reorder_sheet.dart` deleted) → the section
   `＋` and its two doors with query params → the dashed rows (section row out,
   new-book row in) → the Ingredients card and the dot's deletion.
2. **Lane B — the editor seam** (E9 + reading `?book=&section=`). Depends on A
   only for the query-parameter contract, which lands in A's second slice.
3. **Lane C — Move to…** (E8). `setFiling` on `RecipeRepository` beside
   `setFavorite`, the row `⋯`, the target sheet, the announced sentence. The
   refusal grammar is `moveBookContents`' in the singular.
4. **Lane D — `/account`** (E6). ✅ **Landed 2026-09-03** (`b6b1248`) — and
   moved to the FRONT of the order, not the back: building it first gives the
   header link a real destination on day one, so `week_test`'s usual-portion
   leg moves once instead of twice and no interim sheet is needed. The sheet
   became `HouseholdSection`; the `⋯` lost Sign out and the sync line and its
   Household item became `Account`. 1688 host tests green.
5. **Close-out** — sim legs, spec rewrite, QUALITY grades, board tag, tracker.

Traps (memory): ff-merge main first; copy `.env.local` into the worktree; sims
are the orchestrator's at landing, one simulator, serially.

### Test moves — owned by the slice, not by close-out

A slice that deletes an affordance updates every test that drives it **in the
same commit**. Three of these live outside `library_test.dart`, so "the library
sim covers it" is not true:

| What the slice removes | Test that drives it today | Moves to |
|---|---|---|
| the header `⋯` | `integration_test/support/library.dart` — `openLibraryMenu()` taps `ellipsis.first` | the helper is replaced by `openAccount()` (the `users` glyph); `openBookMenu` is untouched |
| the header `⋯` ▸ Household | `week_test.dart:528` (usual-portion leg, plan 0027 P-D3) | ✅ once, in lane D: `Account` → the page, backing out instead of closing a sheet |
| the header `⋯` ▸ Ingredients | `ingredients_test.dart:200-211` | the Ingredients **card** at the end of the library |
| "Reorder books" + its sheet | `library_test.dart:150-154`; host `library_view_test.dart:265-282, 329` | the book `⋯` ▸ Move up; the two presence/absence tests delete with the conditional |
| the `⋯` contents + Sign out | host `library_view_test.dart:190-205, 906` | rewritten against the header's one link, then against `/account` in lane D |

New coverage each lane owes: section `＋` → the editor opens filed (A/B),
`setFiling` and the announced move (C), `/account`'s three sections (D). The
structural `no_bare_repo_write_test` already forces `setFiling` through
`ref.write` — it should stay green by construction, not be amended.

## Decision log

Append-only.

- 2026-09-03 — **E8: a `⋯` on the recipe row, not a long-press** (owner). This
  amends v2 D6, which kept the row a single tap target. Mitigation kept from
  D6: the ★ still only *reports* on the row; the toggle lives in the menu.
- 2026-09-03 — **E2: the dashed add/import chips leave the populated card**
  (owner). With a `＋` on every section label the pair is a shallower second
  way to do the same thing. The chips are not deleted — they stay what they
  already are, the empty shelf's doors (v2 D7·2).
- 2026-09-03 — **New recipe / Import are NOT added to the book `⋯`.** A first
  draft put them there for the all-sectioned book (which renders no
  `Unsectioned` label). Rejected: permanent duplication to serve an edge case
  that E9's `change ›` answers in one tap.
- 2026-09-03 — **"Reorder books" is deleted, not relocated.**
  `_BookReorderSheet.move()` and `_BookMenu._move()` are the same
  splice-and-`reorderBooks`; the capability never leaves.
- 2026-09-03 — **The account door is a link, not a menu** (reversal). An
  identity control had been rejected as "the seed of the next catch-all"; that
  risk belongs to popovers, not to controls that navigate — the pressure to add
  lands on the page, which can take it. Drawn with `FLucideIcons.users`, the
  glyph the shipped `⋯` already uses for Household: a monogram would need
  teaching and this app has no avatars to teach it.
- 2026-09-03 — **`/account` is a pushed page, not a fifth tab.** The four tabs
  are a loop (find · plan · cook · buy), not an index of screens; a monthly act
  does not buy thumb-level space on every screen.
- 2026-09-03 — **Ingredients is a shelf, not a footer row** (reversal). The
  shipped `shopping_list_entry` already carries `ingredient_id` beside
  `free_text` under an XOR check, so the vocabulary is *already* something you
  plan with. A card, not a hairline row — and not a floating pill, which is the
  permanent incompleteness nag v2 D6 refused on browsing rows.

## Notes / open questions

- **Deferred, deliberately (owner, 2026-09-03):** a plan slot taking a **recipe
  OR an ingredient** — most likely one `snacks` slot rather than new slot types.
  `plan_entry.recipe_id` is `not null` today, so it needs a migration; the
  precedent is `shopping_list_entry`'s XOR check. **Not in this plan**, and the
  reason E5 files the vocabulary as a first-class shelf now: the placement must
  not have to move when this lands.
- Tracker row to add: surface the stub queue **at its source** (the import that
  created the ingredients) and at the macro lens, rather than as a global count
  — which would retire the count entirely.
- Tracker row to narrow: "reorder is menu-based, not drag" now has one path
  instead of two. Books and sections still convert together when Forui exposes
  a drag handle.

## Step-done checklist

- [ ] Roadmap row updated (8.12), naming what shipped and what was deferred.
- [ ] `docs/QUALITY.md` grades for books and recipes match reality.
- [ ] `app/AGENTS.md` "Current focus" still true.
- [ ] `make test-sim` run on a booted simulator; result recorded above.
- [ ] Tech-debt rows added for corners cut, retired/narrowed for debt paid.
- [ ] No migrations in this step — say so in the roadmap row rather than
      leaving a reader to wonder about a cloud push.
- [ ] `make ci` green.
