/// [ShoppingRepository] over the local PowerSync SQLite (offline in step 6).
///
/// The read derives cook contributions live from the batch cook plan (spec §4):
/// it reads the week's planned meals, runs the same pure [buildCookPlan] the
/// Cook screen uses, then multiplies each covered recipe's line items by its
/// session scale factor. It overlays the persisted check-off + manual/free-text
/// rows and hands everything to the pure [buildShoppingList].
///
/// Since step 8.14 it derives from the week's **entries** as well as its
/// sessions. A planned meal can be a bare ingredient — a protein bar — which is
/// bought but never cooked (A-D4), so it belongs to no session at all; a
/// derivation that only ever walked sessions would leave a hole in a list
/// somebody shops from. `_derivePlannedIngredients` is that second walk.
///
/// **Both walks join the vocab row without a liveness guard, and neither buys
/// from a retired one.** A row the household has RETIRED is not a fact about
/// food any more — name, aisle and density are all stale — so a recipe line or
/// a planned meal that names one contributes nothing, and says so on the
/// list's third echo channel ([ShoppingList.retiredIngredients]) under the
/// row's last known name. What that replaced was the worst of both: a recipe
/// line was shopped FROM the dead row, while a planned snack (an inner join to
/// a LIVE row) fell off the list altogether, taking its check-off row with it.
///
/// The watch query references every table the load path reads AND selects a
/// column from each — the two shopping tables and the `ingredient` vocab
/// (aisle/density/name) via a `LEFT JOIN … ON 1=1` — so PowerSync's
/// `EXPLAIN`-based detection registers all of them as triggers. An unselected
/// LEFT JOIN is dropped by SQLite before `EXPLAIN` sees it, and its table is
/// then silently missed; selecting a column from each keeps it.
/// `test/core/sync/watch_coverage_test.dart` pins this structurally.
///
/// Writes go through the local VIEWS, so no UPSERT (a view rejects
/// `ON CONFLICT`): entry creation is a find-or-create with a plain INSERT.
///
/// **The overlay is week-scoped.** Every entry — an ingredient someone ticked
/// or topped up, a free-text non-food item — carries the first day of the
/// week it was made
/// against, and the read only takes that week's. So
/// `_findOrCreateIngredientEntry` converges per WEEK, not per household — two
/// devices ticking Flour on next week still meet on one row, and neither of
/// them touches this week's.
library;

import 'dart:convert';

import 'package:sqlite3/common.dart' show Row;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../../core/week_shape.dart';
import '../../cook_plan/data/cook_plan_repository_impl.dart'
    show loadComponentGraph;
import '../../cook_plan/domain/cook_plan.dart';
import '../../planning/data/planning_repository_impl.dart' show loadMembers;
import '../../planning/data/week_variant_repository_impl.dart'
    show loadWeekOverrides;
import '../../planning/domain/planning.dart' show eatersDemand;
import '../../recipes/domain/effective_lines.dart';
import '../../recipes/domain/line_override.dart';
import '../../recipes/domain/recipe.dart';
import '../domain/shopping.dart';
import '../domain/shopping_repository.dart';

const _uuid = Uuid();

/// A recipe line as the shopping list needs it. `line` is the domain
/// [LineItem] the [effectiveLines] seam rules on (id, name, `optional`);
/// `unit` is null when the persisted id isn't a known unit — `rawUnit` keeps
/// the string for the breakdown's unconverted note, and the domain line's
/// `pieces` fallback is never read here. `measure` is resolved when the line
/// is quantified in one (null if its row is missing — the stored count unit
/// then stands, an honest degradation).
typedef _LineItem = ({
  LineItem line,
  String ingredientId,
  double? quantity,
  Unit? unit,
  String? rawUnit,
  Measure? measure,
});

class SqliteShoppingRepository implements ShoppingRepository {
  const SqliteShoppingRepository(
    this._db, {
    required String householdId,
    WeekShape weekShape = WeekShape.monday,
  }) : _householdId = householdId,
       _weekShape = weekShape;

  final SqliteConnection _db;

  /// The household stamped on rows this repo writes (injected — the app passes
  /// the signed-in household, tests pass their own).
  final String _householdId;

  /// The household's week, for the one thing this layer says in words: a
  /// breakdown line's day. The data layer cannot reach up into presentation
  /// for a word, and an offset only names a weekday once the shape is known.
  final WeekShape _weekShape;

  String _weekKey(DateTime weekStart) => isoDateOf(weekStart);

