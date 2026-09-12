/// Shopping-list domain — the DERIVED output view (spec §4).
///
/// PURE DART (invariant 2): no `package:flutter`. The list is a pure function
/// of the batch cook plan's contributions plus a thin persisted overlay
/// (check-off + manual/free-text). [buildShoppingList] sums per-ingredient
/// contributions into rolled-up [ShoppingItem]s, groups them by aisle
/// ([ShoppingGroup]), and keeps the provenance breakdown (spec §4:
/// "Flour — 500g · Curry batch 300g · Cookies 150g · +50g manual").
///
/// Contributions come in three flavours (spec §4):
///   * `cookSession` — DERIVED live from the cook plan (quantity = a recipe
///     line × the session's scale factor). Never persisted.
///   * `planEntry` — DERIVED live from a planned meal that is a bare
///     INGREDIENT rather than a recipe (step 8.14 / A-D4: quantity = its
///     stated per-portion amount × its demand). A snack is never cooked, so it
///     belongs to no session — which is why this derivation walks the week's
///     **entries**, not only its cook sessions. Never persisted.
///   * `manual` — a user top-up on an ingredient, or a quantity on a free-text
///     item. Persisted (`shopping_list_contribution`).
///
/// [aggregateQuantities] is the honest summation core (invariant 3): it sums
/// within a unit family, bridges mass↔volume only when a density is supplied,
/// and NEVER invents a number to force a single total — an ingredient with
/// mixed families and no density yields two honest subtotals, not a guess.
///
/// A measure-quantified contribution folds into that sum via its basis amount,
/// but folding is not the whole answer: when every contribution to an item
/// asked for the SAME measure, the item also carries a
/// [ShoppingItem.measureTotal] and the row reads "1 can (400 g), drained"
/// rather than the 8.47 oz the can happens to weigh. You buy cans.
library;

// Freezed needs each class's private `._` constructor before the factory (for
// the custom getters), which trips the unnamed-first sort lint.
// ignore_for_file: sort_unnamed_constructors_first
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/aisles.dart';
import '../../../core/result/result.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../recipes/domain/effective_lines.dart';

part 'shopping.freezed.dart';

/// Where a contribution comes from (spec §4). `cookSession` contributions are
/// derived from the cook plan; `planEntry` ones from a planned meal that is a
/// bare INGREDIENT rather than a recipe (step 8.14 / A-D4 — nothing is cooked,
/// but it is still bought); `manual` ones are user top-ups / free-text.
enum ContributionSource { cookSession, planEntry, manual }

// --- Builder inputs ----------------------------------------------------------
// Light record types (not entities) the repository assembles from SQL + the
// cook plan and hands to [buildShoppingList]. Keeping them here lets the pure
// builder be unit-tested without a database.

/// One derived cook contribution: a recipe line already scaled by its cook
/// session. `cookDay` and `batched` drive the provenance label.
///
/// `unit` is null when the persisted unit id wasn't recognised (`rawUnit`
/// carries the raw string) — such a line is surfaced in the breakdown as an
/// unconverted note and NEVER summed into a total (invariant 3: falling back
/// to "pieces" would invent semantics for an unknown unit).
///
/// `measure` is the resolved [Measure] when the line was quantified in one
/// ("2 × potato, large") — its gram weight folds the quantity into the mass
/// subtotal. A line whose stored `measure_id` no longer resolves arrives with
/// `measure` null and its stored count unit intact, so it degrades to an
/// honest count rather than invented grams.
/// `forParents` carries the planned recipes a **component** session is cooked
/// for (step 8.6 / D4) — the one extra provenance segment a nested
/// contribution gains ("Romesco Aioli · for Sliders · cook Sat"). Empty for an
/// ordinary meal contribution, which reads exactly as it did before.
/// `weekNote` is the one extra segment a line the WEEK changed carries —
/// "this week, for Pork sausage" / "this week, was 2" / "this week, added" /
/// "this week, ticked in". Null on every line the recipe states itself, which
/// is nearly all of them, and the words come from the same vocabulary the
/// editor's tags speak so a shopper and an editor cannot describe one change
/// two ways.
typedef CookContributionInput = ({
  String ingredientId,
  double? quantity,
  Unit? unit,
  String? rawUnit,
  Measure? measure,
  String recipeTitle,
  int cookDay,
  bool batched,
  List<String> forParents,
  String? weekNote,
});

/// One planned INGREDIENT meal, already multiplied by its demand (step 8.14 /
/// A-D4).
///
/// The list is derived from the batch cook plan **and from the week's entries**
/// — because a snack is never cooked, so it appears in no session, and a
/// derivation that walked only sessions would leave a hole in a list somebody
/// shops from. `quantity` is the entry's stated per-portion amount × the
/// entry's demand (Σ portion factors, the override winning) — a snack two
/// people are having is bought twice.
///
/// `unit` / `rawUnit` / `measure` degrade exactly as [CookContributionInput]'s
/// do: an unrecognised unit or an unusable measure is a visible note, never a
/// number folded into a total. `dayOfWeek` and `mealSlot` label the breakdown
/// ("Snack · Tue").
typedef PlanIngredientInput = ({
  String ingredientId,
  double? quantity,
  Unit? unit,
  String? rawUnit,
  Measure? measure,
  int dayOfWeek,
  String mealSlot,
});

/// One planned recipe's "N components unresolved" echo (step 8.6 / D4).
///
/// An unresolved component contributes NOTHING to the list — never an invented
/// quantity — which would otherwise be an invisible hole in a list somebody
/// shops from. This is what makes the silence legible; the Cook tab's gap card
/// is the surface that fixes it.
typedef UnresolvedComponentNote = ({
  String recipeId,
  String recipeTitle,
  int count,
});

