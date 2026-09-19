/// Cook-plan domain — the DERIVED batch view (spec §4).
///
/// PURE DART (invariant 2): no `package:flutter`. The cook plan is a pure
/// function of the week's meals plus each recipe's shelf life — nothing here is
/// persisted (the repository re-derives it on every change). [buildCookPlan]
/// groups the week's meals by recipe; [clusterSessions] splits one recipe into
/// [CookSession]s bounded by its fridge shelf life (`keeps_for_days`), with a
/// freezer *merge* (spec §4 stretch, built): a freezable recipe's later
/// instance folds into one session — cook once, freeze the far share — instead
/// of opening a second session.
///
/// Days are offsets from the week's own first day, 0..6 (matching
/// `plan_entry.day_of_week`) — the derivation never asks which weekday that
/// is, so it is correct under any household's week and improves under a
/// Sunday-first one: a batch cooked on shopping day heads the week instead of
/// trailing the next day's. The cook day is the earliest covered day. Scale
/// factor is the raw `total_portions / servings_base` — honest, not nudged to
/// a whole batch.
///
/// **Nested recipes (step 8.6 / D3).** A planned recipe's *component* lines
/// derive sessions of their own: each parent session demands `parent scale ×
/// batches-per-parent-batch` of the sub-recipe ([ComponentDemand]), every
/// demand on the same sub-recipe clusters into that recipe's own sessions
/// through the machinery above, and the resulting session's scale reads in
/// BATCHES ([CookSession.batchesToCook]) because portions are the wrong
/// denomination for a sauce. The walk is depth-first with a visited-set guard,
/// so a cycle raced in by two devices stops and flags ([ComponentCycle])
/// instead of looping. A component whose batch math does not resolve becomes a
/// first-class [ComponentGap] on the plan — never a `1×` assumption.
///
/// **The graph is read for ONE week.** A recipe's component lines go through
/// the `effectiveLines` seam before any demand is derived
/// ([componentGraphForWeek]), so an optional sub-recipe is cooked only when the
/// week ticks it in, and the cook plan, the shop and the week's macros all read
/// one rule about which lines count.
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

/// One planned appearance of a recipe in the week — a `plan_entry` reduced to
/// what batching needs: its [dayOfWeek] (0..6 from the week's first day),
/// [mealSlot], and the
/// [portions] it demands (the entry's override, or the sum of its eaters'
/// portion factors — `demandPortions`). Fractional by design: a 1 and a ¾ eater
/// are `1.75`, and nothing here rounds it.
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

/// One parent cook session's demand on a sub-recipe (step 8.6 / D3): the
/// [batches] of it that session needs, and who needs them.
///
/// [parentRecipeId]/[parentTitle] name the **planned** recipe at the top of the
/// walk — the one a person put on the week and will recognise ("for Sausage
/// Sliders"), which is also what the shopping breakdown's extra provenance
/// segment says. [via] names the intermediate recipe when the demand came
/// through one (an aioli inside a sauce inside the sliders); it is null at
/// depth one, which is every demand a printed page has yet produced.
@freezed
abstract class ComponentDemand with _$ComponentDemand {
  const factory ComponentDemand({
    required String parentRecipeId,
    required String parentTitle,

    /// The demanding parent session's cook day (0..6 from the week's first
    /// day) — the day this
    /// batch has to be ready *by*.
    required int cookDay,

    /// Batches of the sub-recipe, already multiplied through the parent
    /// session's own scale factor.
    required double batches,
    String? via,

    /// What the demanding line printed, unscaled — the amount and, when it
    /// was said in one of the target's own words, that word. A card quotes
    /// the line in the words it was written in (`3 blob → 0.15 of a batch`)
    /// rather than re-stating it in a unit nobody typed.
    double? quantity,
    String? measureLabel,
  }) = _ComponentDemand;
}

