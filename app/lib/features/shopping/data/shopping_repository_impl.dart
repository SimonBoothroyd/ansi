/// [ShoppingRepository] over the local PowerSync SQLite.
///
/// The list is derived live: the cook plan ([buildCookPlan]) expands recipe
/// lines by session factor, bare-ingredient meals come from the week's entries,
/// and the week-scoped overlay goes on top ([buildShoppingList]). The watch
/// query selects a column from every table it reads, because SQLite drops an
/// unselected LEFT JOIN (`watch_coverage_test.dart`). Writes go through views,
/// which reject UPSERT.
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

/// A recipe line as the shopping list needs it. `line` is the domain [LineItem]
/// the [effectiveLines] seam rules on. `unit` is null when the persisted id is
/// unknown, and `rawUnit` keeps the string for the breakdown's note. `measure`
/// is null when the line has none or its row is missing.
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

  /// The household's week, for naming a breakdown line's day.
  final WeekShape _weekShape;

  String _weekKey(DateTime weekStart) => isoDateOf(weekStart);

  @override
  Stream<ShoppingList> watchShoppingList(DateTime weekStart) {
    final key = _weekKey(weekStart);
    // Select a column from every table the load reads so each becomes a watch
    // trigger (see the library doc). Tables not tied to the week are
    // cross-joined (`ON 1=1`) only to be seen.
    return _db
        .watch(
          'SELECT wp.id, pe.id, r.keeps_for_days, g.id, li.id, se.id, sc.id, '
          'i.id, im.id, hm.id, wro.id, rm.id '
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
          'LEFT JOIN recipe_measure rm ON 1 = 1 '
          'LEFT JOIN household_member hm ON 1 = 1 '
          'WHERE wp.week_start_date = ? AND wp.deleted_at IS NULL LIMIT 1',
          parameters: [key],
        )
        .asyncMap((_) => _load(key));
  }

  Future<ShoppingList> _load(String weekKey) async {
    final (cook, unresolved, optional, retiredLines) =
        await _deriveCookContributions(weekKey);
    // The week's own entries, not only its cook sessions.
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
      // Both walks can meet a retired row; the shopper reads one sorted list.
      retiredIngredients: [...retiredLines, ...retiredPlanned]
        ..sort((a, b) {
          final c = a.heading.compareTo(b.heading);
          return c != 0 ? c : a.ingredientName.compareTo(b.ingredientName);
        }),
    );
  }

  /// The week's bare-ingredient meals as shopping contributions. They are never
  /// cooked, so no cook session carries them.
  ///
  /// The amount is one portion multiplied by the entry's demand (the eaters'
  /// portion factors, the `portions` override winning). An entry with no amount
  /// contributes nothing; an unresolvable unit or measure becomes a breakdown
  /// note. An entry at a retired row comes back as a [RetiredIngredientNote]
  /// instead.
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
      // Entries with an ingredient only: recipe meals go through the cook
      // derivation and a meal out buys nothing. The join has no liveness guard,
      // so a retired row still yields its last known name for the echo row.
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
      // An unknown unit id stays null (rawUnit keeps the string), never a
      // `pieces` fallback the total could sum.
      final rawUnit = row['unit'] as String?;
      final unit = rawUnit == null ? null : unitById(rawUnit);
      final quantity = (row['quantity'] as num?)?.toDouble();
      final input = (
        ingredientId: row['ingredient_id'] as String,
        // The stated amount is one portion; the demand multiplies it. A measure
        // count scales the same way.
        quantity: quantity == null ? null : quantity * demand,
        unit: unit,
        rawUnit: rawUnit,
        // A measure beside an unrecognised unit is dropped: the quantity's
        // meaning is unknown, so the row surfaces as a note instead.
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

  /// Runs the cook plan for the week, then expands each session's recipe lines,
  /// scaled by the session's factor, into per-ingredient contributions.
  ///
  /// Component sessions flow through the same pipeline and carry an extra
  /// provenance segment naming the plan they serve; a component line itself
  /// never becomes an item. Lines pass through [effectiveLines] first. Returns
  /// the contributions, the unresolved-component echoes, the
  /// optional-lines-not-listed echoes, and the lines whose ingredient is
  /// retired.
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
      // Recipe meals only. A bare-ingredient meal goes through
      // [_derivePlannedIngredients]; a meal out buys nothing.
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

    // The same demand the cook plan derives: the eaters' portion factors, the
    // override winning.
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

    // Line items per recipe, read once, for every recipe the plan cooks,
    // including derived component sessions.
    final lineItems = await _loadLineItems({
      for (final r in plan.recipes) r.recipeId,
    });

    final contributions = <CookContributionInput>[];
    final optionalNotes = <OptionalLinesNote>[];
    final retiredNotes = <RetiredIngredientNote>[];
    for (final recipe in plan.recipes) {
      final batched = recipe.sessions.length > 1;
      final stored = lineItems[recipe.recipeId] ?? const <_LineItem>[];
      // The sessions below expand only the lines the seam keeps; dropped ones
      // become this recipe's echo row. The week's overrides are read once and
      // looked up per recipe.
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
      // A replaced line carries absolute values and an added one has no stored
      // row, so contributions are rebuilt from what the seam returned.
      final items = [
        for (final line in effective.kept)
          // The seam keeps a line at a retired row, but nothing about the row
          // can be shopped, so the echo names it instead.
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
      // Component lines meet the week through the same seam. A sub-recipe this
      // week does not cook buys nothing and is named by title.
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
          // An unrecognised unit cannot be scaled; the raw quantity passes
          // through and the domain keeps it out of the totals.
          final unit = item.unit;
          final scaled = item.quantity == null || unit == null
              ? null
              : scale(Quantity(item.quantity!, unit), session.scaleFactor);
          contributions.add((
            ingredientId: item.ingredientId,
            quantity: unit == null ? item.quantity : scaled?.amount,
            unit: unit,
            rawUnit: item.rawUnit,
            // A measure count scales linearly, so the scaled amount is the
            // measure amount too. A measure beside an unrecognised unit is
            // dropped, and the line surfaces as a note instead.
            measure: unit == null ? null : item.measure,
            recipeTitle: recipe.title,
            cookDay: session.cookDay,
            batched: batched,
            // The extra provenance segment, deepest first: this recipe's line,
            // then the plans it is cooked for. Empty for a meal session.
            forParents: session.demandedBy,
            // And one more when the WEEK changed this line, so the aisle says
            // why the amount is not the recipe's.
            weekNote: note,
          ));
        }
      }
    }

    // The parents whose lists are short because a component could not be
    // derived.
    final titles = {for (final r in plan.recipes) r.recipeId: r.title};
    final unresolved = <UnresolvedComponentNote>[
      for (final e in plan.unresolvedComponentsByParent.entries)
        (recipeId: e.key, recipeTitle: titles[e.key] ?? '', count: e.value),
    ]..sort((a, b) => a.recipeTitle.compareTo(b.recipeTitle));
    optionalNotes.sort((a, b) => a.recipeTitle.compareTo(b.recipeTitle));
    return (contributions, unresolved, optionalNotes, retiredNotes);
  }

  /// The seam's answer in this file's row shape. An untouched line keeps the
  /// stored row; a changed or added one is rebuilt from the domain line.
  static _LineItem _weekLine(LineItem line, _LineItem? stored) {
    if (stored != null && identical(stored.line, line)) return stored;
    return (
      line: line,
      ingredientId: line.ingredientId ?? stored?.ingredientId ?? '',
      quantity: line.quantity,
      unit: line.unit,
      rawUnit: line.unit?.id,
      measure: line.measure,
    );
  }

  /// The provenance segment this line carries, or null when the recipe states
  /// it itself.
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
      // An unknown unit id stays null (rawUnit keeps the string), never a
      // `pieces` fallback the total could sum.
      final rawUnit = row['unit'] as String?;
      final unit = rawUnit == null ? null : unitById(rawUnit);
      final measure = _toMeasure(row);
      (byRecipe[row['recipe_id'] as String] ??= []).add((
        // The domain line the seam rules on. The expansion reads the record's
        // nullable `unit`, not this line's fallback unit.
        line: LineItem(
          id: row['id'] as String,
          ingredientId: ingredientId,
          ingredientName: row['ingredient_name'] as String? ?? '',
          unit: unit ?? pieces,
          quantity: (row['quantity'] as num?)?.toDouble(),
          measureId: row['measure_id'] as String?,
          measure: measure,
          optional: row['optional'] == 1,
          // The vocab join has no liveness guard; this flag keeps a retired
          // row's name out of the aisles.
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

  /// The [Measure] of a row selected with the `measure_*` aliases, or null when
  /// the row has none. The basis is the measure's ingredient's `macros_basis`
  /// (ADR-0008).
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

  /// The week's overlay: the entries stamped with this week, and their manual
  /// contributions.
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

  /// The vocab facts for the ids in hand: name, aisle, density, measures. No
  /// liveness guard: a manual top-up against a retired row keeps its last known
  /// name.
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

  /// Finds the live entry for [ingredientId] on the week [weekKey], or creates
  /// one, and returns its id.
  ///
  /// No unique index guards this, because offline duplicates must still upload.
  /// Devices converge on the oldest live entry (created_at, then id, as
  /// [buildShoppingList] merges); duplicates seen here are folded into it
  /// (contributions re-pointed, checked if any was) and soft-deleted.
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
