/// The cook plan: a derived view of one week's meals, never persisted. Pure
/// Dart.
///
/// [buildCookPlan] groups meals by recipe. A recipe's meals not yet in a
/// cooking (`plan_entry.cooking`) are split by [clusterSessions] into
/// [CookSession]s bounded by its shelf life, within the week alone; a cooking
/// bought this week (its earliest linked meal is here) is one session of its
/// own, whatever weeks its other meals fall in. Days are offsets from the
/// week's own first day, so a cooking's later meal can read 7 or more. A
/// recipe's component lines derive batch-denominated sessions of their own,
/// read through the `effectiveLines` seam for the week
/// ([componentGraphForWeek]); an unresolvable component is a [ComponentGap],
/// never an assumed `1×`.
library;

// Freezed needs each class's private `._` constructor before the factory (for
// the custom getters), which trips the unnamed-first sort lint.
// ignore_for_file: sort_unnamed_constructors_first
import 'dart:math' show max, min;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import '../../planning/domain/planning.dart' show mealSlotRank;
import '../../recipes/domain/component_math.dart';
import '../../recipes/domain/effective_lines.dart';
import '../../recipes/domain/line_override.dart';
import '../../recipes/domain/recipe.dart';

part 'cook_plan.freezed.dart';

/// The fridge life a recipe with none stated is taken to have: for its dates,
/// and for grouping its meals into one cooking.
const kAssumedFridgeDays = 7;

/// One planned appearance of a recipe: its [dayOfWeek] (an offset from the
/// week's first day, 0..6 for a meal of the week, beyond it for a cooking's
/// meal in another week), [mealSlot] and the [portions] it demands. Portions
/// are fractional and never rounded here.
@freezed
abstract class CoveredMeal with _$CoveredMeal {
  const factory CoveredMeal({
    required int dayOfWeek,
    required String mealSlot,
    required double portions,

    /// The planned meal this is, where it came from one.
    String? entryId,

    /// The shares of its eaters who said they ate it — the rest is left
    /// over. Never more than [portions].
    @Default(0.0) double eatenPortions,
  }) = _CoveredMeal;
}

/// A cooking bought in the week: its [id], what it [made] (null while it is
/// still the live sum of its meals), whether its cook chose the
/// [wholeBatch], and every live meal linked to it (and, while it is not
/// cooked, every meal of the week that joins it), counted from the week's
/// first day.
@freezed
abstract class PlannedCooking with _$PlannedCooking {
  const factory PlannedCooking({
    required String id,
    double? made,
    @Default(false) bool wholeBatch,
    @Default(<CoveredMeal>[]) List<CoveredMeal> meals,
  }) = _PlannedCooking;
}

/// A recipe as it appears in the week, before clustering: its shelf life,
/// the [meals] not yet in a cooking, and the [cookings] bought this week.
@freezed
abstract class PlannedRecipe with _$PlannedRecipe {
  const factory PlannedRecipe({
    required String recipeId,
    required String title,
    required double servingsBase,

    /// Fridge shelf life in days; drives clustering. Null = unknown, taken to
    /// be [kAssumedFridgeDays].
    int? keepsForDays,
    @Default(false) bool freezable,

    /// Freezer shelf life in days (only when [freezable]). Null = no limit.
    int? freezerDays,

    /// The week's meals of it not yet in a cooking.
    @Default(<CoveredMeal>[]) List<CoveredMeal> meals,

    /// The cookings of it bought this week.
    @Default(<PlannedCooking>[]) List<PlannedCooking> cookings,
  }) = _PlannedRecipe;
}

/// One parent cook session's demand on a sub-recipe: the [batches] it needs and
/// who needs them.
///
/// [parentRecipeId] / [parentTitle] name the planned recipe at the top of the
/// walk; [via] names the intermediate recipe, null at depth one.
@freezed
abstract class ComponentDemand with _$ComponentDemand {
  const ComponentDemand._();

  const factory ComponentDemand({
    required String parentRecipeId,
    required String parentTitle,

    /// The demanding parent session's cook day (0..6 from the week's first
    /// day): the day this batch must be ready by.
    required int cookDay,

    /// Batches of the sub-recipe, already multiplied through the parent
    /// session's own scale factor.
    required double batches,
    String? via,

    /// What the demanding line printed, unscaled.
    double? quantity,

    /// The target's own word the demanding line was said in, whole so a card
    /// can print what one of it comes to. Null when the line named no word or
    /// the target no longer has it.
    RecipeMeasure? measure,
  }) = _ComponentDemand;

