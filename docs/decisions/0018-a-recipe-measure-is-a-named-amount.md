# ADR-0018 — A recipe measure is a named amount, gated on `makes`

- **Status:** accepted (2026-09-19, Simon — owner-ruled)
- **Companions:** [ADR-0008](./0008-unit-admission-model.md) (a measure is a
  word for one thing, pinned to one number; mass⇄volume belongs to an
  ingredient's density),
  [ADR-0016](./0016-a-measure-that-weighs-a-piece-is-its-word.md) (whose
  whole-measure rules 1–2 this restates one level up).

## Context

A component line can be said in `batch`, or in a unit family the target
recipe's `makes` happens to state. Everything else is unresolved — honestly,
but uselessly: a cook who ladles romesco onto a plate has to say `0.15 batch`,
which is not a sentence anybody says in a kitchen. The owner:

> *"I think we can set makes, but a lot of times I want to say like 1 blob of
> this sauce I made."*

An ingredient already has this: `ingredient_measure` is the household's word
for one of a THING — `clove`, `can (400 g)`, `potato, medium` — pinned to the
row's basis unit. A recipe has the same problem and no way to say it.

A first pass built the word as one number, a **count per batch** (*a batch makes
20 blob*), independent of `makes`, so that a recipe nobody had ever weighed
could still coin a word. The owner overruled it before anything shipped:

> *"I think this needs to work exactly like measures and specify 3 blob and then
> weighs what in what unit, and can only be set when we know what x a recipe
> makes."*

That is the decision below. The count-per-batch design is recorded under
**Rejected alternatives** with his reason.

## Decision

**A recipe measure is the household's word for one of what a recipe makes,
defined exactly as an ingredient's word is: an amount in a unit.** *A blob is 15
g.* `3 blob` is `45 g`, and through the recipe's own same-family yield (`makes
300 g`) that is 0.15 batches — the denomination every derivation downstream
already walks in.

1. **A named amount, not a count of the batch.** `recipe_measure` is `label` +
   `amount` + `unit` (migration 0048), which is `ingredient_measure`'s `label` +
   `basis_amount` one level up. The only structural difference is where the unit
   comes from: an ingredient HAS a basis (ADR-0008) and its measures inherit it,
   while a recipe can state what it makes in mass, volume or count — and in two
   of those at once — so each word carries its own `unit`. Mass, volume and
   count only: `batch` would make the word circular, and an imprecise word
   converts nothing.
2. **It may only be authored against a `makes` it can be held to**, and that is
   the cost of working like the measures the household already knows.
   `authorRecipeMeasure` refuses while the recipe states no yield at all, with a
   sentence that sends the person to MAKES — *"Say what a batch makes first,
   under MAKES. A word like “blob” is a size, and a size is only a share of a
   batch once the batch has one too."* — and the MEASURES list is drawn disabled
   carrying that same sentence. It also refuses a unit whose FAMILY is not one
   the recipe states, naming both sides and the way out, which is the yield's
   optional second denomination. A recipe states up to two, in different
   families, and a word may be said in either.
3. **One conversion path, so the failures are the existing ones.** A measured
   line reaches `resolveComponentAmount`'s yield loop carrying the measure's own
   unit, which means `ComponentYieldMissing` and `ComponentFamilyMismatch` fall
   out of the same code for a word as for a `¼ cup`. A `makes` edited away or
   re-familied under a live word therefore refuses in exactly the words it
   already refuses `2 tbsp` of a butter that only says `250 g`. There is no
   second arm to keep in step, and no new refusal to render.
4. **A `makes` edit that orphans a word warns first.**
   `recipeMeasuresOrphanedBy({measures, from, to})` is that same rule read
   backwards — the words the recipe can hold now and could not after the Save —
   and the editor draws the warning before committing. It **warns, never
   refuses**: what a batch makes is a fact about the recipe and the household may
   restate it. A word already orphaned is not re-reported, because re-warning
   about a gap already on screen teaches a person to dismiss the dialog.
5. **Re-stating `makes` re-states the share, and that is the point.** `blob` =
   15 g is absolute. A batch restated from `300 g` to `600 g` leaves the word
   untouched and makes `45 g` 0.075 of the bigger batch — the blob means the same
   thing in the kitchen either way, which is precisely what an amount buys over a
   count.
6. **No density, ever.** A `blob` said in grams against a recipe that only
   states a volume yield is a family mismatch, exactly as a mass-said component
   amount is. ADR-0008 keeps mass⇄volume to an INGREDIENT's density, because a
   density is a fact about a substance; a recipe is not a substance and has none,
   so its optional second yield denomination is the only bridge that exists here.
7. **A gone word refuses; it never degrades.** A line whose measure has been
   retired, or whose row has not synced here, is `ComponentMeasureMissing`: the
   number is kept, the line joins no total, and every surface names it. It is
   **not** re-read as a count. The word was the only place its amount lived, and
   against a target that *makes 8 piece* the degradation would hand every reading
   0.375 of a batch — a confident wrong number, which poisons the cook plan, the
   shop and the macros in a way a missing one never does (invariant 3). That case
   is kept distinct from rule 3's two: those say the RECIPE stopped saying
   enough, this says the word itself has gone, and they are different things to
   go and fix.
8. **The whole-batch word is found, never stored** — ADR-0016's rules 1 and 2,
   with *the whole yield* where the piece weight was. `wholeMeasureOfRecipe`
   (`recipes/domain/component_units.dart`) is the single place the question is
   answered: the live measure whose amount, converted, equals the recipe's
   ENTIRE same-family yield within the same 1 % (`kWholeMeasureTolerance`) —
   `loaf` = 900 g on a bread that `makes 900 g` — lowest `sort_order` then label
   on a tie, null when the recipe coins no such word or states no yield. When it
   exists it leads the chip row and a fresh component amount opens on it;
   `batch` stays offered right behind it. It moves when `makes` does: restated to
   `1.8 kg`, the loaf is half a batch and stops leading, which is the truth
   rather than a regression.
9. **The offer leads with the recipe's own words** — `componentUnitChoices`
   returns the ingredient dock's own shape one level up: the target's live
   measures (whole one first, then `sort_order`), then `batch`, then the yield
   families the chips already offered. A word the recipe can no longer hold is
   **omitted**, because a chip for it could only ever produce a refusal and the
   fix is MAKES rather than that row — but **the stored selection is always
   offered**, so a line that says `blob` still reads `blob`, marked off-filter,
   with the honest refusal under it. That is the 7.7 rule, and it is what keeps
   an existing line from ever rendering an orphaned value.
10. **A word that merely names a unit is refused** — `cup`, `g`, `batch` —
    against the catalog's own lookup (`unitFromLabel`), never a hand list. The
    chip row already says those words, and one thing with two words on one row
    is what ADR-0016 was written to stop. Everything else is the household's:
    the label is read by the ingredient side's rule exactly (trim, collapse
    whitespace, **case untouched**), duplicates merge on read oldest-first, and
    nothing in the app knows what any word says.
11. **A blob never rounds.** The shop rounds a named-measure count up because a
    shopper buys whole things (ADR-0016 rule 4). A component is **cooked**, not
    bought: `0.15 of a batch` is a real instruction, and rounding it to a whole
    batch would cook seven times what the recipe asks for. Cook's existing
    whole-batch nudge already answers the question that rounding was reaching
    for — it says a batch makes more than this week needs, and that the rest is
    the household's.

`recipe_line_item.unit` therefore loses its `NOT NULL`, made total again by
`num_nonnulls(unit, recipe_measure_id) = 1` (migration 0048): a line's amount is
said in a catalog unit **or** in one of the target's words, never both and never
neither. There is no companion unit a measured line could honestly carry — the
line's number counts WORDS, so the measure's own `g` beside it would read as
`3 g` where the line means 45; `batch` is the right dimension with the wrong
number; `piece` is the degradation rule 7 refuses — so the column is null and
`LineItem` asserts the same shape.

## Consequences

- **A recipe nobody has measured cannot coin a word.** This is the honest cost
  of the ruling, and it is paid at the door rather than hidden: the MEASURES
  list is disabled with a sentence, and the sentence names MAKES. The owner
  chose it knowing that — a word that works like the measures he already knows
  is worth more than a word that works everywhere and means something different.
- **A word can be alive and unresolvable at the same time**, which the previous
  design made impossible. Every surface that prints a measured line therefore
  reads the label off the recipe's **live measures** rather than off the
  resolution: *"3 blob — unresolved — the yield is in volume, this line in
  mass"* says both the household's word and the gap. Only a word that has truly
  gone loses its label, which is the one case with no honest label to print.
- **Rule 3 of ADR-0016 has no analogue, and cannot.** That rule lands an
  imported counted line on the row's whole measure, because the extractor prints
  `piece` and the row already holds a better word for the same fact. A recipe
  measure has nothing to land *from*: an extractor prints units, and a
  household's word for a blob of their own sauce is not in any source page. The
  import review hosts the authoring form and **prefills nothing** into it.
- **Nothing below the resolution seam changed.** Cost, macros, the cook plan and
  the shop consume `batches` and only `batches`; the whole feature is one new
  branch above that seam, feeding the conversion that was already there.
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
- **Two doors will author a word, and the difference is whether the host has a
  Save** (ADR-0011). The recipe editor's MEASURES list defers — it rides
  `Recipe.measures` through `saveRecipe`'s child diff, so a word typed there
  lands with the recipe. The manage-measures page behind the component dock's ＋
  has no Save and writes on tap. Both seams exist in the repository already and
  both go through `authorRecipeMeasure` and the same delete gate, so neither can
  hold a different line than the other or walk round the refusal below.
- **A measured line's amount is not re-denominated from a units-only sheet.**
  Until the authoring control ships, the component quantity sheet — which always
  returns a unit — would silently replace the word with one, and nothing on this
  build could put it back. So the sheet opened on a line carrying a
  `recipe_measure_id` offers that line's own denomination as its single,
  preselected, inert chip and hands back a **null unit**: the number is editable
  and the word cannot be lost. A line whose word has been RETIRED is treated the
  same, for a stronger reason — it has no honest denomination at all, so a unit
  written there would put a confident number where the app was correctly saying
  it did not know. Recipe editor and week-variant editor both, and week mode's
  amount cell routes such a line to this sheet rather than to the INGREDIENT
  one, whose offer cannot express a recipe's word at all.
- **A re-stated word follows every line saying it.** The row keeps its id, so
  `blob` moving from 15 g to 18 g moves every line at once. That is why the
  editor re-states rather than deleting and re-adding, and why the bin is
  refused while anything still says the word — *Can't delete "blob" yet · 3
  lines still say it, in 2 recipes.*
- **The authoring control is the shared amount-and-unit one**, because the fact
  is now the same fact the ingredient side authors: a number and a chip, at the
  household's one chip-picker height. The unit chips it offers are the families
  the recipe's `makes` states.
- **Out of the first slice**, each for its own reason:
  - **the Week slot saying `1 blob`.** A recipe entry's amount is its
    **portions**, which is a different fact from a share of a batch, and
    conflating them would make the week's macro line mean two things. The
    planned **snacks** slot — which takes a recipe *or* an ingredient — is where
    this gets revisited, because that slot already has to hold both
    denominations honestly.
  - **import review prefill.** Covered above: there is nothing to prefill from.
    The form is hosted; it starts empty.
  - **drag-reorder of the measures list.** `sort_order` is stored and read, and
    the list is drawn with a grip, but the gesture is a later pass — the order a
    household types their words in is already the order they get.

## Rejected alternatives

- **A count per batch** — *"a batch makes 20 blob"*, one number, independent of
  `makes`. This was built first, and the owner overruled it: *"I think this needs
  to work exactly like measures and specify 3 blob and then weighs what in what
  unit, and can only be set when we know what x a recipe makes."* It bought a
  real thing — a sauce nobody had weighed could still coin a word — at a price he
  was not willing to pay: the household would have had **two kinds of measure**
  that look identical in a list and mean different things, one saying *what one
  of these is* and the other *how many of these there are*. A person editing both
  in one afternoon has to hold that difference in their head, and nothing on the
  screen would remind them. It also made the word a fact about a batch rather
  than about the thing in the kitchen, so re-stating `makes` silently changed how
  much a blob was — the opposite of what an amount does. Its own consequence,
  that authoring can never be blocked, is answered here by a sentence that names
  the fix.
- **A measure as a fraction of a batch** — *"a blob is 0.05 batch"*. The same
  arithmetic as the count, stated in the form nobody thinks in, and circular: the
  job of the word is to reach a batch.
- **A measure as servings** — reuse `servings_base`. Portions are what a person
  eats and a batch is what a pot holds; ADR-0007's line between them is
  load-bearing, and a word for a ladle of sauce is about the pot.
- **Deriving the measures from `makes`** — "makes 20 blob" as a third yield
  denomination. It would make the word a unit, which it is not: two recipes'
  `blob`s have nothing to do with each other, and the yield pair is pinned to
  *different families* precisely because those denominations convert.
- **A density for a recipe**, so a mass-said word could answer a volume yield.
  Rule 6: a density describes a substance and a recipe is not one. The honest
  bridge already exists and is one field away — the second `makes`.
- **Refusing a `makes` edit that orphans a word.** Rule 4: what a batch makes is
  the recipe's own fact and the household may restate it. A refusal would make
  the measures a fence around the yield, which is backwards.
- **Degrading a gone word to a count** so the line keeps contributing. Rule 7
  answers it; the shape of the harm is a confidently wrong batch share rather
  than a visible gap.
- **A stored pointer at the whole-batch word.** ADR-0016's objection, unchanged:
  a pointer re-aimed later silently changes what a saved line meant, while two
  numbers agreeing read the same on every device.
- **A companion unit on the measured line**, so an older build could read it.
  Every candidate is a stored falsehood beside a number that counts words. The
  two-release rollout — the mappers land one release before the first word is
  written — protects older devices instead.
