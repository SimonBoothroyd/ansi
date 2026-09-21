/// Planning domain entities: the [WeekPlan] the Week screen renders, its
/// [PlanEntry] meals and the household's [Member]s. Pure Dart.
///
/// Meal slots are free text; [kDefaultMealSlots] are the four the UI offers.
/// Which seven days a week is belongs to `core/week_shape.dart`.
library;

// Freezed needs each class's private `._` constructor before the factory (for
// the custom getters), which trips the unnamed-first sort lint.
// ignore_for_file: sort_unnamed_constructors_first
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../recipes/domain/recipe_macros.dart' show IngredientNutrition;

part 'planning.freezed.dart';

/// A person in the household, referenced by id from [PlanEntry.eaterIds].
@freezed
abstract class Member with _$Member {
  const Member._();

  const factory Member({
    required String id,
    required String displayName,

    /// The person's usual portion as a multiple of one recipe serving, in
    /// quarter steps from 0.25 to 3. Read through [demandPortions].
    @Default(1.0) double portionFactor,
  }) = _Member;

  /// The uppercase first letter of [displayName], or '?' when it is empty.
  String get initial =>
      displayName.trim().isEmpty ? '?' : displayName.trim()[0].toUpperCase();
}

/// The quick-pick portion factors; custom values run in quarter steps between
/// [kPortionFactorMin] and [kPortionFactorMax].
const kPortionFactorPicks = [0.5, 0.75, 1.0, 1.25, 1.5];
const kPortionFactorMin = 0.25;
const kPortionFactorMax = 3.0;
const kPortionFactorStep = 0.25;

/// Whether [factor] is a quarter step within
/// [kPortionFactorMin]..[kPortionFactorMax], mirroring the server's check
/// constraint.
bool isValidPortionFactor(double factor) {
  if (factor < kPortionFactorMin - 1e-9 || factor > kPortionFactorMax + 1e-9) {
    return false;
  }
  final steps = factor / kPortionFactorStep;
  return (steps - steps.roundToDouble()).abs() < 1e-9;
}

/// Σ [Member.portionFactor] over [eaterIds]. An eater missing from the roster
/// counts as one portion.
double eatersDemand(
  Iterable<String> eaterIds,
  Map<String, Member> membersById,
) => eaterIds.fold(0, (sum, id) => sum + (membersById[id]?.portionFactor ?? 1));

/// An entry's demand in portions: the [PlanEntry.portions] override when set,
/// else [eatersDemand]. Fractional by design, and never rounded.
double demandPortions(PlanEntry entry, Map<String, Member> membersById) =>
    entry.portions?.toDouble() ?? eatersDemand(entry.eaterIds, membersById);

/// What a planned meal is. Derivations `switch` on it so the compiler checks
/// every kind is handled; a null `recipe_id` must never be read as "skip".
enum PlanEntryKind {
  /// A dish from the Library: cooked, bought, with macros from its own lines.
  recipe,

  /// A bare ingredient eaten as itself: bought, not cooked, weighed from its
  /// vocabulary row.
  ingredient,

  /// A meal eaten out: neither cooked nor bought, and counted only from stated
  /// macros.
  out,
}

/// One planned meal on [dayOfWeek] (0..6 from the week's first day) under a
/// free-text [mealSlot], eaten by [eaterIds].
///
/// Exactly one target is set (the server's `plan_entry_target_xor`): a recipe
/// ([recipeId]; its amount is its portions), an ingredient ([ingredientId],
/// with one portion's amount in [quantity] + [unit] or a named [measure]), or a
/// meal out ([label], optionally with stated per-portion [macros]). Branch on
/// [kind], never on a null [recipeId].
@freezed
abstract class PlanEntry with _$PlanEntry {
  const PlanEntry._();

