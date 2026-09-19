# ADR-0018 — A recipe measure is a count per batch

- **Status:** accepted (2026-09-19, Simon — owner-ruled)
- **Companions:** [ADR-0008](./0008-unit-admission-model.md) (a measure is a
  word for one thing, pinned to one number),
  [ADR-0016](./0016-a-measure-that-weighs-a-piece-is-its-word.md) (whose
  whole-measure rules 1–2 this restates one level up).

## Context

A component line can be said in `batch`, or in a unit family the target
recipe's `makes` happens to state. Everything else is unresolved — honestly,
but uselessly: a sauce nobody weighed has no yield, so the only sentence the
app accepts for it is `0.15 batch`, which is not a sentence anybody says in a
kitchen. The owner:

> *"I think we can set makes, but a lot of times I want to say like 1 blob of
> this sauce I made."*

An ingredient already has this: `ingredient_measure` is the household's word
for one of a THING — `clove`, `can (400 g)`, `potato, medium` — pinned to the
row's basis unit. A recipe has the same problem and no way to say it.

## Decision

**A recipe measure is the household's word for one of what a batch makes, and
one number defines it: how many of them a batch comes to.** *A batch makes 20
blob.* `3 blob` is 3/20 = 0.15 batches, which is the denomination every
derivation downstream already walks in.

1. **A count per batch — not an amount in a yield unit, not servings, not a
   fraction.** `per_batch` counts the word, so it needs no unit, no unit
   family, no density and no bridge: the only conversion it can ever be asked
   for is into batches, and the one number already gives it. `20 blob` is not
   "20 of something in the yield's family"; the yield may not exist.
2. **Independent of `makes`.** Serves, makes and measures are three statements
   about one batch, and none derives from another. Re-stating `makes` does not
   re-state the measures, and re-stating a measure does not re-state `makes` —
   exactly as the two yield denominations are two statements rather than one
   and its consequence. It is drawn under MAKES in the editor because that is
   the fact it restates, not because it depends on it.
3. **A gone word refuses; it never degrades.** A line whose measure has been
   retired, or whose row has not synced here, is `ComponentMeasureMissing`:
   the number is kept, the line joins no total, and every surface names it.
   It is **not** re-read as a count. Three of a thing nobody can measure is
   not three pieces of whatever the batch is counted in, and against a target
   that *makes 8 piece* the degradation would hand every reading 0.375 of a
   batch — a confident wrong number, which poisons the cook plan, the shop and
   the macros in a way a missing one never does (invariant 3).
4. **The whole-batch word is found, never stored** — ADR-0016's rules 1 and 2,
   with *one batch* where the piece weight was. `wholeMeasureOfRecipe`
   (`recipes/domain/component_units.dart`) is the single place the question is
   answered: the live measure whose `per_batch` is 1 within the same 1 %
   (`kWholeMeasureTolerance`), lowest `sort_order` then label on a tie, null
   when the recipe coins no such word. When it exists it leads the chip row
   and a fresh component amount opens on it; `batch` stays offered right after
   it. A line being edited opens on its own stored choice.
5. **The offer leads with the recipe's own words.** `componentUnitChoices`
   returns the ingredient dock's own shape one level up: the target's live
   measures (whole one first, then `sort_order`, then label), then `batch`,
   then the yield families the chips already offered. A word exists on this
   recipe and nowhere else; `cup` and `g` are the catalog, offered against
   everything in the household.
6. **A word that merely names a unit is refused** — `cup`, `g`, `batch` —
   against the catalog's own lookup (`unitFromLabel`), never a hand list. The
   chip row already says those words, and one thing with two words on one row
   is what ADR-0016 was written to stop. Everything else is the household's:
   the label is read by the ingredient side's rule exactly (trim, collapse
   whitespace, **case untouched**), duplicates merge on read oldest-first, and
   nothing in the app knows what any word says.
7. **A blob never rounds.** The shop rounds a named-measure count up because a
   shopper buys whole things (ADR-0016 rule 4). A component is **cooked**, not
   bought: `0.15 of a batch` is a real instruction, and rounding it to a whole
   batch would cook seven times what the recipe asks for. Cook's existing
   whole-batch nudge already answers the question that rounding was reaching
   for — it says a batch makes more than this week needs, and that the rest is
   the household's.

`recipe_line_item.unit` therefore loses its `NOT NULL`, made total again by
`num_nonnulls(unit, recipe_measure_id) = 1` (migration 0048): a line's amount
is said in a catalog unit **or** in one of the target's words, never both and
never neither. There is no companion unit a measured line could honestly
carry — `batch` is the right dimension with the wrong number, `piece` is the
degradation rule 3 refuses — so the column is null and `LineItem` asserts the
same shape.

## Consequences

