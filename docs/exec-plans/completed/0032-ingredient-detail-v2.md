# Exec plan: 0032 — Ingredient detail v2 — the flesh-out form stops being a list of equals

- **Status:** done — retrospective, written 2026-09-04 from the design board's
  prose before it was cut. The arrangement landed 2026-09-03; the band words
  followed on 2026-09-04.
- **Owner:** Simon (rulings) + Claude (design lane, then build)
- **Roadmap step:** follow-up to 8.5 (the ingredients manager, plan 0020) and
  to plan 0027's USDA front
- **Created:** 2026-09-03

## Goal

The flesh-out form (`/ingredients/:id`, and since plan 0029
`/ingredients/new`) had accumulated twelve uppercase labels, five of them
whole sentences shouted in a micro-label style meant for a short noun, and it
ended in four stacked actions on a stub with `Delete ingredient` one flick
below `Confirm`. The owner, driving it:

> "the new ingredient page has now become very cluttered and kind of daunting"

> "the buttons look janky, esp. with the text as written"

> "why is the message an essay"

This pass changes **arrangement and weight only**. Nothing it does removes a
capability, a field, a rule or a guard.

**What went wrong is arithmetic, not any single decision.** Every ruling the
form shipped — plan 0020's D4b/D4c/D7b, F1–F3, G1–G6, plan 0025's scan door,
plan 0027's per-serving mode and its two USDA doors — correctly added one
block to one flat scroll, and each was right on its own. Nobody drew the
result. It accumulated.

## What shipped

`ea8be53` (the form rearranged — three groups, a dock, and the `⋯` built at
last), with `81a715f` (`Fill it in from ▸ Look up in USDA` opens a search
instead of hazarding a guess) and `90f77c9` (the board section) just before
it, then `33c67d3` (nothing matches to USDA on its own) and `c3ac459` (the
band says what it measures) closing it out on 2026-09-04.

- **Three named groups instead of twelve equal shouts** — Identity,
  Nutrition, Units & measures. The five sentence-labels drop a level: a short
  caps noun with the qualifier beneath it in sentence case.
- **The status line moves to the top**, where the first question — *does this
  row count yet?* — is asked.
- **The two fill-in doors meet.** The scanner and "Look up in USDA" were
  fifteen blocks apart although they answer the same question.
- **A dock** for the two commitments — one row, not a stack: a message line,
  then `Save` ghost beside the primary CTA. The sentence that used to live
  inside the button moves to the line above it, which is also where a save
  result or a delete refusal lands, on screen whatever the scroll position.
- **The `⋯` is built at last.** The header had drawn one since the section
  was locked and the code never built the menu, so delete and un-confirming a
  complete row had nowhere to live but the bottom of the scroll. Same
  `FPopoverMenu` as the recipe view's and the book's.
- **Fixed in passing:** `Save` and the CTA now end the page. Neither did, and
  `ingredient_picker.dart` pushes this form and awaits its pop before opening
  the quantity sheet — so finishing a row from a recipe line left the person
  on a page with nothing more to do and no sign that anything was waiting.

## Decision log

> **A numbering collision, stated up front.** This board section's R-series is
> not plan 0029's. `0029-one-save-one-write.md` has its own R1/R2/R3 — a dirty
> new row prompting on Back, `Mark complete` as one transaction, the inline
> button's verb — which are different rulings entirely. The R1–R8 and Q1–Q8
> below are the arrangement pass's.

Everything is **kept** unless a ruling below says otherwise: macros alone gate
`complete` (plan 0020 D5); confirming stays a human act; D4c still locks the
other family and flags a stranded default with its one-tap fix; the delete
refusal still names its recipe count; density is still one stored fact entered
two ways; the measures editor is still the shared one, volume-label redirect
and all.

### The arrangement — R1–R8, ruled 2026-09-03

- **R1 — the field order moves.** The default unit leaves `category +
  default unit` and joins the admission chips, because
  `unitSayableAsDefault()` and the chips are one rule (D4c). **This is the one
  board-level field-order change ever made** — `category + default unit`
  stops being one line — which is why it needed the owner's yes rather than
  being folded in with the rest.
