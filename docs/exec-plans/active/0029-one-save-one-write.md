# Exec plan: one save, one write — and the New-ingredient sheet dissolves

- **Status:** proposed — the three open questions are **ruled** (owner,
  2026-09-03); the plan itself still wants a go-ahead
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
- [ ] **W5b** — `Mark complete` performs the compound save **and** the status
      flip in one transaction (R2). No path leaves a row saved-but-not-marked.
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
- [ ] **C1b** — backing out of a **new** row with anything typed prompts (R1);
      backing out of an **existing** row discards silently.
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

## Rulings (owner, 2026-09-03)

- **R1 — a dirty new row prompts on Back.** *"prompt is good."* C1 makes it
  possible to lose a whole typed row by backing out, so it asks. An **existing**
  row still discards silently: that is what W6 is for, and there is a stored
  version to go back to. The prompt is therefore about *creation*, not about
  editing, and it fires only when the draft would otherwise leave nothing
  behind.

- **R2 — `Mark complete` is one transaction, not two writes.** The owner:
  *"it's a 1-2 combo of save and mark basically."* It already reads that way in
  code (`completeRow` awaits `save()` then `confirmStub()`) — but as **two**
  writes, so a failure between them leaves the row saved and not completed,
  under an error implying neither happened. Under W3 the compound save and the
  status flip go in the **same** `writeTransaction`. ADR-0011's "confirm stays
  immediate" is refined by this: still its own button, still not a field edit,
  but no longer two writes.

- **R3 — the inline button keeps `Save` where it saves, and becomes `Add` where
  it does not.** The owner's reasoning — *"save, because this form is also the
  ingredient editor"* — is right about the **quantity sheet**, whose host does
  commit on tap: `Save` is accurate there and stays. On the **form** under W1
  the same tap adds to a pending list and writes nothing, and a button reading
  `Save` that does not save is the exact confusion this plan exists to remove
  (it would also give the dock's Save a rival again, which plan 0028 just
  fixed). Since the host **already** supplies the commit function (W1), it
  supplies the verb with it: `(commit, label)` from one seam, not a mode flag
  on the widget. Quantity sheet → `(write now, "Save")`. Form →
  `(add to draft, "Add")`. *Reversible: say the word and it is `Save` in both.*

## Docs that move with it

- ADR-0011 flips to **accepted** on sign-off.
- ADR-0008 §2 gains a sentence: the two phrasings are two picks in one row, and
  they land on the form's Save.
- The board's **"Ingredient detail · v2"** section (plan 0028) gains a frame
  for the create state, and its "New ingredient sheet" note is replaced by the
  sheet's obituary.
- `docs/QUALITY.md` — the ingredients row notes the single write path.
