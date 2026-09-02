# Exec plan: Nested recipes — a recipe as an ingredient

- **Status:** done — 2026-09-02. Signed off 2026-09-01 ("D1–D9 as drawn",
  after three pre-sign-off owner refinements: the two-denomination yield,
  the editor MAKES row / frame (h), the conditional "Used in" tab); built
  as four Opus lanes — S `adab7cf` (server) → D `2cbba11` (domain) →
  U `d3daac2` (UI) → I `2d8f53b` (import) — plus the frame-(f) arbitration
  fix `e51bf71` and two sim-pass bug fixes `1151041`/`d4837c3`.
  **1021 host tests · 176 pgTAP · 153 deno · `make test-sim` 6/6** (new
  scenario 6: yield → link → plan → cook gap → delete refusal, on live
  sync). The sim pass also surfaced the **"almonds" plural-search bug**
  (fixed `0a1bc02` + two tracker rows). Deferred honestly: the import
  review leg is host-tested only; method-step recipe refs; cloud push of
  `0017` (all → tracker / roadmap row).
- **Owner:** Simon + Claude (design phase solo, before any fan-out)
- **Roadmap step:** Step 8.6 — Nested recipes
- **Created:** 2026-09-01

## Goal

A sub-recipe reference — `"¼ cup Romesco Aioli (page 38)"` — stops being plain
text and becomes a real recipe↔recipe link with honest semantics on every
surface: the recipe page (a tappable component line), scaling (the amount
scales like any line), the cook plan (planning the parent derives a *cook the
aioli* session), the shopping list (the aioli's ingredients contribute, with
provenance through both levels), macros (the component's share counts, or the
total says why it can't), and import (a matching library recipe is *offered*,
never auto-linked).

Observable done: import the sausage-sliders photo, link its `"Romesco Aioli
(page 38)"` line to the household's Romesco Aioli recipe from the review
screen, plan the sliders for Saturday — and watch the Cook tab grow a
"Romesco Aioli · for Sausage Sliders" session and the Shop tab pick up the
aioli's almonds and peppers with a two-level provenance line. Scale the
sliders to 16 and every derived number doubles.

## The specimens this step answers

`evals/datasets/extraction/gold/sausage-sliders.json` carries six tagged
sub-recipe references, and they span the whole quantity problem:

| Printed line | The question it poses |
|---|---|
| `8 Pretzel Buns (page 97)` | a **count** of the sub-recipe's product |
| `2 tbsp Garlic Butter (page 17)`, melted | a **volume** of it, plus a prep note |
| `¼ cup Romesco Aioli (page 38)` | a **fraction of a batch** — but only if you know the batch makes 1 cup |
| `1 Italian Sausage (page 45)` | the parked owner ruling: *what does the `1` count?* |

The 2026-08-31 ruling (gold `_review`, codified in `_SCHEMA.md`) held these as
plain lines "until 8.6 answers what the `1` counts". D2 is that answer.

## Non-goals — the scope fence

- **Auto-linking, ever.** Matching may *suggest* a household recipe; a human
  taps the link. Same never-invent / no-silent-auto-stub posture as step 8.
- **Fetching or fabricating the referenced recipe.** Page 38 is not in the
  photo. If the aioli isn't in the library yet, the line stays plain text —
  importable later, linkable later (D6/D7). We never mint a stub *recipe*.
- **Cross-household or global links.** `sub_recipe_id` points inside the
  household, like every other row.
- **A prep-day scheduler.** The derived component session says *cook by
  Saturday*; picking a different day is the same persisted-override gap step 5
  deferred for top-level sessions (tracker). One rule for both.
- **Leftover/inventory tracking.** Cooking a whole aioli batch for a ¼-cup
  need leaves ¾ cup over; the session prose says so, nothing stores it.
- **Cook-mode integration** (cook mode itself is still tracker debt).
- **Editing tokenized methods** (tracker, unchanged).
- **`batch` as a unit for ingredient lines.** If D2 admits a batch
  denomination it exists for component lines only.
- **Recipe merge/dedup.** Same fence as 8.5's ingredient merge.

## What already exists — read this before drawing or building

