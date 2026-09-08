# Exec plan: the vocabulary unit audit — are the numbers each row carries honest?

- **Status:** complete — audit read against all 319 rows; the owner ruled on
  the nine flagged rows on 2026-09-08 (R1, R2 and R5 applied, the rest kept)
- **Owner:** Simon (rulings) · agent lane (sweep + fix)
- **Roadmap step:** field test, round six — the roadmap row lands with the
  round-six integration, not from this lane
- **Created:** 2026-09-08

## Goal

Re-read all **319** seeded vocabulary rows for the honesty of the numbers each
one carries — not for how generous its unit list is. The admission rule is
becoming **all-to-all** in a parallel lane (a per-100 g row admits every mass
unit, a per-100 ml row every volume unit, a stored density admits the other
family, and the user prunes per row in the flesh-out form), so "should this row
offer kg of saffron" stopped being a seed question. What is left is the seed's
own job: is the basis right, is the default unit how the household actually
buys the thing, is every stored density a number for *this* substance, and does
the `piece` ruling still describe the data.

Done: every row read against its USDA link and its measures; each defect either
fixed with a citable source or written into the ruling table below with a
recommendation; the seed regenerated and committed alongside.

## Acceptance criteria

- [x] All 319 rows checked on all six axes (stranded defaults, basis, default
      unit, density presence, `piece`, existing `allowed_units` overrides).
- [x] Every change carries a reason and a source in `curation_overrides.jsonl`.
- [x] No density invented: a defect is fixed from FDC/FAO/a printed label, or
      the number is cleared, or the row goes to the ruling table.
- [x] Seed regenerated (`gen-seed`) and the generated SQL committed with the
      inputs.
- [x] `make docs-check`, `make fns-lint`, `deno task test` green.
- [x] Docs stating density coverage updated to match.

## What was checked, and what held

The sweep reconstructed each row's post-pipeline state — prefill from
`usda_links.jsonl` → `usda_food`, then the curation `density`/`macros`
overrides, then the FAO fallback, then measures and `allowed_units` — and read
every row against it.

| # | Axis | Result |
|---|---|---|
| 1 | **Stranded defaults** (`defaultUnitNeedsDensity`) | **0 rows.** Every one of the 185 volume-default rows carries a density; the 12 bare rows are 10 count-default and 2 mass-default. R1 holds by construction, not by luck. |
| 2 | **Basis sanity** | **All 319 rows are per-100 g**, and all 276 USDA links resolve to FDC records, which are per-100 g by definition — so no link disagrees with the row it fills. No liquid or pourable row sits on per-100 g without a density bridging it. There is no per-100 ml row in the template at all. |
| 3 | **Default unit sanity** | 313 rows are how a UK/US household buys or measures the thing. **6 are not, or are inconsistent with their own siblings** — all six are in the ruling table; none is a number that can be wrong, so none was changed unilaterally. |
| 4 | **Density presence** | 307/319 carry one. The 12 bare rows are all counted goods (tortillas, a muffin, seaweed sheets, whole spices, a lime, seitan, two prepared bacons) whose FDC and FAO rejections are already audited and enumerated in the overrides file. **No row was found that a recipe volume-measures and that has a citable density nobody has entered** — so no density was added. |
| 5 | **`piece` (ADR-0010)** | Still exactly as ruled: **76** count-default rows, every one carrying a measure; **142** measure-carrying rows, every one carrying a `remove: ["piece"]` line; **0** rows admit `piece`. Nothing adds or sets `piece` anywhere. The pgTAP assertion in `supabase/tests/unit_admission.sql` still describes the data. |
| 6 | **Existing `allowed_units` overrides** | All 209 read. **198 removals** (268 unit-removals) are curation and stand. **11 additions**: 5 rows / 7 unit-adds are moot; 6 `to_taste` adds are real and stand. Detail below. |

### 5 · the `piece` ruling, re-derived from the data

