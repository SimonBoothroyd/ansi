/// Which units a picker may offer for an ingredient — PURE DART (invariant 2).
///
/// Offering every unit in [kAllUnits] lets a user pick a pair that can never
/// convert honestly ("200 cup" of a mass-default ingredient with no density),
/// which splits aggregation into confusing subtotals. This filter keeps the
/// pickers to combinations the unit system can actually resolve
/// (tech-debt-tracker row `shopping/units`).
library;

import 'package:meta/meta.dart';

import '../../../core/units/macros.dart';
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

/// Which categories admit which imprecise word (ADR-0008 §5: category-gated,
/// not universal — tightened per-WORD by plan 0020 **J3**).
///
/// The gate used to be one set of categories admitting all four words, so
/// anything that earned `pinch` earned `handful` too. It was also bypassed
/// entirely on the import surface, which is how "a dash of kale" came to be
/// offered on the owner's phone. Owner ruling: **pinch and dash are for the
/// spice/seasoning/oil classes; handful is for greens** — that is how cooks
/// actually talk.
///
/// Keys are the vocab's ACTUAL category values (`produce`, `pantry`,
/// `spices & seasoning`, `grains`, `baking`, `fats & oils`, `dairy`,
/// `proteins`). It has no separate 'condiment' category (plan 0013 note), and
/// no leafy/greens category either — `produce` is the nearest thing the
/// vocabulary can express, so it is what `handful` is gated on; a tighter
/// gate would need the seed to split the category, not this map to grow.
/// Condiment-ish pantry rows get theirs via curation overrides.
const kImpreciseCategoryGates = <Unit, Set<String>>{
  pinch: {'spices & seasoning', 'fats & oils'},
  dash: {'spices & seasoning', 'fats & oils'},
  handful: {'produce', 'spices & seasoning'},
  toTaste: {'spices & seasoning', 'fats & oils'},
};

/// The imprecise units [ingredient]'s own category earns it (**J3**), plus its
/// default unit when that is itself imprecise — a row defaulting to `pinch`
/// must always be able to say `pinch`.
///
/// This is the vocab rule. The import amount editor admits `to taste` on top
/// of it for every food, because "plus more, to serve" is legitimately
/// imprecise whatever the ingredient — see `importImpreciseUnitsFor`.
Set<Unit> impreciseUnitsFor(Ingredient ingredient) {
  final category = ingredient.category?.trim().toLowerCase();
  final d = ingredient.defaultUnit;
  return {
    if (d.family == UnitFamily.imprecise) d,
    for (final gate in kImpreciseCategoryGates.entries)
      if (category != null && gate.value.contains(category)) gate.key,
  };
}

/// The ADR-0008 **derived** allowed-unit defaults for [ingredient] — the
/// Dart mirror of the database's `default_allowed_units()` (migration 0012;
/// change one, change both — `unit_admission.sql` and the tests here pin
/// the same vectors). Used as the fallback when a row carries no explicit
/// list (legacy/unsynced rows, freshly typed local stubs), and as the rule
/// the seed pipeline materializes:
///
/// - the **basis family** ([Ingredient.macrosBasis]: /g → weights, /ml →
///   volumes) — the canonical dimension is always sayable, so yeast (tsp
///   default, per-g macros) admits `g`;
/// - the default unit's family, trimmed to kitchen magnitudes near the
///   default ([_kitchenMates] — no `l` for a tsp-default ingredient), **but
///   only when that family IS the basis family, or a density is stored**
///   (plan 0020 **D4c**): being the unit a shop sells the thing in does not
///   make a dimension convertible. A tsp-default per-100 g row with no
///   density cannot honestly say "2 tsp" of anything a macro total reads, so
///   it does not admit spoons until the number that bridges them exists;
/// - the opposite mass/volume family **only** when the ingredient carries a
///   density ([densityUnlockedUnits] — without one, [convert] would fail
///   with `unit/no_density`); since the plan-0020 D4 amendment this fires
///   for a count/imprecise default too ("1 cup diced mango");
/// - the imprecise units per [kImpreciseCategoryGates] — gated word by word
///   since J3, so greens earn `handful` without earning `pinch` (and for
///   imprecise-default rows, their own word).
///
/// A count-default ingredient (eggs, tins) offers count + the basis base:
/// a gram line of a per-g count food computes macros directly, while
/// count↔count needs no conversion at all.
Set<Unit> defaultAllowedUnitSet(Ingredient ingredient) =>
    _derivedSet(ingredient, density: ingredient.densityGPerMl != null);

