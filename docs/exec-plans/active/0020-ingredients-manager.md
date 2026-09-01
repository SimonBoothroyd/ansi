# Exec plan: Ingredients manager — the vocabulary gets a face

- **Status:** in build — signed off 2026-08-31 (D1–D8 as recommended). Lanes S
  (server: 0014 + 0015), M (domain + manager UI) and B (barcode) have merged;
  the post-convergence **polish pass** (D4b, F1, F2, F3, D7b + migration 0016)
  is landing on top. The seed-stub-zero chore is deferred by owner ruling.
- **Owner:** Simon + Claude (design phase solo, before any fan-out)
- **Roadmap step:** Step 8.5 — Ingredients manager
- **Created:** 2026-08-31

## Goal

Give the household vocabulary a screen. Today `ingredient` is written by the
seed, by the picker's add-new, and by import — and read everywhere — but there
is **no place to look at it or change it**. This step lands: a list of the whole
vocab (search, stub surfacing), an ingredient **detail / flesh-out form** that
owns `allowed_units`, density, macros, `canonical_name` and aliases, and can
**confirm a stub into `complete`**; plus **add-from-barcode**. Server-side it
lands the [ADR-0008](../../decisions/0008-unit-admission-model.md) density
amendment, wires the USDA stub prefill that has never fired, and closes the stub
`match_text` divergence.

Observable done: you can open Library ▸ Ingredients, find "Curry leaves, fresh",
see it is a stub, fill it in, confirm it, and watch a recipe that uses it stop
saying `incomplete` — and you can scan a tin of coconut milk and get a real
ingredient row out of it.

## Non-goals — the scope fence

Named here so they don't creep in mid-build. Each is a real thing someone will
ask for; each is a separate slice.

- **Nutrition-label OCR.** Photographing a label and reading the panel. Barcode
  is a primary-key lookup and deterministic; OCR is extraction, i.e. step 8's
  machinery pointed at a new target. Out.
- **Non-food items in the vocab.** Paper towels stay what step 6 made them —
  free-text shopping rows with no `ingredient_id`. The vocabulary is food.
- **Bulk edits / multi-select.** No "set category on 12 rows". A 300-row vocab
  edited by two people does not need it, and it is the fastest way to write a
  wrong density 12 times.
- **Merging two ingredients into one.** Real (import will mint a near-duplicate
  eventually) and genuinely hard — it has to rewrite line items, contributions,
  measures and aliases. Its own slice; tracker row at close-out.
- **Writing back to Open Food Facts.** We read. Contributing corrections
  upstream is a different consent conversation.
- **Barcode anywhere but ingredient creation.** No scan-while-shopping, no
  scanning to check off a list item.
- **Editing the `usda_food` reference set** or exposing it as a browsable
  catalogue. It stays server-only (ADR-0005); the form reaches it only through
  the prefill lookup (D7).
- **Recipe-side changes.** Nothing in `features/recipes` moves. If confirming a
  stub makes a recipe's macros compute, that happens because the data changed,
  not because we touched the recipe code.

## What already exists — read this before drawing or building

This step is **not** a blank page. The design board has carried an ingredient
editor, a barcode flow and a stub queue since the original board, and 7.7/7.8
grew two more frames onto them. The build re-traces and extends these; it does
not invent a parallel design.

| Existing board frame | What it already settles |
|---|---|
| **New ingredient** · create → flesh out | The form's spine: canonical name · "Also known as" alias chips · category + default unit · density · macros per 100 g · a **Source** segment (USDA FDC · Manual · Barcode) · a stub status line · a save CTA |
| **Barcode add** (tagged `stretch`) | **Open Food Facts** is the named source, with an ODbL attribution line; an in-app camera reticle; the result card is product name + brand + barcode + macros; the CTA is "Add as ingredient" |
| **Fleshing-out queue** · stubs before they count | A pushed screen titled "Ingredients" (back chevron, **no bottom nav**); stub rows with a per-row "needs …" hint; the honest-numbers explainer; the USDA/CC0 provenance footer |
| **Macros basis** (`pv2-d`, 7.7) | Macros are entered **as the label reads** — a per-100 g / per-100 ml segment, basis stored not converted |
| **Allowed units** (`pv2-d2`, 7.8/ADR-0008) | The admission section: basis shown · family pre-ticked · dashed chips that unlock with a density · density both-ways entry · measures list · category-gated imprecise toggle |
| **Manage measures** (`pv2-b2`, 7.7/7.8) | Measure rows with provenance dots read in words; the density g/ml ⇄ "a spoon weighs N g" pair; the volume-label redirect |

**Consequently these are recorded as settled, not reopened:** the product-data
source is Open Food Facts (D1 narrows only to *which parts of it we trust*); the
barcode entry point is the New-ingredient form's Source segment; the form's
field order and the allowed-units section's anatomy; the screen is a pushed
route, not a tab (D8 confirms against the `/import` precedent rather than
re-deciding); aliases are editable.

**What is genuinely open** is what the board could not have known: the ADR-0008
density gap found in the step-8 review (D4), the stub-lifecycle rows that were
parked behind the never-built form (D5–D7), and *where the network call runs*
(D2) — a question that only exists because step 8 established an edge-function
precedent after these frames were drawn.