  @override
  Stream<ShoppingList> watchShoppingList(DateTime weekStart) {
    final key = _weekKey(weekStart);
    // Reference every table the load reads and select a column from each so
    // all ten become watch triggers (see the library doc). The shopping,
    // ingredient, measure and member tables aren't tied to the week, so
    // they're cross-joined (`ON 1=1`) purely to be seen.
    return _db
        .watch(
          'SELECT wp.id, pe.id, r.keeps_for_days, g.id, li.id, se.id, sc.id, '
          'i.id, im.id, hm.id, wro.id '
          'FROM week_plan wp '
          'LEFT JOIN plan_entry pe '
          'ON pe.week_plan_id = wp.id AND pe.deleted_at IS NULL '
          // This week's variant changes what the list buys, so a change to it
          // must re-fire the list exactly as a changed recipe line does.
          'LEFT JOIN week_recipe_line_override wro '
          'ON wro.week_plan_id = wp.id AND wro.deleted_at IS NULL '
          'LEFT JOIN recipe r ON r.id = pe.recipe_id '
          'LEFT JOIN ingredient_group g ON g.recipe_id = r.id '
          'LEFT JOIN recipe_line_item li ON li.group_id = g.id '
          'LEFT JOIN shopping_list_entry se ON 1 = 1 '
          'LEFT JOIN shopping_list_contribution sc ON 1 = 1 '
          'LEFT JOIN ingredient i ON 1 = 1 '
          'LEFT JOIN ingredient_measure im ON 1 = 1 '
          'LEFT JOIN household_member hm ON 1 = 1 '
          'WHERE wp.week_start_date = ? AND wp.deleted_at IS NULL LIMIT 1',
          parameters: [key],
        )
        .asyncMap((_) => _load(key));
  }

  Future<ShoppingList> _load(String weekKey) async {
    final (cook, unresolved, optional, retiredLines) =
        await _deriveCookContributions(weekKey);
    // The week's OWN entries, not only its cook sessions (step 8.14 / A-D4).
    final (planned, retiredPlanned) = await _derivePlannedIngredients(weekKey);
    final (entries, manual) = await _loadOverlay(weekKey);
    final meta = await _loadIngredientMeta({
      ...cook.map((c) => c.ingredientId),
      ...planned.map((p) => p.ingredientId),
      ...entries.map((e) => e.ingredientId).whereType<String>(),
    });
    return buildShoppingList(
      cook: cook,
      planned: planned,
      entries: entries,
      manual: manual,
      meta: meta,
      weekdayShort: _weekShape.shortLabels,
      unresolvedComponents: unresolved,
      optionalLines: optional,
      // Both walks can meet a retired row, and a shopper reads one list of
      // what is missing rather than two — so the two channels are one, sorted
      // the way the other echoes are.
      retiredIngredients: [...retiredLines, ...retiredPlanned]
        ..sort((a, b) {
          final c = a.heading.compareTo(b.heading);
          return c != 0 ? c : a.ingredientName.compareTo(b.ingredientName);
        }),
    );
  }

