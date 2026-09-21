/// Shopping-list domain (spec §4): a pure function of the week's derived
/// contributions plus a thin persisted overlay of check-offs and manual
/// top-ups.
///
/// Pure Dart (invariant 2). [buildShoppingList] rolls contributions up into
/// [ShoppingItem]s grouped by aisle, keeping each item's provenance.
/// [aggregateQuantities] sums within a unit family and bridges mass and volume
/// only with a density; it never invents a single total (invariant 3).
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

/// Where a contribution comes from (spec §4). `cookSession` and `planEntry` (a
/// planned bare-ingredient meal) are derived and never persisted; `manual` is a
/// persisted top-up or free-text quantity.
enum ContributionSource { cookSession, planEntry, manual }

// --- Builder inputs ----------------------------------------------------------
// Records the repository assembles for [buildShoppingList], so the pure builder
// is testable without a database.

/// One derived cook contribution: a recipe line already scaled by its session.
/// `cookDay` and `batched` drive the provenance label.
///
/// `unit` is null when the stored unit id is unrecognised (`rawUnit` keeps it);
/// such a line is noted in the breakdown and never summed. `measure` is the
/// resolved [Measure], or null when the stored `measure_id` no longer resolves,
/// in which case the line degrades to its count. `forParents` names the planned
/// recipes a component session is cooked for. `weekNote` is the extra segment
/// for a line this week changed ("this week, was 2"), else null.
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

/// One planned bare-ingredient meal. A snack is in no cook session, so the list
/// also walks the week's entries. `quantity` is the per-portion amount times
/// the entry's demand. `unit`, `rawUnit` and `measure` degrade as
/// [CookContributionInput]'s do; `dayOfWeek` and `mealSlot` label the breakdown
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

/// One planned recipe's "N components unresolved" echo. An unresolved component
/// contributes nothing, so the list says so rather than hide the hole.
typedef UnresolvedComponentNote = ({
  String recipeId,
  String recipeTitle,
  int count,
});

/// One planned recipe's "N lines not listed" echo. `reason` is the recipe's own
/// `optional` rule or this week's variant; the row reads muted because it is a
/// choice, not a defect. `names` are the dropped lines' ingredients in stored
/// order and `lineIds` runs parallel to them, so tapping a name can include
/// that line this week.
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

  /// A bare-ingredient meal on the week: there is no recipe to edit, so the
  /// pick is in the plan, on the entry itself.
  planEntry,
}

/// One line or planned meal whose ingredient the household has retired. It buys
/// nothing, but is echoed at the foot of the list with the row's last known
/// name. `heading` is the recipe's title or the planned meal's provenance
/// label.
typedef RetiredIngredientNote = ({
  String heading,
  String ingredientName,
  RetiredIngredientSite site,
});

/// A persisted shopping entry (check-off and free-text anchor). `createdAt`
/// (ISO-8601) makes duplicate merging deterministic: the oldest live row wins.
typedef ShoppingEntryInput = ({
  String id,
  String? ingredientId,
  String? freeText,
  String? category,
  bool checked,
  Unit? unit,
  String? createdAt,
});

/// A persisted manual contribution. `measureId` is the stored `measure_id`
/// verbatim, kept while the measure row is unsynced so a re-save never strips
/// the FK; `measure` is the resolved [Measure], when there is one.
typedef ManualContributionInput = ({
  String id,
  String entryId,
  double? quantity,
  Unit? unit,
  String? measureId,
  Measure? measure,
  String? note,
});

/// The vocab metadata needed to group and sum (name, aisle, density) plus the
/// row's live measures, sorted by `sort_order`. `pieceBasisAmount` is what one
/// piece weighs in `basis` (ADR-0015); null means `piece` lines stay a bare
/// count.
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

    /// The stored `measure_id` of a manual contribution, kept even while
    /// [measure] is unresolved so a re-save never wipes the FK. Null for
    /// derived lines.
    String? measureId,

    /// The day (0 = first day of the household week) a derived contribution
    /// belongs to, which orders the breakdown. Null for a manual top-up.
    int? cookDay,

    /// The `shopping_list_contribution` id; set only for a `manual`
    /// contribution.
    String? contributionId,
  }) = _ShoppingContribution;
}

/// A rolled-up shopping line: one ingredient or free-text item, its check-off
/// state, its [totals] (more than one when families cannot merge honestly) and
/// the [contributions] behind it.
@freezed
abstract class ShoppingItem with _$ShoppingItem {
  const ShoppingItem._();