/// A derived cook session: one batch to cook on [cookDay], covering [covers]
/// and/or answering [demands].
///
/// Two flavours, and a session is exactly one of them (step 8.6 / D3):
///
/// - a **meal session** covers planned meals and scales in PORTIONS
///   ([totalPortions] / [scaleFactor] = portions ÷ servings_base);
/// - a **component session** answers other recipes' component lines and scales
///   in BATCHES ([batchesToCook], and [scaleFactor] *is* that number).
///
/// They are never merged into one session even for the same recipe on the same
/// day: "4 portions + ¼ batch" is two denominations, and summing them would
/// need a number nobody stated. The two cards sit side by side instead.
///
/// Everything past the stored fields is a pure getter over them.
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

    /// The component demands this batch answers (step 8.6). Non-empty exactly
    /// for a component session.
    @Default(<ComponentDemand>[]) List<ComponentDemand> demands,
  }) = _CookSession;

  /// Whether this session exists to feed another recipe's component line
  /// rather than a planned meal — the card that reads "×¼ batch", not
  /// "×2 — covers 8 portions".
  bool get isComponent => demands.isNotEmpty;

  /// Batches to cook, or null for a meal session. The sum of every demand this
  /// session answers.
  double? get batchesToCook =>
      isComponent ? demands.fold<double>(0, (s, d) => s + d.batches) : null;

  /// The distinct titles of the recipes demanding this component batch, in
  /// first-seen order — the card's "for Sausage Sliders" (and, when two
  /// parents share a batch, both of them).
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

  /// Portions to cook: the sum of every covered meal's demand — fractional
  /// when a portion factor is (P-D4), and said as a fraction. Zero on a
  /// component session — portions are not its denomination ([batchesToCook]
  /// is).
  double get totalPortions => covers.fold(0, (s, m) => s + m.portions);

  /// The multiplier everything downstream scales the recipe's lines by.
  ///
  /// A meal session's is the raw `total_portions / servings_base` — honest,
  /// not rounded to a whole recipe (whole-ingredient scaling is deferred). A
  /// component session's is its batch count directly: one batch means the
  /// recipe as written, so ×batches is exactly right and needs no servings.
  double get scaleFactor {
    final batches = batchesToCook;
    if (batches != null) return batches;
    return servingsBase == 0 ? 0 : totalPortions / servingsBase;
  }

  /// Covered days that fall past the fridge window and are therefore served
  /// from the freezer (only meaningful for a [freezable] recipe with a known
  /// [keepsForDays]).
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
  /// (batch-denominated, step 8.6).
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

/// Who demanded a component the plan could not derive — the planned recipe at
/// the top of the walk, the day it is cooked, and what its line printed.
///
/// [quantity]/[unit] are the demanding line's stored values **as printed**,
/// NOT multiplied by the parent session's scale: the gap card quotes what the
/// page says ("the line asks for ¼ cup"), because a scaled number would be
/// arithmetic done against a yield that is exactly what is missing. [quantity]
/// is null on a numberless line, and the card drops the clause rather than
/// filling it.
///
/// One source per demanding parent: when a parent lists the same target more
/// than once, the first line's amount is the one quoted (the gap is keyed by
/// target + reason, so the two lines are one gap).
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

    /// The target's own word the demanding line said it in, when the target
    /// still has that word — so the card quotes `3 blob` rather than the
    /// count-family unit stored under it.
    ///
    /// Null when the line named no word AND when the word is the very thing
    /// that has gone: a gap card that cannot say what the line asked for
    /// drops the clause rather than printing the number against a unit the
    /// line never meant.
    String? measureLabel,

    /// Whether the line named a word at all. With a null [measureLabel] it is
    /// what tells "this line says cups" apart from "this line says a word
    /// nobody here has".
    @Default(false) bool saysAMeasure,
  }) = _ComponentDemandSource;
}

/// A component the plan could NOT derive a session for (step 8.6 / D3) — the
/// named gap the cook card renders in place of a scale.
///
/// This is a first-class value, not a fallback: the alternative to a gap is
/// assuming one batch, which is precisely the invented number this app
/// refuses. [reason] says which honest refusal it is (no yield, a unit in no
/// yield's family, no amount, a cycle), and [demandedBy] says whose plan is
/// short because of it.
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

/// The whole derived cook plan: one [RecipeCookPlan] per recipe on the week,
/// ordered by earliest cook day then title, plus the component [gaps] that
/// could not be turned into sessions.
@freezed
abstract class CookPlan with _$CookPlan {
  const CookPlan._();

  const factory CookPlan({
    @Default(<RecipeCookPlan>[]) List<RecipeCookPlan> recipes,
    @Default(<ComponentGap>[]) List<ComponentGap> gaps,
  }) = _CookPlan;