  /// The week's bare-INGREDIENT meals as shopping contributions (step 8.14 /
  /// A-D4).
  ///
  /// This is the one piece of real plumbing the ruling asks for: a snack is
  /// never cooked, so it appears in no cook session, and a list derived only
  /// from sessions would be quietly short of the thing somebody planned to
  /// eat. So the derivation walks **entries** here, beside
  /// [_deriveCookContributions]'s walk of the plan.
  ///
  /// The amount is multiplied by the entry's demand — Σ of the eaters' portion
  /// factors, the `portions` override winning — which is the same demand every
  /// other derivation reads (A-D3: a snack two people are having is bought
  /// twice). An entry that states no amount contributes nothing; one whose
  /// unit or measure will not resolve degrades to a visible note in the
  /// breakdown rather than an invented number, exactly as a cook line does.
  ///
  /// An entry at a RETIRED vocab row buys nothing and is not dropped either:
  /// it comes back in the second list as a [RetiredIngredientNote], so the
  /// snack somebody planned still has a row a shopper can read — the check-off
  /// row vanishing with it is how this went unnoticed.
  Future<(List<PlanIngredientInput>, List<RetiredIngredientNote>)>
  _derivePlannedIngredients(String weekKey) async {
    final rows = await _db.getAll(
      'SELECT pe.day_of_week, pe.meal_slot, pe.eaters, pe.portions, '
      'pe.quantity, pe.unit, i.id AS ingredient_id, '
      'i.canonical_name AS ingredient_name, '
      'i.deleted_at AS ingredient_deleted_at, '
      'pe.measure_id, im.label AS measure_label, '
      'im.basis_amount AS measure_amount, i.macros_basis AS measure_basis, '
      'im.sort_order AS measure_sort, im.source AS measure_source '
      'FROM week_plan wp '
      'JOIN plan_entry pe ON pe.week_plan_id = wp.id AND pe.deleted_at IS NULL '
      // The explicit branch: an entry with no ingredient is a RECIPE meal,
      // already covered by the cook derivation. The join carries no liveness
      // guard — an UNSYNCED row still drops out (there is no row to join, and
      // nothing truthful to say about it), but a RETIRED one is joined
      // deliberately, because its last known name is the whole of what the
      // echo row has to say. Nothing else about it is read.
      'JOIN ingredient i ON i.id = pe.ingredient_id '
      'LEFT JOIN ingredient_measure im '
      'ON im.id = pe.measure_id AND im.deleted_at IS NULL '
      'WHERE wp.week_start_date = ? AND wp.deleted_at IS NULL '
      'AND pe.ingredient_id IS NOT NULL '
      'ORDER BY pe.day_of_week, pe.sort_order, pe.created_at',
      [weekKey],
    );
    if (rows.isEmpty) {
      return (const <PlanIngredientInput>[], const <RetiredIngredientNote>[]);
    }

    final members = {for (final m in await loadMembers(_db)) m.id: m};
    final planned = <PlanIngredientInput>[];
    final retired = <RetiredIngredientNote>[];
    for (final row in rows) {
      final eaters = (jsonDecode(row['eaters'] as String? ?? '[]') as List)
          .cast<String>();
      final demand =
          (row['portions'] as int?)?.toDouble() ??
          eatersDemand(eaters, members);
      // An unknown persisted unit id stays null (rawUnit keeps the string)
      // — never a `pieces` fallback, which would let the total sum an
      // invented unit (invariant 3).
      final rawUnit = row['unit'] as String?;
      final unit = rawUnit == null ? null : unitById(rawUnit);
      final quantity = (row['quantity'] as num?)?.toDouble();
      final input = (
        ingredientId: row['ingredient_id'] as String,
        // The stated amount is ONE portion; the week's demand multiplies
        // it. A count in a measure scales linearly, so the same product is
        // the measure amount too.
        quantity: quantity == null ? null : quantity * demand,
        unit: unit,
        rawUnit: rawUnit,
        // A measure beside an UNRECOGNISED unit is dropped: the quantity's
        // semantics are unknown, so pricing it through the measure's
        // weight would sum an invented number. The row surfaces as the
        // unrecognised-unit note instead.
        measure: unit == null ? null : _toMeasure(row),
        dayOfWeek: row['day_of_week'] as int,
        mealSlot: row['meal_slot'] as String,
      );
      if (row['ingredient_deleted_at'] != null) {
        retired.add((
          // The words the breakdown would have carried — the same rule, so a
          // shopper meets one vocabulary whether the snack was buyable or not.
          heading: planIngredientLabel(input, _weekShape.shortLabels),
          ingredientName: row['ingredient_name'] as String? ?? '',
          site: RetiredIngredientSite.planEntry,
        ));
      } else {
        planned.add(input);
      }
    }
    return (planned, retired);
  }

