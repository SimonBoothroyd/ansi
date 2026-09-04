# Exec plan: one save, one write — and the New-ingredient sheet dissolves

- **Status:** proposed (awaiting owner sign-off)
- **Owner:** Simon
- **Decision record:** [ADR-0011](../../decisions/0011-one-save-one-write.md)
- **Follows:** plan 0028's design pass on the flesh-out form (three groups, the
  pinned dock, `Mark complete`, the one-sentence density, the USDA search)
- **Created:** 2026-09-03

## Goal

The flesh-out form writes once, on Save, in one transaction — and then becomes
the create surface, so the New-ingredient sheet stops existing.

Observable when done: `new_ingredient_sheet.dart` is deleted; `＋` on the
manager and the picker's add-new footer open the **form** on an unsaved row;
nothing on the form writes until Save except `Mark complete` and delete; backing
out of a new row leaves no row behind; a failed save leaves nothing half-written.

**Zero migrations.** Nothing here touches the schema.

## Why in this order

Retiring only the sheet's USDA leg first (the obvious cheap win, now that the
form has the search) would be a pass over `new_ingredient_sheet.dart` that this
plan then deletes. The owner's call: *"save on write now, then collapse."*

## Acceptance criteria

- [ ] **W1** — `DensityEntry` and `MeasuresEditor` call no repository. They
      report intent to the host; the host supplies the commit. No boolean mode
      on either widget.
- [ ] **W2** — the quantity sheet still writes immediately (it has no Save),
      through a host-supplied commit that is the only place its behaviour
      differs from the form's.
- [ ] **W3** — one `saveForm` door on the repository takes the whole intent and
      applies it in a single `writeTransaction` across `ingredient`,
      `ingredient_alias` and `ingredient_measure`. Both repos already wrap the
      same `SqliteConnection`.
- [ ] **W4** — the form's draft distinguishes **unloaded** from **empty** for
      every collection it writes back (D6). A save is refused, with its reason,
      while any collection is unloaded — never narrowed.
- [ ] **W5** — nothing on the form writes on tap except `Mark complete` and
      `Delete ingredient`. Aliases, measures, density, "Counts as", the `piece`
      answer, the USDA decline and the USDA pick all land through Save.
- [ ] **W6** — `Back` discards. A row opened, edited and backed out of is
      byte-identical in the database.
- [ ] **C1** — the form accepts **no row id**: children are held in memory and
      the first Save writes row and children in one transaction.
- [ ] **C2** — `new_ingredient_sheet.dart` is deleted. The manager's `＋`, the
      editor picker's footer, the shopping top-up and the import review's
      create-new all open the form; the picker still passes the typed name.
- [ ] **C3** — the barcode door and the USDA search live only on the form. A
      new row created by scan is byte-identical to one created by name and then
      scanned (the 0025 #8 promise, now structurally true).
- [ ] **C4** — the picker's flow still resolves: it pushes the form and awaits
      its pop, and Save/`Mark complete` pop (plan 0028), so the quantity sheet
      opens on the units the form just set.

## Lanes

**Lane A — the shared editors stop writing.** `DensityEntry`,
`MeasuresEditor`, and the `piece` question. Both hosts updated together; the
quantity sheet's behaviour must not change at all, which its existing tests
already pin.

**Lane B — the compound save.** `saveForm` on the repository, the draft type
with its unloaded/empty distinction, and the form's Save rewritten onto it.
Lane A must land first.

**Lane C — the form as create surface.** No row id, in-memory children, first
Save writes everything. Then delete the sheet and repoint its four callers.

Lanes A and B are one worktree; C follows.

## Traps

- **The `piece` question writes `allowed_units` behind the form's back.** Today
  the editor writes it and tells the form so the chips follow. Deferred, the
  answer becomes part of the draft — and the chips must follow the *draft*, not
  a row that has not been written.
- **`applyUsdaProbe` currently does the fill.** Deferred, the pick fills the
  draft and Save lands the stamp. The reconciliation added in `5eb10cd` ("an
  explicit pick outranks a half-typed panel") is **deleted**, not extended.
- **The M-D2 serving offer is already the shape we want** — it defers to Save
  and writes through `setDensity` inside it. Use it as the model.
- **The measures editor's own add-form has a Save button.** Under W1 it stops
  being a write and becomes "add to the list" — it needs a different word, or
  the dock's Save has a rival again.
- **Deleting the sheet deletes U-D7.** The USDA search leg shipped in
  `3a0028e`; the capability survives on the form, but the sheet's own tests go
  with the file.
- **Do not let `Back` discard silently on a dirty new row.** C1 makes it
  possible to lose a whole row by backing out. Needs a prompt, or the row is
  cheap enough to lose — owner's call, listed below.

## Open questions for the owner

- **Q1** — on a *new* row (C1), does `Back` with a typed name prompt, or just
  discard? On an existing row, discard is the point.
- **Q2** — does `Mark complete` stay an immediate write, or fold into Save so
  there is genuinely one write? (ADR-0011 proposes immediate: it is a statement
  about a row, not a field edit.)
- **Q3** — the measures editor's inline `Save` needs a new word under W1.
  `Add` is the obvious one.

## Docs that move with it

- ADR-0011 flips to **accepted** on sign-off.
- ADR-0008 §2 gains a sentence: the two phrasings are two picks in one row, and
  they land on the form's Save.
- The board's **"Ingredient detail · v2"** section (plan 0028) gains a frame
  for the create state, and its "New ingredient sheet" note is replaced by the
  sheet's obituary.
- `docs/QUALITY.md` — the ingredients row notes the single write path.