**Board (locked frames that stand — extensions only, per the kickoff rule):**

| Locked frame | What it already settles for 8.6 |
|---|---|
| **Recipe view v3** (`amount · ingredient · notes`) | The line grammar a component line must render inside — the amount column and note stay; only the identity cell changes |
| **Review recipe** + **Expanded edit card** (step 8) | The card anatomy, the always-visible `raw_amount · ingredient_text` source line, the inline "did you mean" chip idiom a recipe suggestion reuses |
| **Ingredient picker v2** (7.7) | Search-first, sectioned results, honest rows — a "Your recipes" section slots in; the picker is not redrawn |
| **Quantity + unit chips** (7.7/7.8) | The chip-over-keypad sheet and the live conversion line — component chips ride the same dock |
| **Batch cook plan** | The session card (`.session`: when · scale · covers · timeline · split/freezer notes) a component session reuses |
| **Shopping list** | The provenance breakdown rows a nested contribution extends by one segment |
| **Method · chips** (step 9 section) | Ref chips fold at render; a future method-side sub-recipe chip inherits this, not v1 scope |

**Code and data (the seams this step touches):**

- `recipe_line_item` — `ingredient_id` NOT NULL today; D1 relaxes it.
- `recipe` — has `servings_base`, cook/total time; **no yield**. Extraction
  already emits `yield_raw` (`"MAKES: 8 SLIDERS"`) but commit drops it — the
  exact gap that made the sausage `1` unanswerable.
- `scaling.dart` scales any quantified line — a component line scales for free.
- `buildCookPlan`/`clusterSessions` — pure, portion-denominated; D3 adds a
  batch-denominated component demand alongside.
- `buildShoppingList` — contributions already carry recipe title + cook day;
  D4 adds one provenance segment.
- `summarizeRecipeMacros` + the shared incomplete-reasons helper — D8 extends
  the reason vocabulary.
- Import matching — server-side, deterministic, `match_text` phrase
  normalizer shared Dart/TS (8.5); D6 points it at recipe titles too.
- The 8.5 delete precedent: **refused with a count while something live
  points at the row** — D5 reuses it verbatim for recipes.

## Decisions for sign-off

Each carries options and a recommendation. The recommendation is what the
board frames draw; alternatives are annotated on the frames.

---

### D1 — Where a component lives: on the line, not in a new table

The printed page interleaves components among ingredients (buns · butter ·
oil · spice · aioli · onions · sausage, one list). The editor, scaler, and
view all walk `group → line_item` today.

- **(a) `recipe_line_item.sub_recipe_id uuid null` + relax `ingredient_id`
  to nullable, with a XOR check** (exactly one of the two set). A component
  is an ordinary line: group membership, sort order, quantity/unit/note,
  soft delete, sync — all inherited. One migration, one schema.dart column,
  no new view merge anywhere.
- **(b) A separate `recipe_component` table.** Clean FK story, but every
  surface must zip two row sets back into one printed order, and the editor
  needs a second CRUD path.

**Recommendation: (a).** The XOR check is the whole cost. `measure_id` stays
NULL on component lines (measures are an ingredient concept); a CHECK pins
that too.

### D2 — What the amount counts: the printed unit, resolved against a yield

The line says `¼ cup`; batch math needs to know the batch makes 1 cup. This
is the parked sausage question, and the answer is a **yield on the
sub-recipe**:

- `recipe` gains **`yield_qty numeric null` (> 0) + `yield_unit text null`**
  — "makes **1 cup**", "makes **8** (piece)". Nullable; `servings_base`
  remains the portioning truth and the two are independent facts.
- **The yield may carry a second denomination** (owner amendment,
  2026-09-01): `yield_qty_2/yield_unit_2`, same nullability, CHECK-pinned to
  a **different unit family** than the first — "makes **250 g · 16 tbsp**",
  "makes **8 (piece) · 960 g**". Two stated facts, no invention: together
  they bridge families for *this recipe only*, the way an
  `ingredient_measure` bridges count↔mass — without giving recipes a density
  or measures machinery. Capped at two; a third family is a curiosity no
  printed page states.
