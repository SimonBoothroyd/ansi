# Feature: ingredients

**Roadmap:** steps 1, 7.6–7.8 and **8.5** (see `docs/exec-plans/roadmap.md`).

The household's controlled vocabulary and everything that reads or writes it:
the **picker** recipes and shopping select from, the **quantity + unit** entry
surface (chips, measures, density), the **manager** — the screen where the
vocabulary is browsed and edited, including turning a bare `stub` into a
`complete` ingredient — and the **price** a row was last bought at.

**The client never fuzzy-matches for a machine decision** (ADR-0004). Search
here is deterministic retrieval for a human to pick from, over the ~300 synced
household rows. The one network call in the feature is the barcode module's
Open Food Facts read — an exact-key fetch by product code, not matching.

## The surfaces

```
/ingredients            ingredient_list_view.dart    the whole vocab, stub band on top
/ingredients/new        ingredient_detail_view.dart  the form with no row behind it —
                                                     THE add door; `?name=` prefills it
/ingredients/:id        ingredient_detail_view.dart  the same form over a stored row

showIngredientPicker    ingredient_picker.dart       recipe editor, shopping top-up
   └── AddNewIngredientRow: push /ingredients/new → back → resolves with the row
showQuantityUnitSheet   quantity_unit_sheet.dart     every quantity+unit in the app
        └── manage measures + DensityEntry (density_entry.dart)
showUsdaPickSheet       usda_pick_sheet.dart         the USDA short-list a person picks from
showPriceSheet          price_sheet.dart             paid · for · at — the one door a price is entered through,
                                                     and, opened on a stored line, edited or deleted

scanBarcodeForDraft     barcode/barcode_add.dart     the barcode module's one door
applyDraft              domain/apply_draft.dart      how a draft lands on the form's fields
```

`/ingredients` is a **pushed** route reached from the Library's ingredients
shelf, not a fifth bottom-nav tab: the four tabs are the cooking loop, and a
vocabulary is reference data.

## One form, one Save

**The form is the add flow.** There is no separate new-ingredient sheet: a
creation is `/ingredients/new`, which is the same widget with no row behind it
yet. Every add-new door — the manager's ＋, the editor picker's footer, the
shopping top-up, the import review's create-new — pushes that route, and a
picker pushes it *over its own sheet* through `context.pushOnceFor` and awaits
the pop, so the quantity sheet that follows offers the units the form just set.

**A new row is saved complete or not at all.** The create form's dock draws one
button, `Save`, live only while `IngredientFormDraft.completable` holds — the
same gate `Mark complete` applies to a stored stub — and its write marks the
row complete. A stored stub keeps both buttons: the seed's stubs still need
fleshing out, and putting one down half-filled is what a stub is for. So none
of those doors can mint a bare stub any more; a person fills the row in, and
the line that was waiting resolves onto something that counts.

**Nothing is written until Save** ([ADR-0011](../../../../docs/decisions/0011-one-save-one-write.md)).
The form holds everything it intends — the row's fields, the density, the
measures added and removed, the aliases, the piece weight, and whether
to mark the row complete — as one `IngredientFormEdit`, and `saveForm` applies
the lot in a single transaction. `saveForm(null, …)` creates the row and its
children together. Two consequences the surfaces depend on:

- a form with no row behind it is coherent, and backing out of one leaves
  nothing to clean up — no stub is minted as a side effect of opening a screen;
- partial success is not representable. `Mark complete` saves and marks in the
  same statement rather than as two writes with a failure possible between them.

The measures and aliases travel as **deltas**, not replacement lists, so a
stream that failed to load can never become a narrowed set written back.

## One namespace: names and aliases together

A household's ingredient **names and aliases are one namespace**, keyed by
`match_text` (`domain/name_namespace.dart`). The seed's generator already
refuses a vocabulary where two rows — or a row and another row's alias —
normalize to the same text, and the import cascade's exact tier searches names
and aliases as one surface; the form is the third place that has to mean it,
because two live *Sauerkraut* rows make every exact match after them a coin
toss.

So a name or an alias that is already somebody's is **refused**, twice over:

- the form asks when the name field is left (and when an alias is added) and
  prints `Already an ingredient: Sauerkraut` under the field, with the existing
  name as a door onto that row; `Save` goes quiet while it stands;
- `saveForm` asks again **inside the write transaction** and returns
  `Err(nameTakenFailure(…))`, because a sync landing between the tap and the
  write would slip the second row past the first check.