## Decisions for sign-off

Each carries options and a recommendation. The recommendation is what the board
frames draw; alternatives are annotated on the frames.

---

### D1 — What we trust from Open Food Facts

*Source is settled (board: "Barcode add"). Open: what a lookup may write.*

Verified live, 2026-08-31: `GET https://world.openfoodfacts.org/api/v2/product/
{barcode}.json?fields=…` returns 200 with **no key and no account**, honouring a
`fields=` projection. `nutriments` carries `energy-kcal_100g`, `proteins_100g`,
`carbohydrates_100g`, `fat_100g`, plus `nutrition_data_per` telling you whether
the panel was per 100 g or per serving. `quantity` gives the pack size ("400
ml"). Coverage sanity check: **193,525** products tagged `en:united-kingdom`.
Licence: database ODbL, contents DbCL, images CC-BY-SA — the board's existing
ODbL line is right.

- **(a) OFF only, and a lookup may complete a row.** What the existing frame's
  caption says ("imports as `complete` — macros come with it").
- **(b) OFF only, and a lookup **prefills a draft** — never completes a row.**
  OFF is volunteer-entered and unevenly populated; a product with a blank or
  absurd `energy-kcal_100g` is common. Under never-invent, an absent macro must
  render absent, and a machine-supplied number is confirmed by a human before it
  counts (see D5).
- **(c) OFF with a USDA-branded-foods fallback.** More coverage, a second
  ingest pipeline, and a second provenance format to keep honest.

**Recommendation: (b).** Same source, one caption changed. The scan fills name,
brand, pack quantity and whatever macros exist, stamps
`source = 'off:<barcode>'`, and hands you the form with the Confirm button
waiting. Where OFF has no macros the fields stay blank and honest rather than
zero. *This diverges from the existing frame's caption and is annotated as such
on the board.* Also decided here: `nutrition_data_per = "serving"` products get
their macros **left blank with a note**, not divided by a serving size we would
have to guess — per-serving panels do not convert to per-100 without the serving
mass, and OFF's `serving_size` is free text.

---

### D2 — Where the barcode lookup runs: on-device or an edge function

- **(a) On-device HTTP.** `package:http` from the app, a pure-Dart mapper in
  `domain/` turning the JSON into an ingredient draft.
- **(b) A `product-lookup` edge function.** Mirrors `import-recipe`.
- **(c) Edge function with a server-side response cache.**

**Recommendation: (a) on-device.** The import precedent argues *against* copying
itself here. `import-recipe` is server-side for two reasons that both fail to
apply: it holds `ANTHROPIC_API_KEY` (OFF needs no key) and it spends real money
per call, which is why it grew a household allowlist (`auth.ts`). Neither is
true of a free, keyless, public GET.

Three more reasons, in order of weight:

1. **Rate limits are per IP** — 15 req/min for product reads. An edge function
   pools *every household* behind Supabase's egress address onto one budget; on
   device, each phone spends its own. This is not theoretical: during this
   research the anonymous **search** endpoint returned a 503 "not available to
   anonymous users / registered users are not subject to request limits" page
   while the barcode read succeeded — pooling makes that class of failure worse.
2. **ADR-0004 does not cover this.** "Matching is online-only" is about *fuzzy
   matching against a vocabulary* — ranking, thresholds, calibration. A barcode
   is an exact primary-key fetch: no ranking, no scoring, nothing to calibrate.
   Worth stating explicitly because it looks superficially like the same shape.
   The vocab search *inside* the form is the same offline local search the
   picker already does (spec §10, left column).
3. **Boring dependencies.** One `http` call and a pure mapper, versus a deployed
   function with its own JWT gate, deploy step, secrets story and test harness.

Costs, accepted: OFF asks for a `User-Agent` of `AppName/Version (contact)` —
fine to send from the app. Offline, the scan fails cleanly back to the form
("no connection — enter it by hand"), which is what an edge call would do too.
The mapper being pure Dart means it is tested off committed JSON fixtures with
no network in CI.

**Escalation trigger, recorded now:** if OFF starts requiring an account for
product reads, this becomes (b) — the mapper is already the reusable half.

---

### D3 — Scanner plugin, and the camera permission

- **(a) `mobile_scanner`** (`^7.4.0`, verified publisher steenbakker.dev; 2.3k
  likes, 160 pub points, ~1.28M downloads; last publish ~6 weeks before this
  plan). Ships the camera preview *and* the detector. On **iOS it uses
  AVFoundation + Apple Vision** — no ML Kit binary, so the bundled-vs-unbundled
  ML Kit size question is an Android-only concern we don't have yet.
- **(b) `google_mlkit_barcode_scanning`** — detection only; you bring and drive
  your own camera preview. More of our code, more to get wrong.
- **(c) No scanner: type the digits.** Zero dependency, and every barcode is
  13 digits of squinting.

**Recommendation: (a), with (c) always present as a sibling.** A "enter the
number" field sits under the scanner permanently — it is the no-permission
fallback, the damaged-label fallback, **and the only way this path is
exercisable in the iOS Simulator**, which is where `make test-sim` verifies. A
camera-only design would be untestable in our verification loop.

**iOS plist:** `NSCameraUsageDescription` **already exists** in
`app/ios/Runner/Info.plist`, worded for import ("…photograph a recipe to import
it"). It must be **widened**, not added — e.g. "Mise uses the camera to
photograph a recipe, or to scan a product barcode." One string; note it so it
isn't missed. `mobile_scanner` needs no other entitlement on iOS. Permission
denial is a designed state, not a crash (board frame d).

---

### D4 — ADR-0008 amendment: density unlocks volume regardless of default family

The tracker's cup-produce row found this: ADR-0008 §2 says a density "unlocks
the whole other family", but both implementations gate the density leg on the
default unit's family —

```dart
// allowed_units.dart
if (ingredient.densityGPerMl != null &&
    (d.family == UnitFamily.mass || d.family == UnitFamily.volume)) { … }
```
```sql
-- 0012_unit_admission.sql
if p_density_g_per_ml is not null
   and default_family in ('mass', 'volume') then …
```

— so a **piece-default** row with a perfectly good density (mango, tomato,
onion, avocado) admits no volume unit at all, and "1 cup diced mango" fails
`Pick a supported unit` on import. The seed papered over it for 49 produce rows
with a category-gated `allowed_units` patch (`seed_curation.sql`), explicitly
labelled as standing in "until ADR-0008 is amended".

**Amendment text** (replaces ADR-0008 §Decision ¶2's second sentence; the ADR
gains a dated *Amended* note, per ADR-0001's append-not-rewrite habit):

> **A stored density unlocks the other mass/volume family for the ingredient,
> whatever the default unit's family.** Density is a property of the substance,
> not of how the shop sells it: a mango is bought by the piece and still has a
> cup. For a mass- or volume-default row the unlocked set is the *other*
> family's kitchen workhorses, as before. For a **count- or imprecise-default**
> row there is no "other" family, so the density unlocks **both** families'
> workhorses, minus what the basis leg already admits. The unlocked units stay
> demoted below the measures in chip order.

Options on the shape:

- **(a) Amend the rule in `default_allowed_units()` + `densityUnlockedUnits`,
  and delete the seed's produce patch.** One source of the fact.
- **(b) Amend the rule and keep the seed patch as belt-and-braces.**
- **(c) Don't amend; extend the seed patch to cover more categories.**

**Recommendation: (a).** (c) is the status quo that already failed. (b) is the
"two stored copies of one physical fact" that ADR-0008 itself rejects for
density — and a seed `||` patch cannot help a household that creates a
piece-default ingredient *in the app*, which is the actual bug. The safety net
belongs in a **test**, not a duplicated write: a pgTAP assertion that every
produce row with a density admits `cup` after migration, and matching Dart
vectors. Keep the seed's genuinely non-derivable per-row overrides (liquid smoke
`tsp`; allspice/clove/nutmeg `tsp`; hot sauce/sriracha/soy sauce `to_taste`) —
those are not density-derived and have nowhere else to live.

**Migration shape** — `supabase/migrations/0014_density_admission.sql`:

1. `create or replace function default_allowed_units(...)` — drop the
   `and default_family in ('mass','volume')` guard; add the count/imprecise
   branch (`tsp,tbsp,cup,ml` + `g`, `kg` when big, minus the basis leg's).
2. **Backfill by UNION, never by replace.** `allowed_units` is user-owned after
   creation (0012's comment is explicit). So:
   `update ingredient set allowed_units = allowed_units || <density-unlocked>
   where density_g_per_ml is not null and not allowed_units ? '<unit>'` —
   across all households, not just the template. A re-materialize would silently
   discard a household's own edits, which is exactly what this step is building
   a UI to make possible.
3. Dart mirror in `allowed_units.dart` (`defaultAllowedUnitSet` **and**
   `densityUnlockedUnits`, which today returns `const {}` for count/imprecise —
   that is the same bug on the in-app density-write path).
4. Shared vectors extended on both sides (`supabase/tests/unit_admission.sql`,
   `app/test/features/ingredients/allowed_units_test.dart`).

**Found while reading, fix in the same migration:** the two mirrors *already*
disagree. Dart's imprecise leg adds `[pinch, dash, handful, toTaste]`; the SQL's
adds `array['pinch','dash','to_taste']` — **`handful` is missing server-side**.
The shared vectors evidently don't cover an imprecise-gated row. Pin it.

---

### D5 — What flips a stub to `complete`

- **(a) Automatic once density **and** macros are non-null.** What the existing
  board frame's status line says: "completes once density + macros are set."
- **(b) Explicit user confirm; macros required, density optional.**
- **(c) Hybrid — auto for values the user typed, confirm for machine-supplied
  ones (USDA prefill, barcode).**

**Recommendation: (b).** Two independent reasons:

*Why confirm, not automatic.* The server code already assumes it —
`prefillStubFromUsda`'s contract is "The row STAYS `status='stub'` until the
user confirms — the prefill just means the New-ingredient screen opens
pre-populated." Under (a), wiring that prefill (D7) would silently promote a
trigram guess straight into every macro total: never-invent, violated by a
background job. (c) encodes the same insight but makes `status` depend on
*provenance of each field*, which is a rule nobody will remember in six months.

*Why density is not required.* An ingredient whose lines only ever speak its
basis family — yeast in tsp/g, eggs by the piece — never needs a density.
Demanding one either blocks the user or invites a made-up number. So the gate is
**`macros != null` (with its basis)**; density stays optional and simply leaves
the cross-family chips locked, which the form already shows as dashed chips.

*Consequence to accept:* this contradicts the board's queue rows ("needs
density · macros") and product-spec §"Fleshing-out queue" ("stub ingredients
needing density/macros"). Both get reworded: **needs macros** is the block,
"no volume units — add a density" is an advisory hint on the same row. Drawn on
the board; spec edit listed in acceptance criteria.

*Also decided here:* confirm is **reversible** — a `complete` row whose macros
are cleared returns to `stub` rather than sitting as a lie. And the flesh-out
form is reachable for `complete` rows too: this is an ingredient **editor**, not
a one-way queue.

---

### D6 — Closing the stub `match_text` divergence

The app writes `match_text` with its character-level normalizer; the server's
phrase rules (singularize, filler/measure/prep word classes, form-word
reordering) live in `supabase/functions/_shared/normalize.ts` and are not
callable from Dart. So a locally created stub can carry a `match_text` the
server would never have written — and the next import's cascade searches by the
server's rules and misses it.

- **(a) Port `normalize.ts`'s phrase rules to Dart**, with shared test vectors
  pinning the two in step — the pattern `default_allowed_units()` already uses
  for its SQL⇄Dart mirror.
- **(b) A Postgres trigger rewrites `match_text` for
  `source in ('manual','import_stub')` rows.**
- **(c) A tiny `normalize` edge function the save path calls, with the local
  normalizer as the offline fallback.**

**Recommendation: (a).** (b) sounds cheapest until you notice normalize.ts is
TypeScript and a trigger would be plpgsql — a **third** copy of the word sets,
strictly worse than two. (c) adds a network round trip to typing a name, and
still needs (a) as its offline fallback, so it is (a) plus a function. (a) also
keeps stub creation genuinely offline-capable, which the picker's add-new and
import's commit both are today. The port is mechanical: ~250 lines that are
mostly word sets.

Honest cost: a third mirror to keep in step. The mitigation is the same one the
repo already trusts — a shared vector file both sides' tests read, so drift
fails CI rather than failing an import six weeks later.

**New requirement this step introduces regardless of which option wins:** the
flesh-out form must **re-write `match_text` when `canonical_name` changes**.
Today nothing renames an ingredient, so nothing had to; from this step on, a
rename that left the old `match_text` would be a silent matching regression.

---

### D7 — Firing `prefillStubFromUsda`

`prefillStubFromUsda` exists, is unit-tested, and **has no caller** — a stub
syncs up and nothing enriches it. It must stay server-side: `usda_food` never
syncs to a device (ADR-0005).

- **(a) A Postgres `after insert` trigger on `ingredient where status='stub'`**
  — a plpgsql port of the function's one `similarity()` query + one `update`.
- **(b) An `enrich-stub` edge function the client invokes after commit.**
- **(c) Only on demand: a "Look up in USDA" button on the flesh-out form.**

**Recommendation: (a) + (c) together.** (a) means a stub is enriched by the time
it syncs back down — the user opens a pre-populated form without asking, which
is what the prefill was designed for. (c) covers what (a) can't: rows the
trigram missed, and **renames** (you fix "curry leafs" → "Curry leaves, fresh"
and want the lookup re-run). (b) needs a new deployed function plus an
auth gate, and breaks the offline commit path that step 8 deliberately built.

Two things the trigger must get right, called out so they land in the migration:
it runs **inside the client's upload transaction**, so it must be cheap (one
indexed trigram query — `usda_match_trgm` exists) and it must **never fail the
upload**: wrap the body, no-op on any exception. Threshold stays
`USDA_PREFILL_MIN = 0.5`, and the row stays `stub` (D5).

Follow-on: the TypeScript `prefillStubFromUsda` then has no caller again.
**Delete it with its tests** — the same doctrine `match_db.ts` already applied
to `writeCorrectionAlias` ("deleted rather than left as a second, drifting way
to write the same row"). If the owner would rather TS stay authoritative, that
is a vote for (b).

---

### D8 — Where the page lives

*Effectively settled by the existing board frame — the "Fleshing-out queue"
frame draws a back chevron and no bottom nav, i.e. a pushed route.* Confirmed
against code rather than re-decided:

- **(a) A fifth bottom-nav tab.** The bar is `Library · Week · Cook · Shop` —
  those four are the *loop*. A vocabulary manager is reference data, not a step
  of the loop, and a fifth item crowds `FBottomNavigationBar` on a 375pt phone.
- **(b) A pushed `/ingredients` route from the Library header menu**, beside
  "Import a recipe" — the exact precedent `/import` set in step 8
  (`library_view.dart`'s `FPopoverMenu`).
- **(c) Settings-adjacent.** There is no settings screen; the popover's second
  group is just Sign out.

**Recommendation: (b).** Two extra doors, both cheap and both earned:
the menu item carries a **stub count badge** so the queue is discoverable
without hunting; and the picker's "add a new ingredient" plus the import review
screen's create-ingredient path **deep-link into the same detail form**, so
there is one flesh-out surface, not a second inline one.

---

## Approach — a small DAG

```
W0  this plan + board frames  →  owner sign-off
         │
         ├── A  server        0014 migration: D4 amendment + union backfill,
         │                    D7 prefill trigger, pgTAP; delete the TS prefill
         ├── B  app           vocab list + ingredient detail / flesh-out form
         │                    (D5 confirm semantics, allowed-units editor,
         │                    density both-ways, macros+basis, aliases, rename)
         ├── C  barcode       mobile_scanner + OFF client + pure mapper + plist
         │                    (needs B's draft model — B publishes it first)
         └── D  normalizer    normalize.ts phrase rules → Dart + shared vectors
         │
         └── tail  sim scenario · ADR amendment · spec §6/§9 · board lock ·
                   tracker rows retired · roadmap row
```

A and D are independent of everything. B is the long pole. C depends only on B's
ingredient-draft model, so B ships that type first and C proceeds in parallel.
If it is being built by one agent rather than fanned out, the order is
A → B → D → C → tail.

## Acceptance criteria

- [ ] `docs/exec-plans/active/0020-ingredients-manager.md` (this file) signed off
      by Simon, with a decision recorded for D1–D8.
- [ ] Design board carries the "Ingredients manager · v1" section, re-tracing and
      extending the existing frames, with every divergence annotated.
- [ ] **List page:** the whole household vocab, searched with the same
      deterministic local search the picker uses; stub rows badged; honest
      capability hints per row (category · density · measure count).
- [x] **Detail / flesh-out form:** edits `canonical_name` (re-writing
      `match_text`), aliases, category (a **dropdown** of the household's own
      categories since F3 — free text is gone), default unit, macros + basis,
      density both ways, **measures** (the shared 7.7 editor, embedded since
      F2), and **`allowed_units`** — the ADR-0008 section that has never
      existed, with its cross-family half now density-derived per **D4b**.
      Reachable for `complete` rows, not just stubs.
- [ ] **Confirm a stub:** gated per D5; reversible; a recipe using that
      ingredient stops reading `incomplete` without further action.
- [ ] **Barcode:** scan or type a barcode → OFF lookup → prefilled draft →
      confirm. No-permission and not-found states are designed, not crashes.
- [x] `default_allowed_units()` and `defaultAllowedUnitSet` agree on extended
      shared vectors **including** a piece-default-with-density row and an
      imprecise-gated row (the `handful` divergence).
- [x] A stub created in-app and a stub created by import land the **same**
      `match_text` the server's normalizer would write (shared vectors). The
      last residual — import's commit still calling `normalizeSearchQuery` for
      the stub row and the correction alias — is closed, with a repo test that
      pins a case where the two normalizers genuinely differ.
- [x] A stub inserted server-side is USDA-prefilled and still reads `stub`
      (0014 insert leg + 0015 rename leg, pgTAP). **D7b** adds the client
      leg: migration 0016 exposes the same probe as `probe_usda(name)`, a
      security-definer read-only RPC, so a creation flow enriches at birth and
      "Look up in USDA" is a real query — and the row still reads `stub`.
- [ ] Tests cover the new logic: pure-Dart mapper + normalizer + admission
      vectors (unit), form and list (widget/repo over the real-schema harness),
      migration (pgTAP).
- [ ] Docs updated: ADR-0008 amended; product-spec §Ingredient + Fleshing-out
      queue reworded for D5; `import-and-matching.md` §9's two "honest gaps"
      struck; `app/AGENTS.md` focus; `docs/QUALITY.md`.
- [ ] Tracker rows **retired**: flesh-out form; cup-produce/ADR-0008 gap;
      server-arriving density not extending `allowed_units`; stub `match_text`
      divergence; `prefillStubFromUsda` not triggered.

## Decision log

Append-only.

- 2026-08-31 — **Design phase opened.** No app code, no simulator, no
  `supabase/` edits: this step's first deliverable is a signed-off plan plus
  board frames, following the [0014](../completed/0014-import-foundation.md)
  precedent where design froze before any fan-out.
- 2026-08-31 — **The board already had this screen.** An ingredient editor, a
  barcode flow and a stub queue predate this plan (plus 7.7's macros-basis and
  7.8's allowed-units frames). Recorded as settled: OFF as the source, the
  Source-segment entry point, the form's spine, aliases editable, a pushed route
  rather than a tab. Reopened only where later learning conflicts.
- 2026-08-31 — **OFF verified live, not assumed.** Keyless 200 on
  `/api/v2/product/{barcode}.json` with a `fields=` projection; 193,525 UK
  products; macros as `*_100g`. The anonymous **search** endpoint 503s with a
  "registered users are not subject to request limits" page — which is the
  evidence behind D2's per-IP argument.
- 2026-08-31 — **ADR-0004 does not reach a barcode lookup.** Exact-key fetch,
  not vocabulary matching. Stated explicitly so the on-device recommendation
  isn't read as eroding the invariant.

## Notes / open questions

- **`ingredient` deletion is not decided.** The form will want a delete. A row
  referenced by a live recipe line cannot go (the FK is NOT NULL by design —
  0014's commit contract). Suggested rule, for the owner to confirm at sign-off:
  soft-delete only when no live line references it, otherwise refuse with the
  count ("used by 3 recipes"). Not in the acceptance criteria until decided.
- **Density famine tail.** 30 vocab rows still have no density and FAO has
  nothing more for them (tracker). This step gives them a *place to be fixed by
  hand* — it does not fix them. Not an acceptance criterion.
- **`macros_basis` on a barcode row.** OFF panels are per 100 g **or** per 100
  ml and say which. The mapper should carry that straight into `macros_basis`
  rather than defaulting to `g` — cheap, and exactly what 7.7's basis decision
  was for.
- **A measure from a pack size.** OFF's `quantity` ("400 ml") is a ready-made
  measure row ("can = 400 ml"). Tempting and in-scope-adjacent; suggest offering
  it as an opt-in checkbox on the barcode result, not writing it silently.

## Step-done checklist

- [ ] Roadmap row 8.5 updated: status flipped, one line on what shipped and what
      was deliberately deferred.
- [ ] `docs/QUALITY.md` grade for every area touched matches reality.
- [ ] `app/AGENTS.md` "Current focus" and command list still true.
- [ ] Feature steps: `make test-sim` run on a booted simulator, result recorded
      here — including the barcode path via the **typed-number** fallback (the
      simulator has no camera; D3).
- [ ] Tech-debt rows **added** for corners knowingly cut, and **retired** for
      the five rows this step pays off.
- [ ] `make ci` green.
- 2026-08-31 — **Owner sign-off.** D1–D8 decided as recommended (D1 prefill-
  never-complete overrules the old frame caption; D5 macros-gate-completion
  overrules the board/spec wording — both edits are in the acceptance
  criteria). Deletion (the open question) is IN SCOPE with the proposed rule:
  soft-delete only when no live line references the ingredient, else refuse
  showing the count. Build fan-out launched: lane S (server — migration 0014,
  ADR-0008 amendment, prefill trigger, TS deletion, seed-patch retirement),
  lane M (domain + manager UI — normalize port, rename hazard, list/form/
  delete, /ingredients route), lane B (barcode — scanner sheet, on-device OFF
  client, draft mapper), converging like step 8's DAG.
- 2026-08-31 — **D4b (owner, from live exploration of the shipped form).** The
  allowed-units editor offered both families freely; ruled instead: the
  **basis family** (per-100g ⇒ mass, per-ml ⇒ volume) is always admitted; the
  **other family is density-derived** — admitted while a density is saved
  (ADR-0009's unlock) and **stripped when the density is deleted**. Editor
  renders cross-family chips locked with a "needs a density" hint when no
  density exists. Lines already using a stripped unit degrade to the existing
  `unitNotAllowed` flag, never rewritten. Count/imprecise untouched. Refines
  ADR-0009: union-never-remove still governs backfills/reseeds; density
  deletion is the one removal leg, because that admission was derived.
- 2026-08-31 — **Owner exploration findings (live on the sim), batch 1.**
  F1: "Look up in USDA" is a silent no-op on an UNSAVED add-new draft (the
  row doesn't exist to re-read; verified — no local row, empty ps_crud).
  Fix: the button is disabled until the row is saved, and the create flow
  offers save-then-lookup so the server prefill's round-trip is walked, not
  shrugged at. F2: measures are read-only on the flesh-out form ("added from
  a recipe line's quantity sheet") — wrong deferral on the manager screen;
  embed the 7.7 manage-measures editor here. F3: category becomes a dropdown
  of existing categories (+ add-new), not free text. All three land with the
  D4b implementation in the post-convergence polish pass.
- 2026-08-31 — **F1 widened (owner clarification).** The failed flow was
  rename-then-lookup on a SAVED stub (Black Rice → Chicken Breast) with the
  rename still unsaved in the form. F1's fix therefore covers pending EDITS,
  not just unsaved drafts: "Look up in USDA" flushes unsaved changes (save-
  then-lookup) before the re-read, and its helper copy explains the sync
  round-trip it is waiting on. Pairs with migration 0015 (rename re-fires
  the server probe on bare stubs only — fleshed-out rows are never
  re-probed, so a rename can never clobber confirmed numbers).
- 2026-08-31 — **D7b (owner, from exploration): enrichment should not wait for
  sync.** `usda_food` stays server-only (ADR-0005 unmoved), but the trigger's
  probe is additionally exposed as a `probe_usda(name)` security-definer
  function via PostgREST: creation flows call it at birth when online (an
  ingredient is born enriched), and "Look up in USDA" becomes a real probe-
  and-apply instead of a re-read; offline degrades to the 0014/0015 trigger
  path with honest copy. Fill-null-fields-on-bare-stubs-only throughout.
  Policy: stubs are TRANSIENT, not banned (offline + unknown-import paths
  need them); target is zero standing stubs. One-time chore added: drive the
  36 seed stubs to zero in the seed itself (FDC probe + hand curation/OFF
  for FDC-less rows).
- 2026-08-31 — **Polish pass landed (D4b, F1, F2, F3, D7b).** Five owner-ruled
  items, one commit each. **D4b**: `densityStrippedUnits` (derived, not
  listed) + `clearDensity` make the cross-family admission density-derived
  both ways; the basis family is always live; lines already saying a stripped
  unit degrade to `unitNotAllowed` and are never rewritten. ADR-0009 gains a
  refinement note drawing the boundary around its union-never-remove rule.
  **F1**: "Look up in USDA" flushes pending edits before probing (the
  rename-then-lookup flow), and the add sheet draws the button disabled with
  "save first" instead of a silent no-op. **F2**: the 7.7 manage-measures
  editor is extracted (as `DensityEntry` was) and embedded in the form; the
  barcode draft's `packSize` stopped being discarded and earns frame (e)'s
  opt-in tick, stored in the row's own basis and not offered at all where it
  cannot be bridged. **F3**: the category is a live dropdown of the
  household's own categories plus an add-new door. **D7b**: migration 0016
  lifts the trigger's probe into `usda_probe()` and exposes it as
  `probe_usda(name)` — security definer, read-only, granted to
  `authenticated` only; creation flows enrich at birth, offline degrades to
  the trigger path with honest copy, and the two writes are safe to race
  because both fill nulls only on bare stubs from the same probe. Also closed
  in passing: the import-commit `match_text` residual (D6), and a real
  reconciliation bug the F1 test exposed — conditional children in the form's
  `ListView` shifted their siblings onto the wrong elements, wiping hook
  state (the lookup's own note vanished exactly when it succeeded); the
  conditionals are stable slots now.

- 2026-08-31 — **Seed-stub-zero chore DEFERRED (owner).** The 36 template
  stubs stay for now; the D7b probe + barcode + manager badge are the live
  paths for whittling them. Revisit as its own small slice when it itches —
  the FDC-probe-offline + hand-curation approach is scoped above.
- 2026-08-31 — **Owner demo findings, batch 2** (guided sim run of the finished
  manager; the D7b flow itself verified live — rename → flush-save → probe →
  prefilled row, no sync wait). G1: after a successful lookup the OPEN form's
  macro fields do not refresh (row verified filled in SQLite; the banner is
  right, the fields are stale) — the ListView hook-state class the polish
  pass flagged. G2: the density row overflows 55px in its "none yet" state.
  G3: a superseded lookup status note lingers after the state changes. G4:
  a usda-prefilled stub's list hint still reads "needs macros" — it should
  read "needs confirm" (D5's language) once macros are prefilled.
- 2026-08-31 — **D4c (owner, batch 3): the default unit's family is NOT an
  admission source.** With no density, a row admits its BASIS family (+count,
  measures, gated imprecise) — full stop; the default-unit selector locks the
  other family's options too. A row whose current default unit violates the
  rule (cup-default, per-100g, no density — the renamed-rice shape) is
  flagged with a one-tap fix ("switch default to g"), never silently
  rewritten. The density-removal helper copy shrinks to one line COMPUTED
  from the row (it currently claims chips are locked when they aren't), and
  the form's helper prose generally gets an essay-trim. Existing lines in a
  now-locked unit degrade to the standard flag, as everywhere.
- 2026-08-31 — **Batch 2 + D4c landed.** G1: the macro fields re-seed from the
  refreshed row through a **row-version key** on the fields' stable ListView
  slot (the draft is re-seeded, and the key change rebuilds the four
  controllers around it), guarded so it only fires while the draft still says
  what the row last put there — a pending user edit outranks the row, and no
  sibling moves, so the polish pass's stable-slot rule holds. G2: the density
  header and the spoon phrasing are `Wrap`s; a `Spacer` cannot give room it
  has not got. G3: the lookup note moved into the form and carries the row
  version it was written about, so anything that moves the row on retires it —
  one place decides, and it is not the button. G4: a stub with macros hints
  **needs confirm**. G5/**D4c**: `_derivedSet` gates the default-unit mates
  leg on `density || default family == basis family`;
  `densityUnlockedUnits` becomes `derived(with) − derived(without)` (so a
  density landing on a cup-default per-100 g row finally unions `cup` itself,
  which the old cross-leg-only version did not) and `densityStrippedUnits` is
  the same rule read backwards; `allowedUnitsFor` subtracts the density-
  derived units while the number is missing, **including from an explicit
  list** — which is what makes the D4c(d) line degradation true for a stale
  server-materialized list, and closes a D4b half-landing where the editor
  drew a chip locked while the picker still offered it. The default-unit
  selector locks the other family, and a stranded default is flagged with its
  one-tap repair. G6: the density-gap note is one line computed from the
  chips actually drawn locked (it is silent when nothing is), and the form's
  prose lost every clause the UI already shows.
- 2026-08-31 — **The SQL admission mirror is deliberately left one rule
  behind (D4c).** `default_allowed_units()` (0012/0014) still counts the
  default unit's family, and `density_unlocked_units(p_default_unit)` is a
  function of the default unit ALONE — while the Dart unlock is now a
  function of the macros basis too, so parity needs a signature change, not a
  body edit. Not written in this batch, and recorded as tech debt instead,
  because: (a) nothing user-visible diverges — the app subtracts the
  density-derived units on read, so a row materialized under the looser rule
  is drawn locked and refused on a line exactly as if the server had written
  the strict list; (b) the one real gap is a density landing **server-side**
  on a cross-family-default row, where the trigger's union is short by that
  row's own family until an app-side edit re-materializes it; and (c) the
  fix must not touch existing rows — ADR-0009's union-never-remove governs
  server writes, and D4c is a derivation/edit rule, not a licence to backfill
  removals over households' own lists. The pgTAP vectors move with the
  function when it moves; `allowed_units_test.dart` carries the strict rule
  today.
- 2026-08-31 — **Batch 4 (owner exploration + agent verification gate).**
  H1: `make db-up` does not serve edge functions and no target existed — a
  photo import in the dev loop failed as "could not process this recipe"
  with twelve containers up and no edge runtime; `make functions-up` added,
  db-up now says so. H2: the client's unreachable-service error copy is
  misleading ("could not process this recipe" for a connection failure) —
  distinguish unreachable from rejected. **Scenario-5 ruling: option A.**
  mobile_scanner's `analyzeImage` is compile-time refused on the iOS
  Simulator (verified in the plugin's Swift source; deliberate upstream),
  so the sim path for scenario 5 is the TYPED barcode field (identical
  downstream handler), and **scan-from-photo ships in the on-device slice**
  alongside the camera-capture errands — not as a sim-only error state.
- 2026-09-01 — **Batch 5 (owner's Pixel field test — real cookbook photo import
  against cloud).** The extraction pipeline performed perfectly (every gold
  convention manifested: notes routing, to-taste, garnish portions, the
  catch-all collective); all failures are admission-layer or rendering. J1:
  a BLANK-LABEL collective renders as one atomic mega-chip and overflows the
  screen — must render as a wrappable run of chips. J2: unit-chip ranking
  inverted — three imprecise words outrank the ingredient's own measures
  (garlic's clove hidden behind "+1 more" while its printed unit); ALSO
  investigate why "1 clove" flagged at all when the cloud row carries the
  clove measure (review-path measure loading suspect). J3: imprecise
  category gates too loose — pinch/dash offered on kale; ruled: pinch/dash
  for spices/seasonings/oils only, handful stays for leafy. **D4d ruled:
  KEEP D4C STRICT, FIX THE DATA** — a density-seeding pass for volume-default
  rows lacking one (liquids: lemon juice-class; kale-class leafy produce),
  then cloud push (0014-0016, still pending) + reseed + §2b rollout so the
  owner's live household drains its stranded rows.

- 2026-09-01 — **Batch 5 landed (J1–J3), plus J4.** **J1**: a blank-label
  collective now renders as a wrappable RUN of chips — the fold leaves it
  label-less and its constituents (the same list the labelled case already
  carries) become the chips, separated by real text spans, unparenthesised,
  with any step portion on the first. **J2 — the ranking was never wrong.**
  `g piece pinch dash handful (+1 more)` is precisely what `rankedUnitChips`
  emits over an EMPTY measure list; the measures never arrived. The review
  read them through the per-ingredient autoDispose STREAM providers, and
  PowerSync's `watch` does not emit synchronously — an element disposed
  before its first emission completes `.future` with a `StateError` that the
  loader caught into `const []`, so every measure-word unit validated against
  nothing. The fakes hid it (`Stream.value` resolves before anything can
  dispose it). Both readers — `importValidation` and the card's amount-sheet
  pre-selection, the second of which only ever worked by riding on the
  first's subscriptions — now use a batched `measuresByIngredients`, one
  query for the whole import, nothing swallowed. `importValidation` also read
  its repositories after an await, which throws once the element is gone.
  Pinned by a real-schema provider test. **J3**: the imprecise gate is
  per-WORD by category — pinch/dash for `spices & seasoning` + `fats & oils`,
  handful for `produce` + `spices & seasoning`, `to taste` gated the same but
  unconditional on an import line; the import surface no longer unions all
  four onto every match. `produce` is the nearest thing the vocabulary can
  say to "leafy/greens": a tighter handful gate is a SEED question (split the
  category), not a domain one. The SQL mirror's own category gate diverges
  further — recorded with the D4c note, not edited. **J4**: the manager list
  branches on the search FIELD's own hook controller rather than on a query
  that can outlive the text that produced it, so an empty field is the whole
  vocabulary by construction. Caveat: the reported device flip does NOT
  reproduce in the widget harness (the round-trip test is green pre-fix), so
  J4 closes the contradiction structurally and still wants a sim confirmation
  before scenario 5 is called green.
