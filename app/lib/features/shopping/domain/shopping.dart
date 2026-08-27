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
typedef CookContributionInput = ({
  String ingredientId,
  double? quantity,
  Unit unit,
  String recipeTitle,
  int cookDay,
  bool batched,
});

/// A persisted shopping entry row (the check-off + free-text anchor).
typedef ShoppingEntryInput = ({
  String id,
  String? ingredientId,
  String? freeText,
  String? category,
  bool checked,
  Unit? unit,
});

/// A persisted manual contribution attached to an entry.
typedef ManualContributionInput = ({
  String id,
  String entryId,
  double? quantity,
  Unit? unit,
  String? note,
});

/// Ingredient vocab metadata needed to group + sum (name, aisle, density).
typedef IngredientMetaInput = ({
  String name,
  String? category,
  double? densityGPerMl,
  Unit defaultUnit,
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

/// The whole shopping list, grouped by aisle.
@freezed
abstract class ShoppingList with _$ShoppingList {
  const ShoppingList._();

  const factory ShoppingList({
    @Default(<ShoppingGroup>[]) List<ShoppingGroup> groups,
  }) = _ShoppingList;

  bool get isEmpty => groups.isEmpty;
}

// --- Aggregation (honest summation core) -------------------------------------

/// Sums [qs] into as few totals as it can *honestly* (invariant 3).
///
/// - Sums within a unit family by the ratio table (g·kg → one mass total).
/// - Bridges mass↔volume only when [densityGPerMl] is supplied; without it a
///   mixed set yields two subtotals rather than an invented single number.
/// - [UnitFamily.count] totals sum per count unit; [UnitFamily.imprecise] never
///   sums (a "pinch" doubled is still a pinch) — each is kept as-is.
/// - [preferred] biases the display unit when it shares the summed family.
List<Quantity> aggregateQuantities(
  List<Quantity> qs, {
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
      case UnitFamily.imprecise:
        imprecise.add(q);
    }
  }

  final totals = <Quantity>[];

  if (mass.isNotEmpty || volume.isNotEmpty) {
    final canBridge = densityGPerMl != null;
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
String cookLabel(CookContributionInput c, List<String> weekdayShort) =>
    c.batched
    ? '${c.recipeTitle} · cook ${weekdayShort[c.cookDay]}'
    : c.recipeTitle;

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
ShoppingList buildShoppingList({
  required List<CookContributionInput> cook,
  required List<ShoppingEntryInput> entries,
  required Map<String, List<ManualContributionInput>> manual,
  required Map<String, IngredientMetaInput> meta,
  required List<String> weekdayShort,
}) {
  // Index persisted entries by their ingredient (free-text ones stay by id).
  final entryByIngredient = <String, ShoppingEntryInput>{};
  final freeTextEntries = <ShoppingEntryInput>[];
  for (final e in entries) {
    final ing = e.ingredientId;
    if (ing != null) {
      entryByIngredient[ing] = e;
    } else {
      freeTextEntries.add(e);
    }
  }

  // Group derived cook contributions by ingredient, preserving order.
  final cookByIngredient = <String, List<CookContributionInput>>{};
  for (final c in cook) {
    (cookByIngredient[c.ingredientId] ??= []).add(c);
  }

  // Every ingredient that has a cook contribution or a touched entry.
  final ingredientIds = <String>{
    ...cookByIngredient.keys,
    ...entryByIngredient.keys,
  };

  final items = <ShoppingItem>[];
  for (final id in ingredientIds) {
    final entry = entryByIngredient[id];
    final cooks = cookByIngredient[id] ?? const <CookContributionInput>[];
    final manuals = entry == null
        ? const <ManualContributionInput>[]
        : (manual[entry.id] ?? const []);

    // An entry with neither a cook nor a manual contribution is a stale
    // check-off (its recipe was removed) — skip it (lifecycle note, 0006 SQL).
    if (cooks.isEmpty && manuals.isEmpty) continue;

    final m = meta[id];
    final contributions = <ShoppingContribution>[
      for (final c in [
        ...cooks,
      ]..sort((a, b) => a.cookDay.compareTo(b.cookDay)))
        ShoppingContribution(
          source: ContributionSource.cookSession,
          label: cookLabel(c, weekdayShort),
          quantity: c.quantity,
          unit: c.unit,
          cookDay: c.cookDay,
        ),
      for (final man in manuals)
        ShoppingContribution(
          source: ContributionSource.manual,
          label: man.note ?? 'manual top-up',
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

    items.add(
      ShoppingItem(
        entryId: entry?.id,
        ingredientId: id,
        name: m?.name ?? '(unknown ingredient)',
        checked: entry?.checked ?? false,
        totals: aggregateQuantities(
          quantities,
          densityGPerMl: m?.densityGPerMl,
          preferred: m?.defaultUnit,
        ),
        contributions: contributions,
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

  return ShoppingList(groups: groups);
}

const _uncategorised = ' other';
