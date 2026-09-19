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
///   `cup · tbsp · tsp · ml · pt · qt`. There is no density for a recipe, so
///   a family the yields do not state is not offered: the fix is the yield's
///   optional SECOND denomination, not a guessed bridge.
/// - The **stored selection is always admitted** (the 7.7 rule, verbatim): an
///   imported line's printed unit stays an offered chip even when the filter
///   would not raise it, flagged as outside the filter and rendered with the
///   honest unresolved conversion line rather than silently rewritten.
///
/// An INGREDIENT measure never appears here: one is a word for a row
/// ("potato, medium = 213 g" says nothing about a recipe). The target
/// **recipe's** own measures do, and they lead the offer — see
/// [componentUnitChoices], which is the shape a chip row actually reads;
/// [componentUnitChips] is the units-only half under it.
library;

import '../../../core/units/measure.dart' show kWholeMeasureTolerance;
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/unit_choice.dart';
import '../../../core/units/units.dart';
import 'component_math.dart';
import 'recipe.dart';

/// The kitchen workhorses each yield family opens, in chip order (design board
/// frame d draws `cup · tbsp · tsp · ml` for a `makes 1 cup` yield; the US pair
/// joined the tail with — a stock that "makes 1 quart" is a kitchen fact too).
///
/// Deliberately narrower than the catalogue, and narrower than an
/// ingredient's admission list: a component line RESTATES the recipe's own
/// stated yield, so the offer is the handful of sizes a cook says a batch in
/// rather than every unit the family holds. An imprecise or `batch` yield
/// opens nothing — neither converts.
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

/// The recipe's **whole-batch measure**: the live measure of [measures] whose
/// `per_batch` is 1, within [kWholeMeasureTolerance] — a word for one whole
/// run of the recipe. `1 loaf` where a batch makes one loaf.
///
/// It is the batch-side analogue of ADR-0016's whole measure, with *one batch*
/// where the piece weight was, and it carries that ADR's first two rules
/// unchanged. **Found, never stored**: a pointer could be re-aimed later and
/// silently change what a saved line meant, while two numbers agreeing is a
/// fact every device and the server's own SQL read the same way. And **it
/// leads every door**: when one exists it heads the offer and a fresh
/// component amount opens on it, with `batch` kept right behind — the two
/// chips say the same batch, and which one leads is read rather than chosen.
///
/// Ties resolve to the lowest [RecipeMeasure.sortOrder], then label, so every
/// reader picks the same one. Null when the recipe coins no word for one whole
/// batch, where `batch` simply leads on its own.
RecipeMeasure? wholeMeasureOfRecipe(List<RecipeMeasure> measures) {
  RecipeMeasure? whole;
  for (final m in measures) {
    if (!m.saysAShare) continue;
    if ((m.perBatch - 1).abs() > kWholeMeasureTolerance) continue;
    if (whole == null ||
        m.sortOrder < whole.sortOrder ||
        (m.sortOrder == whole.sortOrder &&
            m.label.compareTo(whole.label) < 0)) {
      whole = m;
    }
  }
  return whole;
}

/// What a component line's chip row offers for [target], in chip order:
/// **the recipe's own words lead** — the whole-batch one
/// ([wholeMeasureOfRecipe]) first of all, then the rest in the order they are
/// given — then `batch`, then the yields' families exactly as
/// [componentUnitChips] has always ordered them.
///
/// **The words lead, because a word is what this recipe is.** `blob` and
/// `ladle` exist on this sauce and nowhere else; `cup` and `g` are the
/// catalog, offered against every recipe in the household, and a cook
/// reaching for a blob of romesco should not read past six units the sauce
/// shares with everything else to find it. It is the ingredient dock's own
/// rule, one level up.
///
/// [measures] are the target's live ones (callers pass them `sort_order`-
/// sorted, duplicates already merged). Passing none gives exactly the offer
/// this file gave before recipes could coin a word.
///
/// **The stored selection is always offered**: when [current] falls outside
/// the computed set — a merge-hidden duplicate word, a unit outside the
/// yields' families, an imported line's printed unit — it is appended last and
/// returned as `offFilter`, so a surface can mark it as outside the honest
/// filter rather than hide it. That is the 7.7 rule, verbatim, and it is what
/// keeps an existing line from ever rendering an orphaned value.
///
/// The chip a fresh amount opens on is simply the first of this offer
/// ([firstComponentChoice]). A line being EDITED opens on its own stored
/// choice instead, which is its host's business — this only has to make that
/// choice expressible, and `current` is where it goes.
UnitChoiceOffer componentUnitChoices(
  SubRecipeTarget target,
  List<RecipeMeasure> measures, {
  UnitChoice? current,
}) {
  final whole = wholeMeasureOfRecipe(measures);
  final units = componentUnitChips(yields: target.yields).chips;
  final choices = <UnitChoice>[
    if (whole != null) RecipeMeasureOption(whole),
    for (final m in measures)
      if (m.saysAShare && m.id != whole?.id) RecipeMeasureOption(m),
    for (final unit in units) UnitOption(unit),
  ];
  final offFilter = current != null && !choices.contains(current)
      ? current
      : null;
  if (offFilter != null) choices.add(offFilter);
  return (choices: choices, offFilter: offFilter);
}

/// The chip a component amount opens on when nothing is stored: **the first
/// one offered** ([componentUnitChoices]).
///
/// The recipe's whole-batch word when it has one, else its first word, else
/// `batch` — which the units half always fronts, and which is why this is
/// never empty.
UnitChoice firstComponentChoice(
  SubRecipeTarget target,
  List<RecipeMeasure> measures,
) {
  final choices = componentUnitChoices(target, measures).choices;
  // Totality only: `batch` is always offered, so the offer is never empty.
  return choices.isEmpty ? const UnitOption(batches) : choices.first;
}
