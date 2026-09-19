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
[ADR-0014](../decisions/0014-all-to-all-admission.md) (all to all — a
family is admitted whole and the household prunes per row) and
[ADR-0015](../decisions/0015-piece-weight-is-a-row-fact.md) (a piece
weight is a row fact: `piece` is sayable only on a count-default row that
says what one weighs — the `piece` rows below carry one).

## 1. No density stored

The common case: a row with macros and no density. A cell reading `—
(default needs a density)` is a shape the app refuses to store — the
default unit sits on the far side of the basis family with nothing to
bridge it, so the form flags it and Save offers `g`/`ml` instead.

| Default unit | per 100 g | per 100 ml |
|---|---|---|
| `g` | **g** · kg · oz · lb | — (default needs a density) |
| `kg` | **kg** · g · oz · lb | — (default needs a density) |
| `oz` | **oz** · g · kg · lb | — (default needs a density) |
| `lb` | **lb** · g · kg · oz | — (default needs a density) |
| `ml` | — (default needs a density) | **ml** · tsp · tbsp · fl oz · cup · l · pt · qt |
| `l` | — (default needs a density) | **l** · tsp · tbsp · fl oz · cup · ml · pt · qt |
| `tsp` | — (default needs a density) | **tsp** · tbsp · fl oz · cup · ml · l · pt · qt |
| `tbsp` | — (default needs a density) | **tbsp** · tsp · fl oz · cup · ml · l · pt · qt |
| `fl oz` | — (default needs a density) | **fl oz** · tsp · tbsp · cup · ml · l · pt · qt |
| `cup` | — (default needs a density) | **cup** · tsp · tbsp · fl oz · ml · l · pt · qt |
| `pt` | — (default needs a density) | **pt** · tsp · tbsp · fl oz · cup · ml · l · qt |
| `qt` | — (default needs a density) | **qt** · tsp · tbsp · fl oz · cup · ml · l · pt |
| `piece` | **piece** · g · kg · oz · lb | **piece** · tsp · tbsp · fl oz · cup · ml · l · pt · qt |
| `pinch` | **pinch** · g · kg · oz · lb | **pinch** · tsp · tbsp · fl oz · cup · ml · l · pt · qt |
| `dash` | **dash** · g · kg · oz · lb | **dash** · tsp · tbsp · fl oz · cup · ml · l · pt · qt |
| `handful` | **handful** · g · kg · oz · lb | **handful** · tsp · tbsp · fl oz · cup · ml · l · pt · qt |
| `to taste` | **to taste** · g · kg · oz · lb | **to taste** · tsp · tbsp · fl oz · cup · ml · l · pt · qt |

## 2. With a density stored

The same rows once a `density_g_per_ml` is known. Each cell reads **what
survives the density being deleted** `+` **what the density buys** — the
second half is `densityUnlockedUnits`, which is exactly what deleting the
number takes back. Both halves are in chip order, so a default that was
stranded in table 1 appears in the second half.

