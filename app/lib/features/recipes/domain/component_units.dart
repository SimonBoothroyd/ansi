/// Which units a COMPONENT line may be denominated in — PURE DART
/// (invariant 2), the sub-recipe counterpart of
/// `features/ingredients/domain/allowed_units.dart`.
///
/// The rule (step 8.6 / D2, design board frame d): the offer is
/// **`batch` ∪ the yields' families, kitchen-trimmed**.
///
/// - `batch` is always sayable — one whole run of the recipe needs no yield at
///   all, which is what keeps a yield-less recipe linkable and derivable.
/// - Each stated yield opens its own family, at the magnitudes a kitchen
///   reaches for ([kComponentKitchenUnits]) — a yield of `1 cup` offers
///   `cup · tbsp · tsp · ml · pt · qt`, never `fl oz` or `mg`. There is no
///   density for a recipe, so a family the yields do not state is not
///   offered: the fix is the yield's optional SECOND denomination, not a
///   guessed bridge.
/// - The **stored selection is always admitted** (the 7.7 rule, verbatim): an
///   imported line's printed unit stays an offered chip even when the filter
///   would not raise it, flagged as outside the filter and rendered with the
///   honest unresolved conversion line rather than silently rewritten.
///
/// A measure never appears here: a measure is an *ingredient* concept
/// ("potato, medium = 213 g" says nothing about a recipe), which is why the
/// component sheet also drops the `+` manage-measures chip.
library;

import '../../../core/units/units.dart';
import 'component_math.dart';

/// The kitchen workhorses each yield family opens, in chip order (design board
/// frame d draws `cup · tbsp · tsp · ml` for a `makes 1 cup` yield; the US
/// pair joined the tail with plan 0025 #2 — a stock that "makes 1 quart" is a
/// kitchen fact too).
///
/// Deliberately narrower than the catalogue: label-reading granularity (`mg`,
/// `fl oz`) is not kitchen granularity, and a recipe yield is a kitchen fact.
/// An imprecise or `batch` yield opens nothing — neither converts.
const kComponentKitchenUnits = <UnitFamily, List<Unit>>{
  UnitFamily.volume: [cup, tbsp, tsp, ml, pint, quart],
  UnitFamily.mass: [g, kg],
  UnitFamily.count: [pieces],
};

/// A component sheet's chip offer: the ordered `chips`, plus `offFilter` when
/// the stored selection had to be admitted from outside the rule above (it is
/// also the last element of `chips`), so the UI can mark it subtly rather than
/// hide it — the same shape `UnitChoiceOffer` gives the ingredient sheet.
typedef ComponentUnitOffer = ({List<Unit> chips, Unit? offFilter});

/// The chips a component line quantified against [yields] may say, with
/// [stored] (the line's persisted unit) always admitted.
///
/// Order: `batch` first, then for each stated yield its own unit followed by
/// that family's [kComponentKitchenUnits], then the off-filter stored unit.
ComponentUnitOffer componentUnitChips({
  required List<YieldDenomination> yields,
  Unit? stored,
}) {
  final chips = <Unit>[batches];
  for (final denomination in yields) {
    if (!chips.contains(denomination.unit)) chips.add(denomination.unit);
    for (final unit
        in kComponentKitchenUnits[denomination.unit.family] ?? const <Unit>[]) {
      if (!chips.contains(unit)) chips.add(unit);
    }
  }
  final offFilter = stored != null && !chips.contains(stored) ? stored : null;
  if (offFilter != null) chips.add(offFilter);
  return (chips: chips, offFilter: offFilter);
}