A row never collides with itself, so re-saving a row under the name it already
has is always allowed.

**Every writer asks, not just the form.** `data/name_holder.dart` is the
question as SQL — `nameHolderFor(tx, matchText)`, the live row that already
carries the text as its own name or as one of its aliases — and every write
seam goes through it, inside its own transaction. A rule held by only some of
the writers is not held at all: an alias learned by the import's loop lands in
the same namespace as a name typed on the form, so "extra-firm tofu" corrected
onto *Super Firm Tofu* is refused there too — it is what *Extra Firm Tofu* is
already called.

Where the form *refuses*, though, the loop is simply **silent**: nothing is
learned and nothing is said, because the line has already resolved to the row
the human picked and that is the whole of what they asked for
(`docs/product-specs/import-and-matching.md` §8). The picked row owning the
text — the page printed what the row is already called, or an alias it already
has — is the same answer for a different reason: there is nothing to learn.
`test/structure/alias_writes_ask_the_namespace_test.dart` holds the rule
against the next writer.

The loop asks one thing the form does not have to: **is this a name at all?**
The form's writer typed one; the loop's arrives as whatever the recipe printed,
and a candidate carrying a comma, the word *or*, a slash or a bracket names more
than one thing ("olive oil or cooking oil of choice"). That one is skipped as
silently as a taken name — see `features/import/domain/learnable_alias.dart`.

And when the name is *nearly* somebody's, the form offers the near names under
the pickers' own `DID YOU MEAN` header — `searchRank`'s guarded typo tier over
every live name and alias, at most three rows, and only when nothing was
spelled right (`docs/design-docs/search-and-matching.md` §4). On
`/ingredients/new` tapping one asks before it acts and then pops the form with
the existing row, which is exactly what the door that pushed it was waiting
for. On a row that already exists the names are shown and nothing more:
renaming onto one of them would be a merge, and nothing here merges rows.

**There is no unique index, and there should not be one.** Migration
`0019_shopping_week.sql` states the general reason for its own rows: two
offline devices must each be able to mint a row and converge later, so Postgres
stays permissive. A constraint would turn a convergence into a sync error
nobody can act on; the app refuses a duplicate where somebody is looking at it
instead.

The draft is one `IngredientFormDraft` inside the `IngredientForm` notifier
(`ingredient_view_models.dart`); the view watches it and dispatches intents.
The two seams that need a `BuildContext` — the barcode scanner and the USDA
short-list — open from the view and hand their result back as an intent.

## USDA, and the barcode

A **USDA pick fills the draft**, exactly like typing does. *Fill it in from ▸
Look up in USDA* and *Choose another ▸* open the same short-list
(`usda_pick_sheet.dart` over `UsdaProbe.search`); the pick puts the food's
macros, its density and its provenance into the draft the form is holding, and
the form's own Save lands them. Nothing writes on the tap, and nothing about a
pick confirms the row. **Not this food** (`declineUsdaPrefill`) is the one USDA
act that writes on its own: it strips the prefilled density with the units it
alone unlocked, drops the macros, and leaves `source = usda_declined` — a
distinct fact from "nobody ever linked one", which the provenance line reads.

The query is the name **in the field**, not the stored row, so a rename can be
looked up before it is saved.

**The food is named, never keyed.** `source` holds a key — an FDC id, a
barcode — and no surface prints one: a person cannot look up `FDC 11216`, and
asking them to is asking them to be a lookup table. What every surface says is
`source_label`, the food's own name. `sourceProvenanceLine` (domain) is the one
rule two surfaces print under a row's name — the **manager list** row and the
**import review's identity cell** — as `usda · «description»` for a pick and
`barcode · «brand and product»` for a scan, muted, one line. The ingredient
**picker** is deliberately left out: it is a search surface, and a description
under every row is noise while you type. No label, no line: a row filled before
the column existed carries a stamp and no name, and says nothing rather than
inventing one. Nothing new is read on either surface — the manager's
`watchVocabulary` already selects the column, and the review's line rides on
the `LineValidation` built from the import's one vocab query.

The **form** says the same fact at the head of the macros section. A USDA pick
gets a card — the food, how much of the typed name it answers, and the two
doors — and falls back to the FDC id **only** on a row carrying no label, where
there is nothing else true to say. A scanned row gets the name on one line and
no doors: a barcode is not a match to refuse or re-choose.