  /// Runs the cook plan for the week, then expands each session's recipe line
  /// items scaled by the session's factor into per-ingredient contributions.
  ///
  /// Since 8.6 the plan also carries **component** sessions (D3/D4): a
  /// component session is a cook session, so the sub-recipe's own ingredient
  /// lines flow through this same pipeline, scaled by its batch factor, and
  /// carry one extra provenance segment naming the plan they serve. The
  /// component LINE itself never becomes an item — [_loadLineItems] skips any
  /// row without an `ingredient_id`, which is exactly the component rows (you
  /// buy almonds, not aioli). The second return value is the per-parent
  /// "N components unresolved" echo built from the plan's gaps.
  ///
  /// Each recipe's lines pass through the [effectiveLines] seam before any
  /// session expands them — this is where lines meet the week — and the third
  /// return value is the per-recipe "N optional lines not listed" echo built
  /// from what the seam dropped, ingredient lines and component lines alike.
  ///
  /// The fourth is the lines whose INGREDIENT has been retired: a kept line
  /// pointing at a tombstone expands into no contribution at all — there is no
  /// name to shop by, no aisle to file it under and no density to sum it with
  /// — and is named on its own echo row instead, so the list is never quietly
  /// short of it.
  Future<
    (
      List<CookContributionInput>,
      List<UnresolvedComponentNote>,
      List<OptionalLinesNote>,
      List<RetiredIngredientNote>,
    )
  >
  _deriveCookContributions(String weekKey) async {
    final rows = await _db.getAll(
      'SELECT pe.day_of_week, pe.meal_slot, pe.eaters, pe.portions, '
      'r.id AS recipe_id, r.title, r.servings_base, r.keeps_for_days, '
      'r.freezable, r.freezer_days '
      'FROM week_plan wp '
      'JOIN plan_entry pe ON pe.week_plan_id = wp.id AND pe.deleted_at IS NULL '
      'JOIN recipe r ON r.id = pe.recipe_id AND r.deleted_at IS NULL '
      'WHERE wp.week_start_date = ? AND wp.deleted_at IS NULL '
      // The explicit branch (step 8.14 / B-D2). A bare-ingredient meal has no
      // recipe to expand; it reaches the list through
      // [_derivePlannedIngredients] instead, never by falling through here.
      'AND pe.recipe_id IS NOT NULL '
      'ORDER BY pe.day_of_week, pe.sort_order, pe.created_at',
      [weekKey],
    );
    if (rows.isEmpty) {
      return (
        const <CookContributionInput>[],
        const <UnresolvedComponentNote>[],
        const <OptionalLinesNote>[],
        const <RetiredIngredientNote>[],
      );
    }

    // The same demand the cook plan derives: Σ of the eaters' portion factors,
    // the override winning. The list is otherwise untouched by the factor — it
    // still scales by the session's batch factor, which is where the demand
    // lands.
    final members = {for (final m in await loadMembers(_db)) m.id: m};
    final byRecipe = <String, PlannedRecipe>{};
    final meals = <String, List<CoveredMeal>>{};
    for (final row in rows) {
      final recipeId = row['recipe_id'] as String;
      final eaters = (jsonDecode(row['eaters'] as String? ?? '[]') as List)
          .cast<String>();
      final portions =
          (row['portions'] as int?)?.toDouble() ??
          eatersDemand(eaters, members);
      byRecipe[recipeId] ??= PlannedRecipe(
        recipeId: recipeId,
        title: row['title'] as String,
        servingsBase: (row['servings_base'] as num).toDouble(),
        keepsForDays: row['keeps_for_days'] as int?,
        freezable: (row['freezable'] as int? ?? 0) == 1,
        freezerDays: row['freezer_days'] as int?,
      );
      (meals[recipeId] ??= []).add(
        CoveredMeal(
          dayOfWeek: row['day_of_week'] as int,
          mealSlot: row['meal_slot'] as String,
          portions: portions,
        ),
      );
    }
    final weekOverrides = await loadWeekOverrides(_db, weekKey);
    final graph = await loadComponentGraph(_db);
    final plan = buildCookPlan(
      [
        for (final e in byRecipe.entries)
          e.value.copyWith(meals: meals[e.key] ?? const []),
      ],
      // The same week-filtered graph the Cook tab derives from, so a sub-recipe
      // this week does not cook buys nothing either.
      components: componentGraphForWeek(graph, weekOverrides),
    );

    // Line items per recipe, read once — for every recipe the plan cooks,
    // which since 8.6 includes the sub-recipes it derived component sessions
    // for as well as the ones somebody planned.
    final lineItems = await _loadLineItems({
      for (final r in plan.recipes) r.recipeId,
    });

    final contributions = <CookContributionInput>[];
    final optionalNotes = <OptionalLinesNote>[];
    final retiredNotes = <RetiredIngredientNote>[];
    for (final recipe in plan.recipes) {
      final batched = recipe.sessions.length > 1;
      final stored = lineItems[recipe.recipeId] ?? const <_LineItem>[];
      // The seam (D6b): the sessions below expand only the kept lines, and
      // the dropped ones become this recipe's echo row — never a silent
      // hole in a list somebody shops from.
      // This is where lines meet the week, so this is where the week's
      // variant joins. The overrides are read once per week and looked up per
      // recipe — the variant is per (week, recipe) too, so the sessions below
      // stay correct without a refactor.
      final overrides =
          weekOverrides[recipe.recipeId] ?? const <LineOverride>[];
      final effective = effectiveLines(
        stored.map((i) => i.line),
        overrides: overrides,
      );
      final byBaseLine = {
        for (final o in overrides)
          if (o.recipeLineItemId != null) o.recipeLineItemId!: o,
      };
      final addedById = {
        for (final o in overrides)
          if (o.action == LineOverrideAction.add) o.id: o,
      };
      final storedById = {for (final i in stored) i.line.id: i};
      // The kept lines ARE the week's lines: a replaced one carries absolute
      // values and an added one has no stored row at all, so the contribution
      // is rebuilt from what the seam returned rather than from what was read.
      final items = [
        for (final line in effective.kept)
          // A line at a retired row is kept by the seam — the seam rules on
          // what the WEEK cooks, and the week still asks for this line — but
          // nothing about the row it names can be shopped, so the sessions
          // below expand nothing for it and the echo names it instead.
          if (!line.ingredientDeleted)
            (
              item: _weekLine(line, storedById[line.id]),
              note: _weekNoteFor(line, byBaseLine, addedById, base: storedById),
            ),
      ];
      for (final line in effective.kept) {
        if (!line.ingredientDeleted) continue;
        retiredNotes.add((
          heading: recipe.title,
          // The row's LAST KNOWN name, read off the line rather than the
          // tombstone: it is the only thing that says which line broke.
          ingredientName: line.ingredientName,
          site: RetiredIngredientSite.recipeLine,
        ));
      }
      // The recipe's COMPONENT lines meet the same week through the same seam
      // (it is the graph the plan above was derived from). A sub-recipe this
      // week does not cook buys nothing, and is named here by its title —
      // otherwise the list would be short of a whole sauce in silence.
      final components = componentLinesForWeek(
        graph,
        recipe.recipeId,
        overrides: overrides,
      );
      for (final reason in LineDropReason.values) {
        final names = [
          ...droppedNames(effective, reason),
          ...droppedNames(components, reason),
        ];
        if (names.isEmpty) continue;
        optionalNotes.add((
          recipeId: recipe.recipeId,
          recipeTitle: recipe.title,
          names: names,
          lineIds: [
            ...droppedLineIds(effective, reason),
            ...droppedLineIds(components, reason),
          ],
          reason: reason,
        ));
      }
      for (final session in recipe.sessions) {
        for (final (:item, :note) in items) {
          // An unrecognised unit can't be scaled (it might even be imprecise);
          // pass the raw quantity through — the domain surfaces it as an
          // unconverted note and keeps it out of the totals.
          final unit = item.unit;
          final scaled = item.quantity == null || unit == null
              ? null
              : scale(Quantity(item.quantity!, unit), session.scaleFactor);
          contributions.add((
            ingredientId: item.ingredientId,
            quantity: unit == null ? item.quantity : scaled?.amount,
            unit: unit,
            rawUnit: item.rawUnit,
            // A measure count scales linearly (its stored unit is a count),
            // so the already-scaled amount is the measure amount too. But a
            // measure beside an UNRECOGNISED unit is dropped: the quantity's
            // semantics are unknown AND unscaled, so folding it through the
            // measure's gram weight would sum an invented number — the line
            // surfaces as the unrecognised-unit note instead (invariant 3).
            measure: unit == null ? null : item.measure,
            recipeTitle: recipe.title,
            cookDay: session.cookDay,
            batched: batched,
            // The extra provenance segment, deepest-first: this recipe's own
            // line, then the plan(s) it is being cooked for (D4). Empty for a
            // meal session, which reads exactly as it always has.
            forParents: session.demandedBy,
            // And one more when the WEEK changed this line, so the aisle says
            // why the amount is not the recipe's.
            weekNote: note,
          ));
        }
      }
    }

    // The parents whose lists are short because a component could not be
    // derived — the echo that keeps the silence legible (D4).
    final titles = {for (final r in plan.recipes) r.recipeId: r.title};
    final unresolved = <UnresolvedComponentNote>[
      for (final e in plan.unresolvedComponentsByParent.entries)
        (recipeId: e.key, recipeTitle: titles[e.key] ?? '', count: e.value),
    ]..sort((a, b) => a.recipeTitle.compareTo(b.recipeTitle));
    optionalNotes.sort((a, b) => a.recipeTitle.compareTo(b.recipeTitle));
    return (contributions, unresolved, optionalNotes, retiredNotes);
  }

