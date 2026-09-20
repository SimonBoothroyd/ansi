# Architecture

> The top-level map of the system for humans and agents. Deeper detail lives in `docs/` (see `docs/README.md`); the *why* behind choices is in `docs/decisions/`.

This is the "why", cross-referenced to decision records (`docs/decisions/`). The
"what to build next" lives in `docs/exec-plans/roadmap.md`. Product behaviour lives
in `docs/product-specs/`.

## Stack (decided)

| Layer            | Choice                                   | ADR |
|------------------|------------------------------------------|-----|
| Client framework | Flutter 3.44+                            | 0002 |
| UI components    | Forui (shadcn-style, MIT)                | 0002 |
| State / DI       | Riverpod 3 (codegen) + go_router         | 0003 |
| Models           | Freezed + json_serializable              | 0003 |
| Backend          | Supabase (Postgres + Auth + Storage)     | 0002 |
| Offline sync     | PowerSync (local SQLite + upload queue)  | 0002 |
| Auth             | Google OAuth via Supabase Auth           | 0002 |
| Import extraction| Flash-tier multimodal LLM, server-side   | 0004 |

## The shape of the app

Feature-first + MVVM, which is the layout Flutter's own architecture guide
recommends. Each feature is a vertical slice:

```
lib/features/<feature>/
  domain/         # entities + repository interfaces — PURE DART, no Flutter
  data/           # repository implementations, DTOs, PowerSync queries
  presentation/   # Views (widgets) + ViewModels (Riverpod notifiers)
```

`lib/core/` holds cross-cutting code that never depends on a feature: the unit
system, config, router, theme, the PowerSync database, and the `Result` type.
`lib/shared/` holds reusable widgets.

**Dependency direction:** `presentation → domain ← data`. Views read state from
ViewModels; ViewModels call repository *interfaces* in `domain/`; `data/`
implements them. This is what makes ViewModels and domain logic testable by
overriding a repository provider with a fake — no widget tree, no network.

**Domain purity is enforced.** `core/units` and every `domain/` folder must not
import `package:flutter`. CI greps for violations (`.github/workflows/app.yml`).
It keeps the most important logic (unit conversion, batch clustering, list
aggregation) runnable as plain Dart tests.

## The sync model

One shared household dataset; both members full read/write; everything scoped to
`household_id`. PowerSync owns the write queue: the app reads and writes a local
SQLite database and syncs when online.

Auth gates the whole app (step 7): sign in (Google OAuth, or dev email/password
locally) → `ensure_onboarded` resolves or creates the household → an access-token
hook stamps `household_id` into the JWT → PowerSync `.connect()` scopes every
synced bucket to it ([ADR-0006](./docs/decisions/0006-sync-auth-and-onboarding.md)).
`core/sync/session.dart` drives this; the router holds the user on a
`/connecting` screen until the household is ready. Standing up real cloud
infra: [`docs/cloud-setup.md`](./docs/cloud-setup.md).

Conflict resolution (spec §3): independent rows (list contributions, recipes)
union on concurrent adds and never collide; field edits are last-write-wins
(fine for two trusted users); deletes are soft-delete tombstones. No CRDTs.

```
Flutter app  ──writes──▶  local SQLite  ──PowerSync queue──▶  Supabase Postgres
     ▲                        │                                     │
     └──────reactive reads────┘◀──────PowerSync sync stream─────────┘
```

## The one architectural spine: matching is online-only (ADR-0004)

Recipe import is the only place matching against a *reference set* happens,
and import is always online (we're either fetching a webpage or calling a
vision model). The phone's own search boxes do carry a typo tier, but it is a
deterministic scored comparison over the household's few hundred synced rows,
offered under a "did you mean" header for a human to pick, never a resolution — see
[`docs/design-docs/search-and-matching.md`](./docs/design-docs/search-and-matching.md). That single
fact means the phone never needs an embedding model or the 8,000-row USDA
reference set. The match engine lives entirely server-side (a Supabase edge
function); only human-readable, already-resolved `ingredient` rows sync to the
device.