  bool get isEmpty => recipes.isEmpty && gaps.isEmpty;

  /// How many components each PLANNED recipe is short by — the shopping
  /// list's per-parent echo line ("1 component unresolved"), keyed by the
  /// planned recipe's id.
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

/// Greedy shelf-life clustering for one recipe (spec §4): sort the days the
/// dish appears; start a session at the first; fold each later meal into the
/// current session while it stays within the fridge window
/// ([PlannedRecipe.keepsForDays]); a meal past the window folds in anyway as a
/// *frozen* share when the recipe is [PlannedRecipe.freezable] and the meal is
/// within the freezer window ([PlannedRecipe.freezerDays], null = no limit);
/// otherwise it opens a new session. O(n log n).
///
/// A recipe with no shelf life (unknown) is never split — it yields a single
/// session covering every meal. A *negative* shelf life (bad data) is clamped
/// to 0 ("eat the day you cook") rather than trusted — a negative window would
/// split even same-day meals into separate cooks.
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

/// The same greedy shelf-life clustering [clusterSessions] runs, over the
/// component demands on one sub-recipe (step 8.6 / D3): each cluster becomes
/// one **batch-denominated** session cooked on its earliest demanding parent's
/// cook day, and bounded by the sub-recipe's OWN keeps/freezer facts — a sauce
/// that keeps three days is cooked twice for parents six days apart, exactly
/// as a planned meal would be.
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
        // On or before the earliest demanding parent's cook day (D3).
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

/// The greedy walk both clusterings share: sort by day, start a cluster at the
/// first item, fold each later one in while it stays within the fridge window
/// (or is rescued by the freezer), else open a new cluster. O(n log n).
///
/// An unknown [keepsForDays] never splits — one cluster covering everything,
/// because inventing a window would be inventing a number.
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

/// The whole-batch nudge for a session cooking a fractional batch (step 7.6):
/// round the raw factor UP to `factor` whole batches, which yields
/// `batchPortions` portions — covering the session's demanded portions with
/// `leftoverPortions` to spare. Portions can be fractional when
/// `servings_base` is (formatting trims honestly).
typedef WholeBatchNudge = ({
  int factor,
  double batchPortions,
  double leftoverPortions,
});

/// The nudge for [session], or null when there is nothing to nudge:
/// the raw factor is already a whole number (within float noise), the session
/// is a batch-denominated component one (step 8.6 — its scale is already in
/// batches, and "cook ×1, 3 portions left over" is the wrong sentence for a
/// sauce), or the session's inputs are degenerate (`servings_base` ≤ 0,
/// nothing covered).
///
/// The nudge is display-level advice ("cook ×1 — covers 4 portions · 1 left
/// over"); the honest raw factor stays the number everything else — the
/// shopping list included — scales by (invariant 3).
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

/// The batch a meal being added would join, for the planner's "same batch"
/// hint. `withDay` is the day of the shared batch (its cook day, or the meal it
/// now cooks alongside); `frozen` is true when the new meal is reached from the
/// freezer within that batch.
typedef BatchHint = ({int withDay, bool frozen});

/// Whether adding a meal of a recipe on [newDay] would share a cook session
/// with meals already planned on [plannedDays] (same recipe), under the
/// recipe's shelf life. Returns the batch it joins, or null when the new meal
/// would be its own cook. Runs the real [clusterSessions] over the combined
/// days so the hint never disagrees with the cook plan.
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
      // leaves no *other* day — but it still shares the batch (clusterSessions
      // merges same-day meals into one session). More than one covered meal in
      // the session means the day was already planned: same-batch, same day.
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

/// One component line of a recipe, as the expansion needs it (step 8.6).
/// `quantity` is null on a line that carries no number, which is legal to
/// store and derives nothing.
///
/// `id` is the `recipe_line_item` row's id, because a week's override names
/// the line it is about, and `optional` is the recipe's own flag: both are
/// what [componentGraphForWeek] needs to run the seam over the graph.
typedef ComponentLine = ({
  String id,
  String subRecipeId,
  double? quantity,

  /// The catalog unit, or null when the line is said in one of the target's
  /// own words instead — exactly one of this and `recipeMeasureId` below is
  /// set, as the database pins it.
  Unit? unit,

  /// The target recipe's own word this line is said in, or null. Carried
  /// through the seam so a demand card can print `3 blob` rather than the
  /// count-family unit the row stores underneath it.
  String? recipeMeasureId,
  bool optional,
});

/// A recipe as the component walk sees it: the shelf-life facts a derived
/// session inherits, the yields its own component references are resolved
/// against, and the component lines it is built from.
///
/// The repository supplies one of these per LIVE recipe in the household, so
/// the walk can reach a component of a component without another query. A
/// sub-recipe id the map does not hold is a dangling link: nothing is derived
/// and no gap is raised — the line degrades to the plain text it stored (D5).
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

/// One recipe's component lines as ONE week cooks them: the [effectiveLines]
/// seam's answer — the lines a demand is derived from, and the ones a surface
/// must NAME instead of quietly dropping.
///
/// The seam rules on [LineItem]s, so each component line is read as one: it
/// carries the sub-recipe's title as its name (from [graph]), which is what
/// makes a dropped component say "Romesco Aioli" rather than nothing at all. A
/// recipe [graph] does not hold has no component lines to rule on.
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
      subRecipe: switch (graph[line.subRecipeId]) {
        final target? => SubRecipeTarget(
          id: line.subRecipeId,
          title: target.title,
          measures: target.measures,
        ),
        _ => null,
      },
      quantity: line.quantity,
      recipeMeasureId: line.recipeMeasureId,
      optional: line.optional,
    ),
], overrides: overrides);