  /// The word alone, for the readers that only quote the line back.
  String? get measureLabel => measure?.label;
}

/// A derived cook session: one batch to cook on [cookDay].
///
/// A meal session covers planned meals and scales in portions
/// ([totalPortions]); a component session answers other recipes' component
/// lines and scales in batches ([batchesToCook]). The two are never merged,
/// even for one recipe on one day, because their denominations cannot be
/// summed.
@freezed
abstract class CookSession with _$CookSession {
  const CookSession._();

  const factory CookSession({
    required String recipeId,
    required String recipeTitle,
    required double servingsBase,
    required int cookDay,
    int? keepsForDays,
    @Default(false) bool freezable,
    int? freezerDays,

    /// The meals this batch covers, ascending by day (may include repeats on a
    /// day — e.g. a lunch and a dinner of the same dish).
    @Default(<CoveredMeal>[]) List<CoveredMeal> covers,

    /// The component demands this batch answers. Non-empty exactly
    /// for a component session.
    @Default(<ComponentDemand>[]) List<ComponentDemand> demands,

    /// The cooking this batch is (`cooking.id`); null for meals not yet in
    /// one, grouped by shelf life.
    String? cookingId,

    /// What the cooking made, fixed at its first tick; null while it is the
    /// live sum of [covers].
    double? made,

    /// Whether the cook chose the whole batch: [totalPortions] rounds up to
    /// whole batches, and the spare is made, bought and left over.
    @Default(false) bool wholeBatch,
  }) = _CookSession;

  /// Whether this session feeds another recipe's component line rather than a
  /// planned meal.
  bool get isComponent => demands.isNotEmpty;

  /// Batches to cook, or null for a meal session. The sum of every demand this
  /// session answers.
  double? get batchesToCook =>
      isComponent ? demands.fold<double>(0, (s, d) => s + d.batches) : null;

  /// The distinct titles of the recipes demanding this component batch, in
  /// first-seen order.
  List<String> get demandedBy {
    final seen = <String>{};
    return [
      for (final d in demands)
        if (seen.add(d.parentTitle)) d.parentTitle,
    ];
  }

  /// The meals of a later week this cooking covers (day 7 or more).
  List<CoveredMeal> get laterWeekCovers => [
    for (final m in covers)
      if (m.dayOfWeek > 6) m,
  ];

  /// Distinct days this batch is used, ascending — covered meal days for a
  /// meal session, demanding parents' cook days for a component one.
  List<int> get coveredDays {
    final set = {
      for (final m in covers) m.dayOfWeek,
      for (final d in demands) d.cookDay,
    };
    return set.toList()..sort();
  }

  /// The last day this batch is eaten.
  int get lastCoveredDay => coveredDays.isEmpty ? cookDay : coveredDays.last;

  /// The portions planned for: what the cooking [made], else the sum of
  /// every covered meal's demand, possibly fractional. Zero on a component
  /// session.
  double get plannedPortions =>
      made ?? covers.fold(0, (s, m) => s + m.portions);

  /// Portions to cook: [plannedPortions], rounded up to whole batches when
  /// the cook chose the [wholeBatch].
  double get totalPortions {
    final planned = plannedPortions;
    if (!wholeBatch || servingsBase <= 0 || planned <= 0) return planned;
    return (planned / servingsBase - 1e-9).ceil() * servingsBase;
  }

  /// The portions of this week's own meals (days 0..6): what the week plans
  /// of it, whatever another week eats from the pot.
  double get portionsThisWeek => covers.fold(
    0,
    (s, m) => m.dayOfWeek >= 0 && m.dayOfWeek <= 6 ? s + m.portions : s,
  );

  /// The portions its eaters said they ate.
  double get eatenPortions => covers.fold(0, (s, m) => s + m.eatenPortions);

  /// The planned portions nobody said they ate: bought for, so left over.
  double get uneatenPortions {
    final left = totalPortions - eatenPortions;
    return left > 1e-9 ? left : 0;
  }