| Default unit | per 100 g | per 100 ml |
|---|---|---|
| `g` | **g** · kg · oz · lb + tsp · tbsp · fl oz · cup · ml · l · pt · qt | tsp · tbsp · fl oz · cup · ml · l · pt · qt + **g** · kg · oz · lb |
| `kg` | **kg** · g · oz · lb + tsp · tbsp · fl oz · cup · ml · l · pt · qt | tsp · tbsp · fl oz · cup · ml · l · pt · qt + **kg** · g · oz · lb |
| `oz` | **oz** · g · kg · lb + tsp · tbsp · fl oz · cup · ml · l · pt · qt | tsp · tbsp · fl oz · cup · ml · l · pt · qt + **oz** · g · kg · lb |
| `lb` | **lb** · g · kg · oz + tsp · tbsp · fl oz · cup · ml · l · pt · qt | tsp · tbsp · fl oz · cup · ml · l · pt · qt + **lb** · g · kg · oz |
| `ml` | g · kg · oz · lb + **ml** · tsp · tbsp · fl oz · cup · l · pt · qt | **ml** · tsp · tbsp · fl oz · cup · l · pt · qt + g · kg · oz · lb |
| `l` | g · kg · oz · lb + **l** · tsp · tbsp · fl oz · cup · ml · pt · qt | **l** · tsp · tbsp · fl oz · cup · ml · pt · qt + g · kg · oz · lb |
| `tsp` | g · kg · oz · lb + **tsp** · tbsp · fl oz · cup · ml · l · pt · qt | **tsp** · tbsp · fl oz · cup · ml · l · pt · qt + g · kg · oz · lb |
| `tbsp` | g · kg · oz · lb + **tbsp** · tsp · fl oz · cup · ml · l · pt · qt | **tbsp** · tsp · fl oz · cup · ml · l · pt · qt + g · kg · oz · lb |
| `fl oz` | g · kg · oz · lb + **fl oz** · tsp · tbsp · cup · ml · l · pt · qt | **fl oz** · tsp · tbsp · cup · ml · l · pt · qt + g · kg · oz · lb |
| `cup` | g · kg · oz · lb + **cup** · tsp · tbsp · fl oz · ml · l · pt · qt | **cup** · tsp · tbsp · fl oz · ml · l · pt · qt + g · kg · oz · lb |
| `pt` | g · kg · oz · lb + **pt** · tsp · tbsp · fl oz · cup · ml · l · qt | **pt** · tsp · tbsp · fl oz · cup · ml · l · qt + g · kg · oz · lb |
| `qt` | g · kg · oz · lb + **qt** · tsp · tbsp · fl oz · cup · ml · l · pt | **qt** · tsp · tbsp · fl oz · cup · ml · l · pt + g · kg · oz · lb |
| `piece` | **piece** · g · kg · oz · lb + tsp · tbsp · fl oz · cup · ml · l · pt · qt | **piece** · tsp · tbsp · fl oz · cup · ml · l · pt · qt + g · kg · oz · lb |
| `pinch` | **pinch** · g · kg · oz · lb + tsp · tbsp · fl oz · cup · ml · l · pt · qt | **pinch** · tsp · tbsp · fl oz · cup · ml · l · pt · qt + g · kg · oz · lb |
| `dash` | **dash** · g · kg · oz · lb + tsp · tbsp · fl oz · cup · ml · l · pt · qt | **dash** · tsp · tbsp · fl oz · cup · ml · l · pt · qt + g · kg · oz · lb |
| `handful` | **handful** · g · kg · oz · lb + tsp · tbsp · fl oz · cup · ml · l · pt · qt | **handful** · tsp · tbsp · fl oz · cup · ml · l · pt · qt + g · kg · oz · lb |
| `to taste` | **to taste** · g · kg · oz · lb + tsp · tbsp · fl oz · cup · ml · l · pt · qt | **to taste** · tsp · tbsp · fl oz · cup · ml · l · pt · qt + g · kg · oz · lb |

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

- **Order is meaning.** The default unit is fronted **whatever its
  family** — a row said in pinches leads with `pinch` rather than opening
  on grams — then the rest of that family in kitchen order, then `piece`
  (a count default only, and only while the row has a piece weight), then
  the demoted other mass/volume family (reachable, never fronted — "g of
  milk" is doable but strange), then the imprecise words the row merely
  admits, last.
- **The basis family is unconditional, and whole.** A per-100 g row can
  always say every weight, a per-100 ml row every volume — the canonical
  dimension needs no density, and a family is admitted whole or not at
  all.
- **The user prunes, not the rule.** These are the units a row is created
  with; a household that will never say a litre of yeast turns that chip
  off on the row itself, in the flesh-out form's admission section.
- **A stored list overrides all of this, per row.** A household that
  curates a row's chips owns them, and this table is the fallback for a
  row carrying no list. The one thing an explicit list cannot do is make
  a unit sayable that no density supports — that half is subtracted while
  the number is missing.