/// The household's component [graph] as ONE week cooks it: every recipe's
/// lines through [componentLinesForWeek] with that week's [overridesByRecipe],
/// so a demand is derived from exactly the lines the week actually cooks.
///
/// This is what makes "optional" mean the same thing in Cook as it does in the
/// shop and in a week's macros: a component line the recipe marks optional
/// spawns no session until the week ticks it in, a line the week leaves out
/// spawns none, and a replaced one is cooked at the week's amount. A line the
/// week ruled on comes back with `optional` cleared, which is the seam's own
/// composition rule.
///
/// Runs over the WHOLE graph rather than only the planned recipes: a sub-recipe
/// reached through a component line can itself carry an optional component, and
/// the walk that reaches it reads this same map.
///
/// Only lines that still name a sub-recipe survive — an added or replaced line
/// that names an ingredient is the shop's business, not the cook plan's.
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

/// Builds the whole derived cook plan from the week's [recipes], ordering the
/// cards by earliest cook day then title.
///
/// [components] is the household's component graph (step 8.6 / D3). Passing
/// none — the default — derives exactly what it did before nested recipes
/// existed: meal sessions and nothing else.
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
    // A sub-recipe that is ALSO on the week keeps one card: its meal sessions
    // and its component sessions sit side by side, in two denominations that
    // are never summed.
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

/// The planned recipe a walk descends from — the identity every demand and gap
/// on that branch is attributed to. Kept separate from [ComponentDemandSource]
/// because that carries the per-LINE printed amount, while this is fixed for
/// the whole branch.
typedef _PlannedRoot = ({String recipeId, String title, int cookDay});

/// Walks every planned session's component lines depth-first, returning the
/// [ComponentDemand]s per sub-recipe and the [ComponentGap]s for the ones that
/// could not be resolved (step 8.6 / D3).
///
/// A parent session demanding `f` batches of a sub-recipe whose own line asks
/// for `b` batches of a third recipe demands `f × b` of that third one — the
/// multiplication is the whole recursion.
///
/// The walk carries a **visited set** down each branch. A cycle cannot normally
/// be written (the server trigger and [closesComponentCycle] both refuse
/// one), but two devices racing can outrun the trigger, and a derivation that
/// looped would hang the Cook tab rather than merely be wrong. It stops at the
/// repeat and raises a [ComponentCycle] gap instead.
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
      // the text it stored, with plain-text semantics (D5).
      if (target == null) continue;

      // The word the line says, when the target still has it — carried into
      // every source and demand so a card quotes the line in the words it was
      // written in. Null the moment the word has gone, which is exactly the
      // state a card must not print a number for.
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
        // The source carries the DEMANDING LINE's printed amount, unscaled —
        // frame (f)'s "the line asks for ¼ cup" quotes the page, not
        // arithmetic against the yield that is missing.
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
          measureLabel: said?.label,
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