  /// The multiplier the recipe's lines scale by: `total_portions /
  /// servings_base` for a meal session (whole when the cook chose the
  /// [wholeBatch]); the batch count for a component session.
  double get scaleFactor {
    final batches = batchesToCook;
    if (batches != null) return batches;
    return servingsBase == 0 ? 0 : totalPortions / servingsBase;
  }

  /// The exact multiplier for what is planned, never rounded to a whole
  /// batch: the exact side of the switch.
  double get exactScaleFactor {
    final batches = batchesToCook;
    if (batches != null) return batches;
    return servingsBase == 0 ? 0 : plannedPortions / servingsBase;
  }

  /// Covered days past the fridge window, served from the freezer. Only
  /// meaningful for a [freezable] recipe.
  List<int> get frozenDays {
    final keeps = keepsForDays ?? kAssumedFridgeDays;
    if (!freezable) return const [];
    return [
      for (final d in coveredDays)
        if (d - cookDay > keeps) d,
    ];
  }

  /// True when this batch relies on freezing to reach a later meal.
  bool get hasFreezerRescue => frozenDays.isNotEmpty;
}

/// Every cook session for one recipe, plus recipe-level rollups the card shows.
@freezed
abstract class RecipeCookPlan with _$RecipeCookPlan {
  const RecipeCookPlan._();

  const factory RecipeCookPlan({
    required String recipeId,
    required String title,
    required double servingsBase,
    int? keepsForDays,
    @Default(false) bool freezable,
    int? freezerDays,
    @Default(<CookSession>[]) List<CookSession> sessions,
  }) = _RecipeCookPlan;

  /// The sessions cooked for planned meals (portion-denominated).
  List<CookSession> get mealSessions => [
    for (final s in sessions)
      if (!s.isComponent) s,
  ];

  /// The sessions cooked because another recipe lists this one as a component
  /// (batch-denominated).
  List<CookSession> get componentSessions => [
    for (final s in sessions)
      if (s.isComponent) s,
  ];

  /// Total portions of this recipe cooked across the week (all sessions).
  /// Component sessions contribute nothing — they are counted in batches.
  double get totalPortions => sessions.fold(0, (s, x) => s + x.totalPortions);

  /// The portions the week's own meals of this recipe plan (days 0..6): a
  /// cooking's later-week meals and what it made beyond the plan are not
  /// counted twice.
  double get portionsThisWeek =>
      sessions.fold(0, (s, x) => s + x.portionsThisWeek);

  /// Distinct days this recipe is eaten across the week, ascending.
  List<int> get days {
    final set = {for (final s in sessions) ...s.coveredDays};
    return set.toList()..sort();
  }

  /// The earliest cook day — the plan's sort key.
  int get firstCookDay =>
      sessions.isEmpty ? 0 : sessions.map((s) => s.cookDay).reduce(min);

  /// The earliest slot it is eaten in on [firstCookDay] ([mealSlotRank]):
  /// within one day, lunch reads before dinner.
  int get firstCookSlot {
    final day = firstCookDay;
    final ranks = [
      for (final s in sessions)
        for (final m in s.covers)
          if (m.dayOfWeek == day) mealSlotRank(m.mealSlot),
    ];
    return ranks.isEmpty ? 0 : ranks.reduce(min);
  }

  /// Split into more than one batch because a later meal outran the fridge
  /// window (and the freezer couldn't rescue it).
  bool get isSplit => sessions.length > 1;

  /// Any session leans on the freezer.
  bool get usesFreezer => sessions.any((s) => s.hasFreezerRescue);
}

/// Who demanded a component the plan could not derive: the planned recipe at
/// the top of the walk, its cook day, and what its line printed.
///
/// [quantity] / [unit] are the demanding line's stored values, not scaled by
/// the parent session; [quantity] is null on a numberless line. When a parent
/// lists the same target more than once, the first line is the one quoted.
///
/// [lineId] is that line, in the recipe that holds it: the planned recipe at
/// depth one, [viaRecipeId] below it. It is where the fix lives.
@freezed
abstract class ComponentDemandSource with _$ComponentDemandSource {
  const ComponentDemandSource._();