  /// The seam's answer as this file's row shape. A line the week left alone
  /// keeps the row that was read (`rawUnit` and all); one the week changed —
  /// or added — is rebuilt from the domain line, whose unit is a resolved
  /// [Unit] and therefore never a raw string nobody knows.
  static _LineItem _weekLine(LineItem line, _LineItem? stored) {
    if (stored != null && identical(stored.line, line)) return stored;
    return (
      line: line,
      ingredientId: line.ingredientId ?? stored?.ingredientId ?? '',
      quantity: line.quantity,
      unit: line.unit,
      rawUnit: line.unit.id,
      measure: line.measure,
    );
  }

  /// The provenance segment this line carries, or null when the recipe states
  /// it itself. An exclusion never lands here — the seam dropped it, so there
  /// is no row for a segment to sit on.
  static String? _weekNoteFor(
    LineItem line,
    Map<String, LineOverride> byBaseLine,
    Map<String, LineOverride> addedById, {
    required Map<String, _LineItem> base,
  }) {
    final override = addedById[line.id] ?? byBaseLine[line.id];
    if (override == null) return null;
    return weekProvenanceSegment(
      weekChangeOf(override, base[override.recipeLineItemId ?? '']?.line),
      base[override.recipeLineItemId ?? '']?.line,
    );
  }