/// [defaultAllowedUnitSet] with the density leg forced on or off, so callers
/// can ask the counterfactual — "what would this row admit *with* a density"
/// ([allowedUnitCandidates]' locked chips) and "what does it admit *without*
/// one" ([densityStrippedUnits]) — without minting a copy of the row.
Set<Unit> _derivedSet(Ingredient ingredient, {required bool density}) {
  final d = ingredient.defaultUnit;
  final basisFamily = ingredient.macrosBasis == MacrosBasis.perMl
      ? UnitFamily.volume
      : UnitFamily.mass;
  // Cup/lb-scale defaults justify the big metric sibling (kg / l); spoons
  // and grams don't ("no litres of yeast" applies to kilograms too).
  final big = d == cup || d == lb || d == l || d == kg;

  final units = <Unit>{};
  switch (d.family) {
    // **D4c.** The default unit's family is not an admission source of its
    // own: it rides on the basis family (which needs nothing) or on the
    // density (which is the only honest bridge to the other one). Count and
    // imprecise defaults are untouched — they sit outside the mass⇄volume
    // duality entirely, so there is no bridge for them to be missing.
    case UnitFamily.mass || UnitFamily.volume:
      if (density || d.family == basisFamily) units.addAll(_kitchenMates[d]!);
    case UnitFamily.count:
      units.add(pieces);
    case UnitFamily.imprecise:
      break; // joins the imprecise tail below
  }

  // Basis leg: entry in the canonical dimension is always honest.
  if (basisFamily != d.family) {
    units.add(basisFamily == UnitFamily.mass ? g : ml);
    if (big) units.add(basisFamily == UnitFamily.mass ? kg : l);
  }

  // Density leg: a stored density unlocks the other mass/volume family —
  // whatever the default unit's family (ADR-0008 as amended, plan 0020 D4).
  if (density) {
    units.addAll(_densityCrossLeg(ingredient));
  }

  // Imprecise leg: gated per WORD by category (J3), and an imprecise default
  // always keeps its own word.
  units.addAll(impreciseUnitsFor(ingredient));
  return units;
}

/// The cross-family workhorses a density bridges to, by default unit — the
/// raw ADR-0008 §2 leg, before [_derivedSet] folds it in.
///
/// **ADR-0008 as amended (plan 0020 D4).** A density is a property of the
/// substance, not of how the shop sells it: a mango is bought by the piece
/// and still has a cup. So the unlock does not depend on the default unit's
/// family. A count- or imprecise-default row has no "other" family, so it
/// bridges to BOTH families' workhorses — the big metric siblings staying
/// behind the same `big` gate the mass/volume legs use, which is why Mango's
/// `kg` chip stays locked on the board frame while `cup` opens.
///
/// Not the public answer to "what does a density buy this row": that is
/// [densityUnlockedUnits], which since D4c also counts the default unit's
/// own family when the density is the only thing admitting it.
Set<Unit> _densityCrossLeg(Ingredient ingredient) {
  final d = ingredient.defaultUnit;
  final big = d == cup || d == lb || d == l || d == kg;
  return switch (d.family) {
    UnitFamily.mass => _crossKitchen[UnitFamily.volume]!.toSet(),
    UnitFamily.volume => {g, if (big) kg},
    UnitFamily.count || UnitFamily.imprecise => {
      ..._crossKitchen[UnitFamily.volume]!,
      g,
      if (big) kg,
    },
  };
}

/// What a stored density actually buys [ingredient]: the whole rule read with
/// the density on, minus the whole rule read with it off.
///
/// Derived rather than listed (plan 0020 **D4c**), which is what keeps it
/// honest in both directions — the density write path unions exactly this
/// into the EXPLICIT `allowed_units` list, and [densityStrippedUnits] takes
/// exactly this back. Before D4c this was the cross-family leg alone, and a
/// density landing on a cup-default per-100 g row unioned `g` (already
/// admitted) while leaving `cup` — the row's OWN default — unadmitted.
///
/// - Mango (piece default, per-g macros) → `tsp, tbsp, cup, ml`.
/// - Flour (cup default, per-g macros) → `cup, tbsp, ml, l`: since D4c the
///   volume family is the density's to give, default unit or not.
/// - Milk (ml default, per-ml macros) → `g`.
Set<Unit> densityUnlockedUnits(Ingredient ingredient) => _derivedSet(
  ingredient,
  density: true,
).difference(_derivedSet(ingredient, density: false));

