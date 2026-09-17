/// Planning domain entities — the read aggregate the Week screen renders.
///
/// PURE DART (invariant 2): no `package:flutter`. A [WeekPlan] is one week
/// (addressed by `weekStart`, the date of its own first day) holding the
/// [PlanEntry] meals planned across its seven days. A meal names a recipe, a
/// bare ingredient **or** the words of a meal eaten out — see [PlanEntryKind]
/// and [PlanEntry]. A [Member] is a person in the
/// household; an entry's
/// [PlanEntry.eaterIds] point at them and the sum of their
/// [Member.portionFactor]s is the entry's demand ([demandPortions]) unless the
/// entry's whole-number [PlanEntry.portions] override says otherwise.
///
/// Meal slots are free text (spec §8, not an enum); [kDefaultMealSlots] are the
/// four the UI offers, [mealSlotRank] orders known slots ahead of custom ones
/// within a day, and [defaultMealSlot] is the one an add starts on. Which
/// seven days a week IS — and so which week a date falls in — belongs to the
/// household's week shape (`core/week_shape.dart`).
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

/// A person in the household. Eaters on a [PlanEntry] reference its id;
/// [initial] is the avatar letter.
@freezed
abstract class Member with _$Member {
  const Member._();

  const factory Member({
    required String id,
    required String displayName,

    /// The person's usual portion as a multiple of one recipe serving: `0.75`
    /// for someone who eats three-quarters of a serving. A standing fact about
    /// the person, spent wherever a demand is counted — the cook plan, the
    /// shopping list and the macro lens all read it through [demandPortions].
    /// Quarter steps from 0.25 to 3; the default `1` makes a member weigh
    /// exactly one head.
    @Default(1.0) double portionFactor,
  }) = _Member;

  /// The uppercase first letter of [displayName] for the avatar, or '?' when
  /// the name is empty.
  String get initial =>
      displayName.trim().isEmpty ? '?' : displayName.trim()[0].toUpperCase();
}

/// The portion factors the household can be set to from the segment (P-D2):
/// the five quick picks, and *custom* in quarter steps between
/// [kPortionFactorMin] and [kPortionFactorMax].
const kPortionFactorPicks = [0.5, 0.75, 1.0, 1.25, 1.5];
const kPortionFactorMin = 0.25;
const kPortionFactorMax = 3.0;
const kPortionFactorStep = 0.25;

/// Whether [factor] is one the column accepts: a quarter step within
/// [kPortionFactorMin]..[kPortionFactorMax] (the `0026` check constraint,
/// mirrored so the sheet never offers a value the server would refuse).
bool isValidPortionFactor(double factor) {
  if (factor < kPortionFactorMin - 1e-9 || factor > kPortionFactorMax + 1e-9) {
    return false;
  }
  final steps = factor / kPortionFactorStep;
  return (steps - steps.roundToDouble()).abs() < 1e-9;
}

/// Σ [Member.portionFactor] over [eaterIds] — what the eaters on a meal
/// usually eat, in portions. An eater the roster no longer holds (a
/// tombstoned member) counts as one portion, exactly as the head-count did.
double eatersDemand(
  Iterable<String> eaterIds,
  Map<String, Member> membersById,
) => eaterIds.fold(0, (sum, id) => sum + (membersById[id]?.portionFactor ?? 1));

/// An entry's demand in portions (P-D1): the whole-number [PlanEntry.portions]
/// override when one is set, else [eatersDemand] over its eaters. Fractional
/// by design — `1¾` for a 1 and a ¾ eater — and printed as a fraction, never
/// rounded (P-D4). With every factor at 1 this is [PlanEntry.portionsOrDefault]
/// to the digit (P-D6).
double demandPortions(PlanEntry entry, Map<String, Member> membersById) =>
    entry.portions?.toDouble() ?? eatersDemand(entry.eaterIds, membersById);

/// What a planned meal IS — the one question every derivation asks about an
/// entry, asked once and answered exhaustively.
///
/// It exists so that a null `recipe_id` can never again be read as "skip": a
/// `switch` over this enum is checked for exhaustiveness by the compiler, so a
/// fourth kind cannot be added without every derivation being told to say what
/// it does with it. The server's three-way `plan_entry_target_xor` is the same
/// promise one layer down.
enum PlanEntryKind {
  /// A dish from the Library. Its amount is its portions; it is cooked, it is
  /// bought, and its macros come from its own lines.
  recipe,

