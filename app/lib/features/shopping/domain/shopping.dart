/// Shopping-list domain — the DERIVED output view (spec §4).
///
/// PURE DART (invariant 2): no `package:flutter`. The list is a pure function
/// of the batch cook plan's contributions plus a thin persisted overlay
/// (check-off + manual/free-text). [buildShoppingList] sums per-ingredient
/// contributions into rolled-up [ShoppingItem]s, groups them by aisle
/// ([ShoppingGroup]), and keeps the provenance breakdown (spec §4:
/// "Flour — 500g · Curry batch 300g · Cookies 150g · +50g manual").
///
/// Contributions come in two flavours (spec §4):
///   * `cookSession` — DERIVED live from the cook plan (quantity = a recipe
///     line × the session's scale factor). Never persisted.
///   * `manual` — a user top-up on an ingredient, or a quantity on a free-text
///     item. Persisted (`shopping_list_contribution`).
///
/// [aggregateQuantities] is the honest summation core (invariant 3): it sums
/// within a unit family, bridges mass↔volume only when a density is supplied,
/// and NEVER invents a number to force a single total — an ingredient with
/// mixed families and no density yields two honest subtotals, not a guess.
library;

// Freezed needs each class's private `._` constructor before the factory (for
// the custom getters), which trips the unnamed-first sort lint.
// ignore_for_file: sort_unnamed_constructors_first
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/result/result.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';

part 'shopping.freezed.dart';

/// Where a contribution comes from (spec §4). `cookSession` contributions are
/// derived from the cook plan; `manual` ones are user top-ups / free-text.
enum ContributionSource { cookSession, manual }

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