  const factory ComponentDemandSource({
    required String recipeId,
    required String title,
    required int cookDay,

    /// The `recipe_line_item` that names the target.
    required String lineId,

    /// The intermediate recipe holding [lineId], and its title. Both null at
    /// depth one, where the planned recipe holds it.
    String? viaRecipeId,
    String? via,

    /// The demanding line's catalog unit, null when it was said in one of the
    /// target's own words ([measureLabel]).
    Unit? unit,
    double? quantity,

    /// The target's own word the demanding line was said in, when the target
    /// still has it. Null when the line named no word or the word has gone.
    String? measureLabel,

    /// Whether the line named a word at all; tells a missing word apart from a
    /// catalog unit when [measureLabel] is null.
    @Default(false) bool saysAMeasure,
  }) = _ComponentDemandSource;

  /// The recipe whose line names the target: where that line is fixed.
  String get lineRecipeId => viaRecipeId ?? recipeId;

  /// [lineRecipeId]'s title.
  String get lineRecipeTitle => via ?? title;
}

/// A component the plan could not derive a session for. [reason] says why (no
/// yield, family mismatch, no amount, a cycle) and [demandedBy] says whose plan
/// is short.
@freezed
abstract class ComponentGap with _$ComponentGap {
  const factory ComponentGap({
    /// The sub-recipe that cannot be derived.
    required String recipeId,
    required String title,
    required UnresolvedComponentAmount reason,
    @Default(<ComponentDemandSource>[]) List<ComponentDemandSource> demandedBy,
  }) = _ComponentGap;
}

/// The whole derived cook plan: one [RecipeCookPlan] per recipe, ordered by
/// earliest cook day then title, plus the component [gaps].
@freezed
abstract class CookPlan with _$CookPlan {
  const CookPlan._();

  const factory CookPlan({
    @Default(<RecipeCookPlan>[]) List<RecipeCookPlan> recipes,
    @Default(<ComponentGap>[]) List<ComponentGap> gaps,

    /// This week's meals of a cooking bought in an earlier week, by entry id,
    /// each with that cooking's session counted from this week's first day
    /// (so its cook day is below 0). Not cooked, bought or costed here.
    @Default(<String, CookSession>{}) Map<String, CookSession> eatenFromEarlier,
  }) = _CookPlan;

  bool get isEmpty => recipes.isEmpty && gaps.isEmpty;

  /// The cookings bought this week, each with the portions it is bought for
  /// and the meals it covers, by entry id.
  List<({String recipeId, double portions, Set<String> entryIds})>
  get cookings => [
    for (final r in recipes)
      for (final s in r.mealSessions)
        if (s.cookingId != null)
          (
            recipeId: r.recipeId,
            portions: s.totalPortions,
            entryIds: {
              for (final m in s.covers)
                if (m.entryId case final id?) id,
            },
          ),
  ];