  /// Something you simply *eat* — a protein bar, a yoghurt — planned as itself
  /// rather than dressed up as a one-line recipe. Nothing is cooked; it is
  /// bought, and it is weighed from its vocabulary row.
  ingredient,

  /// A meal eaten out: the words, and the figures the canteen printed when it
  /// printed any. Nothing is cooked and nothing is bought — it fills its slot,
  /// and the week counts it only from macros somebody stated.
  out,
}

/// One planned meal on [dayOfWeek] (an offset from the week's first day, 0..6)
/// under a free-text [mealSlot], eaten by [eaterIds].
///
/// **A meal is a recipe, a bare ingredient, or a meal eaten out** — exactly
/// one of the three, never two and never none (the server's
/// `plan_entry_target_xor` makes it total, the same shape a recipe line's
/// ingredient/sub-recipe XOR has worn since 0017).
///
/// Which target it is — its [kind] — decides which columns speak:
///
/// * a **recipe** meal names [recipeId] ([recipeTitle] denormalised for
///   display, null when the recipe was deleted) and carries no amount of its
///   own — its amount is its [portions] / eaters;
/// * an **ingredient** meal names [ingredientId] ([ingredientName]
///   denormalised, null when the vocab row is gone or has not synced) and
///   states the amount of ONE portion of it in [quantity] + [unit], or in a
///   named [measure] ("1 bar");
/// * a meal **eaten out** names [label] — its own words, which are the whole
///   of it — and optionally the per-portion [macros] that were stated.
///
/// It carries eaters and multiplies whichever it is (A-D3, owner-ruled):
/// multiple people can have the same snack or the same canteen lunch, so
/// [demandPortions] is unchanged and each is an ordinary entry with a
/// different target.
///
/// Branch on [kind] rather than testing [recipeId] for null by hand: a null
/// recipe must never be read as "skip", and a `switch` that names all three
/// cases is how the compiler holds that.
@freezed
abstract class PlanEntry with _$PlanEntry {
  const PlanEntry._();

  const factory PlanEntry({
    required String id,
    required int dayOfWeek,
    required String mealSlot,

    /// The dish, when this meal is one. Null exactly when one of
    /// [ingredientId] / [label] is set (the XOR).
    String? recipeId,
    String? recipeTitle,

    /// The thing this meal IS, when it is a bare ingredient. Null exactly when
    /// one of [recipeId] / [label] is set.
    String? ingredientId,
    String? ingredientName,

    /// The words a meal eaten out IS — "Office lunch". Null exactly when one
    /// of [recipeId] / [ingredientId] is set. There is nothing behind these
    /// words: no recipe, no vocabulary row, nothing to open.
    String? label,

    /// What ONE portion of a meal eaten out was worth, as STATED. Null means
    /// not stated — never zero (invariant 3): the week names such a meal as
    /// uncounted rather than weighing it at nothing. Always null on the other
    /// two kinds, whose figures come from their recipe's lines or their
    /// vocabulary row.
    Macros? macros,

    /// The amount of ONE portion of an ingredient meal. Null (with [unit]) on
    /// a meal that states no amount — which contributes nothing to a total and
    /// says so, rather than being completed by a guess (invariant 3). Always
    /// null on a recipe meal and on a meal eaten out.
    double? quantity,
    Unit? unit,

    /// The persisted `measure_id`, verbatim — kept even while [measure] is
    /// unresolved (the row has not synced, or was soft-deleted) so a re-save
    /// never wipes the FK, exactly as a recipe line's does.
    String? measureId,

    /// The resolved named measure the amount is counted in ("1 bar"), when it
    /// is. [unit] then holds the honest count fallback (`piece`).
    Measure? measure,

    /// The vocab row's macros / basis / density, denormalised for the same
    /// reason [recipeTitle] is: the week's macro sum is a pure function of the
    /// week it already loaded, and reading it a second way — a whole-vocabulary
    /// watch behind the Week screen — would be a second place to drift.
    ///
    /// Null on a recipe meal, and null on an ingredient meal whose row has not
    /// synced; `ingredientPortionMacros` (week_macros.dart) tells that apart
    /// from a row that is present but a stub, and names each.
    IngredientNutrition? nutrition,
    @Default(<String>[]) List<String> eaterIds,

    /// How many portions to cook for. Null means "track the eater count"; a
    /// number is an explicit override for big/small appetites (spec §8).
    int? portions,
  }) = _PlanEntry;