**A row a human edited stops claiming its numbers are the source's.**
`source` is patch-shaped and survives a save (`source = COALESCE(?, source)`),
so without a second fact a row goes on naming a USDA food whose figures are no
longer on it. `ingredient.source_edited` (migration 0034) is that fact: one
synced boolean, set by the **three client write paths that can change a number
on a stored row** — `saveForm`, `setDensity` and `clearDensity` — and only
when the write changes **macros, the macros basis or the density** on a row
whose `source` is a lookup stamp (`isLookupFilled`: `usda_fdc:<id>` or
`off:<barcode>`). Nothing server-side writes it; there is no trigger.

The fence is the design: a rename, a unit toggle, a category, a measure, a
piece weight, an alias and `Mark complete` do not contradict the source
(a piece weight is a number, but not one a lookup supplies), so none
of them may set it, and a save that only touches those leaves the stored value
alone in both directions. A **fresh pick clears it** — the numbers are the new
food's — and so does *Not this food*, which leaves no numbers to have
overridden. Once set it is otherwise sticky: the source's own figures are not
kept on the row, so nothing can tell a number typed back to the food's value
from a coincidence. The provenance card's third state reads *Filled from USDA
· edited here* — the food still named, muted and never amber, because it is
provenance and not a warning — and the two list surfaces lead their line with
`edited ·`, as does the scanned row's own line.

**No machine matches on its own.** `usda_food` never syncs to a device
(ADR-0005), so the app asks the server through the read-only `probe_usda` RPC
(migration `0016`, widened by `0027` to name each candidate and take a limit).
The `ingredient_usda_prefill` trigger that used to enrich stubs on upload was
dropped in migration `0029`: a stub whose owner deliberately did not use the
search would otherwise come back filled one sync later, with a provenance line
claiming a match no human ever made. A stub with no macros is a good stub.

`source_score` is **coverage, not confidence** — the idf-weighted share of the
query the matched description accounts for. It is shown and never acted on.

The barcode module is the same shape: `scanBarcodeForDraft` returns an
`IngredientDraft`, a *sketch* that is never a row, and `applyDraft` lands it on
the form's fields — filling what is empty, keeping what a human typed, and
stamping `off:<barcode>` only where there was no source. The stamp travels with
a **name**: `packLabel` composes the brand and the product name as a shelf
prints them ("Kraft mac & cheese"), drops a brand the product name already
opens with, and returns null when Open Food Facts named neither — null meaning
*no line*, never a name assembled out of nothing. It rides the same Save as the
macros it explains, into `source_label`. No fit score comes with it: a scan is
an exact-key fetch, so there is no coverage of the typed name to report.

**Which 100 the panel is per is the mapper's one wide read** (`_basisFor`).
Open Food Facts files a per-100 ml label under the same `*_100g` keys as a
per-100 g one, and `nutrition_data_per` defaults to `100g` in its own entry
form — so a gram reading there is not a statement and is treated as unstated.
The evidence, strongest first: `nutrition_data_per` *naming* ml (however
spelt); the net quantity printed on the pack (`1,5 l` vs `1 kg`); then
`serving_quantity_unit`, which is weaker because OFF normalises a US
"1 cup (62 g)" into `ml`; then OFF's `en:beverages` category, last because the
drinks branch holds beans and leaves too. A basis says which unit the numbers
are per and nothing more — no density is ever implied by it.

## Layout