/// The units an ingredient admits **only because a density is stored** — what
/// deleting that density takes away again (plan 0020 **D4b**).
///
/// The same rule as [densityUnlockedUnits], read in the opposite direction:
/// what a density adds is exactly what deleting it removes. The **basis
/// family** (per-100 g ⇒ mass, per-100 ml ⇒ volume) always survives, because
/// it never needed a density to be sayable.
///
/// This is the one removal leg in the whole admission model. ADR-0009's
/// union-never-remove rule still governs backfills and reseeds; a density
/// **deletion** is different in kind, because that admission was *derived*
/// from the number being deleted — see the ADR's D4b refinement note.
Set<Unit> densityStrippedUnits(Ingredient ingredient) =>
    densityUnlockedUnits(ingredient);

/// Whether [ingredient]'s stored default unit is one its own admission rules
/// no longer support: a mass/volume default on the far side of the basis
/// family, with no density to bridge it (plan 0020 **D4c** — the renamed-rice
/// shape, `cup` default on a per-100 g row).
///
/// The form draws this as a flag with a one-tap fix ([basisDefaultUnitFix]).
/// It is never repaired silently: a default unit is a statement about how the
/// household buys the thing, and quietly rewriting it would lose that.
bool defaultUnitNeedsDensity(Ingredient ingredient) =>
    ingredient.densityGPerMl == null &&
    !unitSayableAsDefault(ingredient, ingredient.defaultUnit);

/// Whether [unit] may be *chosen* as [ingredient]'s default (**D4c**): the
/// basis family, count and imprecise always; the other mass/volume family
/// only while a density bridges it.
bool unitSayableAsDefault(Ingredient ingredient, Unit unit) {
  if (unit.family != UnitFamily.mass && unit.family != UnitFamily.volume) {
    return true;
  }
  final basisFamily = ingredient.macrosBasis == MacrosBasis.perMl
      ? UnitFamily.volume
      : UnitFamily.mass;
  return unit.family == basisFamily || ingredient.densityGPerMl != null;
}

/// The unit the one-tap D4c fix switches a stranded default to: the basis
/// family's natural unit (`g` for a per-100 g row, `ml` for per-100 ml).
Unit basisDefaultUnitFix(Ingredient ingredient) =>
    ingredient.macrosBasis.baseUnit;

/// Orders an allowed-unit set into ADR-0008 chip order: the default unit
/// fronted, the rest of its family in kitchen order, count next, then the
/// demoted other mass/volume family (basis family first when both are
/// demoted), imprecise last. Stored `allowed_units` is a SET — this is the
/// single place display order comes from.
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

/// The units a unit picker should offer for [ingredient], in ADR-0008 chip
/// order (default first → its family in kitchen order → the demoted other
/// family, which [allowedUnitChoicesFor] places after the measures →
/// imprecise last).
///
/// Reads the **explicit per-ingredient list** ([Ingredient.allowedUnits],
/// migration 0012) when the row carries one — explicit beats derived, and
/// the flesh-out form owns it from creation on. A row without one (legacy,
/// unsynced, a freshly typed local stub) falls back to the same ADR
/// defaults the server materializes ([defaultAllowedUnitSet]).
///
/// **One thing an explicit list cannot do (D4b, widened by D4c): make a unit
/// sayable that no density supports.** A list naming `cup` on a row with no
/// density arrives from plenty of honest places — a server materialization
/// written under the looser pre-D4c rule, an older client, a density deleted
/// where the list did not follow — and offering it would hand the converter a
/// pair it cannot resolve. The density-derived units are subtracted while the
/// number is missing; the editor was already drawing exactly these chips
/// locked, and a recipe line still saying one degrades to the standard
/// `unitNotAllowed` flag rather than being rewritten.
List<Unit> allowedUnitsFor(Ingredient ingredient) {
  final explicit = ingredient.allowedUnits;
  final set = explicit == null || explicit.isEmpty
      ? defaultAllowedUnitSet(ingredient)
      : {...explicit};
  if (ingredient.densityGPerMl == null) {
    set.removeAll(densityStrippedUnits(ingredient));
  }
  return _orderUnits(set, ingredient);
}