  const factory ShoppingItem({
    required String name,

    /// The persisted entry id, or null for a derived ingredient not yet
    /// touched; check-off creates the entry lazily.
    String? entryId,

    /// Null for a free-text (non-food) item.
    String? ingredientId,
    @Default(false) bool checked,
    @Default(<Quantity>[]) List<Quantity> totals,
    @Default(<ShoppingContribution>[]) List<ShoppingContribution> contributions,

    /// The total counted in one measure ("1 can (400 g), drained"), set only
    /// when every quantified contribution asked for that same measure. [totals]
    /// still carries what it weighs.
    MeasureAmount? measureTotal,

    /// The total as a count of pieces, on a `piece`-default row that states a
    /// piece weight (ADR-0015), once everything folded into one basis-family
    /// total. `approx` is true when a plain mass/volume line joined or a
    /// measure is not a whole number of pieces. Null when [measureTotal] is
    /// set.
    PieceTotal? pieceTotal,

    /// A round-up hint ("2.25 → buy 3") beside the total, never replacing it
    /// (invariant 3). Null when the item does not qualify ([wholeUnitHintFor])
    /// or when [measureTotal] or [pieceTotal] is set.
    WholeUnitHint? wholeUnitHint,
  }) = _ShoppingItem;

  /// A free-text non-food item ("paper towels") rather than a vocab ingredient.
  bool get isFreeText => ingredientId == null;

  /// Whether this line has a numeric total (a non-food staple may not).
  bool get hasTotal => totals.isNotEmpty;

  /// Whether any of this item's total comes from the cook plan.
  bool get hasCookContribution =>
      contributions.any((c) => c.source == ContributionSource.cookSession);

  /// Purely user-added (free text, or an ingredient present only through a
  /// manual top-up), so removable wholesale.
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

/// The whole list grouped by aisle, plus its three echoes of what it leaves
/// out: [unresolvedComponents], [optionalLines] and [retiredIngredients].
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

  /// The aisles still to walk: each group with only its unticked items, empty
  /// groups dropped. [groups] stays the full list.
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

  /// Every ticked item, flattened in aisle order then name.
  List<ShoppingItem> get basket => [for (final g in basketGroups) ...g.items];