```
ingredients/
  domain/         PURE DART (no package:flutter)
    ingredient.dart          Ingredient + IngredientAlias (Freezed), the
                             provenance predicates, and the one source line
                             the list and the import review both print
    ingredient_repository.dart  the interface + IngredientFormEdit + DeleteOutcome
    allowed_units.dart       ADR-0008/0009 admission — the Dart mirror of
                             default_allowed_units() / density_unlocked_units()
    normalize.dart           the PHRASE normalizer — Dart twin of normalize.ts
    usda_probe.dart          the probe interface + its offline contract
    measure_repository.dart  named per-ingredient measures
    price.dart               the receipt, its lines, PriceObservation, and the
                             per-basis derivation with its density gate
    price_repository.dart    the price ledger's three reads and its three
                             writes — record, rewrite, take back
    apply_draft.dart         the one rule for landing a barcode draft on a form
    serving_measure.dart     the serving a label prints, kept as the row's one
                             `serving · 2 tbsp` measure — its label, and the
                             amount and unit read back out of it
  data/
    ingredient_repository_impl.dart  SqliteIngredientRepository — read + write
    measure_repository_impl.dart     measures, with merge-on-read for dup labels
    price_repository_impl.dart       the receipt ledger's watched reads
    usda_probe_impl.dart             the `probe_usda` RPC — the feature's one
                                     deliberate read that is not local SQLite
    ingredient_providers.dart        keepAlive repo providers + watch streams
  presentation/
    price_sheet.dart            paid · for · at, over the quantity sheet's own
                                chip row; the dock states the derivation, and
                                a stored line reopens it with a Delete
    ingredient_list_view.dart   the manager list
    ingredient_detail_view.dart the form — create at /ingredients/new, edit at /:id
    ingredient_view_models.dart IngredientForm — the form's draft and its Save
    usda_pick_sheet.dart        the USDA short-list and its candidate rows
    ingredient_picker.dart      the picker + the add-new chain's row
    measures_editor.dart        add/remove named measures, shared by two hosts
    serving_row.dart            the per-serving macro mode: "One serving is
                                [2] [tbsp]", the derivation line under the
                                four fields, and the pack's own two columns
                                checked against each other on a scanned row
    draft_card.dart             the barcode result card
    quantity_unit_sheet.dart    quantity + unit chips, manage measures
    unit_chips.dart             UnitChipRow, the unit dock over the keypad
                                (the chip itself is shared/unit_chip.dart,
                                which also holds the pick sheet a sentence's
                                unit chip opens)
    density_entry.dart          "1 [tbsp] weighs [__] g" on one row; folds
                                to "0.13 g/ml · change" once stated. Shared
    piece_weight_entry.dart     "1 piece weighs [__] g" — the same sentence
                                shape for the count fact; drawn only on a
                                piece-default row. Shared by both hosts
    macros_format.dart          the macro line as a string, and the one
                                display rounding rule behind every printed
                                figure — energy whole, grams to a decimal
    macro_line_text.dart        the same line as a widget, for the DENSE
                                surfaces: energy a flame, fibre a sheaf,
                                each carrying its word to a screen reader
  barcode/        the scan → lookup → draft module
    barcode_add.dart      scanBarcodeForDraft(context) — the ONLY public door
    barcode_scan_sheet.dart camera reticle + a permanent typed-number field
    off_lookup.dart       the on-device Open Food Facts GET + its failure states
    off_mapper.dart       payload → draft, PURE DART, four nutriment keys
    ingredient_draft.dart the hand-off type — a sketch, never a row
```

## The rules this feature exists to hold

- **Honest numbers, never zeros** (invariant 3). A `stub` shows its badge, not a
  0 kcal macro line. Anything a lookup could not establish stays **null with a
  reason attached** — the draft type, the mapper, and the form all preserve that.
- **Macros gate `complete`; density does not; confirming is a human act.** A row
  with no macros cannot be marked complete, so the gate holds below the disabled
  CTA. A USDA or barcode prefill fills fields and stops. Confirming is reversible
  (`unconfirm`).
- **Unit admission is explicit and per-ingredient** (ADR-0008). `allowed_units`
  is materialized at creation and thereafter **user-owned** — extended by
  writes, never silently re-materialized. Since
  [ADR-0009](../../../../docs/decisions/0009-density-unlocks-both-families.md) a
  density unlocks the other mass/volume family whatever the default's family;
  `setDensity` unions that in the same transaction, and `clearDensity` strips
  what the density granted. Since
  [ADR-0014](../../../../docs/decisions/0014-all-to-all-admission.md) a family
  is admitted **whole** — the basis family always, the other one behind the
  density — with no kitchen trim and no magnitude gate, so a gram-default row
  weighs in ounces and pounds and a cup-default one is sayable in teaspoons.
  What a household will never say, it prunes on the row itself: the admission
  chips offer every unit of both families and every imprecise word, and the
  only locked chips are the ones a density would unlock.
  `allowed_units.dart` and the SQL function are mirrors pinned by shared
  vectors — change one, change both.