/// One chip of the flesh-out form's admission editor (board `pv2-d2`, step
/// 7.8 — the section that never got built until 8.5).
typedef UnitAdmission = ({Unit unit, bool selected, bool locked});

/// The admission editor's chips for [ingredient], in ADR-0008 chip order.
///
/// Three states, which is the whole point of the section: `selected` chips
/// are what a line may say today; unselected-and-unlocked chips are ones the
/// ADR would admit and the user has turned off (or not yet on); `locked`
/// chips are the dashed ones — units only a **density** would unlock, drawn
/// rather than hidden so the form explains what entering a density buys.
///
/// A stored unit outside the derived rules still appears, selected and
/// unlocked: an explicit list is user-owned and must never be silently
/// dropped by an editor that only understands the defaults.
///
/// **D4b — the cross-family leg is density-derived, so it locks with the
/// density.** A chip is locked when it is a [densityStrippedUnits] admission
/// on a row that carries no density, *even if the stored list still names
/// it*: a list can arrive that way from a device that wrote it before the
/// density was deleted, and the editor must say what the number actually
/// supports rather than what the list happens to hold. The basis family and
/// the default unit's own family are never locked — they need no density.
List<UnitAdmission> allowedUnitCandidates(Ingredient ingredient) {
  final selected = allowedUnitsFor(ingredient).toSet();
  final admissible = defaultAllowedUnitSet(ingredient);
  // The same rules re-run as if a density existed: the difference is exactly
  // what a density would unlock.
  final withDensity = _derivedSet(ingredient, density: true);
  // Empty while a density is stored — nothing is density-locked then.
  final needsDensity = ingredient.densityGPerMl == null
      ? densityStrippedUnits(ingredient)
      : const <Unit>{};
  final all = {...selected, ...admissible, ...withDensity};
  return [
    for (final u in _orderUnits(all, ingredient))
      (
        unit: u,
        selected: selected.contains(u) && !needsDensity.contains(u),
        locked:
            needsDensity.contains(u) ||
            (!admissible.contains(u) && !selected.contains(u)),
      ),
  ];
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
    final a = measure.amount;
    final amount = a == a.roundToDouble() ? a.toStringAsFixed(0) : '$a';
    return '${measure.label} ($amount ${measure.basis.baseUnit.label})';
  }

  @override
  bool operator ==(Object other) =>
      other is MeasureOption && other.measure.id == measure.id;

  @override
  int get hashCode => measure.id.hashCode;
}

/// The catalog volume unit a bare [label] names ("tbsp", "Cups ", "ml"…),
/// or null when it names none. Measures must never duplicate volume units —
/// density owns volume conversion (frame-b review, plan 0011; ADR-0008 §2:
/// a volume-named weight mapping IS a density) — so the add-measure form
/// uses the resolved unit to REDIRECT the entry into density instead of
/// merely refusing it.
///
/// Robust to casing, surrounding whitespace, and the simple `s` plural
/// ("Cups ", "tbsps") — the trivial disguises a typed label wears.
Unit? volumeUnitFromLabel(String label) {
  final normalized = label.trim().toLowerCase();
  final singular = normalized.endsWith('s')
      ? normalized.substring(0, normalized.length - 1)
      : null;
  for (final u in kAllUnits) {
    if (u.family != UnitFamily.volume) continue;
    for (final name in [u.id.toLowerCase(), u.label.toLowerCase()]) {
      if (normalized == name || singular == name) return u;
    }
  }
  return null;
}

/// Whether [label] is just the name of a catalog volume unit — see
/// [volumeUnitFromLabel]. Keeps the chip row / manage UI from offering (or
/// authoring) a volume-named measure that slipped in anyway; the seed
/// pipeline skips FDC volume portions for the same reason.
bool isVolumeUnitLabel(String label) => volumeUnitFromLabel(label) != null;

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
