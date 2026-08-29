/// Which units a picker may offer for an ingredient — PURE DART (invariant 2).
///
/// Offering every unit in [kAllUnits] lets a user pick a pair that can never
/// convert honestly ("200 cup" of a mass-default ingredient with no density),
/// which splits aggregation into confusing subtotals. This filter keeps the
/// pickers to combinations the unit system can actually resolve
/// (tech-debt-tracker row `shopping/units`).
library;

import 'package:meta/meta.dart';

import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import 'ingredient.dart';

// --- Kitchen ordering & trimming (ADR-0008 §Consequences) --------------------

/// Kitchen display order within each family: the units a cook reaches for
/// first, ahead of metric jugs and customary conversions. The default unit is
/// always fronted; the rest of its admitted family follows in this order.
const _kitchenOrder = {
  UnitFamily.volume: [tsp, tbsp, cup, ml, l, flOz],
  UnitFamily.mass: [g, kg, oz, lb, mg],
};

/// The kitchen-magnitude mates offered alongside each default unit — the
/// ADR-0008 trim: a family is admitted only at magnitudes a kitchen would
/// use near the default ("no litres of yeast", no `mg` anywhere a recipe
/// speaks in cups). Sets, not orderings — display order is [_kitchenOrder]
/// with the default fronted. `mg`/`fl oz` reach a picker only as the default
/// (or admitted stored) unit: they are label-reading granularity, not
/// kitchen granularity.
const _kitchenMates = <Unit, Set<Unit>>{
  tsp: {tsp, tbsp},
  tbsp: {tbsp, tsp, cup, ml},
  cup: {cup, tbsp, ml, l},
  ml: {ml, l, tsp, tbsp, cup},
  l: {l, ml, cup},
  flOz: {flOz, tbsp, cup, ml},
  g: {g, kg},
  kg: {kg, g},
  mg: {mg, g},
  oz: {oz, lb, g},
  lb: {lb, oz, g, kg},
};

/// What a density unlocks of the *other* mass/volume family: the kitchen
/// workhorses only, demoted below measures in display order ("g of milk" is
/// doable but strange — ADR-0008).
const _crossKitchen = {
  UnitFamily.volume: [tsp, tbsp, cup, ml],
  UnitFamily.mass: [g, kg],
};

/// [units] filtered to [family], ordered kitchen-first with [first] fronted.
List<Unit> _kitchenSorted(Set<Unit> units, UnitFamily family, {Unit? first}) {
  return [
    if (first != null && units.contains(first)) first,
    for (final u in _kitchenOrder[family]!)
      if (u != first && units.contains(u)) u,
  ];
}

/// The units a unit picker should offer for [ingredient], in ADR-0008 chip
/// order: default unit first → its family's kitchen mates in kitchen order →
/// the density-unlocked other family (demoted — [allowedUnitChoicesFor]
/// places it after the measures) → imprecise last.
///
/// Derived from the ingredient's `default_unit` and density:
///
/// - the default unit's family, trimmed to kitchen magnitudes near the
///   default ([_kitchenMates] — no `l` for a tsp-default ingredient);
/// - the opposite mass/volume family **only** when the ingredient carries a
///   density — without one, [convert] would fail with `unit/no_density` —
///   and only its kitchen workhorses ([_crossKitchen]);
/// - the [UnitFamily.imprecise] units always ("a pinch" is valid of anything,
///   and never converts or scales anyway — invariant 3).
///
/// A count-default ingredient (eggs, tins) offers only count + imprecise:
/// count converts to nothing else, density or not, so mass/volume would only
/// invite an unresolvable line.
List<Unit> allowedUnitsFor(Ingredient ingredient) {
  final d = ingredient.defaultUnit;
  final units = <Unit>[];
  switch (d.family) {
    case UnitFamily.mass || UnitFamily.volume:
      units.addAll(_kitchenSorted(_kitchenMates[d]!, d.family, first: d));
      if (ingredient.densityGPerMl != null) {
        final other = d.family == UnitFamily.mass
            ? UnitFamily.volume
            : UnitFamily.mass;
        units.addAll(_crossKitchen[other]!);
      }
    case UnitFamily.count:
      units.add(pieces);
    case UnitFamily.imprecise:
      break; // the imprecise tail below carries the default too
  }
  units.addAll([pinch, dash, toTaste]);
  return units;
}

// --- v2: units + the ingredient's live measures (step 7.6) -------------------