/// One planned recipe's "N lines not listed" echo, and WHY they are not.
///
/// A dropped line contributes NOTHING to the list — the `effectiveLines` seam
/// dropped it before the session was expanded — and the recipe it belongs to
/// says so, by name, in the same group-header voice as
/// [UnresolvedComponentNote]. The difference is the colour: an unresolved
/// component is a defect somebody can fix, a dropped line is a rule somebody
/// chose, so the row reads muted rather than amber. `names` are the dropped
/// lines' ingredient names in stored order.
///
/// `reason` decides the words, not the shape: the recipe's own `optional`
/// rule, or this week's variant leaving the line out. An exclusion cannot be
/// a provenance segment — there is no row left to hang one on — so it takes
/// this row, which is the whole reason the seam names what it drops.
///
/// `lineIds` runs PARALLEL to `names` — the recipe line behind each name, so
/// the row can be a door: tapping an optional name writes this week's include
/// row for that line, and the item arrives with its "ticked in" provenance.
typedef OptionalLinesNote = ({
  String recipeId,
  String recipeTitle,
  List<String> names,
  List<String> lineIds,
  LineDropReason reason,
});

/// Where a line at a RETIRED ingredient sits — which is the whole difference
/// between the two echo rows, because it names the next tap.
enum RetiredIngredientSite {
  /// A recipe line: the pick is in that recipe, whose editor re-points it.
  recipeLine,

  /// A bare-INGREDIENT meal on the week (migration 0033): there is no recipe
  /// to edit, so the pick is in the plan, on the entry itself.
  planEntry,
}

/// One line — a recipe's, or a planned meal of its own — whose ingredient the
/// household has RETIRED.
///
/// Nothing about a retired row is a fact about food any more, so nothing is
/// derived from it: not a name to shop by, not an aisle to file it under, not
/// a density to sum it with. The line therefore buys NOTHING. But it is not
/// dropped either — a list quietly short of a thing somebody planned to eat is
/// worse than one that says what is missing — so it leaves the aisles and
/// takes an echo row at the bottom, in [UnresolvedComponentNote]'s voice,
/// carrying the row's LAST KNOWN name and where to pick again.
///
/// `heading` is the echo's group-header word: the recipe's title, or the
/// planned meal's own provenance label ("Snack · Tue"), which is exactly what
/// the breakdown would have said had there been anything to buy.
typedef RetiredIngredientNote = ({
  String heading,
  String ingredientName,
  RetiredIngredientSite site,
});

/// A persisted shopping entry row (the check-off + free-text anchor).
/// `createdAt` (ISO-8601) makes duplicate-entry merging deterministic: the
/// oldest live row per ingredient is the canonical one on every device.
typedef ShoppingEntryInput = ({
  String id,
  String? ingredientId,
  String? freeText,
  String? category,
  bool checked,
  Unit? unit,
  String? createdAt,
});

/// A persisted manual contribution attached to an entry. `measureId` is the
/// stored `measure_id` verbatim (kept even while the measure row hasn't
/// synced, so an edit re-save never strips the FK — mirrors the recipe
/// line's `measureId`);
/// `measure`, when set, is the resolved [Measure] the top-up was quantified
/// in.
typedef ManualContributionInput = ({
  String id,
  String entryId,
  double? quantity,
  Unit? unit,
  String? measureId,
  Measure? measure,
  String? note,
});

/// Ingredient vocab metadata needed to group + sum (name, aisle, density),
/// plus the ingredient's live measures (sorted by their `sort_order`) — they
/// gate and price the whole-unit hint on count foods.
///
/// `pieceBasisAmount` is what ONE of the ingredient weighs, in `basis`
/// (`piece_basis_amount` / `macros_basis` — ADR-0015: a piece weight is a row
/// fact, exactly as a density is). It is the number a bare `piece` line folds
/// into the basis subtotal through, the way a measure folds through its own
/// amount; null on a row that states none, whose `piece` lines then stay an
/// honest bare count.
typedef IngredientMetaInput = ({
  String name,
  String? category,
  double? densityGPerMl,
  Unit defaultUnit,
  List<Measure> measures,
  double? pieceBasisAmount,
  MacrosBasis basis,
});

// --- Display entities --------------------------------------------------------

/// One line of the provenance breakdown under an item's total.
@freezed
abstract class ShoppingContribution with _$ShoppingContribution {
  const factory ShoppingContribution({
    required ContributionSource source,

    /// The provenance label, e.g. "Curry · cook Mon", "Oat Cookies", or
    /// "manual top-up".
    required String label,

    /// Null for a bare non-food item (renders as a dash).
    double? quantity,
    Unit? unit,

    /// The measure the quantity is counted in ("2 × potato, large"), when the
    /// contribution was quantified in one; [unit] is null then.
    Measure? measure,

    /// The persisted `measure_id` of a manual contribution, verbatim — kept
    /// even while [measure] is unresolved (row not yet synced / soft-deleted)
    /// so the edit sheet's re-save never wipes the FK for every device
    /// (mirrors the recipe line's [measureId]). Null for cook lines (derived,
    /// never re-saved here).
    String? measureId,

    /// The day (0=Mon..6=Sun) a DERIVED contribution belongs to — a session's
    /// cook day, or a planned snack's own day — which orders the breakdown.
    /// Null for a manual top-up, which belongs to no day.
    int? cookDay,

    /// The persisted `shopping_list_contribution` id — set only for a `manual`
    /// contribution (a cook one is derived, so it has none). Lets the UI edit
    /// or remove this specific top-up.
    String? contributionId,
  }) = _ShoppingContribution;
}