- **A default unit the row cannot say blocks Save.** The chips refuse to offer
  a default outside the basis family while no density bridges it
  (`defaultUnitOfferFor`) — those units are *named* under the row instead, in
  the allowed-units note's own voice, so the person reads what a density would
  buy rather than tapping a chip that is about to be refused. The stored
  default is drawn whatever its state, because a basis flipped (or a USDA pick
  landed) after the default was chosen strands the one already there. The form draws the flag with its one-tap fix *and* refuses
  the write, naming the unit, the basis and both ways out — a density below,
  or the basis family's own unit. Nothing is rewritten silently: how a
  household buys a thing is a statement, so the person picks.
  **`piece` is the same rule with the other number** (ADR-0015): a `piece`
  default with no piece weight is stranded, reads *piece needs a weight on this
  row — enter one below, or switch to g*, and refuses Save the same way. Only a
  row created before that ruling can already be in that state.
- **A piece weight is a row fact, and it is what admits `piece`**
  ([ADR-0015](../../../../docs/decisions/0015-piece-weight-is-a-row-fact.md)).
  `piece_basis_amount` is what **one** of the row weighs, in its basis unit;
  `piece_source` says whether a person typed it or the seed borrowed it from a
  curated size. `piece` is admitted **iff the default unit is `piece` and the
  row states a weight** — never on a row with any other default unit — so
  setting the number unions `piece` in and clearing it strips `piece` out,
  exactly as `setDensity` / `clearDensity` do for the other family. Nothing is
  curated off a row and no measure is pointed at: measures stay the words for
  sizes, fragments and containers.
  - **A measure that weighs what the piece weighs is the row's word for one**
    ([ADR-0016](../../../../docs/decisions/0016-a-measure-that-weighs-a-piece-is-its-word.md)).
    `wholeMeasureOf` is the one reading — the live measure within 1 % of the
    piece weight, lowest `sort_order` then label — found by weight, never
    stored. The chip row leads with it and `piece (67 g)` stays offered after
    it; a row that weighs a piece but names no size leads with `piece`. What a
    caller naming no choice opens on follows from that, and from nothing else
    — see the chip row's own bullet.
  - **On the form**, `PieceWeightEntry` sits beside `DensityEntry` and is drawn
    only while the default unit is `piece`. It reports intent like every other
    shared editor (ADR-0011); the form's Save lands it with the rest.
  - **In the quantity sheet's manage state** the same editor writes on tap,
    because that host has no Save — so the `piece` chip appears the moment a
    weight is entered.
- **The chip row is one control, and one filter answers for it.**
  `allowedUnitChoicesFor` is what every quantity surface draws — the recipe
  line, the import review, the week's ingredient slot, the price sheet, the
  receipt's pack door — so a rule about what may be offered is written once.
  Two measures are never offered: one whose label merely names a volume unit
  (density owns volume, ADR-0008 §2) and the row's **serving**, which is the
  size a nutrition panel is printed per rather than one anybody cooks, plans
  or shops in (owner). Both stay re-selectable where a line already says one,
  through the off-filter admission every stored choice gets.
  - **A surface with nothing stored opens on the first chip**
    (`firstOfferedChoice`): the row's whole measure where it has one, else its
    first word, else the default unit — which is simply where the row's own
    words run out, since the catalog half fronts it. A surface that has
    something to reopen on — a line being edited, a pack in the words it was
    last bought in — passes that and never asks.
- **A price is an event, and the figure a screen reads is derived from it.**
  The ledger is `receipt` + `receipt_line` (migration 0044) and a hand-typed
  price is a one-line `manual` receipt, so a typed price and a scanned one are
  the same fact read the same way — one table, one ledger, and no separate
  observation row. `77¢ / 100 g` is computed at read time, never written back:
  a pack re-weighed or a discount corrected moves every screen at once. Money
  is integer cents throughout
  (`core/money.dart`); a discount rides beside the printed figure rather than
  inside it, and **what was paid is `cents - discount_cents`**.
  - **The pack is kept twice, and the two answer different questions.**
    `pack_basis_amount` is what the cents bought in the row's **basis unit**,
    beside `basis_amount` and `piece_basis_amount`, and it is the only number
    a figure is derived from. `pack_amount` with `pack_unit` (a units.dart
    catalog id) is what the person SAID — and where they tapped one of the
    row's own measures instead, `pack_unit` is null and `pack_amount` is the
    COUNT of it, with `measure_id` carrying the word (migration 0046). So the
    ledger prints `$3.49 for 1 lb` and `for bag (454 g)` rather than restating
    a pound as 454 g, while the per-100 figure goes on reading the basis. They
    must be able to disagree: a household that re-weighs its `bag` is saying
    what a bag is today, and last month's $3.49 bought last month's bag.
  - **The honesty gate is at entry.** `packInBasis` resolves the typed pack
    into the basis and refuses across mass↔volume without the row's density —
    the macros' own gate, on the same boundary — so the sheet's dock says why
    and Done is refused rather than a number being stored the row cannot
    support. In practice the chip row is the admission set, so a unit the row
    cannot convert is never offered; the dock's refusal is the backstop, and
    the one a person actually reaches is an imprecise word.
  - **A line that is not a price is not a zero.** No pack stated, not food, no
    ingredient (the server detaches a receipt line when its ingredient is
    retired — a receipt is history and never blocks a prune) and nothing paid
    all mean *no observation*, so the Price group says `— none yet` beside its
    own heading and offers one door.
  - **Every stored price is a tap, onto the sheet that entered it.** The Price
    group's *Latest* line and each row under *Before* reopen `PriceEditor` on
    that line — paid, pack and store as they were given — and Done writes an
    UPDATE (`updatePrice`) rather than a second receipt, keeping the day the
    price was paid on: an edit is a correction, not a second shop. A
    **Delete** under it soft-deletes the line after the app's shared confirm
    (`askAnsi`, destructive). The line's receipt moves with it **only when it
    is this app's one-line `manual` kind** — a photographed receipt is a piece
    of paper, so its store, its date and its printed subtotal stay as printed
    and the paper is never deleted from here.