- A component line is denominated either in **`batch`** (always available:
  `qty 1, unit 'batch'` = one whole run of the sub-recipe, `qty` = batches
  directly) or in **a unit of either yield's family** (resolvable only when
  a comparable yield is set: `batches = qty ÷ yield_qty` via `core/units`,
  same-family against whichever denomination matches — no other bridge
  exists for a recipe, so `2 tbsp` of a butter whose only yield reads
  `250 g` is *unresolved*, honestly, until someone states the tbsp side).
- **Stored-selection admission carries over** (the 7.7 rule, verbatim): an
  imported line's printed unit is always an admissible chip even when the
  sheet wouldn't offer it — rendered with the honest *unresolved against the
  yield* conversion line, never silently rewritten.
- **No yield ⇒ no invented number.** The link, the view, and scaling all
  still work; the cook plan and macros surface a named gap — *"Romesco Aioli
  doesn't say how much it makes — set its yield"* — and never assume 1 batch.
- **The sausage answer:** yield `8 piece` on the page-45 recipe makes
  `1 Italian Sausage` = ⅛ batch. The `1` counts pieces of the yield.
- Import prefill (small, honest): commit parses `yield_raw` into
  `yield_qty/yield_unit` when it is a plain `amount + known unit`
  (`"MAKES 1 CUP"`); anything fancier stays raw and the field stays null.

