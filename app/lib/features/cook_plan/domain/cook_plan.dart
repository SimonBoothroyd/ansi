/// The cook plan: a derived view of the week's meals, never persisted. Pure
/// Dart.
///
/// [buildCookPlan] groups meals by recipe and [clusterSessions] splits each
/// recipe into [CookSession]s bounded by its shelf life, folding freezable
/// shares into one cook. Days are offsets 0..6 from the week's own first day. A
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
import '../../recipes/domain/component_math.dart';
import '../../recipes/domain/effective_lines.dart';
import '../../recipes/domain/line_override.dart';
import '../../recipes/domain/recipe.dart';

part 'cook_plan.freezed.dart';

/// One planned appearance of a recipe in the week: its [dayOfWeek] (0..6 from
/// the week's first day), [mealSlot] and the [portions] it demands. Portions
/// are fractional and never rounded here.
@freezed
abstract class CoveredMeal with _$CoveredMeal {
  const factory CoveredMeal({
    required int dayOfWeek,
    required String mealSlot,
    required double portions,
  }) = _CoveredMeal;
}

/// A recipe as it appears across the week, before clustering: its shelf life
/// and every [meals] entry that calls for it. The clustering input.
@freezed
abstract class PlannedRecipe with _$PlannedRecipe {
  const factory PlannedRecipe({
    required String recipeId,
    required String title,
    required double servingsBase,

    /// Fridge shelf life in days; drives clustering. Null = unknown (the recipe
    /// has no shelf-life set yet) → the recipe is never split.
    int? keepsForDays,
    @Default(false) bool freezable,

    /// Freezer shelf life in days (only when [freezable]). Null = no limit.
    int? freezerDays,
    @Default(<CoveredMeal>[]) List<CoveredMeal> meals,
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

  /// Portions to cook: the sum of every covered meal's demand, possibly
  /// fractional. Zero on a component session.
  double get totalPortions => covers.fold(0, (s, m) => s + m.portions);

  /// The multiplier the recipe's lines scale by: `total_portions /
  /// servings_base`, unrounded, for a meal session; the batch count for a
  /// component session.
  double get scaleFactor {
    final batches = batchesToCook;
    if (batches != null) return batches;
    return servingsBase == 0 ? 0 : totalPortions / servingsBase;
  }

  /// Covered days past the fridge window, served from the freezer. Only
  /// meaningful for a [freezable] recipe with a known [keepsForDays].
  List<int> get frozenDays {
    final keeps = keepsForDays;
    if (!freezable || keeps == null) return const [];
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

  /// Distinct days this recipe is eaten across the week, ascending.
  List<int> get days {
    final set = {for (final s in sessions) ...s.coveredDays};
    return set.toList()..sort();
  }

  /// The earliest cook day — the plan's sort key.
  int get firstCookDay =>
      sessions.isEmpty ? 0 : sessions.map((s) => s.cookDay).reduce(min);

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
@freezed
abstract class ComponentDemandSource with _$ComponentDemandSource {
  const factory ComponentDemandSource({
    required String recipeId,
    required String title,
    required int cookDay,

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
  }) = _CookPlan;

  bool get isEmpty => recipes.isEmpty && gaps.isEmpty;

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

/// Greedy shelf-life clustering for one recipe: a meal joins the current
/// session while it is within [PlannedRecipe.keepsForDays], or as a frozen
/// share when the recipe is [PlannedRecipe.freezable] and within
/// [PlannedRecipe.freezerDays] (null = no limit); otherwise it opens a new
/// session.
///
/// An unknown shelf life never splits. A negative one is clamped to 0.
List<CookSession> clusterSessions(PlannedRecipe recipe) {
  final keeps = _clampWindow(recipe.keepsForDays);
  final freezerDays = _clampWindow(recipe.freezerDays);
  return [
    for (final cluster in _clusterByDay<CoveredMeal>(
      recipe.meals,
      dayOf: (m) => m.dayOfWeek,
      keepsForDays: keeps,
      freezable: recipe.freezable,
      freezerDays: freezerDays,
    ))
      CookSession(
        recipeId: recipe.recipeId,
        recipeTitle: recipe.title,
        servingsBase: recipe.servingsBase,
        cookDay: cluster.first.dayOfWeek,
        keepsForDays: keeps,
        freezable: recipe.freezable,
        freezerDays: freezerDays,
        covers: List.unmodifiable(cluster),
      ),
  ];
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
/// cluster covering everything.
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
/// session is a component one, or its inputs are degenerate.
///
/// Display advice only: everything else, the shopping list included, scales by
/// the raw factor.
WholeBatchNudge? wholeBatchNudgeFor(CookSession session) {
  if (session.isComponent) return null;
  final raw = session.scaleFactor;
  if (session.servingsBase <= 0 || raw <= 0) return null;
  if ((raw - raw.round()).abs() < 1e-9) return null; // already whole
  final factor = raw.ceil();
  final batchPortions = factor * session.servingsBase;
  return (
    factor: factor,
    batchPortions: batchPortions,
    leftoverPortions: batchPortions - session.totalPortions,
  );
}

/// The batch a meal being added would join. `withDay` is the day of the shared
/// batch; `frozen` is true when the new meal is reached from the freezer.
typedef BatchHint = ({int withDay, bool frozen});

/// The batch a meal on [newDay] would share with meals already on
/// [plannedDays], or null when it would be its own cook. Runs the real
/// [clusterSessions] so the hint cannot disagree with the cook plan.
BatchHint? batchHintFor({
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
    final days = session.coveredDays;
    if (!days.contains(newDay)) continue;
    final others = days.where((d) => d != newDay).toList();
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
CookPlan buildCookPlan(
  List<PlannedRecipe> recipes, {
  Map<String, ComponentRecipe> components = const {},
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
    return c != 0 ? c : a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return CookPlan(recipes: plans, gaps: gaps);
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