| assertion | value today |
|---|---|
| count-default rows | 76 |
| …of those, carrying ≥1 measure | 76 |
| measure-carrying rows (any default) | 142 |
| `remove: ["piece"]` lines | 143 |
| rows whose materialized list admits `piece` | **0** |

The 143rd removal is `cherry tomato`, whose borrowed `cherry` measure the same
2026-09-02 pass dropped; the ruling is kept as the record even though the row is
now measure-less and cup-default. The overrides header said "66 of the 142
removals are already no-ops"; the true figures are **67 of 143**, and the header
is corrected in this change.

### 6 · which overrides survive all-to-all

Under all-to-all a per-100 g row admits every mass unit outright, and a stored
density admits every volume unit too. An override that only **added** a
mass/volume unit therefore says nothing the rule will not already say.

| override | units added | status |
|---|---|---|
| `allspice ground` · `clove ground` · `nutmeg ground` | `tsp` | **moot** — and already moot today: ADR-0009's count/imprecise leg gives a pinch-default row with a density both families. |
| `coconut milk canned` | `cup`, `tbsp`, `ml` | **moot** — same leg, count-default with a density. |
| `liquid smoke` | `tsp` | **moot** — same leg, dash-default with a density. |
| `hot sauce` · `sriracha` · `soy sauce` · `tamari` · `liquid amino` · `vegan worcestershire sauce` | `to_taste` | **stands.** `to_taste` is imprecise and category-gated; the vocabulary has no `condiment` category, so these six are the only way those rows say it. All-to-all does not touch the imprecise gate. |

None is deleted here: the generator accepts them all, and the file is the
decision record. The parallel lane's ADR can cite this table to say the seven
mass/volume adds became redundant, and that the six `to_taste` adds did not.

Removals, for the same question: of 268 unit-removals, **187 bite** — today and
under all-to-all alike. The 81 that do not are the 67 `piece` removals on
mass/volume-default rows (written deliberately, per ADR-0010) and 14 `handful`
removals on `fats & oils` rows, which the per-word category gate never admitted
in the first place. All-to-all changes neither count: it widens the mass/volume
legs, and every removal that bites is a mass/volume or imprecise word the rule
already offered.

## What changed

Three default units, all owner-ruled (R1, R2, R5 below). No density, macro,
measure, alias, name or `match_text` moved, so **this change contains no
rename** and the release checklist's rename-before-reseed trap does not apply.

| row | what | why |
|---|---|---|
| `flour tortilla` | `default_unit` `oz` → **`piece`** | the two other tortilla rows are `piece`, and its own default measure is `tortilla`; lands with the all-to-all rule so the row keeps the mass family |
| `frozen peas` | `default_unit` `lb` → **`cup`** | one freezer-bag habit, three defaults; the fresh sibling is `cup` |
| `frozen edamame` | `default_unit` `oz` → **`cup`** | as above |
| `dried coconut flakes` | `default_unit` `oz` → **`cup`** | every recipe line says "½ cup"; density present |

`supabase/seed.sql` regenerated (`deno task gen-seed`); every other generated
seed file is byte-identical.

**Deferred, not applied:** the audit proposed clearing `cinnamon stick`'s
density (0.5275 is FDC 171320's *ground* cinnamon on a row counted by the
quill — the `star anise` shape). The owner asked for findings only, so the
number stands until ruled on; the row's `piece` and imprecise words are
already removed, so nothing volume-measures it today.

## What needs Simon's ruling

Nine rows, none a provably wrong number. **Ruled 2026-09-08:** R1, R2 and R5
applied as recommended (see *What changed*); R3, R4, R6, R7, R8 and R9 kept
as they are.