Two lookups that look similar but are different jobs (design doc §10):

- **Machine proposes, then a human confirms** — import reconciliation. Online,
  full ranked cascade, auto-accepts above a threshold. Server-side.
- **Human picks from a list** — every search box on the phone (the ingredient
  picker, both recipe pickers, the Library). Offline, one three-tier rule
  (`searchRank`) over the synced rows. On-device.

The barcode add flow does not bend this: a barcode is a **primary
key**, so the Open Food Facts read is an exact-key fetch, not matching, and it
runs on the device (the API is keyless and free, and its rate limit is per IP —
a shared server address would pool every household onto one budget). What comes
back is a *draft*, never a row.

## Two-tier ingredient vocabulary (ADR-0005)

- `ingredient` — the household's lean, curated vocabulary (~150–300 rows). The
  match target, and the only ingredient data that syncs to devices.
- `usda_food` — the full USDA FoodData Central reference, read-only,
  server-side only. Used to *create* ingredients and to prefill stubs. Never
  matched against at import.

**Nothing matches an ingredient to USDA on its own.** Because `usda_food` never
reaches a device, the one door to it is `probe_usda`, a read-only `security
definer` RPC called when a person opens the USDA search on the flesh-out form.
It ranks with BM25 over four server-only index tables (migration `0029`),
writes nothing, and hands back candidates; the pick fills the form's **draft**,
and the draft lands with everything else in a single Save
([ADR-0011](./docs/decisions/0011-one-save-one-write.md)). A row stays
`status='stub'` until a human confirms it, because confirming is a human act.

That human works in `features/ingredients`, which owns the in-app **manager**
(`/ingredients`) and the flesh-out form at `/ingredients/:id` — the one place a
vocabulary row is created or edited: `allowed_units`, density, macros, name,
aliases. So the admission list ([ADR-0008](./docs/decisions/0008-unit-admission-model.md),
amended by [ADR-0009](./docs/decisions/0009-density-unlocks-both-families.md)) is
no longer write-once-at-creation. That list is also where `piece` lives or does
not, and what puts it there is a **number on the row**:
[ADR-0015](./docs/decisions/0015-piece-weight-is-a-row-fact.md) makes
`piece_basis_amount` — what one of the thing weighs — a row fact exactly as
`density_g_per_ml` is. A density unlocks the other mass/volume family; a piece
weight unlocks `piece`, and only on a row whose default unit is `piece`. A
`piece` default with no weight is a stranded default the form refuses to save,
so nothing downstream ever has to decide what a `piece` meant. Measures keep
the job they always had: the words for sizes, fragments and containers.

Matching against a couple hundred ingredients the household actually uses is
high-precision; matching against 8k SR Legacy rows is not.