  const factory PlanEntry({
    required String id,
    required int dayOfWeek,
    required String mealSlot,

    /// The dish, when this meal is a recipe.
    String? recipeId,
    String? recipeTitle,

    /// The vocabulary row, when this meal is a bare ingredient.
    String? ingredientId,
    String? ingredientName,

    /// The words of a meal eaten out, e.g. "Office lunch".
    String? label,

    /// One portion's stated macros for a meal eaten out. Null means not stated,
    /// never zero. Always null on the other two kinds.
    Macros? macros,

    /// The amount of one portion of an ingredient meal. Null (with [unit])
    /// states no amount and contributes nothing to a total. Always null on the
    /// other two kinds.
    double? quantity,
    Unit? unit,

    /// The persisted `measure_id`, kept even while [measure] is unresolved so a
    /// re-save never wipes the FK.
    String? measureId,

    /// The resolved named measure ("1 bar"); [unit] then holds the count
    /// fallback (`piece`).
    Measure? measure,

    /// The vocab row's macros, basis and density, denormalised so the week's
    /// macro sum needs no second watch. Null on a recipe meal and on an
    /// ingredient meal whose row has not synced.
    IngredientNutrition? nutrition,
    @Default(<String>[]) List<String> eaterIds,

    /// How many portions to cook for; null tracks the eater count.
    int? portions,
  }) = _PlanEntry;

  /// What this meal is, from whichever target column is set.
  PlanEntryKind get kind => label != null
      ? PlanEntryKind.out
      : ingredientId != null
      ? PlanEntryKind.ingredient
      : PlanEntryKind.recipe;

  /// The name this meal shows, or null when its recipe or vocab row is gone.
  String? get title => switch (kind) {
    PlanEntryKind.recipe => recipeTitle,
    PlanEntryKind.ingredient => ingredientName,
    PlanEntryKind.out => label,
  };

  /// The [portions] override, or the eater head-count — before portion factors.
  /// The demand a plan cooks for is [demandPortions].
  int get portionsOrDefault => portions ?? eaterIds.length;
}

/// The words for a meal whose recipe or vocab row is gone, one sentence per
/// kind. A meal eaten out keeps its own label.
String deletedTargetLabel(PlanEntry entry) => switch (entry.kind) {
  PlanEntryKind.recipe => '(deleted recipe)',
  PlanEntryKind.ingredient => '(deleted ingredient)',
  PlanEntryKind.out => '(that meal)',
};

/// One week, addressed by [weekStart] (the date of its first day, date-only),
/// holding every meal planned across it.
@freezed
abstract class WeekPlan with _$WeekPlan {
  const WeekPlan._();

  const factory WeekPlan({
    required String id,
    required DateTime weekStart,
    String? label,
    @Default(<PlanEntry>[]) List<PlanEntry> entries,
  }) = _WeekPlan;

  /// The entries on [dayOfWeek], ordered by meal slot then stored order.
  /// Decorates with the source index because [List.sort] is not stable.
  List<PlanEntry> entriesForDay(int dayOfWeek) {
    final day = entries.where((e) => e.dayOfWeek == dayOfWeek).toList();
    final indexed = [for (var i = 0; i < day.length; i++) (i, day[i])]
      ..sort((a, b) {
        final ra = mealSlotRank(a.$2.mealSlot);
        final rb = mealSlotRank(b.$2.mealSlot);
        return ra != rb ? ra.compareTo(rb) : a.$1.compareTo(b.$1);
      });
    return [for (final p in indexed) p.$2];
  }
}

/// The meal slots the UI offers, in day order. Users may type any other label.
const kDefaultMealSlots = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];

/// The slot a new meal starts on: the first of [kDefaultMealSlots] that none of
/// [dayEntries] fills, or Dinner when all are. Case-insensitive; a custom slot
/// fills none of them.
String defaultMealSlot(Iterable<PlanEntry> dayEntries) {
  final taken = {for (final e in dayEntries) e.mealSlot.trim().toLowerCase()};
  return kDefaultMealSlots.firstWhere(
    (s) => !taken.contains(s.toLowerCase()),
    orElse: () => 'Dinner',
  );
}

/// Orders a meal slot within a day: known slots in meal order, then custom
/// slots. Case-insensitive.
int mealSlotRank(String slot) {
  final i = kDefaultMealSlots.indexWhere(
    (s) => s.toLowerCase() == slot.toLowerCase(),
  );
  return i < 0 ? kDefaultMealSlots.length : i;
}

/// One recipe whose this-week changes a copy did not carry, and how many. A
/// copy never carries variants forward, and names what it left.
typedef VariantLeftBehind = ({String recipeTitle, int changes});

/// What a copy of last week carried, and what it could not.
typedef CopyLastWeekResult = ({
  int meals,
  List<VariantLeftBehind> variantsLeftBehind,
});