Alternatives: denominate components in *servings* of the sub-recipe (clean
math, but `"¼ cup"` stops being what the page printed — breaks the review
screen's source-line honesty); or give recipes measures/density like
ingredients (machinery nothing needs yet — the two-denomination yield is
the deliberate lightweight cut of that idea).

**Recommendation: as drawn above — a one-or-two-denomination yield +
{batch ∪ the yields' families} units.**

### D3 — Cook plan: a component is a real derived session

- **(a) Component demand joins the derivation.** Each parent cook session
  demands `parent scale × batches-per-parent-batch` of the sub-recipe; all
  demands on the same sub-recipe cluster into that recipe's own sessions
  (existing machinery, one new demand flavour), labeled **"for Sausage
  Sliders"**, cook day = on/before the earliest demanding parent's cook day,
  bounded by the sub-recipe's own `keeps_for_days`/freezer facts. Scale reads
  in batches (`×¼ batch — makes 1 cup, you need ¼`), not portions.
  Unresolved yield ⇒ the session card renders the named gap instead of a
  number, with a one-tap "set yield" (the D2 state).
- **(b) A note on the parent card only** — shopping then needs its own
  expansion path, and "cook the aioli first" never gets a day.
- **(c) Flatten silently into the parent** — the aioli's method disappears;
  worst option.

**Recommendation: (a).** Pure derivation, no new tables. Recursion (a
component inside a component) walks depth-first; a cycle cannot be written
(D5) and the walker still carries a visited-set guard that stops and flags
rather than looping (two-device races).

### D4 — Shopping: contributions flow through; provenance names both levels

Falls out of D3(a): a component session is a cook session, so the
sub-recipe's ingredient lines contribute scaled by its batch factor through
the existing pipeline. The breakdown row gains one segment: **"Romesco
Aioli · for Sliders · cook Sat 60 ml"**. The component line itself never
becomes a shopping item (you don't buy aioli — you buy almonds). An
unresolved-yield component contributes **nothing** (never invent); the Cook
tab's gap card is the fix-it surface, and the shopping group header for the
parent carries a one-line echo ("1 component unresolved") so the list's
silence is legible.

**Recommendation: as described** (it is mostly a consequence of D3; the open
choice is the echo line, which the frame draws — alternative: no echo,
silence).

### D5 — Referential life: no cycles; deletion refused with a count

- **Linking A→B is refused when B (transitively) reaches A** — checked on
  device at link time over synced rows. A SQL mirror trigger is drawn as a
  second line of defense but recorded as one-rule-behind debt if deferred
  (the 8.5 admission-mirror precedent; owner may rule it in or out of v1).
- **Deleting a recipe that is someone's component is refused with a count**
  — *"Used in 2 recipes"* — the 8.5 ingredient-delete ruling, verbatim.
- **A dangling link cannot normally arise**; if sync races one in, the line
  renders its stored text with a muted *"linked recipe missing"* state and
  degrades to plain text semantics (nothing derived), never crashes.

**Recommendation: all three as stated; SQL cycle trigger in v1** (it is ~20
lines of plpgsql and pgTAP, and a cycle poisons every derivation walk).

### D6 — Import: suggest at review, deterministically; never touch extraction

- **(a) Extraction flags candidates** — a contract change, gold re-labels,
  benchmark re-runs. Expensive, and the flag adds nothing matching can't see.
- **(b) Matching-side only.** The server matcher runs each line's
  `ingredient_text` through the shared normalizer against **household recipe
  titles** as well as the vocab (cross-reference noise like `"(page 38)"`
  stripped the way parentheticals already are). A title hit yields a
  suggestion the review card renders as the existing chip idiom: **"↪ your
  recipe · Romesco Aioli"**. Tapping links the line (it becomes a component
  line, D1); ignoring it leaves plain text — exactly today's behaviour, and
  the gold specimens still commit unchanged when unlinked. No contract
  change, no gold churn, ADR-0004 intact.
- **(c) Nothing at import** — link by hand in the editor afterwards (D7
  provides the affordance regardless).

**Recommendation: (b).** Review-card rules for a *linked* line: no
ingredient match required, no `allowed_units` gate (admission is an
ingredient concept — the unit is checked against the target's yield family
at *derive* time, D2); Save's all-valid gate counts a linked line as valid
when its amount is set.

### D7 — Editor: link from the picker; the line is the affordance

- The **ingredient picker v2 gains a "Your recipes" section** below the
  ingredient results when the query hits recipe titles (distinct row glyph,
  the recipe's `makes …` as its hint; a yield-less recipe still links — the
  row says *"no yield yet"*). The picker is otherwise untouched (locked).
- Picking a recipe opens the **same quantity sheet**, chips = **`batch` +
  the yield family's kitchen-trimmed units**; the conversion line reads the
  batch math live (*"¼ cup = ¼ of a batch · makes 1 cup"*) or the honest
  *"no yield set"*.
- On the recipe page, a component line renders as the v3 grammar with the
  identity cell a **recipe chip** (link glyph + title); tap pushes the
  sub-recipe's page. On an editor line the same chip sits where the
  ingredient name sits.
- Converting an existing plain line ↔ component line = re-picking from the
  same picker (no special "convert" affordance).

**Recommendation: all four as drawn.** Alternative annotated on the frame: a
separate "＋ sub-recipe" add-row instead of a picker section — rejected as a
second door to the same act (the intake-screen "one form, two doors" rule
cuts the other way here: it is one act, one door).

### D8 — Macros: the component's share counts, or the total says why not

A resolvable component (yield set, comparable unit, target summary
`complete`) contributes `sub-recipe total macros × batches`. Anything else
makes the parent `incomplete` with a new named reason in the shared helper's
vocabulary — **`1 sub-recipe unresolved`** (no yield / family mismatch) or
**`1 sub-recipe incomplete`** (target's own summary refuses) — rendered in
the same three surfaces (picker row, macro panel, review) from the one
helper, so the wording cannot drift. Recursive with the D3 visited-set.

**Recommendation: as stated.**

### D9 — The sub-recipe's own face: yield line + "used in"

The target recipe's page gains two facts: the hero meta row shows
**"makes 1 cup"** beside servings (editable in the editor next to
servings — the same field import prefills), and the back-links live in a
**"Used in · N" tab** (owner-ruled 2026-09-01, replacing the drafted hero
row): a third tab beside Ingredients · Method, **rendered only while the
count is non-zero** with the count in its label — so a recipe used in
nothing keeps today's two-tab page, and no one stares at an empty pane.
Its rows are real: target · amount · share of a batch, each pushing the
parent. The count is the same count D5's delete refusal speaks (one query,
two uses). Alternatives: the unfolding hero row (first draft — cramped,
buried the rows); an always-present tab (empty on most mains); defer
"used in" to tracker and ship yield only — but the delete refusal already
needs the count, and a refusal naming recipes you cannot find from here
would be a dead end.

**The editor face** (owner-caught gap, 2026-09-01 — the step-2 editor was
never drawn on the board, so its numbers block gets its first frame): a
**MAKES row under SERVES** — amount + unit, plus the optional second
denomination whose unit selector offers only the *other* families, with a
✕ to drop it. **The import Review screen reuses the same row**, with the
`yield_raw` source line visible above it: commit prefills only a plain
`amount + known unit` ("MAKES: 8 SLIDERS" → `8 piece`); anything fancier
leaves the fields empty over the visible source text and waits for a
human — the attempt-then-flag pattern 0014 ruled for servings, on the same
screen. On import the amount is therefore *usually user-set*, and a
yield-less recipe still saves, links and scales — only derived numbers
wait. (Rejected: parsing harder — a wrong yield silently poisons every
derived number downstream; an empty field is honest and one tap from
right.)

**Recommendation: all of it in v1.**

---

## Approach — lanes after sign-off (a DAG, like 8.5)

1. **Lane S — server.** Migration `0017_nested_recipes.sql`: line-item
   `sub_recipe_id` + XOR/measure checks, recipe `yield_qty/yield_unit` (+
   the second-denomination pair, different-family CHECK),
   the cycle trigger, delete-refusal count RPC (or client query), sync-rules
   + powersync schema + `db-schema.md` regen; pgTAP for XOR, cycle, RLS.
   Matching: recipe-title candidates in the match response (D6). Commit:
   `yield_raw` prefill parse (D2).
2. **Lane D — domain (pure Dart, after S freezes shapes).** Batch-math
   resolver (`core` or recipes domain), cook-plan component demand +
   clustering + gap states, shopping pass-through + provenance segment +
   echo, macro recursion + reasons. Mirrored tests for every branch,
   incl. cycle-guard and unresolved-yield honesty.
3. **Lane U — UI (after the board section locks).** Recipe-view component
   chip + push; editor picker section + quantity-sheet chips + conversion
   line; the editor's MAKES row (frame h — both denominations, other-family
   lock); "used in"; cook/shop card faces.
4. **Lane I — import UI.** Review-card suggestion chip + linked-line card
   state + Save-gate arithmetic; the Review screen's MAKES row over the
   `yield_raw` source line (frame h — the yield does not gate Save).
5. **Close-out.** `make test-sim` scenario (import→link→plan→cook→shop),
   roadmap row, QUALITY.md, tracker retire (the 8.6 deferral row) + add
   (whatever corners get cut), gold `_review`/`_SCHEMA.md` note updated to
   point here, cloud push ledger.

## Acceptance criteria

- [x] D1–D9 ruled by the owner; board section "Nested recipes · v1" frozen.
- [x] A component line links, renders, scales, and pushes to its target
      (scaling is host-tested; the rest sim-verified, scenario 6).
- [x] Planning a parent derives the component session with honest batch
      scale; unresolved yield renders the named gap, never `1×` (scenario 6
      asserts the absence of ×1 explicitly).
- [x] Shopping shows two-level provenance; unresolved contributes nothing
      (scenario 6).
- [x] Cycle write refused (app + SQL — pgTAP covers self/2-step/3-step +
      the UPDATE leg); delete refused with a count (sim-verified).
- [x] Import offers, never auto-links; unlinked commits byte-identical to
      today (host-tested incl. the gold byte-fidelity pin; not sim-driven —
      tracker).
- [x] Macros fold a resolvable component; the three incomplete surfaces name
      the sub-recipe reasons from the shared helper (host-tested; one such
      reason render is what scenario 6's overflow fix exercised on-device).
- [x] Tests cover the new logic (host + pgTAP + a sim scenario).
- [x] Docs updated: roadmap, tracker, `import-and-matching.md` §degradation
      + §6.1, `db-schema.md` (regen), gold `_review` + `_SCHEMA.md`
      resolution notes, QUALITY.md, app/AGENTS.md scenario count.

## Decision log

- 2026-09-01 — Step opened as a design phase. Owner's standing rule
  restated: **no UI until the design board contains the design; no new
  design where the board already carries one** — the new section extends
  the locked Recipe-view-v3 / review-card / picker-v2 / cook / shop frames
  and redraws none of them. D1–D9 drafted with recommendations; proposal
  frames drawn on the board (section "Nested recipes · v1", proposed tag).
  Found while drafting: extraction already captures `yield_raw` but commit
  drops it — the yield column (D2) is the missing half of the parked
  "what does the `1` count" ruling.
- 2026-09-01 — **Owner amendment to D2 (pre-sign-off): the yield takes up to
  two denominations** in different families ("makes 250 g · 16 tbsp"). Asked
  as "can we allow setting both g and tbsp"; adopted because two stated
  facts bridge mass↔volume for that recipe honestly — it dissolves the
  imported-`2 tbsp`-against-a-`250 g`-yield unresolved case without giving
  recipes density/measures machinery. Also recorded: the 7.7
  stored-selection admission rule carries over to component lines (a printed
  unit is always an admissible chip, rendered unresolved rather than
  rewritten). Board frames (b) and (d) updated to draw both.
- 2026-09-01 — **Owner-caught gap: no editor design existed** ("i still
  can't see a design for the recipe editor, e.g. on import, as amount will
  need to be user set probably?") — frame (b) *said* "edited beside
  servings in the editor" but nothing drew it, and the step-2 editor
  pre-dates the board discipline entirely. Added board frame (h) "Editor ·
  what it makes": the SERVES · MAKES numbers block (second denomination
  offers only the other families), and the import Review screen reusing
  the same row over the visible `yield_raw` source line — prefill only
  parses a plain `amount + known unit`, everything else is user-set
  (0014's servings attempt-then-flag precedent). D9 updated to carry it.
- 2026-09-01 — **Owner ruling on D9's back-links: a "Used in" tab**, not
  the drafted hero row ("maybe should be a new tab?"). Adopted as a
  **conditional** third tab — rendered only while the count is non-zero,
  count in the label ("Used in · 2") — because an always-present tab is an
  empty pane on most mains, while the hero row was cramped and buried the
  rows. Frame (b) redrawn; D9 text updated.
- 2026-09-01 — **Signed off: "D1–D9 as drawn."** Board section flipped from
  proposed to signed-off; build lanes launched (S → D → U → I), each as an
  Opus subagent per the owner's standing delegation instruction. One lane
  bookkeeping correction from the plan text: `buildCommit` is client-side
  Dart, so the `yield_raw` prefill parse moves from lane S to lane I
  (matching's recipe-title candidates stay in S — that part is the edge
  function).

## Notes / open questions

- Does the week-planner's recipe picker need to *hide* pure-component
  recipes (an aioli as Tuesday dinner is odd but harmless)? Leaning no —
  plan anything; the cook plan just batches it. Not a D; flag at build if it
  grates.
- The cook-day for a component session currently derives as the parent's
  cook day; a persisted override is the same tracker debt as step 5's.

## Step-done checklist

The code landing is not the step landing. Tick these before setting Status to
done and moving this file to `completed/`.

- [x] Roadmap row updated: status flipped, one line on what shipped and what
      was deliberately deferred.
- [x] `docs/QUALITY.md` grade for every area touched matches reality (five
      rows annotated).
- [x] `app/AGENTS.md` "Current focus" and command list still true (smoke
      section now says six scenarios).
- [x] Feature steps: `make test-sim` run on a booted simulator — **6/6, All
      tests passed (3m30s, iPhone 17, live local stack)**, re-confirmed on
      the committed tree; two real bugs found on-device and fixed
      (`1151041`, `d4837c3`).
- [x] Tech-debt rows **added** (import leg sim gap · method-step refs ·
      scenario-2 flake · single-word fuzzy · singularizer divergence) and
      **retired** (the 2026-08-31 "nested recipes are deferred" row).
- [ ] New migrations or seed changes? **`0017` + the function's recipe
      matcher have NOT reached cloud** — the deploy workflow is being
      reworked in a parallel session; the roadmap row says so. Push + ledger
      entry when it lands (the one open box on this list).
- [x] `make ci` green (run at close-out, 2026-09-02).