/// One entry of a unit picker: either a catalog [Unit] or one of the
/// ingredient's named [Measure]s ("potato, large (299 g)"). Sealed so a picker
/// can switch exhaustively.
@immutable
sealed class UnitChoice {
  const UnitChoice();

  /// The dropdown label.
  String get label;
}

final class UnitOption extends UnitChoice {
  const UnitOption(this.unit);

  final Unit unit;

  @override
  String get label => unit.label;

  @override
  bool operator ==(Object other) => other is UnitOption && other.unit == unit;

  @override
  int get hashCode => unit.hashCode;
}

final class MeasureOption extends UnitChoice {
  const MeasureOption(this.measure);

  final Measure measure;

  @override
  String get label {
    final g = measure.grams;
    final grams = g == g.roundToDouble() ? g.toStringAsFixed(0) : '$g';
    return '${measure.label} ($grams g)';
  }

  @override
  bool operator ==(Object other) =>
      other is MeasureOption && other.measure.id == measure.id;

  @override
  int get hashCode => measure.id.hashCode;
}

/// Whether [label] is just the name of a catalog volume unit ("tbsp",
/// "cup", "ml"…). Measures must never duplicate volume units — density owns
/// volume conversion (frame-b review, plan 0011): the seed pipeline skips
/// FDC volume portions for the same reason, this keeps the chip row / manage
/// UI from offering (or authoring) one that slipped in anyway.
///
/// Robust to casing, surrounding whitespace, and the simple `s` plural
/// ("Cups ", "tbsps") — the trivial disguises a typed label wears.
bool isVolumeUnitLabel(String label) {
  final normalized = label.trim().toLowerCase();
  final singular = normalized.endsWith('s')
      ? normalized.substring(0, normalized.length - 1)
      : null;
  for (final u in kAllUnits) {
    if (u.family != UnitFamily.volume) continue;
    for (final name in [u.id.toLowerCase(), u.label.toLowerCase()]) {
      if (normalized == name || singular == name) return true;
    }
  }
  return false;
}

/// A unit picker's full offer: the filtered `choices`, plus `offFilter` when
/// the stored selection had to be admitted from outside the filter (it is
/// also the last element of `choices`) so the UI can style it subtly
/// ("not in filter") rather than hide it.
typedef UnitChoiceOffer = ({List<UnitChoice> choices, UnitChoice? offFilter});

/// [allowedUnitsFor] plus the ingredient's live [measures], as picker choices
/// in ADR-0008 chip order: the default unit's own set leads, then one
/// [MeasureOption] per measure in the given order (callers pass them
/// `sort_order`-sorted), then the demoted other-family units ("g of milk" —
/// reachable, never fronted), then imprecise last. Measures whose label
/// merely names a volume unit are excluded — see [isVolumeUnitLabel].
///
/// A measure needs no density gate — its stored weight IS the bridge — and it
/// applies to any ingredient that has one, count-default included (that's the
/// whole point: count foods finally reach mass honestly).
///
/// **The stored selection is always offered** (the retired dropdowns' rule —
/// an existing line must never render an orphaned value): when [current] is
/// set and falls outside the computed set — a merge-hidden duplicate measure,
/// a cross-family unit whose density was removed, a unit the kitchen trim
/// dropped — it is appended last and returned as `offFilter`, so every entry
/// surface inherits the guarantee and can still mark the chip as outside the
/// honest filter.
UnitChoiceOffer allowedUnitChoicesFor(
  Ingredient ingredient,
  List<Measure> measures, {
  UnitChoice? current,
}) {
  final defaultFamily = ingredient.defaultUnit.family;
  // A mass/volume unit outside the default unit's family is a demoted
  // admission (density- or basis-unlocked): offered, but after the measures.
  bool demoted(Unit u) =>
      (u.family == UnitFamily.mass || u.family == UnitFamily.volume) &&
      u.family != defaultFamily;

  final units = allowedUnitsFor(ingredient);
  final choices = <UnitChoice>[
    for (final u in units)
      if (!demoted(u) && u.family != UnitFamily.imprecise) UnitOption(u),
    for (final m in measures)
      if (!isVolumeUnitLabel(m.label)) MeasureOption(m),
    for (final u in units)
      if (demoted(u)) UnitOption(u),
    for (final u in units)
      if (u.family == UnitFamily.imprecise) UnitOption(u),
  ];
  final offFilter = current != null && !choices.contains(current)
      ? current
      : null;
  if (offFilter != null) choices.add(offFilter);
  return (choices: choices, offFilter: offFilter);
}
