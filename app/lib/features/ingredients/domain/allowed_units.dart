/// Which units a picker may offer for an ingredient — PURE DART (invariant 2).
///
/// The rule is short, and it is meant to be (ADR-0014). A row may be said in
/// its whole **basis family** (per-100 g ⇒ every mass unit, per-100 ml ⇒ every
/// volume unit), in the **other** mass/volume family once a density bridges
/// the two, in `piece` when it is counted AND the row says what one weighs
/// (ADR-0015: a piece weight is the count fact the way a density is the
/// volume fact), and in the imprecise words its category earns. Nothing else
/// is trimmed away: a household prunes what it does not want row by row, in
/// the flesh-out form's chips.
///
/// The one thing still refused is the pair that cannot convert — "200 cup" of
/// a mass-default row with no density would split aggregation into subtotals
/// nobody can add up, so the other family stays out until the number that
/// bridges it exists.
library;

import 'package:meta/meta.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/units.dart';
import 'ingredient.dart';

// --- Kitchen ordering (ADR-0008 §Consequences) -------------------------------

/// Kitchen display order within each family — the order a cook reaches for
/// them, not the order the catalog declares them. The default unit is always
/// fronted; the rest of its family follows in this order.
///
/// Volume runs spoons → the sizes a bottle or a recipe prints (`fl oz`, `cup`)
/// → the metric jug → the US pair, which is last because it is what an
/// American recipe prints rather than what this kitchen measures in. Mass runs
/// metric then customary, for the same reason.
///
/// Order only: which units are *admitted* is [_derivedSet]'s answer, and a
/// catalog unit missing from these lists still renders — [_orderUnits] ends
/// with whatever it did not place.
const _kitchenOrder = {
  UnitFamily.volume: [tsp, tbsp, flOz, cup, ml, l, pint, quart],
  UnitFamily.mass: [g, kg, oz, lb],
};

/// Every catalog unit of [family]. A mass/volume family is admitted whole or
/// not at all, so this is the rule's unit of admission as well as a roster.
Iterable<Unit> _familyUnits(UnitFamily family) =>
    kIngredientUnits.where((u) => u.family == family);

/// Which categories admit which imprecise word (ADR-0008 §5: category-gated,
/// not universal, and gated per WORD).
///
/// One set of categories admitting all four words would mean anything earning
/// `pinch` earns `handful` too, which is how "a dash of kale" becomes
/// offerable. **Pinch and dash are for the spice/seasoning/oil classes;
/// handful is for greens** — that is how cooks actually talk. Every surface
/// reads this map, the import review included.
///
/// Keys are the vocab's ACTUAL category values (`produce`, `pantry`, `spices &
/// seasoning`, `grains`, `baking`, `fats & oils`, `dairy`, `proteins`). It has
/// no separate 'condiment' category, and no leafy/greens category either —
/// `produce` is the nearest thing the vocabulary can express, so it is what
/// `handful` is gated on; a tighter gate would need the seed to split the
/// category, not this map to grow. Condiment-ish pantry rows get theirs via
/// curation overrides.
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

/// The **derived** allowed-unit defaults for [ingredient] — the Dart mirror
/// of the database's `default_allowed_units()` (change one, change both:
/// `unit_admission.sql` and the tests here pin the same vectors). Used as the
/// fallback when a row carries no explicit list (legacy/unsynced rows, freshly
/// typed local stubs), and as the rule the seed pipeline materializes.
///
/// Four bullets, and that is the whole rule (ADR-0014, ADR-0015):
///
/// - the **basis family**, whole ([Ingredient.macrosBasis]: /g → every mass
///   unit, /ml → every volume unit) — the canonical dimension is always
///   sayable, so yeast (tsp default, per-g macros) admits `g` and `kg` alike;
/// - the **other** mass/volume family, whole, but only while a density is
///   stored ([densityUnlockedUnits]) — without one [convert] would fail with
///   `unit/no_density`. A density is a property of the substance, not of how
///   the shop sells it, so this fires for a count- or imprecise-default row
///   too ("1 cup diced mango");
/// - `piece` on a count-default row that carries a **piece weight**
///   ([Ingredient.pieceBasisAmount]) — the count fact the way the density is
///   the volume fact. A count default with no weight admits no `piece`: an
///   unweighed count is exactly the line the converter cannot bridge, and
///   `piece` is never derived for any other default unit at all;
/// - the imprecise words per [kImpreciseCategoryGates] — gated word by word,
///   so greens earn `handful` without earning `pinch` (and an imprecise
///   default always keeps its own word).
///
/// A row's own default unit needs no clause of its own: it is in the basis
/// family, or in the other one and therefore density-gated, which is exactly
/// what [unitSayableAsDefault] refuses to store without a number.
Set<Unit> defaultAllowedUnitSet(Ingredient ingredient) => _derivedSet(
  ingredient,
  density: ingredient.densityGPerMl != null,
  piece: ingredient.pieceBasisAmount != null,
);