  /// How many components each planned recipe is short by, keyed by its id.
  Map<String, int> get unresolvedComponentsByParent {
    final counts = <String, int>{};
    for (final gap in gaps) {
      for (final source in gap.demandedBy) {
        counts.update(source.recipeId, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    return counts;
  }
}

/// Greedy shelf-life clustering for one recipe's meals not yet in a cooking,
/// within one week: a meal joins the current session while it is within
/// [PlannedRecipe.keepsForDays] ([kAssumedFridgeDays] when unknown), or as a
/// frozen share when the recipe is [PlannedRecipe.freezable] and within
/// [PlannedRecipe.freezerDays] (null = no limit); otherwise it opens a new
/// session. A negative shelf life is clamped to 0.
///
/// Each of [PlannedRecipe.cookings] follows as one session of its own, never
/// split or merged: what a cooking holds was fixed when it was born.
List<CookSession> clusterSessions(PlannedRecipe recipe) {
  final keeps = _clampWindow(recipe.keepsForDays);
  final freezerDays = _clampWindow(recipe.freezerDays);
  CookSession session(
    List<CoveredMeal> covers, {
    String? cookingId,
    double? made,
    bool wholeBatch = false,
  }) => CookSession(
    recipeId: recipe.recipeId,
    recipeTitle: recipe.title,
    servingsBase: recipe.servingsBase,
    cookDay: covers.first.dayOfWeek,
    keepsForDays: keeps,
    freezable: recipe.freezable,
    freezerDays: freezerDays,
    covers: List.unmodifiable(covers),
    cookingId: cookingId,
    made: made,
    wholeBatch: wholeBatch,
  );
  final sessions = [
    for (final cluster in _clusterByDay<CoveredMeal>(
      recipe.meals,
      dayOf: (m) => m.dayOfWeek,
      keepsForDays: keeps ?? kAssumedFridgeDays,
      freezable: recipe.freezable,
      freezerDays: freezerDays,
    ))
      session(cluster),
    for (final cooking in recipe.cookings)
      if (cooking.meals.isNotEmpty)
        session(
          [...cooking.meals]
            ..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek)),
          cookingId: cooking.id,
          made: cooking.made,
          wholeBatch: cooking.wholeBatch,
        ),
  ];
  // In day order, so a cooking cooked Sunday reads before a cook on
  // Wednesday, whichever kind each is; a tie keeps the order above.
  final order = [for (var i = 0; i < sessions.length; i++) i]
    ..sort((a, b) {
      final d = sessions[a].cookDay.compareTo(sessions[b].cookDay);
      return d != 0 ? d : a.compareTo(b);
    });
  return [for (final i in order) sessions[i]];
}

/// [clusterSessions] over the component demands on one sub-recipe: each cluster
/// is one batch-denominated session on its earliest demanding parent's cook
/// day, bounded by the sub-recipe's own shelf life.
List<CookSession> clusterComponentSessions({
  required String recipeId,
  required String title,
  required double servingsBase,
  required List<ComponentDemand> demands,
  int? keepsForDays,
  bool freezable = false,
  int? freezerDays,
}) {
  final keeps = _clampWindow(keepsForDays);
  final freezer = _clampWindow(freezerDays);
  return [
    for (final cluster in _clusterByDay<ComponentDemand>(
      demands,
      dayOf: (d) => d.cookDay,
      keepsForDays: keeps,
      freezable: freezable,
      freezerDays: freezer,
    ))
      CookSession(
        recipeId: recipeId,
        recipeTitle: title,
        servingsBase: servingsBase,
        // On or before the earliest demanding parent's cook day.
        cookDay: cluster.first.cookDay,
        keepsForDays: keeps,
        freezable: freezable,
        freezerDays: freezer,
        demands: List.unmodifiable(cluster),
      ),
  ];
}

/// A negative shelf-life window (bad data) clamped to 0 — "eat the day you
/// cook". Trusting it would split even same-day meals into separate cooks.
int? _clampWindow(int? days) => days == null ? null : max(0, days);

/// The greedy walk both clusterings share. An unknown [keepsForDays] yields one
/// cluster covering everything: a component batch of a recipe with no shelf
/// life is never split.
List<List<T>> _clusterByDay<T>(
  List<T> items, {
  required int Function(T) dayOf,
  required int? keepsForDays,
  required bool freezable,
  required int? freezerDays,
}) {
  if (items.isEmpty) return const [];
  // Stable ascending sort by day so same-day items keep their input order.
  final sorted = [...items]..sort((a, b) => dayOf(a).compareTo(dayOf(b)));
  if (keepsForDays == null) return [sorted];

  final clusters = <List<T>>[];
  var start = dayOf(sorted.first);
  var current = <T>[sorted.first];
  for (final item in sorted.skip(1)) {
    final gap = dayOf(item) - start;
    final freezerReaches =
        freezable && (freezerDays == null || gap <= freezerDays);
    if (gap <= keepsForDays || freezerReaches) {
      current.add(item);
    } else {
      clusters.add(current);
      start = dayOf(item);
      current = [item];
    }
  }
  clusters.add(current);
  return clusters;
}

/// The whole-batch nudge for a fractional session: round the raw factor up to
/// `factor` whole batches, yielding `batchPortions` portions with
/// `leftoverPortions` to spare.
typedef WholeBatchNudge = ({
  int factor,
  double batchPortions,
  double leftoverPortions,
});

/// The nudge for [session], or null when the factor is already whole, the
/// session is a component one, or its inputs are degenerate. Read off what is
/// planned ([CookSession.exactScaleFactor]), so it stands while the whole
/// batch is chosen ([CookSession.wholeBatch]), which the shop and the
/// leftovers then follow.
WholeBatchNudge? wholeBatchNudgeFor(CookSession session) {
  if (session.isComponent) return null;
  final raw = session.exactScaleFactor;
  if (session.servingsBase <= 0 || raw <= 0) return null;
  if ((raw - raw.round()).abs() < 1e-9) return null; // already whole
  final factor = raw.ceil();
  final batchPortions = factor * session.servingsBase;
  return (
    factor: factor,
    batchPortions: batchPortions,
    leftoverPortions: batchPortions - session.plannedPortions,
  );
}

/// The batch a meal being added would join. `withDay` is the day of the shared
/// batch; `frozen` is true when the new meal is reached from the freezer.
typedef BatchHint = ({int withDay, bool frozen});

/// The batch a meal on [newDay] would share with meals already on
/// [plannedDays], or null when it would be its own cook. Runs the real
/// [clusterSessions] (through [batchSessionFor]) so the hint cannot disagree
/// with the cook plan.
BatchHint? batchHintFor({
  required List<int> plannedDays,
  required int newDay,
  int? keepsForDays,
  bool freezable = false,
  int? freezerDays,
}) {
  final session = batchSessionFor(
    plannedDays: plannedDays,
    newDay: newDay,
    keepsForDays: keepsForDays,
    freezable: freezable,
    freezerDays: freezerDays,
  );
  if (session == null) return null;
  final others = session.coveredDays.where((d) => d != newDay).toList();
  if (others.isEmpty) {
    // `coveredDays` is distinct, so a second meal on an already-planned day
    // shows no other day; more than one covered meal means same batch, same
    // day.
    return session.covers.length > 1
        ? (withDay: session.cookDay, frozen: false)
        : null;
  }
  final withDay = others.contains(session.cookDay)
      ? session.cookDay
      : others.first;
  return (withDay: withDay, frozen: session.frozenDays.contains(newDay));
}

/// The session a meal on [newDay] would be cooked in, once added beside the
/// meals already on [plannedDays] (one covered meal per entry, so a day
/// planned twice is two). Null when nothing is planned yet, since there is no
/// batch to join. Clustered by the real [clusterSessions].
CookSession? batchSessionFor({
  required List<int> plannedDays,
  required int newDay,
  int? keepsForDays,
  bool freezable = false,
  int? freezerDays,
}) {
  if (plannedDays.isEmpty) return null;
  final recipe = PlannedRecipe(
    recipeId: 'hint',
    title: '',
    servingsBase: 1,
    keepsForDays: keepsForDays,
    freezable: freezable,
    freezerDays: freezerDays,
    meals: [
      for (final d in [...plannedDays, newDay])
        CoveredMeal(dayOfWeek: d, mealSlot: 'x', portions: 1),
    ],
  );
  for (final session in clusterSessions(recipe)) {
    if (session.coveredDays.contains(newDay)) return session;
  }
  return null;
}

/// One component line of a recipe, as the expansion needs it. `quantity` is
/// null on a numberless line. `id` is the `recipe_line_item` id a week's
/// override names; `optional` is the recipe's own flag.
typedef ComponentLine = ({
  String id,
  String subRecipeId,
  double? quantity,

  /// The catalog unit, or null when the line is said in one of the target's own
  /// words; exactly one of this and `recipeMeasureId` is set.
  Unit? unit,

  /// The target recipe's own word this line is said in, or null. Carried
  /// through the seam so a demand card can print `3 blob`.
  String? recipeMeasureId,
  bool optional,
});

/// A recipe as the component walk sees it: shelf life, yields and component
/// lines.
///
/// The repository supplies one per live recipe in the household. A sub-recipe
/// id the map does not hold is a dangling link: nothing is derived and no gap
/// is raised.
typedef ComponentRecipe = ({
  String title,
  double servingsBase,
  int? keepsForDays,
  bool freezable,
  int? freezerDays,
  List<YieldDenomination> yields,

  /// This recipe's own live words. A PARENT's line saying one of them
  /// resolves through it; a word this list has not got is a named gap.
  List<RecipeMeasure> measures,
  List<ComponentLine> components,
});

/// One recipe's component lines as one week cooks them, through the
/// [effectiveLines] seam. Each line carries the sub-recipe's title from [graph]
/// so a dropped component can be named.
EffectiveLines componentLinesForWeek(
  Map<String, ComponentRecipe> graph,
  String recipeId, {
  List<LineOverride> overrides = const [],
}) => effectiveLines([
  for (final line in graph[recipeId]?.components ?? const <ComponentLine>[])
    LineItem(
      id: line.id,
      ingredientName: graph[line.subRecipeId]?.title ?? '',
      unit: line.unit,
      subRecipeId: line.subRecipeId,
      // The whole target, yields and words: a line's amount resolves against
      // both.
      subRecipe: switch (graph[line.subRecipeId]) {
        final target? => SubRecipeTarget(
          id: line.subRecipeId,
          title: target.title,
          yieldQty: target.yields.firstOrNull?.qty,
          yieldUnit: target.yields.firstOrNull?.unit,
          yieldQty2: target.yields.elementAtOrNull(1)?.qty,
          yieldUnit2: target.yields.elementAtOrNull(1)?.unit,
          measures: target.measures,
        ),
        _ => null,
      },
      quantity: line.quantity,
      recipeMeasureId: line.recipeMeasureId,
      optional: line.optional,
    ),
], overrides: overrides);

/// The household's component [graph] as one week cooks it: every recipe's lines
/// through [componentLinesForWeek] with [overridesByRecipe].
///
/// Runs over the whole graph, because a sub-recipe can itself carry an optional
/// component. Only lines that still name a sub-recipe survive.
Map<String, ComponentRecipe> componentGraphForWeek(
  Map<String, ComponentRecipe> graph,
  Map<String, List<LineOverride>> overridesByRecipe,
) => {
  for (final entry in graph.entries)
    entry.key: (
      title: entry.value.title,
      servingsBase: entry.value.servingsBase,
      keepsForDays: entry.value.keepsForDays,
      freezable: entry.value.freezable,
      freezerDays: entry.value.freezerDays,
      yields: entry.value.yields,
      measures: entry.value.measures,
      components: [
        for (final line in componentLinesForWeek(
          graph,
          entry.key,
          overrides: overridesByRecipe[entry.key] ?? const [],
        ).kept)
          if (line.subRecipeId case final subRecipeId?)
            (
              id: line.id,
              subRecipeId: subRecipeId,
              quantity: line.quantity,
              unit: line.unit,
              recipeMeasureId: line.recipeMeasureId,
              optional: false,
            ),
      ],
    ),
};

/// Builds the derived cook plan from the week's [recipes], ordered by earliest
/// cook day then title. [components] is the household's component graph; empty
/// derives meal sessions only.
///
/// [eatenFromEarlier] is this week's meals of cookings bought in an earlier
/// week, carried onto the plan for the readers that pass over them.
CookPlan buildCookPlan(
  List<PlannedRecipe> recipes, {
  Map<String, ComponentRecipe> components = const {},
  Map<String, CookSession> eatenFromEarlier = const {},
}) {
  final plans = <RecipeCookPlan>[];
  for (final r in recipes) {
    final sessions = clusterSessions(r);
    if (sessions.isEmpty) continue;
    plans.add(
      RecipeCookPlan(
        recipeId: r.recipeId,
        title: r.title,
        servingsBase: r.servingsBase,
        keepsForDays: r.keepsForDays,
        freezable: r.freezable,
        freezerDays: r.freezerDays,
        sessions: sessions,
      ),
    );
  }

  final (demands, gaps) = expandComponentDemands(plans, components);
  for (final entry in demands.entries) {
    final recipe = components[entry.key];
    if (recipe == null) continue;
    final sessions = clusterComponentSessions(
      recipeId: entry.key,
      title: recipe.title,
      servingsBase: recipe.servingsBase,
      keepsForDays: recipe.keepsForDays,
      freezable: recipe.freezable,
      freezerDays: recipe.freezerDays,
      demands: entry.value,
    );
    if (sessions.isEmpty) continue;
    // A sub-recipe that is also on the week keeps one card holding both kinds
    // of session.
    final existing = plans.indexWhere((p) => p.recipeId == entry.key);
    if (existing >= 0) {
      plans[existing] = plans[existing].copyWith(
        sessions: [...plans[existing].sessions, ...sessions],
      );
    } else {
      plans.add(
        RecipeCookPlan(
          recipeId: entry.key,
          title: recipe.title,
          servingsBase: recipe.servingsBase,
          keepsForDays: recipe.keepsForDays,
          freezable: recipe.freezable,
          freezerDays: recipe.freezerDays,
          sessions: sessions,
        ),
      );
    }
  }

  plans.sort((a, b) {
    final c = a.firstCookDay.compareTo(b.firstCookDay);
    if (c != 0) return c;
    final slot = a.firstCookSlot.compareTo(b.firstCookSlot);
    return slot != 0
        ? slot
        : a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return CookPlan(
    recipes: plans,
    gaps: gaps,
    eatenFromEarlier: eatenFromEarlier,
  );
}

/// The planned recipe a walk descends from, fixed for the whole branch.
typedef _PlannedRoot = ({String recipeId, String title, int cookDay});

/// Walks every planned session's component lines depth-first, returning the
/// [ComponentDemand]s per sub-recipe and the [ComponentGap]s.
///
/// A parent demanding `f` batches of a sub-recipe that asks `b` batches of a
/// third demands `f × b` of it. A visited set stops at a cycle (two racing
/// devices can outrun the server trigger) and raises a [ComponentCycle] gap
/// instead of looping.
(Map<String, List<ComponentDemand>>, List<ComponentGap>) expandComponentDemands(
  List<RecipeCookPlan> plans,
  Map<String, ComponentRecipe> components,
) {
  final demands = <String, List<ComponentDemand>>{};
  // Keyed so the same recipe failing the same way for two parents is ONE gap
  // with two demanding sources, not two cards saying the same thing.
  final gaps = <String, ComponentGap>{};

  void walk({
    required String recipeId,
    required double factor,
    required _PlannedRoot root,
    required String? via,
    required Set<String> visited,
  }) {
    final recipe = components[recipeId];
    if (recipe == null) return;
    for (final line in recipe.components) {
      final target = components[line.subRecipeId];
      // A dangling link derives nothing and flags nothing: the line renders
      // the text it stored, with plain-text semantics.
      if (target == null) continue;

      // The word the line says, when the target still has it; null otherwise.
      final said = switch (line.recipeMeasureId) {
        final id? => recipeMeasureById(id, target.measures),
        _ => null,
      };

      void raise(UnresolvedComponentAmount reason) {
        final key = '${line.subRecipeId}/$reason';
        final gap =
            gaps[key] ??
            ComponentGap(
              recipeId: line.subRecipeId,
              title: target.title,
              reason: reason,
            );
        // The source carries the demanding line's printed amount, unscaled.
        gaps[key] = gap.demandedBy.any((s) => s.recipeId == root.recipeId)
            ? gap
            : gap.copyWith(
                demandedBy: [
                  ...gap.demandedBy,
                  ComponentDemandSource(
                    recipeId: root.recipeId,
                    title: root.title,
                    cookDay: root.cookDay,
                    lineId: line.id,
                    // Below depth one, the line is in the recipe being walked.
                    viaRecipeId: via == null ? null : recipeId,
                    via: via,
                    quantity: line.quantity,
                    unit: line.unit,
                    measureLabel: said?.label,
                    saysAMeasure: line.recipeMeasureId != null,
                  ),
                ],
              );
      }

      if (visited.contains(line.subRecipeId)) {
        raise(const ComponentCycle());
        continue;
      }
      final amount = resolveComponentAmount(
        quantity: line.quantity,
        unit: line.unit,
        yields: target.yields,
        recipeMeasureId: line.recipeMeasureId,
        measures: target.measures,
      );
      if (amount is! ResolvedComponentAmount) {
        raise(amount as UnresolvedComponentAmount);
        continue;
      }
      final batches = factor * amount.batches;
      (demands[line.subRecipeId] ??= []).add(
        ComponentDemand(
          parentRecipeId: root.recipeId,
          parentTitle: root.title,
          cookDay: root.cookDay,
          batches: batches,
          via: via,
          quantity: line.quantity,
          measure: said,
        ),
      );
      walk(
        recipeId: line.subRecipeId,
        factor: batches,
        root: root,
        via: target.title,
        visited: {...visited, line.subRecipeId},
      );
    }
  }

  for (final plan in plans) {
    for (final session in plan.mealSessions) {
      walk(
        recipeId: plan.recipeId,
        factor: session.scaleFactor,
        root: (
          recipeId: plan.recipeId,
          title: plan.title,
          cookDay: session.cookDay,
        ),
        via: null,
        visited: {plan.recipeId},
      );
    }
  }
  return (demands, gaps.values.toList());
}
