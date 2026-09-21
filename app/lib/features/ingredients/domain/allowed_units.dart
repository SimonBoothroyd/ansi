/// Which units a picker may offer for an ingredient. Pure Dart (invariant 2).
///
/// A row may be said in its basis family, in the other mass/volume family once
/// a density bridges the two, in `piece` when it is counted and states a piece
/// weight, and in the imprecise words its category earns. The household prunes
/// the rest row by row. See ADR-0014 and ADR-0015.
library;

import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/unit_choice.dart';
import '../../../core/units/unit_words.dart';
import '../../../core/units/units.dart';
import 'ingredient.dart';
import 'serving_measure.dart';

// Re-exported so surfaces that read the offer need one import.
export '../../../core/units/measure.dart' show kWholeMeasureTolerance;
export '../../../core/units/unit_choice.dart';
export '../../../core/units/unit_words.dart'
    show isVolumeUnitLabel, unitFromLabel, volumeUnitFromLabel;

// --- Kitchen ordering (ADR-0008 §Consequences) -------------------------------

/// Kitchen display order within each family. Order only: admission is
/// [_derivedSet]'s answer, and [_orderUnits] appends any catalog unit missing
/// here. The row's own measures lead the whole offer ([allowedUnitChoicesFor]).
const _kitchenOrder = {
  UnitFamily.volume: [tsp, tbsp, flOz, cup, ml, l, pint, quart],
  UnitFamily.mass: [g, kg, oz, lb],
};

/// The units an amount stored in the row's basis (a measure's weight, a piece's
/// weight) may be typed in: the basis family in kitchen order, plus the other
/// mass/volume family while a density bridges them (ADR-0009). The entry-side
/// twin of [allowedUnitsFor].
List<Unit> basisConvertibleUnits(Ingredient ingredient) {
  final basisFamily = ingredient.macrosBasis.baseUnit.family;
  final other = basisFamily == UnitFamily.mass
      ? UnitFamily.volume
      : UnitFamily.mass;
  return [
    ..._kitchenOrder[basisFamily]!,
    if (ingredient.densityGPerMl != null) ..._kitchenOrder[other]!,
  ];
}

/// Every catalog unit of [family]. A mass/volume family is admitted whole or
/// not at all, so this is the rule's unit of admission as well as a roster.
Iterable<Unit> _familyUnits(UnitFamily family) =>
    kIngredientUnits.where((u) => u.family == family);

/// Which categories admit which imprecise word, gated per word (ADR-0008 §5):
/// pinch and dash for spices, seasonings and oils, handful for greens.
///
/// Keys are the vocab's actual category values. There is no greens category, so
/// `handful` is gated on `produce`; condiment-like pantry rows get theirs
/// through curation overrides.
const kImpreciseCategoryGates = <Unit, Set<String>>{
  pinch: {'spices & seasoning', 'fats & oils'},
  dash: {'spices & seasoning', 'fats & oils'},
  handful: {'produce', 'spices & seasoning'},
  toTaste: {'spices & seasoning', 'fats & oils'},
};

/// The imprecise units [ingredient]'s category earns, plus its default unit
/// when that is itself imprecise. The import editor also admits `to taste` for
/// every food; see `importImpreciseUnitsFor`.
Set<Unit> impreciseUnitsFor(Ingredient ingredient) {
  final category = ingredient.category?.trim().toLowerCase();
  final d = ingredient.defaultUnit;
  return {
    if (d.family == UnitFamily.imprecise) d,
    for (final gate in kImpreciseCategoryGates.entries)
      if (category != null && gate.value.contains(category)) gate.key,
  };
}

/// The derived allowed-unit defaults for [ingredient]: the Dart mirror of the
/// database's `default_allowed_units()` (change both; `unit_admission.sql` and
/// the tests pin the same vectors). The fallback for a row with no explicit
/// list. See ADR-0014 and ADR-0015.
///
/// - The basis family, whole ([Ingredient.macrosBasis]).
/// - The other mass/volume family, only while a density is stored
///   ([densityUnlockedUnits]); without one [convert] fails with
///   `unit/no_density`.
/// - `piece`, only on a count-default row with a piece weight
///   ([Ingredient.pieceBasisAmount]).
/// - The imprecise words per [kImpreciseCategoryGates], plus an imprecise
///   default's own word.
///
/// [unitSayableAsDefault] covers the default unit itself.
Set<Unit> defaultAllowedUnitSet(Ingredient ingredient) => _derivedSet(
  ingredient,
  density: ingredient.densityGPerMl != null,
  piece: ingredient.pieceBasisAmount != null,
);