/// One planned recipe's "N optional lines not listed" echo.
///
/// An optional line contributes NOTHING to the list — the `effectiveLines`
/// seam dropped it before the session was expanded — and the recipe it
/// belongs to says so, by name, in the same group-header voice as
/// [UnresolvedComponentNote]. The difference is the colour: an unresolved
/// component is a defect somebody can fix, an optional line is a rule
/// somebody chose, so the row reads muted rather than amber. `names` are the
/// dropped lines' ingredient names in stored order.
typedef OptionalLinesNote = ({
  String recipeId,
  String recipeTitle,
  List<String> names,
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
typedef IngredientMetaInput = ({
  String name,
  String? category,
  double? densityGPerMl,
  Unit defaultUnit,
  List<Measure> measures,
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
    /// (mirrors the recipe line's `measureId`). Null for cook lines (derived,
    /// never re-saved here).
    String? measureId,

    /// Cook day (0=Mon..6=Sun) for a cook contribution — orders the breakdown.
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

    /// An honest round-up hint ("2.25 → buy 3") for a measure-bearing count
    /// ingredient — a HINT beside the total, never a replaced total
    /// (invariant 3). Null when the item doesn't qualify (see
    /// [wholeUnitHintFor]).
    WholeUnitHint? wholeUnitHint,
  }) = _ShoppingItem;

  /// A free-text non-food item ("paper towels") rather than a vocab ingredient.
  bool get isFreeText => ingredientId == null;

  /// Whether this line has a numeric total (a non-food staple may not).
  bool get hasTotal => totals.isNotEmpty;

  /// True once the item has any provenance worth showing (more than a single
  /// source, or a manual top-up alongside cook sources).
  bool get hasBreakdown =>
      contributions.length > 1 ||
      contributions.any((c) => c.source == ContributionSource.manual);

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

/// The whole shopping list, grouped by aisle, plus the per-parent
/// [unresolvedComponents] echo (step 8.6 / D4) and the per-recipe
/// [optionalLines] echo — what the list is short by, and why it is silent about
/// it.
@freezed
abstract class ShoppingList with _$ShoppingList {
  const ShoppingList._();

  const factory ShoppingList({
    @Default(<ShoppingGroup>[]) List<ShoppingGroup> groups,
    @Default(<UnresolvedComponentNote>[])
    List<UnresolvedComponentNote> unresolvedComponents,
    @Default(<OptionalLinesNote>[]) List<OptionalLinesNote> optionalLines,
  }) = _ShoppingList;

  bool get isEmpty => groups.isEmpty;
}

// --- Aggregation (honest summation core) -------------------------------------

/// An amount counted in a [Measure] ("2 × potato, large"), awaiting honest
/// summation via the measure's gram weight.
typedef MeasureAmount = ({double amount, Measure measure});

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
/// - a mass or volume total converts through a measure of the SAME family
///   as its basis — "674 g ≈ 2.25 × potato, large → buy 3" — marked
///   `approx` (a cross-family pair would need a density this hint doesn't
///   carry, and [amountInMeasure] refuses it honestly). The measure used is
///   the one the total's contributions were actually counted in
///   ([usedMeasures], when they all agree — hinting "buy 3 medium" against
///   a total built from large potatoes would misprice it); an item with NO
///   measure provenance falls back to the ingredient's primary measure
///   (lowest `sort_order`), and one with *disagreeing* provenance gets no
///   hint (no single honest unit to round to).
///
/// Always a hint BESIDE the honest total, never a replacement (invariant 3).
WholeUnitHint? wholeUnitHintFor({
  required List<Quantity> totals,
  required List<Measure> measures,
  List<Measure> usedMeasures = const [],
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
    final usedIds = {for (final m in usedMeasures) m.id};
    final Measure? measure;
    if (usedIds.length > 1) {
      return null; // disagreeing provenance — no single honest unit
    } else if (usedMeasures.isNotEmpty) {
      measure = usedMeasures.first;
    } else {
      measure = measures.isEmpty ? null : measures.first;
    }
    if (measure == null) return null;
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

// Aisle order for the grouped list. Anything unknown sorts after these,
// alphabetically; free-text "Non-food" always sits last.
const _aisleOrder = <String>[
  'produce',
  'meat',
  'dairy',
  'baking',
  'grains',
  'pantry',
  'spices & seasoning',
  'fats & oils',
];

const _nonFoodLabel = 'Non-food';

/// Title-cases an aisle label for display ("spices & seasoning" → "Spices &
/// Seasoning").
String _titleCase(String s) => s
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// The provenance label for a cook contribution: the recipe title, plus its
/// cook day when the recipe is batched into more than one session (so the
/// breakdown disambiguates which cook it came from).
///
/// A **component** contribution (step 8.6 / D4) gains one segment naming the
/// planned recipe it is cooked for, and always carries its cook day: "Romesco
/// Aioli · for Sliders · cook Sat". Two levels, deepest first — the recipe
/// whose line this actually is, then the plan it serves.
String cookLabel(CookContributionInput c, List<String> weekdayShort) {
  final forParents = c.forParents;
  return [
    c.recipeTitle,
    if (forParents.isNotEmpty) 'for ${forParents.join(' + ')}',
    if (c.batched || forParents.isNotEmpty) 'cook ${weekdayShort[c.cookDay]}',
  ].join(' · ');
}

/// Assembles the derived shopping list from its parts (spec §4).
///
/// [cook] are the derived cook contributions; [entries] the persisted
/// check-off/free-text rows; [manual] the persisted manual contributions keyed
/// by their entry; [meta] the ingredient vocab (name, aisle, density).
/// [weekdayShort] labels cook days without pulling a formatter into the domain.
///
/// An entry is only surfaced while it has at least one live contribution (a
/// cook one or a manual one) or is a free-text item — so an ingredient whose
/// recipe was deleted (leaving only a stale checked row) drops off the list.
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
/// it left out.
ShoppingList buildShoppingList({
  required List<CookContributionInput> cook,
  required List<ShoppingEntryInput> entries,
  required Map<String, List<ManualContributionInput>> manual,
  required Map<String, IngredientMetaInput> meta,
  required List<String> weekdayShort,
  List<UnresolvedComponentNote> unresolvedComponents = const [],
  List<OptionalLinesNote> optionalLines = const [],
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

  // Every ingredient that has a cook contribution or a touched entry.
  final ingredientIds = <String>{
    ...cookByIngredient.keys,
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
    final manuals = <ManualContributionInput>[
      for (final e in ingredientEntries) ...manual[e.id] ?? const [],
    ];

    // An entry with neither a cook nor a manual contribution is a stale
    // check-off (its recipe was removed) — skip it (lifecycle note, 0006 SQL).
    if (cooks.isEmpty && manuals.isEmpty) continue;

    final m = meta[id];
    final contributions = <ShoppingContribution>[
      for (final c in [
        ...cooks,
      ]..sort((a, b) => a.cookDay.compareTo(b.cookDay)))
        // A quantity whose unit wasn't recognised is surfaced as an
        // unconverted note (no quantity/unit → renders as a dash + note) and
        // stays out of the totals: summing it under an assumed unit would
        // invent semantics (invariant 3). A measure with a non-positive/NaN
        // gram weight is bad data and gets the same treatment — a visible
        // "not counted" note, never a silent drop from the total. A valid
        // measure-quantified line keeps its measure so the fold below can
        // price it in grams.
        if (c.unit == null && c.measure == null && c.quantity != null)
          ShoppingContribution(
            source: ContributionSource.cookSession,
            label:
                '${cookLabel(c, weekdayShort)} · '
                'not counted (unrecognised unit'
                '${c.rawUnit == null ? '' : ' "${c.rawUnit}"'})',
            cookDay: c.cookDay,
          )
        else if (c.measure != null &&
            !(c.measure!.amount > 0) &&
            c.quantity != null)
          ShoppingContribution(
            source: ContributionSource.cookSession,
            label:
                '${cookLabel(c, weekdayShort)} · '
                'not counted (invalid measure "${c.measure!.label}")',
            cookDay: c.cookDay,
          )
        // A measure counts THINGS, so its row always stores a count unit
        // ('piece'). A NON-count unit beside a measure_id is a contradictory
        // row — is the number grams or a measure count? Folding it through
        // the gram weight would invent mass (the review's ×299 leaks), so it
        // degrades to a visible note like the paths above.
        else if (c.measure != null &&
            c.unit != null &&
            c.unit!.family != UnitFamily.count &&
            c.quantity != null)
          ShoppingContribution(
            source: ContributionSource.cookSession,
            label:
                '${cookLabel(c, weekdayShort)} · '
                'not counted (measure beside non-count unit '
                '"${c.unit!.label}")',
            cookDay: c.cookDay,
          )
        else
          ShoppingContribution(
            source: ContributionSource.cookSession,
            label: cookLabel(c, weekdayShort),
            quantity: c.quantity,
            unit: c.measure == null ? c.unit : null,
            measure: c.measure,
            cookDay: c.cookDay,
          ),
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

    final quantities = <Quantity>[
      for (final c in contributions)
        if (c.measure == null && c.quantity != null && c.unit != null)
          Quantity(c.quantity!, c.unit!),
    ];
    final measured = <MeasureAmount>[
      for (final c in contributions)
        if (c.measure != null && c.quantity != null)
          (amount: c.quantity!, measure: c.measure!),
    ];

    final totals = aggregateQuantities(
      quantities,
      measured: measured,
      densityGPerMl: m?.densityGPerMl,
      preferred: m?.defaultUnit,
    );
    items.add(
      ShoppingItem(
        entryId: entry?.id,
        ingredientId: id,
        name: m?.name ?? '(unknown ingredient)',
        checked: checked,
        totals: totals,
        contributions: contributions,
        wholeUnitHint: m == null
            ? null
            : wholeUnitHintFor(
                totals: totals,
                measures: m.measures,
                // The measures this total was actually counted in (deduped by
                // id): the hint prices in these when they agree, rather than
                // whichever measure happens to sort first.
                usedMeasures: [
                  for (final id in {for (final e in measured) e.measure.id})
                    measured.firstWhere((e) => e.measure.id == id).measure,
                ],
              ),
      ),
    );
  }

  // Bucket food items by their ingredient's aisle (free-text = non-food).
  final byAisle = <String, List<ShoppingItem>>{};
  for (final item in items) {
    final category = meta[item.ingredientId]?.category?.toLowerCase();
    (byAisle[category ?? _uncategorised] ??= []).add(item);
  }

  final groups = <ShoppingGroup>[];
  final aisles = byAisle.keys.toList()
    ..sort((a, b) {
      final ai = _aisleOrder.indexOf(a);
      final bi = _aisleOrder.indexOf(b);
      if (ai != -1 && bi != -1) return ai.compareTo(bi);
      if (ai != -1) return -1;
      if (bi != -1) return 1;
      return a.compareTo(b);
    });
  for (final aisle in aisles) {
    final label = aisle == _uncategorised ? 'Other' : _titleCase(aisle);
    groups.add(
      ShoppingGroup(
        label: label,
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
  );
}

const _uncategorised = '\u0000other';