/// A rolled-up shopping line: one ingredient (or free-text item), its check-off
/// state, its aggregated [totals] (usually one [Quantity]; more when families
/// can't be merged honestly), and the [contributions] behind it.
///
/// A line every contribution asked for in the SAME measure also carries a
/// [measureTotal] — the count you put in the basket, with [totals] as what it
/// weighs.
@freezed
abstract class ShoppingItem with _$ShoppingItem {
  const ShoppingItem._();

  const factory ShoppingItem({
    required String name,

    /// The persisted entry id, if this line has one (a checked or topped-up
    /// ingredient, or a free-text item). Null for a purely-derived ingredient
    /// the user hasn't touched yet — check-off lazily creates the entry.
    String? entryId,

    /// Null for a free-text (non-food) item.
    String? ingredientId,
    @Default(false) bool checked,
    @Default(<Quantity>[]) List<Quantity> totals,
    @Default(<ShoppingContribution>[]) List<ShoppingContribution> contributions,

    /// The item's total counted in ONE measure — "1 can (400 g), drained" —
    /// set only when every quantified contribution asked for that same
    /// measure. You buy the can, so the row says cans; [totals] still carries
    /// the canonical mass/volume the cans weigh, which the row shows beside
    /// it. Null the moment a plain mass/volume line or a second measure joins
    /// the sum — neither has a single countable answer, so the family sum is
    /// the only honest total.
    MeasureAmount? measureTotal,

    /// The item's total as a count of PIECES — "2½ piece" — on a row whose
    /// default unit is `piece` and that states what one weighs (ADR-0015),
    /// once everything asked for has folded into ONE basis-family total: the
    /// `piece` lines through the piece weight, the measures through theirs,
    /// the plain mass/volume lines as they are. A lime asked for as `1 lime,
    /// whole` here and `1½ piece` there is 2½ limes, not `67 g + 1½ piece`.
    /// `approx` is false when every contribution was a `piece` line or a
    /// measure that is a whole number of pieces (`lime, whole` = 67 g on a 67
    /// g piece), true when a plain mass/volume line joined or a measure did
    /// not divide evenly (`onion, small` = 70 g on a 110 g piece). [totals]
    /// still carries the mass the count weighs. Null on every other row, and
    /// null when [measureTotal] is set — a row asked for in one named measure
    /// is counted in that measure, which is the more specific thing to buy.
    PieceTotal? pieceTotal,

    /// An honest round-up hint ("2.25 → buy 3") for a measure-bearing count
    /// ingredient — a HINT beside the total, never a replaced total
    /// (invariant 3). Null when the item doesn't qualify (see
    /// [wholeUnitHintFor]), and null whenever [measureTotal] or [pieceTotal]
    /// is set: a row already counted in its measure or its pieces needs no
    /// second way to say the same thing (each count carries its own
    /// round-up under it).
    WholeUnitHint? wholeUnitHint,
  }) = _ShoppingItem;

  /// A free-text non-food item ("paper towels") rather than a vocab ingredient.
  bool get isFreeText => ingredientId == null;

  /// Whether this line has a numeric total (a non-food staple may not).
  bool get hasTotal => totals.isNotEmpty;

  /// Whether any of this item's total comes from the cook plan.
  bool get hasCookContribution =>
      contributions.any((c) => c.source == ContributionSource.cookSession);

  /// Purely user-added — a free-text item, or an ingredient that exists only
  /// because of a manual top-up. Such a line can be removed wholesale. A
  /// cook-derived line is never removed here (edit the week instead; drop its
  /// top-up via the edit sheet).
  bool get isUserAdded => entryId != null && !hasCookContribution;
}

/// A shopping aisle group ("Produce", "Baking", "Non-food").
@freezed
abstract class ShoppingGroup with _$ShoppingGroup {
  const factory ShoppingGroup({
    required String label,
    @Default(<ShoppingItem>[]) List<ShoppingItem> items,
  }) = _ShoppingGroup;
}

/// The whole shopping list, grouped by aisle, plus its three echo channels —
/// the per-parent [unresolvedComponents] (step 8.6 / D4), the per-recipe
/// [optionalLines], and the [retiredIngredients] whose vocab row is gone. What
/// the list is short by, and why it is silent about it.
@freezed
abstract class ShoppingList with _$ShoppingList {
  const ShoppingList._();

  const factory ShoppingList({
    @Default(<ShoppingGroup>[]) List<ShoppingGroup> groups,
    @Default(<UnresolvedComponentNote>[])
    List<UnresolvedComponentNote> unresolvedComponents,
    @Default(<OptionalLinesNote>[]) List<OptionalLinesNote> optionalLines,
    @Default(<RetiredIngredientNote>[])
    List<RetiredIngredientNote> retiredIngredients,
  }) = _ShoppingList;

  bool get isEmpty => groups.isEmpty;

  /// The aisles as the shopper still has to walk them: each group with only
  /// its UNTICKED items, and a group whose items are all ticked dropped. A
  /// ticked row leaves its aisle for the [basket] so what is and isn't grabbed
  /// yet reads at a glance; [groups] stays the full list for everything that
  /// counts items.
  List<ShoppingGroup> get openGroups => [
    for (final g in groups)
      if (g.items.any((i) => !i.checked))
        g.copyWith(
          items: [
            for (final i in g.items)
              if (!i.checked) i,
          ],
        ),
  ];

  /// Every ticked item, flattened in aisle order then name — what the one
  /// section at the bottom of the list holds, for whatever counts it. The
  /// order is the aisles' own, so a row's position is predictable: it sits
  /// where its aisle would have put it.
  List<ShoppingItem> get basket => [for (final g in basketGroups) ...g.items];

  /// The basket keeps its aisles: each group with only its TICKED items, and
  /// a group with none dropped — the mirror of [openGroups]. A ticked row is
  /// re-found the way it was found, under the aisle it was walked to.
  List<ShoppingGroup> get basketGroups => [
    for (final g in groups)
      if (g.items.any((i) => i.checked))
        g.copyWith(
          items: [
            for (final i in g.items)
              if (i.checked) i,
          ],
        ),
  ];