/// [defaultAllowedUnitSet] with the density and piece-weight legs forced on
/// or off, so callers can ask the counterfactual — "what would this row admit
/// *with* a density" ([allowedUnitCandidates]' locked chips) and "what does it
/// admit *without* one" ([densityStrippedUnits], [pieceStrippedUnits]) —
/// without minting a copy of the row.
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
    // `batch` is a sub-recipe denomination and never an ingredient's unit; an
    // imprecise default earns no family of its own and rides the line below.
    // `piece` needs BOTH: a count default (the owner's ruling — piece shows
    // only where the row is counted) and a weight for one (ADR-0015).
    if (ingredient.defaultUnit.family == UnitFamily.count && piece) pieces,
    ...impreciseUnitsFor(ingredient),
  };
}

/// What a stored density actually buys [ingredient]: the whole rule read with
/// the density on, minus the whole rule read with it off.
///
/// Derived rather than listed, which is what keeps it honest in both directions
/// — the density write path unions exactly this into the EXPLICIT
/// `allowed_units` list, and [densityStrippedUnits] takes exactly this back.
///
/// It is the whole other family, whatever the default unit: a per-100 g row
/// gains every volume unit, a per-100 ml row every mass unit. A row whose own
/// default sits on that side (flour, `cup` on a per-100 g basis) has the
/// density to thank for its default too.
Set<Unit> densityUnlockedUnits(Ingredient ingredient) {
  final piece = ingredient.pieceBasisAmount != null;
  return _derivedSet(
    ingredient,
    density: true,
    piece: piece,
  ).difference(_derivedSet(ingredient, density: false, piece: piece));
}

/// The units an ingredient admits **only because a density is stored** — what
/// deleting that density takes away again.
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

/// What a stored **piece weight** buys [ingredient]: `piece`, on a
/// count-default row, and nothing anywhere else (ADR-0015). Derived the way
/// [densityUnlockedUnits] is — the rule read with the weight on, minus the
/// rule read with it off — so the two legs of the admission model cannot
/// drift apart. The piece-weight write path unions exactly this into the
/// explicit list; [pieceStrippedUnits] takes exactly this back.
Set<Unit> pieceUnlockedUnits(Ingredient ingredient) {
  final density = ingredient.densityGPerMl != null;
  return _derivedSet(
    ingredient,
    density: density,
    piece: true,
  ).difference(_derivedSet(ingredient, density: density, piece: false));
}

/// The units an ingredient admits **only because a piece weight is stored** —
/// what clearing that weight takes away again. The same rule as
/// [pieceUnlockedUnits], read in the opposite direction, and the mirror of
/// [densityStrippedUnits]: an admission derived from a number goes with the
/// number.
Set<Unit> pieceStrippedUnits(Ingredient ingredient) =>
    pieceUnlockedUnits(ingredient);

/// Whether [ingredient]'s stored default unit is one its own admission rules no
/// longer support: a mass/volume default on the far side of the basis family,
/// with no density to bridge it (the renamed-rice shape, `cup` default on a
/// per-100 g row).
///
/// The form draws this as a flag with a one-tap fix ([basisDefaultUnitFix])
/// **and refuses to save while it holds**: a flag alone is advice, and a basis
/// flipped after the default was chosen would otherwise let a row the chips
/// never offered reach the database. It is never repaired silently either — a
/// default unit is a statement about how the household buys the thing, so the
/// refusal names both fixes and the person picks one.
bool defaultUnitNeedsDensity(Ingredient ingredient) =>
    ingredient.densityGPerMl == null &&
    !unitSayableAsDefault(ingredient, ingredient.defaultUnit);

/// The count-side stranded default (ADR-0015): a `piece` default on a row
/// with no piece weight. The same shape as [defaultUnitNeedsDensity] — the
/// default names a unit nothing on the row can convert — and it gets the same
/// treatment: the form draws the flag with its ways out (enter what one
/// weighs, or switch to the basis unit) and **refuses Save** while it holds. A
/// row is not saveable as piece-default with nothing weighing a piece
/// (ADR-0015, owner-ruled).
///
/// It is deliberately NOT folded into [unitSayableAsDefault]: `piece` stays
/// pickable on the chip row with no weight yet, because picking it is what
/// makes the weight field appear. The refusal, not the chip, holds the line.
bool defaultUnitNeedsPieceWeight(Ingredient ingredient) =>
    ingredient.defaultUnit.family == UnitFamily.count &&
    ingredient.pieceBasisAmount == null;