| # | row | what the data says | recommendation |
|---|---|---|---|
| R1 | `flour tortilla` | default `oz`, while `corn tortilla` and `tostada shell` are `piece` — and its own curated default measure is already `tortilla` (49 g). Nobody buys tortillas by the ounce. | **Flip to `piece`, but after the all-to-all rule lands.** Under D4c today a count default with no density admits only `g` once the `piece` removal applies, so flipping now would *shrink* the row from `{g, kg, oz, lb}` to `{g}`. Under all-to-all it lands at `{g, kg, oz, lb, piece-removed}` either way, and the default finally reads like the shopping. |
| R2 | `pea frozen` (`lb`) · `edamame frozen` (`oz`) · `corn frozen` (`cup`) | Three defaults for one shopping habit — a bag from the freezer, poured by the cup. The fresh siblings (`pea`, `edamame`) are both `cup`. | Make the frozen rows `cup`, matching `corn frozen` and their own fresh siblings. Both carry densities, so R1 is satisfied and the change is legal today as well as after all-to-all. |
| R3 | `sea salt` | density **1.2342** — FDC's *table* salt (≈6 g/tsp), the identical number `fine sea salt`, `table salt` and `kala namak` carry. If "Sea Salt" means the coarse crystals rather than the fine grind, it is ~25 % heavy, and the row is indistinguishable from `Fine Sea Salt`. | Rule what the row means. If coarse: a `typical:` fill near **1.0** (1 tsp coarse sea salt ≈ 5 g), sitting between the curated `kosher salt` 0.7 and table salt's 1.234. Left alone here — no citable source pins a "sea salt" grind, and inventing one is the thing this audit refuses. |
| R4 | `mixed peppercorn` | density **0.4666** is FDC 170931's *ground* black pepper. Whole corns pack nearer 0.55–0.6. | Keep unless you want a label-sourced fill. Unlike `cinnamon stick`, this row is **`tsp`-default**, so R1 forbids simply clearing the number — the fix would have to be a better one, and the error is ~18 %, not 10×. |
| R5 | `coconut flake dried` | default `oz`, while every recipe line says "½ cup shredded coconut". Density 0.3593 is present. | `cup`. Low stakes under all-to-all (the units are admitted either way); it only changes what a fresh line prefills with. |
| R6 | `peanut` | default `tbsp`, while `almond`, `cashew`, `walnut`, `pecan`, `hazelnut` and `brazil nut` are all `cup`. `pine nut` and `pistachio` are `tbsp` too. | `cup` if peanuts are an ingredient here, `tbsp` if they are the garnish. The `tbsp` trio reads like a deliberate garnish class — say so and it stops looking like drift. |
| R7 | `bay leaf` | density **0.1217** is FDC 170917's *crumbled*-leaf portion; the row is counted whole (`leaf`, 0.2 g). | **Keep.** Unlike ground cinnamon against a quill, this is the same dried leaf in a slightly different state, the number is already at the light end, and no recipe volume-measures whole bay leaves. Listed only so the whole-spice sweep is complete. |
| R8 | `rice vinegar` | its label-sourced macros are printed **per 100 ml** and stored on a per-100 g row (`source: label:typical unseasoned rice vinegar`). | **Keep.** The row's stored density is 1.0, so the two bases coincide to within the rounding the label already carries. Flagged because it is the only place in the seed where a per-volume figure was written onto a per-mass basis. |
| R9 | `handful` on produce | ADR-0009's per-word gate hands `handful` to all 108 `produce` rows; only `liquid smoke` ever had it removed. "A handful of butternut squash" is offerable. | **Keep.** It is the ADR's stated, accepted consequence, and all-to-all does not touch the imprecise gate. Raised so the lane's ADR can say the imprecise leg is out of its scope. |

## How the reseed reaches cloud

Per [`docs/release.md`](../../release.md) §4.2 step 5 and §4.4, and
[`cloud-setup.md`](../../cloud-setup.md) §2b. **Nothing here was run against
cloud.**

1. **Template reseed.** Actions → `deploy-supabase` → Run workflow with
   **`reseed_template`** ticked. It applies `seed.sql` → `seed_usda.sql`
   (skipped, already populated) → `seed_prefill.sql` → `seed_measures.sql` →
   `seed_curation.sql` against the member-less template household. Tick it
   because `supabase/seed/**` and a generated `seed_*.sql` changed.