  /// Whether the list has items and every one of them is ticked — the aisles
  /// are empty but the trip is not. The single place "all ticked" is known.
  bool get allTicked => groups.isNotEmpty && openGroups.isEmpty;
}

// --- The last tick -----------------------------------------------------------

/// The identity a row keeps across a tick: its ingredient, or for a free-text
/// item its entry. The entry id alone would not do — a derived row has none
/// until its first check-off creates one, so keying on it would make the
/// untick-and-re-tick of the same row look like a new list.
String shoppingItemIdentity(ShoppingItem item) =>
    item.ingredientId ?? item.entryId ?? item.name;

/// Whether ticking [item] is the tick that finishes [list]: the list holds
/// more than one item, [item] is still unticked, and every other item is
/// ticked. Decided on the list as it stands BEFORE the write, on this phone —
/// a list that arrives all-ticked by sync was finished by the other phone,
/// and that is not this phone's moment. A list of one item is a chore, not a
/// trip, and never qualifies.
bool completesTheList(ShoppingList list, ShoppingItem item) {
  final items = [for (final g in list.groups) ...g.items];
  if (items.length < 2 || item.checked) return false;
  final id = shoppingItemIdentity(item);
  return items.every((i) => i.checked || shoppingItemIdentity(i) == id);
}

/// The list's identity for "once per list": its items' identities, sorted and
/// joined, so unticking and re-ticking the last row is the same list and a
/// row added since is a new one. The viewed week is the caller's to prepend —
/// the same items next week are a new trip.
String completionKeyOf(ShoppingList list) {
  final ids = [
    for (final g in list.groups)
      for (final i in g.items) shoppingItemIdentity(i),
  ]..sort();
  return ids.join('|');
}

// --- Aggregation (honest summation core) -------------------------------------

/// An amount counted in a [Measure] ("2 × potato, large") — an input awaiting
/// honest summation via the measure's gram weight, and, once summed, the shape
/// of a [ShoppingItem.measureTotal].
typedef MeasureAmount = ({double amount, Measure measure});

/// A [ShoppingItem.pieceTotal]: the honest, possibly fractional `count` of
/// pieces the row's total comes to, and whether that count is `approx` — read
/// back from a mass or volume somebody stated rather than from pieces and
/// whole-piece measures alone.
typedef PieceTotal = ({double count, bool approx});

/// Sums [qs] into as few totals as it can *honestly* (invariant 3).
///
/// - Sums within a unit family by the ratio table (g·kg → one mass total).
/// - Bridges mass↔volume only when a *positive* [densityGPerMl] is supplied
///   (a zero/negative density is bad data, treated like none); without one a
///   mixed set yields two subtotals rather than an invented single number.
/// - [measured] amounts fold into the **mass** subtotal via each measure's
///   gram weight (a measure is a stored, sourced mass — spec §4, step 7.6).
///   One with a non-positive gram weight (bad data) is skipped, never summed
///   under a guessed weight.
/// - [UnitFamily.count] totals sum per count unit; [UnitFamily.imprecise] never
///   sums (a "pinch" doubled is still a pinch) — identical imprecise units
///   collapse into ONE entry (two recipes each wanting a pinch → "pinch", not
///   "pinch + pinch"), but distinct ones are never merged.
/// - [preferred] biases the display unit when it shares the summed family.
List<Quantity> aggregateQuantities(
  List<Quantity> qs, {
  List<MeasureAmount> measured = const [],
  double? densityGPerMl,
  Unit? preferred,
}) {
  final mass = <Quantity>[];
  final volume = <Quantity>[];
  final counts = <String, double>{};
  final imprecise = <Quantity>[];
  for (final q in qs) {
    switch (q.unit.family) {
      case UnitFamily.mass:
        mass.add(q);
      case UnitFamily.volume:
        volume.add(q);
      case UnitFamily.count:
        counts.update(q.unit.id, (v) => v + q.amount, ifAbsent: () => q.amount);
      case UnitFamily.batch:
        // A component line never becomes a shopping item (D4 — you buy
        // almonds, not aioli), so nothing should reach here. If foreign data
        // ever does, it sums per unit like a count rather than vanishing: a
        // visible odd total beats a silent hole.
        counts.update(q.unit.id, (v) => v + q.amount, ifAbsent: () => q.amount);
      case UnitFamily.imprecise:
        // Collapse identical imprecise units: amounts on them carry no meaning
        // (they never scale or sum), so one line per unit is the honest render.
        if (!imprecise.any((e) => e.unit == q.unit)) imprecise.add(q);
    }
  }
  for (final m in measured) {
    // The measure's basis amount is a stored basis-family quantity, so the
    // fold is exact — into MASS for a per-g measure, into VOLUME for a
    // per-ml one (ADR-0008: measures map into the ingredient's basis, never
    // across it). Only a positive amount is trusted (mirrors the density
    // guard above).
    if (!(m.measure.amount > 0)) continue;
    final total = m.amount * m.measure.amount;
    if (m.measure.basis == MacrosBasis.perMl) {
      volume.add(Quantity(total, ml));
    } else {
      mass.add(Quantity(total, g));
    }
  }

  final totals = <Quantity>[];

  if (mass.isNotEmpty || volume.isNotEmpty) {
    final canBridge = densityGPerMl != null && densityGPerMl > 0;
    if (mass.isNotEmpty && volume.isNotEmpty && canBridge) {
      // Unify volume into mass via density, then one mass total.
      final unified = [...mass];
      for (final v in volume) {
        final r = convert(v, to: g, densityGPerMl: densityGPerMl);
        if (r case Ok(:final value)) unified.add(value);
      }
      final t = _sumFamily(unified, preferred);
      if (t != null) totals.add(t);
    } else {
      // No bridge (single family, or mixed without a density) → honest per
      // family: a mass subtotal and/or a volume subtotal.
      final m = _sumFamily(mass, preferred);
      final v = _sumFamily(volume, preferred);
      if (m != null) totals.add(m);
      if (v != null) totals.add(v);
    }
  }

  for (final e in counts.entries) {
    final unit = unitById(e.key);
    if (unit != null) totals.add(Quantity(e.value, unit));
  }
  totals.addAll(imprecise);
  return totals;
}

