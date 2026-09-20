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
/// [componentUnitChoices], which is the shape a chip row reads.
///
/// A recipe measure is a named amount in a unit (ADR-0018), so it obeys the
/// same family rule the units do: a word said in grams is offered only while
/// the recipe states a mass yield, and a `makes` edited away takes the word out
/// of the offer with it. The one exception is the stored selection, which is
/// always offered — see [componentUnitChoices].
library;

import '../../../core/result/result.dart';
import '../../../core/units/measure.dart' show kWholeMeasureTolerance;
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/unit_choice.dart';
import '../../../core/units/units.dart';
import 'component_math.dart';
import 'recipe.dart';
import 'recipe_measure_authoring.dart';

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

/// The catalog units a line quantified against [yields] may say: `batch`,
/// then each stated yield's own unit followed by that family's
/// [kComponentKitchenUnits].
List<Unit> _unitChips(List<YieldDenomination> yields) {
  final chips = <Unit>[batches];
  for (final denomination in yields) {
    if (!chips.contains(denomination.unit)) chips.add(denomination.unit);
    for (final unit
        in kComponentKitchenUnits[denomination.unit.family] ?? const <Unit>[]) {
      if (!chips.contains(unit)) chips.add(unit);
    }
  }
  return chips;
}

/// The recipe's **whole-batch measure**: the live measure of [measures] whose
/// amount is the recipe's ENTIRE same-family yield, within
/// [kWholeMeasureTolerance] — a word for one whole run of the recipe. `loaf` =
/// 900 g on a bread that `makes 900 g`; whatever they called the one thing a
/// recipe that `makes 1 piece` makes.
///
/// It is the batch-side analogue of ADR-0016's whole measure, with *the whole
/// yield* where the piece weight was, and it carries that ADR's first two rules
/// unchanged. **Found, never stored**: a pointer could be re-aimed later and
/// silently change what a saved line meant, while two numbers agreeing is a
/// fact every device and the server's own SQL read the same way. And **it
/// leads every door**: when one exists it heads the offer and a fresh
/// component amount opens on it, with `batch` kept right behind — the two
/// chips say the same batch, and which one leads is read rather than chosen.
///
/// It therefore needs [yields], and it moves when they do: a `makes` restated
/// from `900 g` to `1.8 kg` stops `loaf` leading, which is the truth — a loaf
/// is half a batch now — rather than a regression. Null when the recipe coins
/// no such word, or states no yield at all, where `batch` simply leads on its
/// own.
///
/// Ties resolve to the lowest [RecipeMeasure.sortOrder], then label, so every
/// reader picks the same one.
RecipeMeasure? wholeMeasureOfRecipe(
  List<RecipeMeasure> measures,
  List<YieldDenomination> yields,
) {
  RecipeMeasure? whole;
  for (final m in measures) {
    if (!m.saysAnAmount) continue;
    if (!_isAWholeBatch(m, yields)) continue;
    if (whole == null ||
        m.sortOrder < whole.sortOrder ||
        (m.sortOrder == whole.sortOrder &&
            m.label.compareTo(whole.label) < 0)) {
      whole = m;
    }
  }
  return whole;
}

/// Whether one of [measure] is the whole of a stated yield — the same one part
/// in a hundred, either side, that the ingredient side allows a piece weight
/// (`kWholeMeasureTolerance`, read relatively, as `wholeMeasureOf` reads it).
bool _isAWholeBatch(RecipeMeasure measure, List<YieldDenomination> yields) {
  for (final denomination in yields) {
    if (denomination.unit.family != measure.unit.family) continue;
    final converted = convert(
      Quantity(measure.amount, measure.unit),
      to: denomination.unit,
    );
    if (converted case Ok(:final value)) {
      if ((value.amount - denomination.qty).abs() <=
          kWholeMeasureTolerance * denomination.qty) {
        return true;
      }
    }
  }
  return false;
}

/// What a component line's chip row offers for [target], in chip order:
/// **the recipe's own words lead** — the whole-batch one
/// ([wholeMeasureOfRecipe]) first of all, then the rest in the order they are
/// given — then `batch`, then the yields' families.
///
/// **The words lead, because a word is what this recipe is.** `blob` and
/// `ladle` exist on this sauce and nowhere else; `cup` and `g` are the
/// catalog, offered against every recipe in the household, and a cook
/// reaching for a blob of romesco should not read past six units the sauce
/// shares with everything else to find it. It is the ingredient dock's own
/// rule, one level up.
///
/// [measures] are the target's live ones, `sort_order`-sorted, with any
/// merge-hidden twins behind them — deduped here ([offeredRecipeMeasures]), so
/// a caller never has to know which list it is holding. Passing none gives
/// exactly the offer this file gave before recipes could coin a word.
///
/// **A word the recipe can no longer hold is not offered.** A measure resolves
/// through the yield in its own family, so one said in grams against a recipe
/// that now only says `makes 1.25 cup` cannot be turned into a share of a batch
/// at all ([recipeMeasureResolvesAgainst], which is one call of the real
/// resolution rather than a second reading of the rule). Offering it would put
/// a chip on the row that produces nothing but a refusal — and the fix is the
/// recipe's MAKES, which a chip row is not the place to reach.
///
/// **The stored selection is always offered**, and that exception covers the
/// orphaned word too: when [current] falls outside the computed set — a
/// merge-hidden duplicate word, a word whose yield has been edited away, a unit
/// outside the yields' families, an imported line's printed unit — it is
/// appended last and returned as `offFilter`, so a surface can mark it as
/// outside the honest filter rather than hide it. That is the 7.7 rule,
/// verbatim, and it is what keeps an existing line from ever rendering an
/// orphaned value: a line that already says `blob` still reads `blob`, with the
/// refusal under it, instead of silently becoming a number in some other unit.
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
  final yields = target.yields;
  // The offer says each word once. The loaded list also carries the twins the
  // merge hides — they are there so a LINE can be resolved by id — and the
  // line's own row wins its word here, so an existing selection lights one
  // chip and it is the row that line means.
  final offered = offeredRecipeMeasures(
    measures,
    keep: current is RecipeMeasureOption ? current.measure.id : null,
  );
  final whole = wholeMeasureOfRecipe(offered, yields);
  final units = _unitChips(yields);
  final choices = <UnitChoice>[
    if (whole != null) RecipeMeasureOption(whole),
    for (final m in offered)
      if (m.id != whole?.id && recipeMeasureResolvesAgainst(m, yields))
        RecipeMeasureOption(m),
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
/// The recipe's whole-batch word when it has one, else the first of its words
/// the recipe can still hold, else `batch` — which the units half always
/// fronts, and which is why this is never empty.
UnitChoice firstComponentChoice(
  SubRecipeTarget target,
  List<RecipeMeasure> measures,
) {
  final choices = componentUnitChoices(target, measures).choices;
  // Totality only: `batch` is always offered, so the offer is never empty.
  return choices.isEmpty ? const UnitOption(batches) : choices.first;
}