/// [defaultAllowedUnitSet] with the density and piece-weight legs forced on or
/// off, for the counterfactuals [allowedUnitCandidates], [densityStrippedUnits]
/// and [pieceStrippedUnits] ask.
Set<Unit> _derivedSet(
  Ingredient ingredient, {
  required bool density,
  required bool piece,
}) {
  final basisFamily = ingredient.macrosBasis == MacrosBasis.perMl
      ? UnitFamily.volume
      : UnitFamily.mass;
  final otherFamily = basisFamily == UnitFamily.mass
      ? UnitFamily.volume
      : UnitFamily.mass;
  return {
    ..._familyUnits(basisFamily),
    if (density) ..._familyUnits(otherFamily),
    // `batch` is never an ingredient's unit. `piece` needs both a count default
    // and a piece weight (ADR-0015).
    if (ingredient.defaultUnit.family == UnitFamily.count && piece) pieces,
    ...impreciseUnitsFor(ingredient),
  };
}

/// What a stored density buys [ingredient]: the rule with the density on, minus
/// the rule with it off, which is the whole other family. The density write
/// path unions exactly this into the explicit list.
Set<Unit> densityUnlockedUnits(Ingredient ingredient) {
  final piece = ingredient.pieceBasisAmount != null;
  return _derivedSet(
    ingredient,
    density: true,
    piece: piece,
  ).difference(_derivedSet(ingredient, density: false, piece: piece));
}

/// The units admitted only because a density is stored, which deleting it takes
/// away; the basis family always survives. The one removal leg in the admission
/// model (see ADR-0009's note on density deletion).
Set<Unit> densityStrippedUnits(Ingredient ingredient) =>
    densityUnlockedUnits(ingredient);

/// What a stored piece weight buys [ingredient]: `piece` on a count-default
/// row, nothing elsewhere (ADR-0015). Derived as [densityUnlockedUnits] is.
Set<Unit> pieceUnlockedUnits(Ingredient ingredient) {
  final density = ingredient.densityGPerMl != null;
  return _derivedSet(
    ingredient,
    density: density,
    piece: true,
  ).difference(_derivedSet(ingredient, density: density, piece: false));
}

/// The piece weight as a [Measure] the converter understands. Null when the row
/// has no weight.
Measure? pieceAsMeasure(Ingredient ingredient) {
  final amount = ingredient.pieceBasisAmount;
  if (amount == null) return null;
  return Measure(
    id: 'piece',
    label: 'piece',
    amount: amount,
    basis: ingredient.macrosBasis,
  );
}

/// The row's whole measure: the live measure whose amount equals the row's
/// piece weight ([Ingredient.pieceBasisAmount], within
/// [kWholeMeasureTolerance]), or null. See ADR-0016.
///
/// Derived by weight, never stored as a pointer, so a saved line cannot
/// silently change meaning. Skips a measure that merely names a volume unit
/// ([isVolumeUnitLabel]) and the row's serving ([isServingMeasure]). Ties
/// resolve to the lowest [Measure.sortOrder], then label.
Measure? wholeMeasureOf(Ingredient ingredient, List<Measure> measures) {
  final weight = ingredient.pieceBasisAmount;
  if (weight == null || !(weight > 0)) return null;
  Measure? whole;
  for (final m in measures) {
    if (isVolumeUnitLabel(m.label) || isServingMeasure(m)) continue;
    if ((m.amount - weight).abs() > kWholeMeasureTolerance * weight) continue;
    if (whole == null ||
        m.sortOrder < whole.sortOrder ||
        (m.sortOrder == whole.sortOrder &&
            m.label.compareTo(whole.label) < 0)) {
      whole = m;
    }
  }
  return whole;
}

/// The `piece` chip's label: `piece (350 g)` on a row that states a piece
/// weight, else the bare word.
String pieceChipLabel(Ingredient ingredient) {
  final amount = ingredient.pieceBasisAmount;
  if (amount == null) return pieces.label;
  final basis = ingredient.macrosBasis.baseUnit;
  return '${pieces.label} (${formatAmountIn(amount, basis)} ${basis.label})';
}

/// The units admitted only because a piece weight is stored; the mirror of
/// [densityStrippedUnits].
Set<Unit> pieceStrippedUnits(Ingredient ingredient) =>
    pieceUnlockedUnits(ingredient);

/// Whether the stored default is a mass/volume unit outside the basis family
/// with no density to bridge it (`cup` on a per-100 g row). The form flags it
/// with [basisDefaultUnitFix] and refuses Save while it holds; it is never
/// repaired silently.
bool defaultUnitNeedsDensity(Ingredient ingredient) =>
    ingredient.densityGPerMl == null &&
    !unitSayableAsDefault(ingredient, ingredient.defaultUnit);