  /// The mirror of [openGroups]: each group with only its ticked items.
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

/// The identity a row keeps across a tick: its ingredient, or a free-text
/// item's entry. A derived row has no entry id until its first check-off.
String shoppingItemIdentity(ShoppingItem item) =>
    item.ingredientId ?? item.entryId ?? item.name;

/// Whether ticking [item] finishes [list]: more than one item, [item] unticked
/// and every other item ticked. Decided before the write, so a list that
/// arrives all-ticked by sync does not qualify.
bool completesTheList(ShoppingList list, ShoppingItem item) {
  final items = [for (final g in list.groups) ...g.items];
  if (items.length < 2 || item.checked) return false;
  final id = shoppingItemIdentity(item);
  return items.every((i) => i.checked || shoppingItemIdentity(i) == id);
}

// --- Aggregation (honest summation core) -------------------------------------

/// An amount counted in a [Measure] ("2 × potato, large"); also the shape of a
/// [ShoppingItem.measureTotal].
typedef MeasureAmount = ({double amount, Measure measure});

/// A [ShoppingItem.pieceTotal]: the possibly fractional `count`, and whether it
/// is `approx` (read back from a stated mass or volume).
typedef PieceTotal = ({double count, bool approx});

/// Sums [qs] into as few totals as it honestly can (invariant 3).
///
/// - Sums within a unit family through the ratio table.
/// - Bridges mass and volume only with a positive [densityGPerMl]; otherwise a
///   mixed set yields two subtotals.
/// - [measured] amounts fold in through each measure's basis amount; a
///   non-positive one is skipped.
/// - [UnitFamily.count] sums per unit. [UnitFamily.imprecise] never sums:
///   identical words collapse to one entry, distinct ones stay apart.
/// - [preferred] sets the display unit when it shares the summed family.
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
        // A component line should never reach here; if one does, sum it per
        // unit rather than drop it.
        counts.update(q.unit.id, (v) => v + q.amount, ifAbsent: () => q.amount);
      case UnitFamily.imprecise:
        // Collapse identical imprecise units: amounts on them carry no meaning
        // (they never scale or sum), so one line per unit is the honest render.
        if (!imprecise.any((e) => e.unit == q.unit)) imprecise.add(q);
    }
  }
  for (final m in measured) {
    // A measure folds into its own basis family, never across it (ADR-0008).
    // Only a positive amount is trusted.
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

/// Sums same-family [qs], displayed in [preferred] when it shares the family,
/// else in the input unit with the largest share. Null when empty.
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

/// A whole-unit round-up hint: the fractional `count`, the whole units to
/// `buy`, and what one unit is (`unitLabel`). `approx` is true when the count
/// was derived from a mass total.
typedef WholeUnitHint = ({
  double count,
  int buy,
  String unitLabel,
  bool approx,
});

/// The round-up hint for an item's [totals], or null (spec §4). Offered only
/// for a single, fractional total: a count rounds up directly; a mass or volume
/// converts through the primary same-family measure and is marked `approx`
/// ([amountInMeasure] refuses a cross-family pair).
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

// Aisle order lives in `core/aisles.dart`. "Non-food" is this list's own and
// always last.
const _nonFoodLabel = 'Non-food';

/// The provenance label for a cook contribution: the recipe title, plus its
/// cook day when the recipe is batched into more than one session. A component
/// adds the planned recipe it serves ("Romesco Aioli · for Sliders · cook
/// Sat"); a line the week changed adds its week note last.
String cookLabel(CookContributionInput c, List<String> weekdayShort) {
  final forParents = c.forParents;
  return [
    c.recipeTitle,
    if (forParents.isNotEmpty) 'for ${forParents.join(' + ')}',
    if (c.batched || forParents.isNotEmpty) 'cook ${weekdayShort[c.cookDay]}',
    if (c.weekNote != null) c.weekNote!,
  ].join(' · ');
}

/// The provenance label for a planned bare-ingredient meal: slot and day
/// ("Snack · Tue").
String planIngredientLabel(PlanIngredientInput p, List<String> weekdayShort) =>
    '${p.mealSlot} · ${weekdayShort[p.dayOfWeek]}';

/// One derived contribution, with the degradations every derived source shares.
/// An unrecognised unit, a measure with a non-positive or NaN weight, or a
/// non-count unit beside a measure id becomes a visible "not counted" note and
/// stays out of the totals (invariant 3).
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

/// The total as a count of one measure, or null. Set only when every quantified
/// contribution named the same measure and no plain line joined them.
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

/// The row's piece weight as a [Measure] the fold understands (ADR-0015). Null
/// when the row states none, or a non-positive one.
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

/// The total as a count of pieces, or null ([ShoppingItem.pieceTotal]). Needs a
/// `piece` default, a piece weight and exactly one basis-family total; divides
/// through [amountInMeasure]. A row counted in one named measure keeps that
/// count. `approx` means the count was read back from a weight.
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
/// [cook] are the derived cook contributions, [planned] the week's
/// bare-ingredient meals, [entries] the persisted rows, [manual] the manual
/// contributions keyed by entry and [meta] the vocab. [weekdayShort] is seven
/// short names in the household's own week order, indexed by a meal's offset.
///
/// An entry shows only while it has a live contribution or is free text. Two
/// live entries for one ingredient can exist (two offline devices; no unique
/// index, by design) and merge deterministically: contributions unioned,
/// checked is any-checked, the oldest row is canonical. [unresolvedComponents],
/// [optionalLines] and [retiredIngredients] pass through untouched.
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

  // The week's bare-ingredient meals belong to no cook session.
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
    // Merge duplicates: oldest is canonical, checked is any-checked, manual
    // contributions are unioned.
    final entry = ingredientEntries.isEmpty ? null : ingredientEntries.first;
    final checked = ingredientEntries.any((e) => e.checked);
    final cooks = cookByIngredient[id] ?? const <CookContributionInput>[];
    final snacks = plannedByIngredient[id] ?? const <PlanIngredientInput>[];
    final manuals = <ManualContributionInput>[
      for (final e in ingredientEntries) ...manual[e.id] ?? const [],
    ];

    // An entry with no live contribution of any kind is a stale check-off (its
    // recipe or its snack was removed), so skip it.
    if (cooks.isEmpty && snacks.isEmpty && manuals.isEmpty) continue;

    final m = meta[id];
    final contributions = <ShoppingContribution>[
      // Both derived sources go through [_derivedContribution] and interleave
      // by day.
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

    // A `piece` line folds into the basis subtotal through the piece weight
    // (ADR-0015).
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

    // The default unit is a display preference for stated amounts only; a sum
    // that exists only through folded measures stays in its basis.
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