- **Rule 3 of ADR-0016 has no analogue, and cannot.** That rule lands an
  imported counted line on the row's whole measure, because the extractor
  prints `piece` and the row already holds a better word for the same fact. A
  recipe measure has nothing to land *from*: an extractor prints units, and a
  household's word for a blob of their own sauce is not in any source page.
  The import review hosts the authoring form and **prefills nothing** into it.
- **Nothing below the resolution seam changed.** Cost, macros, the cook plan
  and the shop consume `batches` and only `batches`; the whole feature is one
  new branch above that seam and one new case in four exhaustive switches.
- **A measured line weighs nothing.** `lineAmountInBasis` answers null for it,
  as it must: a share of a batch is not a mass, and the parent's figures come
  from the target's own walk rather than from the line.
- **An older app build cannot read a measured line**, so **the data layer ships
  a release before the authoring UI.** A build that predates this casts the
  column with a hard `as String` and throws on a NULL, skips such a line
  silently in the cook plan and the shop, and prints `3 batch` in the "used in"
  list. The read seam is therefore landed on its own — every loader, every
  watch, both write doors and the delete gate, with no screen that can create a
  measure — so that the first word written anywhere in the household lands on
  devices that already resolve, cost, macro, cook and shop it correctly.
- **The write refusal is the repository's, not the form's.** A line denominated
  in neither a unit nor a word, and a week's amount naming a word with no
  number, are both refused *before* they are written
  (`UndenominatedLineError`, `WordlessOverrideError`). The database refuses them
  too, but it refuses them on UPLOAD — and a rejected upload makes the PowerSync
  connector drop the whole crud transaction, taking every write queued beside it
  in silence. A throw in front of a person costs one save; a refusal up there
  costs the queue. `LineItem`'s own asserts say the same shape and are compiled
  out of a release build, which is why they are not the guard.
- **Two doors author a word, and the difference is whether the host has a Save**
  (ADR-0011). The recipe editor's MEASURES list defers — it rides
  `Recipe.measures` through `saveRecipe`'s child diff, so a word typed there
  lands with the recipe. The manage-measures page behind the component dock's ＋
  has no Save and writes on tap. Both go through `authorRecipeMeasure` and the
  same delete gate, so neither can hold a different line than the other or walk
  round the refusal below.
- **`per_batch` is one number and one phrasing.** The add form takes no unit
  chip; the trailing `/ batch` is a fixed word. Nobody measures a blob with a
  spoon — what a cook knows is roughly how many this makes — and it is the
  same trade ADR-0008's density row made when it deleted its second phrasing.
- **A re-stated word follows every line saying it.** The row keeps its id, so
  `blob` moving from 20 to 24 moves every line at once. That is why the
  editor re-states rather than deleting and re-adding, and why the bin is
  refused while anything still says the word — *Can't delete "blob" yet · 3
  lines still say it, in 2 recipes.*
- **Out of the first slice**, each for its own reason:
  - **the Week slot saying `1 blob`.** A recipe entry's amount is its
    **portions**, which is a different fact from a share of a batch, and
    conflating them would make the week's macro line mean two things. The
    planned **snacks** slot — which takes a recipe *or* an ingredient — is
    where this gets revisited, because that slot already has to hold both
    denominations honestly.
  - **import review prefill.** Covered above: there is nothing to prefill
    from. The form is hosted; it starts empty.
  - **drag-reorder of the measures list.** `sort_order` is stored and read,
    and the list is drawn with a grip, but the gesture is a later pass — the
    order a household types their words in is already the order they get.

## Rejected alternatives

- **A measure as an amount in the yield's unit** — "a blob is 15 ml". It
  reintroduces every fact the feature exists to avoid: a unit, a family, and a
  yield to convert against. A recipe whose `makes` is unstated could then coin
  a word and still not be sayable, which is the exact case the owner raised.
- **A measure as a fraction of a batch** — "a blob is 0.05 batch". The same
  arithmetic, stated in the form nobody thinks in. A cook knows roughly how
  many blobs a batch makes; nobody knows a blob is a twentieth.
- **A measure as servings** — reuse `servings_base`. Portions are what a
  person eats and a batch is what a pot holds; ADR-0007's line between them is
  load-bearing, and a word for a ladle of sauce is about the pot.
- **Deriving the measures from `makes`** — "makes 20 blob" as a third yield
  denomination. It would make the word a unit, which it is not: two recipes'
  `blob`s have nothing to do with each other, and the yield pair is pinned to
  *different families* precisely because those denominations convert.
- **Degrading a gone word to a count** so the line keeps contributing. Rule 3
  answers it; the shape of the harm is a confidently wrong batch share rather
  than a visible gap.
- **A stored pointer at the whole-batch word.** ADR-0016's objection,
  unchanged: a pointer re-aimed later silently changes what a saved line
  meant, while two numbers agreeing read the same on every device.
