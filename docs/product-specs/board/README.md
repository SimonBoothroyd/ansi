# The design board — how it is kept

The board is **what the app looks like today**. One file per screen. Open
[`index.html`](./index.html) in a browser; every other file is one view.

- [`board.css`](./board.css) — the shared visual language: tokens, phone
  chrome, frame anatomy. Every view links it and nothing else styles a frame.
- `index.html` — the masthead, the system strip (palette · type · the
  freshness signature) and one status row per view.
- One file per view, in the order the app is used: `library` · `book` · `recipe-page` ·
  `recipe-editor` · `import-review` · `ingredient-picker` ·
  `quantity-measures` · `recipe-picker-confirm` · `ingredients-manager` ·
  `ingredient-detail` · `week` · `cook-shop` · `navigation` · `errors-sync` ·
  `account`.
- [`not-built.html`](./not-built.html) — frames that were drawn and never
  built, each citing its row in [`backlog.md`](../../exec-plans/backlog.md).

## The rules

1. **Replace, never append.** When a design pass lands, you rewrite the
   screen's frames and refresh its status date. There is no `v2` section and
   no second copy of a screen. A file small enough to rewrite is the whole
   point of the split: "replace `week.html`" is a possible instruction in a
   way that "replace lines 3304–3672" never was.
2. **A proposal is drawn in the screen's own file**, with a `proposed` status,
   until it ships. Then the frames it replaces are deleted.
3. **No decisions here.** Rulings, alternatives that lost, owner quotes,
   sign-off dates and test results belong to the exec plan or the ADR. The
   status line links them; the board draws pixels.
4. **A frame that knowingly differs from code says so**, in one `differs:`
   line on that frame — never silently.
5. **The status date is a verification date.** It is the last time somebody
   read the view against `app/lib`. Bump it when you have actually looked.
6. **A wide frame is not a version.** The phone frame and the wide frame
   (web, iPad landscape — the `≥ 1024` layout) are both current at once, so
   both live in the screen's own file. Wide frames sit in their own
   `.board-wide` row under an `<h2>` rule reading `Wide · ≥ 1024`, drawn in
   the `.desk` chrome from `board.css`, and every wide frame's name opens
   with the word *wide*. A screen whose wide answer is "centred, unchanged"
   draws no wide frame; its status line carries one clause instead. While a
   wide frame is unbuilt it is `proposed`, like any proposal.

## The status line

One per view, fixed grammar:

```
built · matches code <date> · features/<dir> · <ADR / plan links>
built · differs <date>: <one sentence> · features/<dir> · <links>
not built · <backlog row>
```

A view with a wide answer adds one clause, after the links:

```
… · wide: proposed <plan link>        (frames drawn, not built)
… · wide: matches code <date>          (built and read against app/lib)
… · wide: same, centred at 640         (no frame; the phone layout, capped)
```

## Working on a screen

A lane or agent brief that touches UI **starts by re-verifying the view it
touches** against `app/lib` — the frames, then the copy strings — and either
refreshes the date or writes the `differs:` line. That re-verification is what
keeps the date honest; a date nobody earns is worse than none.