/// Sums same-family [qs] via the ratio table, returned in a display unit:
/// [preferred] when it shares the family, else the input unit carrying the
/// largest share (so g·g·kg reads in kg when kg dominates). Null when empty.
Quantity? _sumFamily(List<Quantity> qs, Unit? preferred) {
  if (qs.isEmpty) return null;
  final family = qs.first.unit.family;
  var base = 0.0;
  for (final q in qs) {
    base += q.amount * (q.unit.ratioToBase ?? 1);
  }
  Unit target;
  if (preferred != null &&
      preferred.family == family &&
      preferred.ratioToBase != null) {
    target = preferred;
  } else {
    target = qs
        .reduce(
          (a, b) =>
              a.amount * (a.unit.ratioToBase ?? 1) >=
                  b.amount * (b.unit.ratioToBase ?? 1)
              ? a
              : b,
        )
        .unit;
  }
  return Quantity(base / (target.ratioToBase ?? 1), target);
}

/// A whole-unit round-up hint on a shop line: the honest fractional `count`
/// ("2.25"), the whole units to `buy` ("3"), and what one unit is
/// (`unitLabel`). `approx` is true when the count was derived from a mass
/// total via a measure's gram weight (weight→count is approximate; a direct
/// fractional count is not).
typedef WholeUnitHint = ({
  double count,
  int buy,
  String unitLabel,
  bool approx,
});

/// The round-up hint for an item's [totals], or null (spec §4, step 7.6).
///
/// The hint is offered only when the item rolled up to a SINGLE total (a
/// mixed count+mass item would need a hint that covers both — a guess) and
/// that total is fractional:
///
/// - a fractional count total ("2.25 piece") rounds up directly — a count is
///   already a whole-thing tally, so it needs no measure and no default-unit
///   gate;
/// - a mass or volume total converts through the ingredient's primary measure
///   (lowest `sort_order`) of the SAME family as its basis — "674 g ≈ 2.25 ×
///   potato, large → buy 3" — marked `approx` (a cross-family pair would need
///   a density this hint doesn't carry, and [amountInMeasure] refuses it
///   honestly).
///
/// A total whose contributions were ALL counted in one measure never reaches
/// here: it is a [ShoppingItem.measureTotal], already said in that measure.
/// This hint exists for the other shape — a mass total the shopper has to
/// translate into things on a shelf.
///
/// Always a hint BESIDE the honest total, never a replacement (invariant 3).
WholeUnitHint? wholeUnitHintFor({
  required List<Quantity> totals,
  required List<Measure> measures,
}) {
  if (totals.length != 1) return null;
  final total = totals.single;

  bool fractional(double v) => v > 0 && (v - v.round()).abs() > 1e-9;

  if (total.unit.family == UnitFamily.count && fractional(total.amount)) {
    return (
      count: total.amount,
      buy: total.amount.ceil(),
      unitLabel: total.unit.label,
      approx: false,
    );
  }
  if (total.unit.family == UnitFamily.mass ||
      total.unit.family == UnitFamily.volume) {
    if (measures.isEmpty) return null;
    final measure = measures.first;
    final inMeasure = amountInMeasure(total, measure);
    if (inMeasure case Ok(:final value) when fractional(value)) {
      return (
        count: value,
        buy: value.ceil(),
        unitLabel: measure.label,
        approx: true,
      );
    }
  }
  return null;
}

// --- Builder -----------------------------------------------------------------

// The aisle order is `core/aisles.dart` — one walk through a shop, shared with
// the ingredients manager so the two screens never disagree about it.
// Free-text "Non-food" is this list's own, and always sits last.
const _nonFoodLabel = 'Non-food';

/// The provenance label for a cook contribution: the recipe title, plus its
/// cook day when the recipe is batched into more than one session (so the
/// breakdown disambiguates which cook it came from).
///
/// A **component** contribution (step 8.6 / D4) gains one segment naming the
/// planned recipe it is cooked for, and always carries its cook day: "Romesco
/// Aioli · for Sliders · cook Sat". Two levels, deepest first — the recipe
/// whose line this actually is, then the plan it serves.
/// A line the WEEK changed gains one more segment at the end, saying why this
/// amount is not the recipe's: "Ragù · cook Tue · this week, for Pork
/// sausage". One extra segment on the line that already exists — no new row
/// type, no badge.
String cookLabel(CookContributionInput c, List<String> weekdayShort) {
  final forParents = c.forParents;
  return [
    c.recipeTitle,
    if (forParents.isNotEmpty) 'for ${forParents.join(' + ')}',
    if (c.batched || forParents.isNotEmpty) 'cook ${weekdayShort[c.cookDay]}',
    if (c.weekNote != null) c.weekNote!,
  ].join(' · ');
}

/// The provenance label for a planned INGREDIENT meal (step 8.14 / A-D4):
/// the slot it sits in and the day it is for — "Snack · Tue". No cook day and
/// no batch, because nothing about it is cooked; the item's own name is
/// already the thing being bought, so the segment says *when*, not *what*.
String planIngredientLabel(PlanIngredientInput p, List<String> weekdayShort) =>
    '${p.mealSlot} · ${weekdayShort[p.dayOfWeek]}';

