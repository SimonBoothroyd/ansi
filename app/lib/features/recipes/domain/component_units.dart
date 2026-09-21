/// Which units a component line may be denominated in. Pure Dart.
///
/// The offer is the target recipe's measures, then `batch`, then each stated
/// yield's family ([kComponentKitchenUnits]). A recipe has no density, so an
/// unstated family, and any measure in it (ADR-0018), is not offered. The
/// stored selection is always offered, flagged. See [componentUnitChoices].
library;

import '../../../core/result/result.dart';
import '../../../core/units/measure.dart' show kWholeMeasureTolerance;
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/unit_choice.dart';
import '../../../core/units/units.dart';
import 'component_math.dart';
import 'recipe.dart';
import 'recipe_measure_authoring.dart';

/// The units each yield family offers, in chip order. Narrower than the
/// catalog: a component line restates the recipe's own yield. An imprecise or
/// `batch` yield opens nothing.
const kComponentKitchenUnits = <UnitFamily, List<Unit>>{
  UnitFamily.volume: [cup, tbsp, tsp, ml, pint, quart],
  UnitFamily.mass: [g, kg],
  UnitFamily.count: [pieces],
};

/// `batch`, then each stated yield's own unit followed by that family's
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

/// The recipe's whole-batch measure: the live measure whose amount equals the
/// recipe's entire same-family yield within [kWholeMeasureTolerance] (`loaf` =
/// 900 g on a bread that `makes 900 g`); see ADR-0016. Found by comparison,
/// never stored, so it moves with [yields]. Null when none matches. Ties go to
/// the lowest [RecipeMeasure.sortOrder], then label.
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

/// Whether one [measure] is the whole of a stated yield, within
/// `kWholeMeasureTolerance` read relatively.
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

/// A component chip row's offer for [target]: the whole-batch measure
/// ([wholeMeasureOfRecipe]), the other measures as given, `batch`, then the
/// yields' families.
///
/// [measures] are deduped here ([offeredRecipeMeasures]); one that no longer
/// resolves ([recipeMeasureResolvesAgainst]) is dropped. When [current] is
/// outside the computed set it is appended and returned as `offFilter`, so an
/// existing line never silently changes denomination.
UnitChoiceOffer componentUnitChoices(
  SubRecipeTarget target,
  List<RecipeMeasure> measures, {
  UnitChoice? current,
}) {
  final yields = target.yields;
  // Each word once; the line's own row wins its word, so an existing selection
  // lights the chip that line means.
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

/// The chip a fresh component amount opens on: the first of
/// [componentUnitChoices]. Never empty, since `batch` is always offered.
UnitChoice firstComponentChoice(
  SubRecipeTarget target,
  List<RecipeMeasure> measures,
) {
  final choices = componentUnitChoices(target, measures).choices;
  // Totality only: `batch` is always offered, so the offer is never empty.
  return choices.isEmpty ? const UnitOption(batches) : choices.first;
}