Both tables (+ `ingredient_alias`) live in `supabase/migrations/0002`;
`ingredient_measure` (migrations `0009`/`0010`, step 7.6) rides with the
vocab: named per-ingredient measures with gram weights ("1 potato, medium =
213 g") — the honest count↔mass bridge for count foods
(`app/lib/core/units/measure.dart`), referenced by nullable `measure_id` FKs
on `recipe_line_item` and `shopping_list_contribution`, each row carrying its
weight's provenance (`source`, 0010). Its recipe-side counterpart is
`recipe_measure` (migration `0048`): a household word for one of what a
*recipe* makes — `blob`, `ladle`, `patty` — defined the same way, as an
`amount` in a `unit` (a blob is 15 g), so a component line can say `3 blob` of
a sauce and the recipe's own `makes` turns the 45 g into a share of a batch. It
carries its own unit rather than inheriting a basis, because a recipe has no
single one; it may only be coined while the recipe states a `makes` in the
unit's family; and it carries no provenance, because a recipe's words only ever
come from the household that wrote the recipe. The rows that fill the
ingredient measures come from the
checked-in seeds (`supabase/seed_vocab.sql` — the whole curated household
vocabulary in one generated file: ingredients with their densities, macros,
piece weights and explicit `allowed_units`, plus their aliases and measures;
`seed_usda.sql` + `seed_usda_index.sql` — the server-only USDA reference and
its search index), run in that order by `supabase db reset`. The vocabulary
is not derived from raw sources any more: `seed_vocab.sql` is generated from
`supabase/seed/snapshot.jsonl`, an export of the owner's live household, so
the direction is **cloud → seed** and the curated rows ARE the input
(`supabase/seed/README.md`).

## Data flow: plan → cook → shop

The whole product is one derivation pipeline (spec §4):

```
week_plan (what you want to eat)
   │  group by recipe, split by shelf life (greedy, O(n log n))
   ▼
batch cook plan (cook sessions: when to cook, at what scale)
   │  one contribution per (cook session, ingredient), scaled by the session
   ▼
shopping list (summed in canonical base, with per-source provenance)
```

The cook plan and shopping list are *derived views*, not hand-authored — the
core product thesis (see `docs/product-specs/product-spec.md` §4). Both are
computed at read time: there is **no** `cook_session` table, and the shopping
list's cook contributions are re-derived per device (steps 5–6). The only
persisted shopping state is the thin overlay — per-ingredient check-off plus
manual/free-text contributions (`shopping_list_entry` / `shopping_list_contribution`,
migration `0006`; ADR-0007).

## Environments & secrets

Client config (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `POWERSYNC_URL`) is injected
at build time via `--dart-define` and read in `lib/core/config/env.dart`. Nothing
sensitive is committed. The extraction model key is a **server-side** secret set
on the edge function, never shipped to the client.

## Where each area stands

One row per area of the system, so a gap is visible without reading the code.
🟢 solid · 🟡 partial · 🔴 thin or missing. A 🟡 or 🔴 row names the gap that
holds it there; a 🟢 row names what holds it up. Detail lives behind the link —
this table stays one line per area.

| Area | Grade | The gap | Link |
|---|---|---|---|
| Unit system (`core/units`) | 🟢 | Conversions, named measures and the count↔basis bridge are pure Dart, and a missing density or a bad amount refuses instead of guessing; one number rule prints and parses a kitchen unit as a fraction and a scale unit as a decimal, held by a structural test that no surface formats its own. | [ADR-0008](./docs/decisions/0008-unit-admission-model.md) · [unit-and-measure-matching.md](./docs/design-docs/unit-and-measure-matching.md) |
| Ingredient data model + vocab | 🟢 | The seed is an export of the live curated household (cloud → seed), so seeded rows carry the measures, densities, piece weights and explicit `allowed_units` a person actually chose; one admission rule with a Dart mirror and shared vectors keeps SQL and app honest, and the generator lists every row that overrules it. | [ADR-0009](./docs/decisions/0009-density-unlocks-both-families.md) · [db-schema.md](./docs/generated/db-schema.md) |
| Ingredients manager (`features/ingredients`) | 🟢 | `/ingredients` and the flesh-out form own the vocabulary; the form writes once, on Save, in one transaction. Names and aliases share one namespace, and a row is retired only when nothing live names it — refused in the app and in the database. A price is an event kept as a receipt line, read back as a per-100 figure derived every time, never stored. | [README](./app/lib/features/ingredients/README.md) · [ADR-0011](./docs/decisions/0011-one-save-one-write.md) · [ADR-0017](./docs/decisions/0017-a-cost-is-a-unit-price-never-an-allocation.md) |
| Barcode add (`features/ingredients/barcode`) | 🟡 | No camera leg has run on physical hardware — a live scan, in-app capture and the camera-denied notice are one device errand — and nothing tests the live Open Food Facts API, so an upstream shape change would surface in a user's hands. | [tracker](./docs/exec-plans/tech-debt-tracker.md) |
| Recipes (`features/recipes`) | 🟢 | Editor, page, scaling, nested components and per-serving macros run off one summation that reports `incomplete` rather than a wrong number; cost is its twin over the same walk, naming an unpriced line and printing what the priced lines come to as an `at least` floor. Week mode stores a cook's changes as deltas over the base recipe, and a component line is said in a unit or in one of the target recipe's own measures. A structural test keeps money out of the macro record and macros out of the cost one. | [README](./app/lib/features/recipes/README.md) · [product-spec.md](./docs/product-specs/product-spec.md) · [ADR-0017](./docs/decisions/0017-a-cost-is-a-unit-price-never-an-allocation.md) · [ADR-0018](./docs/decisions/0018-a-recipe-measure-is-a-named-amount.md) |
| Books (`features/books`) | 🟢 | Library v3's header, row creation and refused delete, with a recipe row that carries serves and honest per-serving macros — or serves alone when the numbers are not honest. A book has a page of its own, `/books/:id`, drawn from the card's widgets; on a wide window the Library is an open ledger in one lazy list. | [plan 0028](./docs/exec-plans/completed/0028-library-v3.md) · [plan 0047](./docs/exec-plans/completed/0047-wide-screens.md) |
| Navigation (`shared/ansi_tab_shell.dart`, `core/router`) | 🟢 | One `StatefulShellRoute` under one bar, wrapped with every pushed route in one outer `ShellRoute`, so the chrome stands beside the content without moving a back rule — held row by row against the real route shape, beside the structural tests for the no-footer, no-bare-modal and guarded-push rules. On the web the URL is the route. Android's predictive back is verified only in a simulated binding. | [navigation.md](./docs/design-docs/navigation.md) |
| Wide screens (`shared/ansi_layout.dart`) | 🟢 | One file reads the viewport and one wrapper applies the 640 measure, held by a structural test that fails on a `MediaQuery.sizeOf`, a `.size` or a `LayoutBuilder` anywhere else under `lib/`. From `lg` up a rail or sidebar replaces the bar and `showAnsiSheet` presents as a dialog; each view that earns the width takes it through one `fullWidth` flag. The phone's 44 px target is not applied to pointer controls, and mouse drag-to-scroll stays off by choice. | [wide-screen.md](./docs/design-docs/wide-screen.md) |
| Sync layer (`core/sync`) | 🟢 | Onboarding, the household JWT claim and the queue drain are pinned by pgTAP and real-`ps_crud` tests; the offline-queue drain and a two-client session remain untested. | [ADR-0006](./docs/decisions/0006-sync-auth-and-onboarding.md) · [cloud-setup.md](./docs/cloud-setup.md) |
| Planning (`features/planning`) | 🟢 | Week v3's three drawn targets, the viewed week that Cook and Shop follow, and fractional demand from each member's `portion_factor`. A slot takes a recipe, a bare ingredient or a meal eaten out — exactly one target, enforced by a server check and read through one `kind`; a recipe can be varied for one week, one variant per (week, recipe); and the household picks the day its week starts on. The week's foot states what the plan costs to cook, `at least …` when a meal is left out of it, and what the week's receipts came to, never reconciled against it. | [README](./app/lib/features/planning/README.md) · [product-spec.md](./docs/product-specs/product-spec.md) · [ADR-0017](./docs/decisions/0017-a-cost-is-a-unit-price-never-an-allocation.md) |
| Cook-plan (`features/cook_plan`) | 🟢 | The plan is derived at read time — shelf-life clustering, freezer merge and batch-denominated component sessions over a graph filtered for the week on screen, so an optional sub-recipe is cooked only where the week includes it — with no `cook_session` table to fall out of date; the cook day is still display-only. A wide window draws the same plan as one schedule sheet — a row per recipe against seven day columns drawn once — off the same words and the same keep-window geometry the phone's card reads, so neither form can say something the other does not. | [tracker](./docs/exec-plans/tech-debt-tracker.md) |
| Shopping (`features/shopping`) | 🟢 | The list is derived per device over a thin persisted overlay — cook sessions and planned ingredients through one degradation rule — sums only within a family unless a density bridges it, and shows bad data rather than dropping it. A row is counted and bought in the measure it was asked for, says where it came from and reads by aisle; ticked rows gather in one basket section. The trip's estimate sums the rows it can price and prints `at least …` when one has none. A foot door scans the receipt that ends the trip; the ledger's door is a header action, drawn once the household has kept a receipt. | [README](./app/lib/features/shopping/README.md) · [ADR-0007](./docs/decisions/0007-shopping-list-thin-overlay.md) · [ADR-0017](./docs/decisions/0017-a-cost-is-a-unit-price-never-an-allocation.md) |
| Import pipeline, server (`supabase/functions`) | 🟢 | One forced LLM path into a deterministic, household-scoped cascade that asks once per tier over the whole line set, answering as an event stream that names each stage as it finishes; tested end to end without network or keys against blessed gold labels. `import-receipt` reads a photographed receipt through the same spine: it writes nothing and teaches the vocabulary nothing — a spying executor asserts every statement it issues is a select — and recalls the household's own past answers per printed name ([§12.4.1](./docs/product-specs/import-and-matching.md#1241-what-the-household-itself-remembers)). | [import-and-matching.md](./docs/product-specs/import-and-matching.md) · [ADR-0004](./docs/decisions/0004-matching-is-online-only.md) |
| Import client (`features/import`) | 🟢 | One merged, always-editable review screen — sections renamed, added and deleted without losing a line, lines minted and dragged — over pure-Dart resolution and validation, with the commit pinned against the server's golden fixture. The reading screen is a checklist the server fills in over its event stream, never a timed guess. A wide window is three columns: the source, the lines, and one line's form. No camera leg has run on real hardware. | [README](./app/lib/features/import/README.md) · [import-and-matching.md](./docs/product-specs/import-and-matching.md) |
| Receipts (`features/receipts`) | 🟢 | A photographed receipt reads through the recipe import's own pipeline and is confirmed line by line, the lines' sum held against the printed subtotal — or, where the strip prints none, its total less tax — as a flag rather than a refusal. No alias is learned; the household's own pack and match carry over under the printed name ([§12.4.1](./docs/product-specs/import-and-matching.md#1241-what-the-household-itself-remembers)). Save writes the receipt and every line it kept in one transaction, and a saved receipt opens on the same review, where Save rewrites its rows in place. The desk's three-column review is drawn and unbuilt. | [README](./app/lib/features/receipts/README.md) · [ADR-0017](./docs/decisions/0017-a-cost-is-a-unit-price-never-an-allocation.md) |
| Evals (`evals/`) | 🟡 | The matching half runs in CI, but the extraction half needs real provider keys and a local photo corpus — the corpus, its gold and every saved run are local-only because they are cookbook pages — so the half that chose the provider is unprotected in CI and there is no trend line outside the owner's machine. | [evals/AGENTS.md](./evals/AGENTS.md) |
| Errors & sync health (cross-cutting) | 🟢 | Every UI write goes through one door held by a structural test, one error state carries a mapped reason, and one sync-health provider feeds three readouts that cannot disagree — the shell's banner, `/account` and the Shop list's line. | [errors-and-sync-health.md](./docs/design-docs/errors-and-sync-health.md) |
| Docs / harness | 🟢 | `make docs-check` holds required files, link resolution, stream drift, table integrity, the ADR index and the freshness of the generated schema, so a skipped `make docs` is caught rather than noticed. | [docs/README.md](./docs/README.md) |
| CI (`.github/workflows`) | 🟢 | Six workflows cover the app, backend, docs, evals, release and the Supabase deploy; a tag builds the browser bundle beside the phones and attaches it, with the Pages deploy a separate job gated on a host existing. The simulator smoke stays a local gate by choice, because it needs a booted device. | [release.md](./docs/release.md) |

**The bar for "done" on any slice:** logic lives in the right layer (domain is
pure Dart) · tests cover it and would fail if it broke · a behaviour change
updates the doc that describes it · `make ci` and `make docs-check` are green.
