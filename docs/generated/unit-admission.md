<!-- GENERATED FILE — do not edit. Regenerate with `make docs` (scripts/gen_docs.sh). -->
# Unit admission — what a line may be said in (generated)

Which units a recipe line or a shopping top-up may be denominated in, for
every default unit the catalog offers and both macro bases. Each cell is
the real domain rule run over a bare vocabulary row — no explicit per-row
`allowed_units` list and no category — so it is what `allowedUnitsFor`
actually returns, in the chip order the pickers draw, rather than a
restatement of the rule.

The rule lives in `app/lib/features/ingredients/domain/allowed_units.dart`
and is mirrored in SQL by `default_allowed_units()`, which stamps the
stored list on insert. It was decided by
[ADR-0008](../decisions/0008-unit-admission-model.md) (the model),
[ADR-0009](../decisions/0009-density-unlocks-both-families.md) (a density
unlocks the other family whatever the default unit is),
[ADR-0010](../decisions/0010-piece-is-an-admission-fact.md) (`piece` is
curated, never inferred), [ADR-0012](../decisions/0012-tsp-mates-cup.md)
and [ADR-0013](../decisions/0013-mass-ladder-symmetric.md) (the volume and
mass ladders are symmetric).

## 1. No density stored

The common case: a row with macros and no density. A cell reading `—
(default needs a density)` is a shape the app refuses to store — the
default unit sits on the far side of the basis family with nothing to
bridge it, so the form flags it and Save offers `g`/`ml` instead.

| Default unit | per 100 g | per 100 ml |
|---|---|---|
| `g` | **g** · kg · oz · lb | — (default needs a density) |
| `kg` | **kg** · g · oz · lb | — (default needs a density) |
| `mg` | **mg** · g | — (default needs a density) |
| `oz` | **oz** · g · kg · lb | — (default needs a density) |
| `lb` | **lb** · g · kg · oz | — (default needs a density) |
| `ml` | — (default needs a density) | **ml** · tsp · tbsp · cup · l · pt · qt |
| `l` | — (default needs a density) | **l** · cup · ml · pt · qt |
| `tsp` | — (default needs a density) | **tsp** · tbsp |
| `tbsp` | — (default needs a density) | **tbsp** · tsp · cup · ml · pt |
| `fl oz` | — (default needs a density) | **fl oz** · tbsp · cup · ml · pt |
| `cup` | — (default needs a density) | **cup** · tsp · tbsp · ml · l · pt · qt |
| `pt` | — (default needs a density) | **pt** · cup · ml · qt |
| `qt` | — (default needs a density) | **qt** · cup · ml · l · pt |
| `piece` | **piece** · g | **piece** · ml |
| `pinch` | g · **pinch** | ml · **pinch** |
| `dash` | g · **dash** | ml · **dash** |
| `handful` | g · **handful** | ml · **handful** |
| `to taste` | g · **to taste** | ml · **to taste** |

## 2. With a density stored

The same rows once a `density_g_per_ml` is known. Each cell reads **what
survives the density being deleted** `+` **what the density buys** — the
second half is `densityUnlockedUnits`, which is exactly what deleting the
number takes back. Both halves are in chip order, so a default that was
stranded in table 1 appears in the second half.

| Default unit | per 100 g | per 100 ml |
|---|---|---|
| `g` | **g** · kg · oz · lb + tsp · tbsp · cup · ml · pt | ml + **g** · kg · oz · lb · tsp · tbsp · cup · pt |
| `kg` | **kg** · g · oz · lb + tsp · tbsp · cup · ml · pt | ml · l + **kg** · g · oz · lb · tsp · tbsp · cup · pt |
| `mg` | **mg** · g + tsp · tbsp · cup · ml · pt | ml + **mg** · g · tsp · tbsp · cup · pt |
| `oz` | **oz** · g · kg · lb + tsp · tbsp · cup · ml · pt | ml + **oz** · g · kg · lb · tsp · tbsp · cup · pt |
| `lb` | **lb** · g · kg · oz + tsp · tbsp · cup · ml · pt | ml · l + **lb** · g · kg · oz · tsp · tbsp · cup · pt |
| `ml` | g + **ml** · tsp · tbsp · cup · l · pt · qt | **ml** · tsp · tbsp · cup · l · pt · qt + g |
| `l` | g · kg + **l** · cup · ml · pt · qt | **l** · cup · ml · pt · qt + g · kg |
| `tsp` | g + **tsp** · tbsp | **tsp** · tbsp + g |
| `tbsp` | g + **tbsp** · tsp · cup · ml · pt | **tbsp** · tsp · cup · ml · pt + g |
| `fl oz` | g + **fl oz** · tbsp · cup · ml · pt | **fl oz** · tbsp · cup · ml · pt + g |
| `cup` | g · kg + **cup** · tsp · tbsp · ml · l · pt · qt | **cup** · tsp · tbsp · ml · l · pt · qt + g · kg |
| `pt` | g · kg + **pt** · cup · ml · qt | **pt** · cup · ml · qt + g · kg |
| `qt` | g · kg + **qt** · cup · ml · l · pt | **qt** · cup · ml · l · pt + g · kg |
| `piece` | **piece** · g + tsp · tbsp · cup · ml · pt | **piece** · ml + tsp · tbsp · cup · pt · g |
| `pinch` | g · **pinch** + tsp · tbsp · cup · ml · pt | ml · **pinch** + tsp · tbsp · cup · pt · g |
| `dash` | g · **dash** + tsp · tbsp · cup · ml · pt | ml · **dash** + tsp · tbsp · cup · pt · g |
| `handful` | g · **handful** + tsp · tbsp · cup · ml · pt | ml · **handful** + tsp · tbsp · cup · pt · g |
| `to taste` | g · **to taste** + tsp · tbsp · cup · ml · pt | ml · **to taste** + tsp · tbsp · cup · pt · g |

## 3. Imprecise words, by category

The tables above use a row with no category, so they show no imprecise
word except an imprecise default keeping its own. The words are gated per
WORD by the row's category — greens earn `handful` without earning
`pinch` — and a category absent from this table earns none of them. (The
import amount editor admits `to taste` on top of this for any food:
"plus more, to serve" is legitimately imprecise whatever the ingredient.)

| Category | pinch | dash | handful | to taste |
|---|---|---|---|---|
| `fats & oils` | ✓ | ✓ | — | ✓ |
| `produce` | — | — | ✓ | — |
| `spices & seasoning` | ✓ | ✓ | ✓ | ✓ |

## How to read it

- **Order is meaning.** The default unit is fronted, then the rest of its
  family in kitchen order, then `piece`, then the demoted other
  mass/volume family (reachable, never fronted — "g of milk" is doable but
  strange), then the imprecise words last.
- **The basis family is unconditional.** A per-100 g row can always say
  `g`, a per-100 ml row `ml` — the canonical dimension needs no density.
- **The `big` gate.** The big metric siblings `kg` and `l` ride only with
  a cup/lb-scale default (`cup`, `pt`, `qt`, `l`, `lb`, `kg`) — no litres
  of yeast, and no kilograms on a row that speaks in spoons.
- **`mg` and `fl oz` never join a picker.** They are label-reading
  granularity, not kitchen granularity, so they reach a picker only as a
  row's own default unit — their own rows here are the only place they
  appear.
- **A stored list overrides all of this, per row.** A household that
  curates a row's chips owns them; this table is what a row is created
  with, and the fallback for a row carrying no list. The one thing an
  explicit list cannot do is make a unit sayable that no density supports
  — that half is subtracted while the number is missing.