2. **No rename precedes it.** The §5 trap — a `match_text` that moved arriving
   as a *new* row and orphaning the old one — does not apply: this change edits
   one density and four doc counts, and moves no key.
3. **Existing households**: `supabase/rollout_ingredient_refresh.sql`, preview
   first, then run, then re-preview to 0.

   **Read this before assuming the fix lands everywhere.** That script is
   deliberately **monotone** — it fills `density_g_per_ml` only where the
   household's is *null*, and replaces `allowed_units` with the *union* of the
   household's list and the template's. It never removes. So:

   - The `cinnamon stick` clear reaches **new** households through the reseed
     and **does not** reach an already-onboarded one; that household keeps
     0.5275 and the volume admissions it granted until somebody clears the
     density on the row's flesh-out form, which strips them in the same write
     (ADR-0009 §D4b).
   - Any **default-unit** ruling from the table above (R1, R2, R5, R6) reaches
     new households only, in any case: the rollout carries two columns and
     `default_unit` is not one of them.

   Both are correct behaviour, not gaps — `allowed_units` is user-owned after
   creation (ADR-0008 §4) and ADR-0009 rule 3 forbids a backfill that removes.
   They are written down so nobody reads "reseeded" as "fixed everywhere".
4. `scripts/cloud_verify.sh` afterwards. Its pinned counts (319 rows, 283 with
   macros) are unchanged by this pass; it does not count densities.

## Decision log

- 2026-09-08 — Scope read from the owner's brief: this is not a magnitude
  prune. With all-to-all landing, "kg of saffron" is the user's call in the
  flesh-out form, so the audit is about the honesty of stored numbers only.
- 2026-09-08 — `cinnamon stick` cleared rather than refilled. FDC has no
  whole-quill record and FAO v2.0's cinnamon is ground, so the only honest
  options were "clear" and "guess". `star anise` set the precedent in the same
  file for exactly this shape.
- 2026-09-08 — `flour tortilla` **not** flipped to `piece` in this pass despite
  being clearly wrong, because under the *current* D4c rule the flip shrinks the
  row's admitted list. Sequenced behind the all-to-all lane instead (R1).
- 2026-09-08 — No `allowed_units` override deleted. Seven mass/volume adds are
  moot under all-to-all (and already moot today), but the generator accepts them
  and the file is the decision record; they are listed for the lane's ADR
  instead.

## Notes / open questions

- The whole-spice sweep found exactly two rows of that shape (`star anise`,
  `cinnamon stick`) and one near-miss (`bay leaf`, R7). `mixed peppercorn` (R4)
  is the same failure mode held in place by R1.
- 59 of the 81 `density` overrides carry their citation in the `reason` text but
  no machine-readable `source` field. The README makes `source` optional and the
  reasons do cite labels and FDC portions, so nothing is unprovenanced — but a
  future pass could lift those citations into `source` so provenance is readable
  off the database row, not only off this file.

## Verification

| command | result |
|---|---|
| `cd supabase/seed/scripts && deno task gen-seed` | 319 ingredients · 138 aliases · 13 macro + **81** density + 209 allowed-unit overrides + 133 default measures · 12 FAO fills, 11 audited FAO rejections, 19 since filled by curation |
| `cd supabase/seed/scripts && deno task gen-measures` | declines without the FDC bundles (documented; no measure changed, `seed_measures.sql` untouched) |
| `cd supabase/seed/scripts && deno task test` | 25 passed, 0 failed |
| `make fns-lint` | clean |
| `make docs-check` | clean |

Deliberately not run (owner's instruction): `make db-reset`, `supabase test db`,
`make ci-full`, `make test-sim`. The `piece` and admission assertions in
`supabase/tests/unit_admission.sql` were checked **statically** against the
reconstructed post-pipeline state instead; none of their pinned counts (142
measure-carrying rows, 0 rows admitting `piece`, the >40 piece-default produce
rows) is moved by this change.