  Future<Map<String, List<_LineItem>>> _loadLineItems(
    Set<String> recipeIds,
  ) async {
    if (recipeIds.isEmpty) return const {};
    final placeholders = List.filled(recipeIds.length, '?').join(', ');
    final rows = await _db.getAll(
      'SELECT g.recipe_id, li.id, li.ingredient_id, li.quantity, li.unit, '
      'li.optional, ing.canonical_name AS ingredient_name, '
      'ing.deleted_at AS ingredient_deleted_at, '
      'li.measure_id, im.label AS measure_label, '
      'im.basis_amount AS measure_amount, i2.macros_basis AS measure_basis, '
      'im.sort_order AS measure_sort, im.source AS measure_source '
      'FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id AND g.deleted_at IS NULL '
      'LEFT JOIN ingredient ing ON ing.id = li.ingredient_id '
      'LEFT JOIN ingredient_measure im '
      'ON im.id = li.measure_id AND im.deleted_at IS NULL '
      'LEFT JOIN ingredient i2 ON i2.id = im.ingredient_id '
      'WHERE g.recipe_id IN ($placeholders) AND li.deleted_at IS NULL '
      'ORDER BY li.sort_order, li.created_at',
      recipeIds.toList(),
    );
    final byRecipe = <String, List<_LineItem>>{};
    for (final row in rows) {
      final ingredientId = row['ingredient_id'] as String?;
      if (ingredientId == null) continue;
      // An unknown persisted unit id stays null (rawUnit keeps the string) —
      // NOT a `pieces` fallback, which would let the total sum an invented
      // unit (invariant 3: honest numbers).
      final rawUnit = row['unit'] as String?;
      final unit = rawUnit == null ? null : unitById(rawUnit);
      final measure = _toMeasure(row);
      (byRecipe[row['recipe_id'] as String] ??= []).add((
        // The domain line the seam rules on. Its `unit` is the honest
        // fallback the recipe page also shows; the expansion reads the
        // record's nullable `unit` instead, so nothing invented is summed.
        line: LineItem(
          id: row['id'] as String,
          ingredientId: ingredientId,
          ingredientName: row['ingredient_name'] as String? ?? '',
          unit: unit ?? pieces,
          quantity: (row['quantity'] as num?)?.toDouble(),
          measureId: row['measure_id'] as String?,
          measure: measure,
          optional: row['optional'] == 1,
          // The vocab row is joined WITHOUT the liveness guard (so a retired
          // row still hands over its last known name); this is the flag that
          // stops that name reaching an aisle as if the row were fine.
          ingredientDeleted: row['ingredient_deleted_at'] != null,
        ),
        ingredientId: ingredientId,
        quantity: (row['quantity'] as num?)?.toDouble(),
        unit: unit,
        rawUnit: rawUnit,
        measure: measure,
      ));
    }
    return byRecipe;
  }

  /// The resolved [Measure] of a row selected with the
  /// `measure_id`/`measure_label`/`measure_amount`/`measure_basis`/
  /// `measure_sort` aliases, or null when the row has no measure (or its
  /// measure row is missing). The basis comes from the measure's own
  /// ingredient (`macros_basis` — the single stored fact, ADR-0008).
  Measure? _toMeasure(Row row) {
    final id = row['measure_id'] as String?;
    final label = row['measure_label'] as String?;
    final amount = (row['measure_amount'] as num?)?.toDouble();
    if (id == null || label == null || amount == null) return null;
    return Measure(
      id: id,
      label: label,
      amount: amount,
      basis: MacrosBasis.fromDb(row['measure_basis'] as String?),
      sortOrder: (row['measure_sort'] as int?) ?? 0,
      source: row['measure_source'] as String?,
    );
  }

  /// The week's overlay: the entries stamped with THIS week, and their manual
  /// contributions. A row stamped with another week belongs to a list this is
  /// not, so it is not read here — and neither is a row carrying no week at
  /// all, which only an older client writes and the server stamps onto the
  /// week it was created in.
  Future<(List<ShoppingEntryInput>, Map<String, List<ManualContributionInput>>)>
  _loadOverlay(String weekKey) async {
    final entryRows = await _db.getAll(
      'SELECT id, ingredient_id, free_text, category, checked, unit, '
      'created_at '
      'FROM shopping_list_entry WHERE deleted_at IS NULL '
      'AND week_start_date = ?',
      [weekKey],
    );
    final entries = [
      for (final r in entryRows)
        (
          id: r['id'] as String,
          ingredientId: r['ingredient_id'] as String?,
          freeText: r['free_text'] as String?,
          category: r['category'] as String?,
          checked: (r['checked'] as int? ?? 0) == 1,
          unit: unitById(r['unit'] as String? ?? ''),
          createdAt: r['created_at'] as String?,
        ),
    ];

    final contribRows = await _db.getAll(
      'SELECT sc.id, sc.entry_id, sc.quantity, sc.unit, sc.note, '
      'sc.measure_id, im.label AS measure_label, '
      'im.basis_amount AS measure_amount, i2.macros_basis AS measure_basis, '
      'im.sort_order AS measure_sort, im.source AS measure_source '
      'FROM shopping_list_contribution sc '
      'LEFT JOIN ingredient_measure im '
      'ON im.id = sc.measure_id AND im.deleted_at IS NULL '
      'LEFT JOIN ingredient i2 ON i2.id = im.ingredient_id '
      'JOIN shopping_list_entry se ON se.id = sc.entry_id '
      'AND se.deleted_at IS NULL '
      "WHERE sc.deleted_at IS NULL AND sc.source_type = 'manual' "
      'AND se.week_start_date = ? '
      'ORDER BY sc.created_at',
      [weekKey],
    );
    final manual = <String, List<ManualContributionInput>>{};
    for (final r in contribRows) {
      final entryId = r['entry_id'] as String;
      (manual[entryId] ??= []).add((
        id: r['id'] as String,
        entryId: entryId,
        quantity: (r['quantity'] as num?)?.toDouble(),
        unit: unitById(r['unit'] as String? ?? ''),
        // The stored id verbatim, kept even while the measure row is missing
        // (unsynced/deleted) so an edit re-save never wipes the FK.
        measureId: r['measure_id'] as String?,
        measure: _toMeasure(r),
        note: r['note'] as String?,
      ));
    }
    return (entries, manual);
  }