/// The count-side stranded default (ADR-0015): a `piece` default with no piece
/// weight. Flagged and refused at Save like [defaultUnitNeedsDensity]. Not
/// folded into [unitSayableAsDefault], because picking `piece` is what reveals
/// the weight field.
bool defaultUnitNeedsPieceWeight(Ingredient ingredient) =>
    ingredient.defaultUnit.family == UnitFamily.count &&
    ingredient.pieceBasisAmount == null;

/// Whether [ingredient]'s stored default is stranded for EITHER reason — the
/// one predicate a Save gate or a status line should ask.
bool defaultUnitStranded(Ingredient ingredient) =>
    defaultUnitNeedsDensity(ingredient) ||
    defaultUnitNeedsPieceWeight(ingredient);

/// Whether [unit] may be chosen as [ingredient]'s default: the basis family,
/// count and imprecise always; the other mass/volume family only with a
/// density.
bool unitSayableAsDefault(Ingredient ingredient, Unit unit) {
  if (unit.family != UnitFamily.mass && unit.family != UnitFamily.volume) {
    return true;
  }
  final basisFamily = ingredient.macrosBasis == MacrosBasis.perMl
      ? UnitFamily.volume
      : UnitFamily.mass;
  return unit.family == basisFamily || ingredient.densityGPerMl != null;
}

/// The unit the one-tap fix switches a stranded default to: the basis family's
/// natural unit (`g` for a per-100 g row, `ml` for per-100 ml).
Unit basisDefaultUnitFix(Ingredient ingredient) =>
    ingredient.macrosBasis.baseUnit;

/// The default-unit row's offer: the units that may be chosen now, and those a
/// missing density keeps out, in chip order.
typedef DefaultUnitOffer = ({List<Unit> choices, List<Unit> needDensity});

/// What the default-unit chip row draws: the units passing
/// [unitSayableAsDefault], with the rest named under the row. The stored
/// default is always a chip, even when stranded ([defaultUnitStranded] paints
/// it). `piece` is offered with no piece weight yet; see
/// [defaultUnitNeedsPieceWeight].
DefaultUnitOffer defaultUnitOfferFor(Ingredient ingredient) {
  final choices = <Unit>[];
  final needDensity = <Unit>[];
  for (final u in kIngredientUnits) {
    if (unitSayableAsDefault(ingredient, u) || u == ingredient.defaultUnit) {
      choices.add(u);
    } else {
      needDensity.add(u);
    }
  }
  return (choices: choices, needDensity: _orderUnits(needDensity, ingredient));
}

/// Orders a unit set into chip order: the default unit first (whatever its
/// family), the rest of its family in kitchen order, count, the other
/// mass/volume family, imprecise last. Stored `allowed_units` is a set, so
/// display order comes only from here.
List<Unit> _orderUnits(Iterable<Unit> unitsIn, Ingredient ingredient) {
  final remaining = unitsIn.toSet();
  final d = ingredient.defaultUnit;
  final basisFamily = ingredient.macrosBasis == MacrosBasis.perMl
      ? UnitFamily.volume
      : UnitFamily.mass;
  final out = <Unit>[];
  void take(Unit u) {
    if (remaining.remove(u)) out.add(u);
  }

  if (d.family == UnitFamily.imprecise) take(d);
  if (d.family == UnitFamily.mass || d.family == UnitFamily.volume) {
    take(d);
    _kitchenOrder[d.family]!.forEach(take);
  }
  take(pieces);
  final demotedFamilies = switch (d.family) {
    UnitFamily.mass => const [UnitFamily.volume],
    UnitFamily.volume => const [UnitFamily.mass],
    _ =>
      basisFamily == UnitFamily.mass
          ? const [UnitFamily.mass, UnitFamily.volume]
          : const [UnitFamily.volume, UnitFamily.mass],
  };
  for (final family in demotedFamilies) {
    _kitchenOrder[family]!.forEach(take);
  }
  for (final u in [pinch, dash, handful, toTaste]) {
    take(u);
  }
  // Totality: anything the groups above don't know still renders (a future
  // catalog unit must degrade to "offered late", never "silently hidden").
  out.addAll(remaining);
  return out;
}