/// One DERIVED contribution, with the three degradations every derived source
/// shares — the cook plan's and the week's snacks read one rule, so the two
/// cannot drift.
///
/// A quantity whose unit wasn't recognised is surfaced as an unconverted note
/// (no quantity/unit → renders as a dash + note) and stays out of the totals:
/// summing it under an assumed unit would invent semantics (invariant 3). A
/// measure with a non-positive/NaN gram weight is bad data and gets the same
/// treatment — a visible "not counted" note, never a silent drop from the
/// total. And a measure counts THINGS, so its row always stores a count unit
/// (`piece`): a NON-count unit beside a measure id is a contradictory row (is
/// the number grams or a measure count?), and folding it through the gram
/// weight would invent mass, so it degrades the same way. A valid
/// measure-quantified line keeps its measure so the fold can price it.
ShoppingContribution _derivedContribution({
  required ContributionSource source,
  required String label,
  required double? quantity,
  required Unit? unit,
  required String? rawUnit,
  required Measure? measure,
  required int day,
}) {
  final String? refusal;
  if (unit == null && measure == null && quantity != null) {
    refusal =
        'not counted (unrecognised unit'
        '${rawUnit == null ? '' : ' "$rawUnit"'})';
  } else if (measure != null && !(measure.amount > 0) && quantity != null) {
    refusal = 'not counted (invalid measure "${measure.label}")';
  } else if (measure != null &&
      unit != null &&
      unit.family != UnitFamily.count &&
      quantity != null) {
    refusal = 'not counted (measure beside non-count unit "${unit.label}")';
  } else {
    refusal = null;
  }

  if (refusal != null) {
    return ShoppingContribution(
      source: source,
      label: '$label · $refusal',
      cookDay: day,
    );
  }
  return ShoppingContribution(
    source: source,
    label: label,
    quantity: quantity,
    unit: measure == null ? unit : null,
    measure: measure,
    cookDay: day,
  );
}

/// The item's total as a count of ONE measure, or null.
///
/// Set only when nothing else was asked for: every quantified contribution
/// named the same measure and no plain mass/volume/count line joined them. A
/// can plus 200 g, or a large potato plus a medium one, has no single
/// countable answer — the canonical family sum is then the only honest total
/// (invariant 3), and each provenance line keeps its own words regardless.
MeasureAmount? _measureTotal(
  List<Quantity> quantities,
  List<MeasureAmount> measured,
) {
  if (quantities.isNotEmpty || measured.isEmpty) return null;
  final measure = measured.first.measure;
  if (!(measure.amount > 0)) return null;
  if (measured.any((e) => e.measure.id != measure.id)) return null;
  return (
    amount: measured.fold<double>(0, (sum, e) => sum + e.amount),
    measure: measure,
  );
}

/// The row's piece weight as the [Measure] the fold already understands: `n
/// piece` is `n × amount` of the basis unit, exactly like a named measure
/// (ADR-0015 — the shop converts a `piece` line through the piece weight the
/// way the macro engine does). Null when the row states no weight, or a
/// non-positive one: nothing is invented for it, and its `piece` lines stay
/// an honest bare count.
Measure? _pieceMeasureOf(IngredientMetaInput? meta) {
  final amount = meta?.pieceBasisAmount;
  if (amount == null || !(amount > 0)) return null;
  return Measure(
    id: pieces.id,
    label: pieces.label,
    amount: amount,
    basis: meta!.basis,
  );
}

/// The item's total as a count of pieces, or null ([ShoppingItem.pieceTotal]).
///
/// Offered only on a row whose default unit is `piece` and that states a
/// piece weight, once the sum collapsed to exactly ONE basis-family total —
/// a second subtotal means something could not be folded, and a count that
/// covered only half the row would be a guess. The count is that total
/// divided by the piece weight (through [amountInMeasure], so a total the
/// density bridged into the other family still reads honestly, and one it
/// could not bridge refuses). A row already counted in one named measure
/// keeps that count: `2 potato, large` is more specific than `≈ 2¾ piece`.
///
/// `approx` is the honesty flag: a plain mass or volume line, or a measure
/// that is not a whole number of pieces, means the count was read back from
/// a weight rather than tallied.
PieceTotal? _pieceTotal({
  required IngredientMetaInput? meta,
  required Measure? pieceMeasure,
  required List<Quantity> totals,
  required List<Quantity> quantities,
  required List<MeasureAmount> measured,
  required MeasureAmount? measureTotal,
}) {
  if (meta == null || pieceMeasure == null) return null;
  if (meta.defaultUnit != pieces || measureTotal != null) return null;
  if (totals.length != 1) return null;
  final inPieces = amountInMeasure(
    totals.single,
    pieceMeasure,
    densityGPerMl: meta.densityGPerMl,
  );
  if (inPieces case Ok(:final value)) {
    bool wholePieces(Measure m) {
      final ratio = m.amount / pieceMeasure.amount;
      return (ratio - ratio.round()).abs() < 1e-6;
    }

    return (
      count: value,
      approx:
          quantities.isNotEmpty || measured.any((e) => !wholePieces(e.measure)),
    );
  }
  return null;
}