  /// The vocab facts the ids in hand need — name, aisle, density, measures.
  ///
  /// No liveness guard, deliberately: every id that reaches here already
  /// earned a row on the list, and the only way a RETIRED one can (the two
  /// derivations above leave theirs out) is a manual top-up somebody typed
  /// against it. That row stays, and the honest label for it is the last known
  /// name — a `(unknown ingredient)` would hide which thing they topped up.
  Future<Map<String, IngredientMetaInput>> _loadIngredientMeta(
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await _db.getAll(
      'SELECT id, canonical_name, category, density_g_per_ml, default_unit, '
      'piece_basis_amount, macros_basis '
      'FROM ingredient WHERE id IN ($placeholders)',
      ids.toList(),
    );

    // The ingredients' live measures, primary (lowest sort_order) first —
    // they gate the whole-unit hint and price its mass→count conversion.
    final measureRows = await _db.getAll(
      'SELECT im.ingredient_id, im.id AS measure_id, '
      'im.label AS measure_label, im.basis_amount AS measure_amount, '
      'i2.macros_basis AS measure_basis, im.sort_order AS measure_sort, '
      'im.source AS measure_source '
      'FROM ingredient_measure im '
      'JOIN ingredient i2 ON i2.id = im.ingredient_id '
      'WHERE im.ingredient_id IN ($placeholders) AND im.deleted_at IS NULL '
      'ORDER BY im.sort_order, im.created_at',
      ids.toList(),
    );
    final measuresByIngredient = <String, List<Measure>>{};
    for (final r in measureRows) {
      final measure = _toMeasure(r);
      if (measure == null) continue;
      (measuresByIngredient[r['ingredient_id'] as String] ??= []).add(measure);
    }

    return {
      for (final r in rows)
        r['id'] as String: (
          name: r['canonical_name'] as String,
          category: r['category'] as String?,
          densityGPerMl: (r['density_g_per_ml'] as num?)?.toDouble(),
          defaultUnit: unitById(r['default_unit'] as String? ?? '') ?? pieces,
          measures: measuresByIngredient[r['id']] ?? const <Measure>[],
          pieceBasisAmount: (r['piece_basis_amount'] as num?)?.toDouble(),
          basis: MacrosBasis.fromDb(r['macros_basis'] as String?),
        ),
    };
  }

  // --- Writes ----------------------------------------------------------------