/// The catalog units a picker offers for [ingredient], in chip order.
/// [allowedUnitChoicesFor] puts the row's measures in front.
///
/// Reads the explicit [Ingredient.allowedUnits] when the row carries one, else
/// [defaultAllowedUnitSet]. An explicit list cannot make a unit sayable that no
/// density supports: those units are subtracted while the number is missing,
/// and a recipe line still saying one degrades to the `unitNotAllowed` flag.
List<Unit> allowedUnitsFor(Ingredient ingredient) {
  final explicit = ingredient.allowedUnits;
  // A row can always say its own default unit. Unioned before the fences below,
  // so a default the numbers cannot support still reads as stranded.
  final set =
      (explicit == null || explicit.isEmpty
            ? defaultAllowedUnitSet(ingredient)
            : {...explicit})
        ..add(ingredient.defaultUnit);
  if (ingredient.densityGPerMl == null) {
    set.removeAll(densityStrippedUnits(ingredient));
  }
  // The count-side fence (ADR-0015): no `piece` without a piece weight, or on a
  // row whose default is not a count. A stored line saying it is offered
  // off-filter.
  if (ingredient.pieceBasisAmount == null ||
      ingredient.defaultUnit.family != UnitFamily.count) {
    set.remove(pieces);
  }
  return _orderUnits(set, ingredient);
}

/// One chip of the ingredient form's admission editor.
typedef UnitAdmission = ({Unit unit, bool selected, bool locked});

/// The admission editor's chips, in chip order: every catalog mass/volume unit
/// and imprecise word, plus `piece` on a count-default row.
///
/// `selected` chips are what a line may say today. `locked` chips (the other
/// family with no density, `piece` with no piece weight) are drawn dashed, even
/// when the stored list names them. The basis family is never locked.
List<UnitAdmission> allowedUnitCandidates(Ingredient ingredient) {
  final selected = allowedUnitsFor(ingredient).toSet();
  // Empty while a density is stored — nothing is density-locked then.
  final needsDensity = ingredient.densityGPerMl == null
      ? densityStrippedUnits(ingredient)
      : const <Unit>{};
  final countDefault = ingredient.defaultUnit.family == UnitFamily.count;
  final needsPieceWeight = countDefault && ingredient.pieceBasisAmount == null
      ? const {pieces}
      : const <Unit>{};
  final locked = {...needsDensity, ...needsPieceWeight};
  final all = {
    ...selected,
    ...defaultAllowedUnitSet(ingredient),
    ..._familyUnits(UnitFamily.mass),
    ..._familyUnits(UnitFamily.volume),
    ..._familyUnits(UnitFamily.imprecise),
    if (countDefault) pieces,
  };
  // `piece` on a non-count row is not drawn, and the next save drops it.
  if (!countDefault) all.remove(pieces);
  return [
    for (final u in _orderUnits(all, ingredient))
      (
        unit: u,
        selected: selected.contains(u) && !locked.contains(u),
        locked: locked.contains(u),
      ),
  ];
}

// --- Units plus the ingredient's live measures -------------------------------

/// [allowedUnitsFor] plus the row's live [measures] as picker choices. Measures
/// lead: the whole measure ([wholeMeasureOf]) first, then the rest in the given
/// (`sort_order`) order, then the catalog units.
///
/// - A measure that merely names a volume unit ([isVolumeUnitLabel]) and the
///   row's serving ([isServingMeasure]) are never offered.
/// - An imprecise default unit leads the catalog half, once.
/// - A measure needs no density gate; its stored weight is the bridge.
/// - [current] is always offered: outside the computed set it is appended last
///   and returned as `offFilter`.
///
/// A surface opens on the first choice ([firstOfferedChoice]).
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
  final whole = wholeMeasureOf(ingredient, measures);
  // An imprecise default leads the catalog instead of sinking to the tail.
  final leadWord = defaultFamily == UnitFamily.imprecise
      ? ingredient.defaultUnit
      : null;
  final choices = <UnitChoice>[
    if (whole != null) MeasureOption(whole),
    for (final m in measures)
      if (!isVolumeUnitLabel(m.label) &&
          !isServingMeasure(m) &&
          m.id != whole?.id)
        MeasureOption(m),
    if (leadWord != null && units.contains(leadWord)) UnitOption(leadWord),
    for (final u in units)
      if (!demoted(u) && u.family != UnitFamily.imprecise) UnitOption(u),
    for (final u in units)
      if (demoted(u)) UnitOption(u),
    for (final u in units)
      if (u.family == UnitFamily.imprecise && u != leadWord) UnitOption(u),
  ];
  final offFilter = current != null && !choices.contains(current)
      ? current
      : null;
  if (offFilter != null) choices.add(offFilter);
  return (choices: choices, offFilter: offFilter);
}

/// The chip a quantity surface opens on when nothing is stored: the first one
/// offered by [allowedUnitChoicesFor].
UnitChoice firstOfferedChoice(Ingredient ingredient, List<Measure> measures) {
  final choices = allowedUnitChoicesFor(ingredient, measures).choices;
  // Totality only: the basis family is always admitted, so the offer is never
  // actually empty.
  return choices.isEmpty ? UnitOption(ingredient.defaultUnit) : choices.first;
}