- **R2 — the dock exists.** ~95 px, permanently, for `Save` + the CTA and the
  message line. Delete and un-confirm go behind the `⋯`.
- **R3 — the CTA is short.** The promise leaves the button for the line above
  it, which is what lets `Save` and the CTA share one row.
- **R4 — the heading is "Units & measures".** The owner: *"for Units &
  measures I think I prefer that rather than slightly more cutesy phrases."*
  *What a line may say* is retired as a heading and survives where it already
  lives, as the hint under Allowed units.
- **R5 — the stranded-default flag stays, quietly.** The locked-chip warning
  goes; the stranded default does not, because it names a unit **the row is
  already using**, and hiding it would hide a broken row from the only person
  who can fix it. It stops being an amber card: the chip is drawn dotted in
  the "gone" colour and one line under the row carries the fix inline. Roughly
  90 px becomes roughly 20.
- **R6 — `Mark complete`, not `Finalize`, and the list hint follows.** The
  state is literally called `complete` (`IngredientStatus.complete`), and the
  strip at the top already reads *"Complete — counts in conversions and macro
  totals."* The app was using **three words for two states**: the list hinted
  `needs confirm`, the button said `Confirm`, the status said `Complete`. One
  word, used as the verb, collapses that, and it pairs exactly with the `⋯`'s
  inverse, *Return it to a stub*. **Not `Finalize`:** it promises
  irreversibility, and D5 makes this explicitly reversible — a button that
  says finalize above a menu item that undoes it is a worse lie than the one
  being fixed. The knock-on was ruled too: the list view's stub hint becomes
  **`needs completing`**, so both screens use one word for one act.
