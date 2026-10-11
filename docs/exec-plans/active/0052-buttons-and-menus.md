# Exec plan: A pass over buttons and menus

- **Status:** built on `ccr-d2ad9000-tfiwl1` — widget tests, analyze and docs-check pass; the two simulator files that open the editor from the recipe page (`recipe_editor`, `nested`) are updated but not run
- **Owner:** Simon (design and rulings), agents in lanes
- **Roadmap step:** Next 3 — a design pass, off the owner's ask
- **Created:** 2026-10-11

## Goal

*"Some of our menus (esp on recipes) are starting to look a bit crowded."*
— the owner, 2026-10-11. Each feature added its own item to the recipe
page's `⋯`, at the place it was built, so the menu's order became the order
things shipped. Read every `FPopoverMenu` in `app/lib`, make the
recipe page's lighter, and make the rest follow the same few rules.

## What the read found

| Menu | Finding |
|---|---|
| Recipe page `⋯` | Up to **eight items in one flat list**: Favorite, line figures, Keep screen on, Share link, Stop sharing, Edit, Edit for this week, Delete. Edit — the page's most-used verb — sat sixth, under three toggles and two share items. Delete sat directly under the week door, in the same group, not red. The board drew it red; the code did not. |
| Week switcher | **This week** and **Jump to today** both called `today()`: the same item twice. |
| Book `⋯` | Move up on the first book and Move down on the last were offered and did nothing. |
| Section `⋯` | The same dead moves, and **Delete** in the same group as Rename, where the book's Delete stands apart. |
| Ingredient editing `⋯` | Delete ingredient not set apart and not red. |
| Ingredient fact sheet `⋯` | One item, *Edit*. Kept: the reading posture deliberately draws no buttons but *Fill it in* ([ingredient-detail.html](../../product-specs/board/ingredient-detail.html)). |
| Method `⋯` (editor) | One item, *Convert to plain text*. Kept: it is rare and lossy, and the `⋯` is what keeps it out of reach of a stray tap. |
| Library recipe row `⋯`, section `＋` | Two items each, both used. Unchanged. |

## The rules the pass holds

1. **A page's most-used verb is a button, not a menu item.** On the recipe
   page that is Edit: a pencil in the bar (in the hero at expanded), beside
   the `⋯`.
2. **The `⋯` groups by what an item touches,** and a group boundary is
   drawn. On the recipe page: what the household holds (*Favorite*, *Share
   link*, *Stop sharing*), how this phone reads the page (*Keep screen on*,
   *Show line figures* — written nowhere), and Delete.
3. **Delete is last, alone in its group, and red** (`FItemVariant.destructive`)
   — in every menu that has one.
4. **A menu does not offer what would do nothing** — no Move up on the first
   row, no Move down on the last.
5. **No item twice.** One door per destination within a menu.

## Rulings

- **From a week, the pencil asks which edit.** Plan 0044 put *Edit recipe*
  and *Edit for this week · Tue & Sat only* side by side so the two read as
  two. They still do: the pencil goes straight to the editor from the
  Library, and from a week that plans the recipe it opens those same two
  items. The choice appears only where there is one. *Proposed by the pass;
  the owner's look on a phone is still owed.*
- **Unchanged on purpose:** the copy of every item, the confirms behind
  Delete and Stop sharing, *Show line figures* offered only from the tab it
  changes, the sun in the bar while the screen is held on.

## Done

- [x] `recipe_view.dart`: `_EditDoor` (the pencil, and the two-door choice
      from a week); `_RecipeMenu` in three `FItemGroup`s, Delete destructive.
- [x] `week_header.dart`: *Jump to today* removed; *Copy last week into this
      one* in its own group, which is absent off the Week.
- [x] `book_rows.dart`: book and section moves offered only where the order
      can take them; *Delete section* in its own group; both deletes red.
- [x] `ingredient_detail_view.dart`: *Delete ingredient* in its own group,
      red; the first group absent on a stub.
- [x] Widget tests: the pencil's two doors and the Library's straight path
      (`recipe_week_arrival_test`, `recipe_wide_test`), the recipe `⋯`'s
      groups and red Delete, the book and section moves and deletes
      (`library_view_test`), the week menu's three jumps (`week_header_test`).
- [x] Board: [recipe-page.html](../../product-specs/board/recipe-page.html)
      (the pencil in every bar, the grouped menus, the week's choice),
      [library.html](../../product-specs/board/library.html),
      [cook-shop.html](../../product-specs/board/cook-shop.html),
      [ingredient-detail.html](../../product-specs/board/ingredient-detail.html).
- [ ] `make test-sim FILE=recipe_editor` and `FILE=nested` — both reach the
      editor through `editRecipeFromPage`, which now taps the pencil.
- [ ] The owner's look at the recipe page on a phone.