- **A rename rewrites `match_text`** through `normalizeMatchText` in the same
  statement. The server writes `match_text` with the phrase rules; the app must
  write the same ones, or a locally created row carries text the next import's
  cascade would never find. Vectors in
  `test/features/ingredients/normalize_vectors.json` are copied from
  `normalize.test.ts` and pin the two implementations together.
- **Delete is refused while a live recipe line points at the row**, with the
  count. It is a soft delete, and the aliases go with it — an alias outliving
  its ingredient resolves to nothing.
- **Writes are view-safe**: local PowerSync tables are SQLite views, so every
  statement is a plain INSERT/UPDATE — a view rejects `ON CONFLICT`.
- **Mutations go through the keepAlive repo provider**, never a throwaway
  notifier held across an async gap.

## Tests

- Domain: `allowed_units_test` (the ADR vectors, shared with
  `supabase/tests/unit_admission.sql`), `normalize_test` (the shared JSON
  vectors), `apply_draft_test` (including the pack-naming rules),
  `ingredient_test` (the provenance predicates and the one source line),
  `price_test` (every refusal of the derivation and the entry gate, what is a
  price as against what is only a line of a receipt, and the two denominations
  a pack is kept in).
- Repo on a real `PowerSyncDatabase`: `ingredient_repository_test`,
  `measure_repository_test` — search/recents, `saveForm` create and edit,
  density round-trips, confirm/unconfirm, delete refusal, aliases — and
  `price_repository_test`, which also pins that the typed price is two rows in
  one transaction and both plain INSERTs, that an edit is a PATCH and never an
  upsert, and that a delete takes a one-line manual receipt with it and leaves
  a photographed one standing.
- Widget: `ingredient_list_test`, `ingredient_form_test`,
  `ingredient_usda_test`, `ingredient_macros_test`, `ingredient_picker_test`,
  `quantity_unit_sheet_test`, `ingredient_price_test`.
- Layout: `density_entry_test` — the density sentence holding one run at
  402 pt, its leading space, and the fold. It loads the real fonts
  (`test/helpers/fonts.dart`) because the test binding draws every glyph as a
  square of the font size, and a run-count measured under that face is a fact
  about the fallback typeface rather than about the app.
- ViewModel: `ingredient_form_notifier_test` asks the form's draft and its Save
  directly — what one call hands the repository, with no widget tree.
- Barcode: `barcode/` — mapper and lookup against committed fixtures (no
  network), the scan sheet's failure states, and the public door's contract.
- Server-side: `supabase/tests/receipts.sql` pins the price fact's shape — the
  closed enumerations, the fence that only a food line carries a pack in
  either denomination, the pack as entered beside the pack in the basis, the
  typed price as a one-line `manual` receipt, and the retire that detaches a
  receipt line instead of refusing. The admission functions are pinned by
  `supabase/tests/unit_admission.sql` (pgTAP), not by anything in this feature.
  `source_edited`'s column — its default, its round-trip, and that **no
  trigger** and no rename touches it — is pinned by
  `supabase/tests/source_edited.sql`; its writers and its non-writers are
  pinned in `ingredient_repository_test`.