  /// What this meal IS — the one question every derivation asks, asked in one
  /// place and answered from the columns the XOR fills.
  ///
  /// The label is read first because it is the only one of the three that
  /// needs no second row to exist: a meal eaten out is its words.
  PlanEntryKind get kind => label != null
      ? PlanEntryKind.out
      : ingredientId != null
      ? PlanEntryKind.ingredient
      : PlanEntryKind.recipe;

  /// The name this meal shows, or null when the row it names is gone — a
  /// deleted recipe, or a vocab row this device cannot see. Null is a real
  /// answer for either of those: the surfaces print their own words for it.
  /// A meal eaten out is never nameless, because its name is the whole of it.
  String? get title => switch (kind) {
    PlanEntryKind.recipe => recipeTitle,
    PlanEntryKind.ingredient => ingredientName,
    PlanEntryKind.out => label,
  };

  /// The entry's own portion count before the household's factors: the
  /// [portions] override, or the eater HEAD-count. The demand a plan cooks
  /// for is [demandPortions], which weighs each eater by their
  /// [Member.portionFactor]; this is the factor-less figure the override
  /// stepper counts in.
  int get portionsOrDefault => portions ?? eaterIds.length;
}

/// The standing words for a meal whose target is GONE — a deleted recipe, or a
/// vocab row this device cannot see. One sentence per kind, in one place,
/// because a deleted recipe and a deleted ingredient are different sentences
/// and every surface must say the same one.
///
/// A meal eaten out cannot reach here: its words are its target, so it has
/// nothing to lose. It keeps its own label, and the fallback names the case
/// rather than pretending it cannot happen.
String deletedTargetLabel(PlanEntry entry) => switch (entry.kind) {
  PlanEntryKind.recipe => '(deleted recipe)',
  PlanEntryKind.ingredient => '(deleted ingredient)',
  PlanEntryKind.out => '(that meal)',
};

/// One active week, addressed by [weekStart] — the date of its own first day,
/// date-only. [entries] are every meal planned across the week; the view
/// groups them by day.
@freezed
abstract class WeekPlan with _$WeekPlan {
  const WeekPlan._();

  const factory WeekPlan({
    required String id,
    required DateTime weekStart,
    String? label,
    @Default(<PlanEntry>[]) List<PlanEntry> entries,
  }) = _WeekPlan;

  /// The entries on [dayOfWeek] (0..6 from the week's first day), ordered by
  /// meal slot then their stored order — one day column of the grid.
  /// [entries] is assumed to already carry the repository's within-slot order
  /// (sort_order, created_at);
  /// this decorates with the source index for a stable sort, since Dart's
  /// [List.sort] is not guaranteed stable.
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

/// The meal slots the UI offers by default, in the order a day eats them.
/// Users may type any other label (spec §8) — these are only the quick picks
/// and the canonical display order.
const kDefaultMealSlots = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];

/// The slot a meal added to a day starts on: the first of [kDefaultMealSlots],
/// in day order, that none of [dayEntries] already fills — an empty day starts
/// at Breakfast, a day with a breakfast on it at Lunch, and a day holding only
/// a dinner still at Breakfast, because that is the next meal nobody has
/// planned. Dinner once all four are filled. Case-insensitive, so a typed
/// `dinner` fills Dinner; a custom slot such as Brunch fills none of them.
String defaultMealSlot(Iterable<PlanEntry> dayEntries) {
  final taken = {for (final e in dayEntries) e.mealSlot.trim().toLowerCase()};
  return kDefaultMealSlots.firstWhere(
    (s) => !taken.contains(s.toLowerCase()),
    orElse: () => 'Dinner',
  );
}

/// Orders a meal slot within a day: the known slots first, in meal order, then
/// any custom slot (rank = [kDefaultMealSlots].length) alphabetically-stable by
/// insertion. Case-insensitive so "dinner" and "Dinner" rank together.
int mealSlotRank(String slot) {
  final i = kDefaultMealSlots.indexWhere(
    (s) => s.toLowerCase() == slot.toLowerCase(),
  );
  return i < 0 ? kDefaultMealSlots.length : i;
}

/// One recipe whose this-week changes a copy did NOT carry, and how many.
///
/// "Just this week" is the whole promise, so carrying a variant forward would
/// turn it into a recipe edit made by accretion. A silent drop is the same bug
/// as a silent carry, pointing the other way — so the copy names what it left.
typedef VariantLeftBehind = ({String recipeTitle, int changes});

/// What a copy of last week carried, and what it could not.
typedef CopyLastWeekResult = ({
  int meals,
  List<VariantLeftBehind> variantsLeftBehind,
});