  /// Finds the live entry for [ingredientId] **on the week [weekKey]** or
  /// creates one there, returning its id.
  ///
  /// Two offline devices can each create an entry for the same ingredient and
  /// merge later — no unique index guards this (one would make the offline
  /// duplicate fail upload and lose its data). Instead every device converges
  /// on the same canonical row: the *oldest* live entry (created_at, then id —
  /// the same order [buildShoppingList] merges by). When duplicates are seen
  /// here, they're folded into the canonical row losslessly — contributions
  /// re-pointed, checked propagated (any-checked) — then soft-deleted.
  Future<String> _findOrCreateIngredientEntry(
    SqliteWriteContext tx,
    String ingredientId,
    String weekKey,
  ) async {
    final rows = await tx.getAll(
      'SELECT id, checked FROM shopping_list_entry '
      'WHERE ingredient_id = ? AND week_start_date = ? AND deleted_at IS NULL '
      'ORDER BY created_at, id',
      [ingredientId, weekKey],
    );
    if (rows.isNotEmpty) {
      final canonicalId = rows.first['id'] as String;
      if (rows.length > 1) {
        final dupIds = [for (final r in rows.skip(1)) r['id'] as String];
        final anyDupChecked = rows
            .skip(1)
            .any((r) => (r['checked'] as int? ?? 0) == 1);
        final now = _now();
        final placeholders = List.filled(dupIds.length, '?').join(', ');
        // Keep the duplicates' manual top-ups by re-pointing them first.
        await tx.execute(
          'UPDATE shopping_list_contribution SET entry_id = ?, updated_at = ? '
          'WHERE entry_id IN ($placeholders) AND deleted_at IS NULL',
          [canonicalId, now, ...dupIds],
        );
        if (anyDupChecked) {
          await tx.execute(
            'UPDATE shopping_list_entry SET checked = 1, updated_at = ? '
            'WHERE id = ? AND checked = 0',
            [now, canonicalId],
          );
        }
        await tx.execute(
          'UPDATE shopping_list_entry SET deleted_at = ?, updated_at = ? '
          'WHERE id IN ($placeholders)',
          [now, now, ...dupIds],
        );
      }
      return canonicalId;
    }

    final id = _uuid.v4();
    final now = _now();
    await tx.execute(
      'INSERT INTO shopping_list_entry '
      '(id, household_id, ingredient_id, checked, week_start_date, '
      'created_at, updated_at) VALUES (?, ?, ?, 0, ?, ?, ?)',
      [id, _householdId, ingredientId, weekKey, now, now],
    );
    return id;
  }

  @override
  Future<void> setIngredientChecked({
    required String ingredientId,
    required bool checked,
    required DateTime weekStart,
  }) async {
    final flag = checked ? 1 : 0;
    final key = _weekKey(weekStart);
    await _db.writeTransaction((tx) async {
      final entryId = await _findOrCreateIngredientEntry(tx, ingredientId, key);
      await tx.execute(
        'UPDATE shopping_list_entry SET checked = ?, updated_at = ? '
        'WHERE id = ?',
        [flag, _now(), entryId],
      );
    });
  }

  @override
  Future<void> setEntryChecked({
    required String entryId,
    required bool checked,
  }) async {
    final flag = checked ? 1 : 0;
    await _db.execute(
      'UPDATE shopping_list_entry SET checked = ?, updated_at = ? WHERE id = ?',
      [flag, _now(), entryId],
    );
  }

  @override
  Future<void> addTopUp({
    required String ingredientId,
    required double quantity,
    required Unit unit,
    required DateTime weekStart,
    String? measureId,
  }) async {
    final key = _weekKey(weekStart);
    await _db.writeTransaction((tx) async {
      final entryId = await _findOrCreateIngredientEntry(tx, ingredientId, key);
      final now = _now();
      await tx.execute(
        'INSERT INTO shopping_list_contribution '
        '(id, household_id, entry_id, source_type, quantity, unit, '
        'measure_id, created_at, updated_at) '
        "VALUES (?, ?, ?, 'manual', ?, ?, ?, ?, ?)",
        [
          _uuid.v4(),
          _householdId,
          entryId,
          quantity,
          unit.id,
          measureId,
          now,
          now,
        ],
      );
    });
  }

  @override
  Future<void> editContribution({
    required String contributionId,
    required double quantity,
    required Unit unit,
    String? measureId,
  }) async {
    await _db.execute(
      'UPDATE shopping_list_contribution SET quantity = ?, unit = ?, '
      'measure_id = ?, updated_at = ? WHERE id = ?',
      [quantity, unit.id, measureId, _now(), contributionId],
    );
  }

  @override
  Future<void> removeContribution({required String contributionId}) async {
    final now = _now();
    await _db.execute(
      'UPDATE shopping_list_contribution SET deleted_at = ?, updated_at = ? '
      'WHERE id = ?',
      [now, now, contributionId],
    );
  }

  @override
  Future<void> addFreeTextItem({
    required String text,
    required DateTime weekStart,
    String? category,
  }) async {
    final now = _now();
    await _db.execute(
      'INSERT INTO shopping_list_entry '
      '(id, household_id, free_text, category, checked, week_start_date, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, 0, ?, ?, ?)',
      [_uuid.v4(), _householdId, text, category, _weekKey(weekStart), now, now],
    );
  }

  @override
  Future<void> removeEntry({required String entryId}) async {
    final now = _now();
    await _db.writeTransaction((tx) async {
      await tx.execute(
        'UPDATE shopping_list_entry SET deleted_at = ?, updated_at = ? '
        'WHERE id = ?',
        [now, now, entryId],
      );
      await tx.execute(
        'UPDATE shopping_list_contribution SET deleted_at = ?, updated_at = ? '
        'WHERE entry_id = ?',
        [now, now, entryId],
      );
    });
  }

  String _now() => DateTime.now().toUtc().toIso8601String();
}