/// Whether [ingredient]'s stored default is stranded for EITHER reason — the
/// one predicate a Save gate or a status line should ask.
bool defaultUnitStranded(Ingredient ingredient) =>
    defaultUnitNeedsDensity(ingredient) ||
    defaultUnitNeedsPieceWeight(ingredient);

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

/// Orders an allowed-unit set into chip order: the default unit fronted, the
/// rest of its family in kitchen order, count next, then the demoted other
/// mass/volume family (basis family first when both are demoted), imprecise
/// last. Stored `allowed_units` is a SET — this is the single place display
/// order comes from.
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

/// The units a unit picker should offer for [ingredient], in chip order
/// (default first → its family in kitchen order → the demoted other family,
/// which [allowedUnitChoicesFor] places after the measures → imprecise last).
///
/// Reads the **explicit per-ingredient list** ([Ingredient.allowedUnits]) when
/// the row carries one — explicit beats derived, and the flesh-out form owns
/// it from creation on. Since the rule stopped trimming, that list is mostly
/// how a row gets *narrower* than the rule: the household prunes what it will
/// never say. A row without one (legacy, unsynced, a freshly typed local stub)
/// falls back to the derived defaults the server materializes
/// ([defaultAllowedUnitSet]).
///
/// **One thing an explicit list cannot do: make a unit sayable that no density
/// supports.** A list naming `cup` on a row with no density arrives from
/// plenty of honest places — an older client, a density deleted where the list
/// did not follow — and offering it would hand the converter a pair it cannot
/// resolve. The density-derived units are subtracted while the number is
/// missing; the editor draws exactly those chips locked, and a recipe line
/// still saying one degrades to the standard `unitNotAllowed` flag rather than
/// being rewritten.
List<Unit> allowedUnitsFor(Ingredient ingredient) {
  final explicit = ingredient.allowedUnits;
  final set = explicit == null || explicit.isEmpty
      ? defaultAllowedUnitSet(ingredient)
      : {...explicit};
  if (ingredient.densityGPerMl == null) {
    set.removeAll(densityStrippedUnits(ingredient));
  }
  // The same fence for the count side (ADR-0015): a list naming `piece` on a
  // row with no piece weight — every list written before the weight existed
  // — would hand the converter a count nothing weighs; and `piece` on a row
  // whose default is not a count is a curation the rule no longer has
  // (owner: piece shows only where the default unit is piece). A stored line
  // still saying it is offered off-filter, never rewritten.
  if (ingredient.pieceBasisAmount == null ||
      ingredient.defaultUnit.family != UnitFamily.count) {
    set.remove(pieces);
  }
  return _orderUnits(set, ingredient);
}

/// One chip of the flesh-out form's admission editor (board `pv2-d2`, step
/// 7.8 — the section that never got built until 8.5).
typedef UnitAdmission = ({Unit unit, bool selected, bool locked});

/// The admission editor's chips for [ingredient], in chip order.
///
/// Every catalog unit of both mass/volume families is a chip, and so is every
/// imprecise word, because the user is the one who prunes now: a chip the rule
/// does not derive is drawn unselected and TAPPABLE rather than hidden or
/// dashed. `piece` joins them only on a count-default row (ADR-0015 — it is
/// never offered where the default unit is not a count), and there it is
/// locked until the row carries a piece weight.
///
/// Two states carry the meaning. `selected` chips are what a line may say
/// today; `locked` chips are the dashed ones — the other mass/volume family
/// while no density is stored, and `piece` while no piece weight is — drawn
/// rather than hidden so the form explains what entering the number buys.
///
/// A chip is locked even when the stored list still names it: a list can
/// arrive that way from a device that wrote it before the density was deleted,
/// and the editor must say what the number supports rather than what the list
/// happens to hold. The basis family is never locked — it needs no density.
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
  // A stored list naming `piece` on a non-count row is a curation the rule no
  // longer knows; the chip is not drawn, and the list stops carrying it on the
  // form's next save (the same fate a density-locked unit has).
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
    final amount = formatNumber(measure.amount);
    return '${measure.label} ($amount ${measure.basis.baseUnit.label})';
  }

  @override
  bool operator ==(Object other) =>
      other is MeasureOption && other.measure.id == measure.id;

  @override
  int get hashCode => measure.id.hashCode;
}

/// The catalog volume unit a bare [label] names ("tbsp", "Cups ", "ml"…), or
/// null when it names none. Measures must never duplicate volume units —
/// density owns volume conversion (ADR-0008 §2: a volume-named weight mapping
/// IS a density) — so the add-measure form uses the resolved unit to REDIRECT
/// the entry into density instead of merely refusing it.
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
/// in chip order: the default unit's own set leads, then one
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
/// a cross-family unit whose density was removed, a unit the household pruned
/// off the row — it is appended last and returned as `offFilter`, so every
/// entry surface inherits the guarantee and can still mark the chip as outside
/// the honest filter.
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