- **R7 — the density segment is deleted.** Owner: *"grams per spoon hides
  intent of things like cup"* — it did. Two rounds went into naming a segment
  (*a spoon weighs…* → *grams per spoon* → *g per spoon or cup*) whose only
  job was to choose between a phrasing a person would use and one they would
  have to compute. **The best answer to the label question turned out to be
  that there is no label.** One self-describing sentence replaces it — *1 tbsp
  of this weighs __ g* — with `ml` among the picks so a known g/ml stays
  exactly typeable (`1 ml of this weighs 0.66 g` is the same arithmetic, since
  ml's ratio to base is 1). Three problems dissolve with it: the tightest row
  on the page loses two chips; the naming problem goes entirely; and the
  measures-editor redirect (typing "cup" as a measure label) lands here with
  `cup` pre-picked instead of having to flip a mode.
- **R8 — `Save` and the CTA close the page.** `save()` stays **pure** — it is
  also used as a flush by three callers (the USDA lookup, which must probe the
  *stored* name; *Choose another*; the stranded-default one-tap fix), and none
  of those may navigate. So the button handler pops and `save()` does not.

### The questions the code answered — Q1, Q2, Q5, Q8

- **Q1 — default and allowed units belong together: yes.** They are the same
  rule. `unitSayableAsDefault()` and the chips' own candidate list are **one
  predicate wearing two hats** — D4c is precisely the ruling that the chips
  *and the default-unit selector* lock the other family's options. They were a
  whole group apart, so the greyed-out chip and the dashed chip that explain
  each other could not be seen together. It also gives the stranded-default
  flag its repair back: the flag says *"enter one below"*, and below is now
  the next section rather than two groups away.
- **Q2 — the imprecise section: no, fold it in.** It was a labelled heading
  over one read-only derived string, which on most rows says *"none —
  category-gated"*. It is not editable and never was: the words are a fact
  about the **category**, not about this row. The app already draws imprecise
  units as chips after a thin divider in the quantity sheet; the form had the
  data, filtered it out, and re-rendered it as prose two sections later.
  Folding it back after a divider deletes one section and one filter, and a
  row with none renders nothing at all instead of a heading saying "none".
- **Q5 — two warnings that read alike: one goes, one stays and gets quiet.**
  Hiding the locked units until there is a density: yes — six dashed grey
  chips plus a note is a lot of screen to say what one sentence says better
  (*"cup · tbsp · ml unlock when this row has a density"*), and the sentence
  answers *why can't I pick cup* **by name and with the remedy**, which a
  dashed chip cannot. The other warning is not the same warning and cannot be
  hidden: *"cup needs a density on this row"* is about the unit the row
  **already uses**. Hiding it until a density arrives means the app knows the
  row is broken and says nothing, and the person has no reason to add a
  density because nobody told them anything was wrong. It stops shouting
  instead (R5) — D4d had already ruled *keep D4c strict, fix the data*, and
  nineteen stranded rows got a real density, so this is now a rare state, and
  a rare state should not own an amber card with a heading, a body and a
  button.
- **Q8 — a distinguisher: no.** Owner: *"do we need a distinguisher? I don't
  think anyone will ever really do the division themselves."* They won't, and
  we don't. The one real user of the g/ml field was somebody copying a
  reference value, and `ml` in the picker serves them exactly. The phrasing
  that replaces it is already the app's voice: the serving offer says *"1 tbsp
  weighs 14 g — set as density"*, never *"set 0.947 g/ml"*.

### The USDA band, re-ruled 2026-09-04

The band word survived two rounds and changed meaning in both. Recorded here
because the measurement exists nowhere else.

- **Rev 7 deleted the word, and was wrong to.** The argument was that
  `close match` / `a guess` (plan 0027 U-D1) only warned that a *machine* had
  chosen, so once plan 0029 dropped the prefill trigger — nothing matches a
  row to USDA without a person picking from the search — the warning had
  nothing to warn about.
- **Rev 8 kept it and re-said it, on a measurement.** Against **267 curated
  pairs**, a pick that covers every word of the name is the right food **63 %**
  of the time, against **34 %** for one that covers only part. The signal is
  real and worth drawing. But it is **not a graded band**: the score is
  **bimodal** — 226 of 264 sit at exactly 1.0, and **nothing falls between
  0.85 and 1.0** — so every threshold in that range asks one yes/no question,
  and **0.85 was a boolean in a threshold's clothes**.
- **So the words change rather than go.** `UsdaMatchFit` tags rows **`all
  words`** / **`some words`**, and the provenance card reads *matches every
  word of "Black Rice"* or *matches only part of …*. The cut is at full
  coverage, not at 0.85. What it reports is **fit to the name you typed** — a
  coverage fact — not confidence a machine no longer has. Plan 0027's decision
  log carries the supersession.
- The provenance card also stops being an arrival state: it can only exist
  *after* a pick, so it is quiet rather than amber, and *Not this food* is now
  how you **unlink**, not how you undo a machine's guess.

### Follow-up, recorded not actioned

- **ADR-0008 wants one clarifying sentence, not an amendment.** It says
  density is *"enterable two equivalent ways"*. That stays true after R7 — the
  two ways stop being two controls and become **two picks in one row**. The
  ADR's own text has never been touched, and this is worth the owner's eye
  because it is an ADR and not a frame. Deliberately left as a note here
  rather than edited in.

## Notes

- **Cost, as estimated and as built:** one file rearranged
  (`ingredient_detail_view.dart`), four widgets retired into the dock and the
  menu, one filter and one amber card deleted, and about twenty-five widget
  test finders updated for affordances and strings that moved (the CTA, the
  list's `needs confirm` hint, the scan label, the folded imprecise section) —
  no behaviour change, so no new test beyond the finders, plus the sim smoke's
  scroll targets.
- **What this pass deliberately did not do:** it did not touch the
  New-ingredient sheet, the *other* screen "the new ingredient page" could
  have meant, nor rebalance what lived on the sheet versus the form. That
  question was answered instead by ADR-0011 and plan 0029, which deleted the
  sheet the next day.
- Order within Units & measures: default unit → allowed units → density →
  measures → counts as. It follows the copy that already existed (the
  stranded flag says *"enter one below"*, the dashed chips said *"need a
  density"*) and keeps density next to measures, which is where the
  volume-label redirect throws you.

## Step-done checklist

- [x] The form's three groups, the dock and the `⋯` shipped in `ea8be53`.
- [x] `Mark complete` and the `needs completing` list hint landed together.
- [x] `UsdaMatchFit` replaced `UsdaBand` (`c3ac459`); plan 0027's decision log
      records the supersession.
- [x] `make ci` green at every landing.
- [ ] ADR-0008's clarifying sentence — open, owner's call (above).