/// Assembles the derived shopping list from its parts (spec §4).
///
/// [cook] are the derived cook contributions; [planned] the week's bare
/// INGREDIENT meals, already multiplied by their demand (step 8.14 / A-D4);
/// [entries] the persisted check-off/free-text rows; [manual] the persisted
/// manual contributions keyed by their entry; [meta] the ingredient vocab
/// (name, aisle, density). [weekdayShort] labels days without pulling a
/// formatter into the domain — seven short names in the household's OWN week
/// order, indexed by a meal's offset, never by a calendar weekday.
///
/// An entry is only surfaced while it has at least one live contribution (a
/// cook one, a planned snack, or a manual one) or is a free-text item — so an
/// ingredient whose recipe was deleted (leaving only a stale checked row)
/// drops off the list.
///
/// A `piece` line on a row that states a piece weight folds into the basis
/// subtotal through that weight, exactly as a measure folds through its own
/// ([IngredientMetaInput], ADR-0015), and a `piece`-default row so weighed
/// reads a count of pieces as its total once everything folded into one
/// ([ShoppingItem.pieceTotal]). A row with no piece weight is untouched: its
/// `piece` lines stay an honest bare count beside whatever else was asked
/// for, which is the row's own legacy state to fix.
///
/// Two live entries for the same ingredient can exist (two offline devices each
/// touching Flour, merged later — no unique index guards this, by design: one
/// would make the offline dupe fail upload and lose data). They are merged
/// deterministically here: manual contributions are unioned, checked is
/// any-checked, and the oldest row (created_at, id) is the canonical entry — so
/// no device silently drops the other's top-ups or check-off.
/// [unresolvedComponents] is carried through to the built list untouched — the
/// cook plan's gaps, counted per planned recipe (step 8.6 / D4). So is
/// [optionalLines]: the lines the `effectiveLines` seam dropped before [cook]
/// was derived, named per recipe. The builder never sees an optional line as a
/// contribution — the drop happens at the seam, once, where the per-week
/// override will later join — it only carries the echo so the list can say what
/// it left out. And so is [retiredIngredients]: the lines, and the planned
/// meals, whose ingredient the household has retired — dropped from the
/// derivation upstream (nothing about a retired row can be shopped) and named
/// here for the same reason the other two are.
ShoppingList buildShoppingList({
  required List<CookContributionInput> cook,
  required List<ShoppingEntryInput> entries,
  required Map<String, List<ManualContributionInput>> manual,
  required Map<String, IngredientMetaInput> meta,
  required List<String> weekdayShort,
  List<PlanIngredientInput> planned = const [],
  List<UnresolvedComponentNote> unresolvedComponents = const [],
  List<OptionalLinesNote> optionalLines = const [],
  List<RetiredIngredientNote> retiredIngredients = const [],
}) {
  // Index persisted entries by their ingredient (free-text ones stay by id),
  // keeping every duplicate so it can be merged rather than dropped.
  final entriesByIngredient = <String, List<ShoppingEntryInput>>{};
  final freeTextEntries = <ShoppingEntryInput>[];
  for (final e in entries) {
    final ing = e.ingredientId;
    if (ing != null) {
      (entriesByIngredient[ing] ??= []).add(e);
    } else {
      freeTextEntries.add(e);
    }
  }
  // Oldest-first (created_at, then id) — the same canonical row on every
  // device regardless of the order the rows synced in.
  for (final list in entriesByIngredient.values) {
    list.sort((a, b) {
      final c = (a.createdAt ?? '').compareTo(b.createdAt ?? '');
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  }

  // Group derived cook contributions by ingredient, preserving order.
  final cookByIngredient = <String, List<CookContributionInput>>{};
  for (final c in cook) {
    (cookByIngredient[c.ingredientId] ??= []).add(c);
  }

  // …and the week's bare-ingredient meals, which belong to NO cook session
  // (A-D4: nothing about a snack is cooked) and would be missing from the list
  // entirely if the derivation only ever walked sessions.
  final plannedByIngredient = <String, List<PlanIngredientInput>>{};
  for (final p in planned) {
    (plannedByIngredient[p.ingredientId] ??= []).add(p);
  }

  // Every ingredient that has a derived contribution or a touched entry.
  final ingredientIds = <String>{
    ...cookByIngredient.keys,
    ...plannedByIngredient.keys,
    ...entriesByIngredient.keys,
  };

  final items = <ShoppingItem>[];
  for (final id in ingredientIds) {
    final ingredientEntries =
        entriesByIngredient[id] ?? const <ShoppingEntryInput>[];
    // Merge duplicates: oldest is canonical, checked is any-checked, and the
    // manual contributions of every duplicate are unioned (oldest entry's
    // first) so nothing a second device added goes missing.
    final entry = ingredientEntries.isEmpty ? null : ingredientEntries.first;
    final checked = ingredientEntries.any((e) => e.checked);
    final cooks = cookByIngredient[id] ?? const <CookContributionInput>[];
    final snacks = plannedByIngredient[id] ?? const <PlanIngredientInput>[];
    final manuals = <ManualContributionInput>[
      for (final e in ingredientEntries) ...manual[e.id] ?? const [],
    ];

    // An entry with no live contribution of any kind is a stale check-off (its
    // recipe or its snack was removed) — skip it (lifecycle note, 0006 SQL).
    if (cooks.isEmpty && snacks.isEmpty && manuals.isEmpty) continue;

    final m = meta[id];
    final contributions = <ShoppingContribution>[
      // The two DERIVED sources read one rule (see [_derivedContribution]) and
      // interleave by day, so a Tuesday snack sits beside a Tuesday cook
      // rather than in a section of its own.
      for (final c in [
        for (final c in cooks)
          (
            day: c.cookDay,
            build: () => _derivedContribution(
              source: ContributionSource.cookSession,
              label: cookLabel(c, weekdayShort),
              quantity: c.quantity,
              unit: c.unit,
              rawUnit: c.rawUnit,
              measure: c.measure,
              day: c.cookDay,
            ),
          ),
        for (final p in snacks)
          (
            day: p.dayOfWeek,
            build: () => _derivedContribution(
              source: ContributionSource.planEntry,
              label: planIngredientLabel(p, weekdayShort),
              quantity: p.quantity,
              unit: p.unit,
              rawUnit: p.rawUnit,
              measure: p.measure,
              day: p.dayOfWeek,
            ),
          ),
      ]..sort((a, b) => a.day.compareTo(b.day)))
        c.build(),
      for (final man in manuals)
        if (man.measure != null &&
            !(man.measure!.amount > 0) &&
            man.quantity != null)
          ShoppingContribution(
            source: ContributionSource.manual,
            label:
                '${man.note ?? 'manual top-up'} · '
                'not counted (invalid measure "${man.measure!.label}")',
            measureId: man.measureId,
            contributionId: man.id,
          )
        // Same contradictory-row guard as the cook path (the sheet always
        // stores 'piece' beside a measure — anything else is foreign data).
        else if (man.measure != null &&
            man.unit != null &&
            man.unit!.family != UnitFamily.count &&
            man.quantity != null)
          ShoppingContribution(
            source: ContributionSource.manual,
            label:
                '${man.note ?? 'manual top-up'} · '
                'not counted (measure beside non-count unit '
                '"${man.unit!.label}")',
            measureId: man.measureId,
            contributionId: man.id,
          )
        else
          ShoppingContribution(
            source: ContributionSource.manual,
            label: man.note ?? 'manual top-up',
            quantity: man.quantity,
            unit: man.measure == null ? man.unit : null,
            measureId: man.measureId,
            measure: man.measure,
            contributionId: man.id,
          ),
    ];

    // A `piece` line on a row that states a piece weight is priced through
    // that weight exactly as a measure is through its own (ADR-0015) — it
    // joins the basis subtotal rather than sitting beside it as a bare count.
    // The provenance line above keeps its own words either way.
    final pieceMeasure = _pieceMeasureOf(m);
    bool isWeighedPiece(ShoppingContribution c) =>
        pieceMeasure != null && c.measure == null && c.unit == pieces;
    final quantities = <Quantity>[
      for (final c in contributions)
        if (c.measure == null &&
            c.quantity != null &&
            c.unit != null &&
            !isWeighedPiece(c))
          Quantity(c.quantity!, c.unit!),
    ];
    final measured = <MeasureAmount>[
      for (final c in contributions)
        if (c.measure != null && c.quantity != null)
          (amount: c.quantity!, measure: c.measure!),
    ];
    final weighedPieces = <MeasureAmount>[
      for (final c in contributions)
        if (isWeighedPiece(c) && c.quantity != null)
          (amount: c.quantity!, measure: pieceMeasure!),
    ];

    // The ingredient's default unit is a *display* preference for amounts the
    // recipes actually stated — 500 g + 500 g of flour reading in kg. A sum
    // that exists only because measures were folded into their basis has no
    // stated unit to honour, so restating it in oz would answer a question
    // nobody asked: it stays in the basis it was folded into.
    final statesMassOrVolume = quantities.any(
      (q) =>
          q.unit.family == UnitFamily.mass ||
          q.unit.family == UnitFamily.volume,
    );
    final totals = aggregateQuantities(
      quantities,
      measured: [...measured, ...weighedPieces],
      densityGPerMl: m?.densityGPerMl,
      preferred: statesMassOrVolume ? m?.defaultUnit : null,
    );
    // A weighed `piece` line is not the named measure, so a row it joined
    // has no single named count.
    final measureTotal = weighedPieces.isEmpty
        ? _measureTotal(quantities, measured)
        : null;
    final pieceTotal = _pieceTotal(
      meta: m,
      pieceMeasure: pieceMeasure,
      totals: totals,
      quantities: quantities,
      measured: measured,
      measureTotal: measureTotal,
    );
    items.add(
      ShoppingItem(
        entryId: entry?.id,
        ingredientId: id,
        name: m?.name ?? '(unknown ingredient)',
        checked: checked,
        totals: totals,
        measureTotal: measureTotal,
        pieceTotal: pieceTotal,
        contributions: contributions,
        wholeUnitHint: m == null || measureTotal != null || pieceTotal != null
            ? null
            : wholeUnitHintFor(totals: totals, measures: m.measures),
      ),
    );
  }

  // Bucket food items by their ingredient's aisle (free-text = non-food).
  final byAisle = <String, List<ShoppingItem>>{};
  for (final item in items) {
    (byAisle[aisleKey(meta[item.ingredientId]?.category)] ??= []).add(item);
  }

  final groups = <ShoppingGroup>[];
  final aisles = byAisle.keys.toList()..sort(compareAisles);
  for (final aisle in aisles) {
    groups.add(
      ShoppingGroup(
        label: aisleLabel(aisle),
        items: byAisle[aisle]!
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          ),
      ),
    );
  }

  // Non-food (free-text) items, always last.
  final nonFood = <ShoppingItem>[];
  for (final e in freeTextEntries) {
    final manuals = manual[e.id] ?? const [];
    final contributions = <ShoppingContribution>[
      for (final man in manuals)
        ShoppingContribution(
          source: ContributionSource.manual,
          label: man.note ?? 'manual',
          quantity: man.quantity,
          unit: man.unit,
          contributionId: man.id,
        ),
    ];
    final quantities = <Quantity>[
      for (final c in contributions)
        if (c.quantity != null && c.unit != null)
          Quantity(c.quantity!, c.unit!),
    ];
    nonFood.add(
      ShoppingItem(
        entryId: e.id,
        name: e.freeText ?? '',
        checked: e.checked,
        totals: aggregateQuantities(quantities),
        contributions: contributions,
      ),
    );
  }
  if (nonFood.isNotEmpty) {
    groups.add(
      ShoppingGroup(
        label: _nonFoodLabel,
        items: nonFood
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          ),
      ),
    );
  }

  return ShoppingList(
    groups: groups,
    unresolvedComponents: unresolvedComponents,
    optionalLines: optionalLines,
    retiredIngredients: retiredIngredients,
  );
}
