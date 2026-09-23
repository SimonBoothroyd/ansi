/// [RecipeRepository] over the local PowerSync SQLite.
///
/// Reads assemble recipe, group and line-item rows into the aggregate and react
/// to local writes via `watch`. `saveRecipe` diffs a recipe's children against
/// the stored tree in a transaction. Deletes are soft.
library;

import 'dart:convert';

import 'package:sqlite3/common.dart' show Row;
import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import '../../ingredients/data/price_repository_impl.dart' show loadCostPrices;
import '../../ingredients/domain/price.dart';
import '../domain/component_math.dart';
import '../domain/method_step.dart';
import '../domain/recipe.dart';
import '../domain/recipe_cost.dart';
import '../domain/recipe_macros.dart';
import '../domain/recipe_measure_authoring.dart' show offeredRecipeMeasures;
import '../domain/recipe_repository.dart';
import 'recipe_measure_repository_impl.dart'
    show loadRecipeMeasures, writeRecipeMeasures;

class SqliteRecipeRepository implements RecipeRepository {
  const SqliteRecipeRepository(this._db, {required String householdId})
    : _householdId = householdId;

  final SqliteConnection _db;

  /// The household stamped on rows this repo writes.
  final String _householdId;

  @override
  Stream<List<RecipeSummary>> watchRecipes() {
    // The summaries carry computed macros, so the watch must fire on every
    // table the load reads. Each LEFT JOIN selects a column: SQLite omits a
    // join whose columns go unused, and an omitted join is an unwatched table.
    // Rows are ignored; each fire re-loads.
    return _db
        .watch(
          'SELECT r.id, g.id, li.id, ing.id, im.id, sub.title, rm.id '
          'FROM recipe r '
          'LEFT JOIN ingredient_group g ON g.recipe_id = r.id '
          'LEFT JOIN recipe_line_item li ON li.group_id = g.id '
          'LEFT JOIN ingredient ing ON ing.id = li.ingredient_id '
          'LEFT JOIN ingredient_measure im ON im.id = li.measure_id '
          'LEFT JOIN recipe sub ON sub.id = li.sub_recipe_id '
          // A component line said in one of its target's words resolves through
          // that word, so a measure change moves a summary's macros.
          'LEFT JOIN recipe_measure rm ON rm.recipe_id = sub.id '
          'WHERE r.deleted_at IS NULL',
        )
        .asyncMap((_) => _loadSummaries());
  }

  /// Every recipe's cost, keyed by id. A separate read from [watchRecipes]: a
  /// cost moves when a receipt lands, and a macro summary never carries money
  /// (ADR-0017).
  @override
  Stream<Map<String, RecipeCostSummary>> watchRecipeCosts() {
    // Every table the load reads, each with a selected column: an unselected
    // LEFT JOIN is dropped by SQLite and never triggers the watch.
    return _db
        .watch(
          'SELECT r.id, g.id, li.id, ing.id, im.id, sub.title, rm.id, '
          'rl.id, rc.id FROM recipe r '
          'LEFT JOIN ingredient_group g ON g.recipe_id = r.id '
          'LEFT JOIN recipe_line_item li ON li.group_id = g.id '
          'LEFT JOIN ingredient ing ON ing.id = li.ingredient_id '
          'LEFT JOIN ingredient_measure im ON im.id = li.measure_id '
          'LEFT JOIN recipe sub ON sub.id = li.sub_recipe_id '
          // What a measured component line costs is a share of the target's
          // batch, and the word is what says which share.
          'LEFT JOIN recipe_measure rm ON rm.recipe_id = sub.id '
          'LEFT JOIN receipt_line rl ON rl.ingredient_id = li.ingredient_id '
          'LEFT JOIN receipt rc ON rc.id = rl.receipt_id '
          'WHERE r.deleted_at IS NULL',
        )
        .asyncMap((_) => _loadCosts());
  }

  Future<Map<String, RecipeCostSummary>> _loadCosts() async {
    final (nodes, nutrition) = await loadRecipeMacroNodes(_db);
    final pricingOf = pricingResolver(nutrition, await loadCostPrices(_db));
    return {
      for (final entry in nodes.entries)
        entry.key: summarizeRecipeCost(
          servingsBase: entry.value.servingsBase,
          lines: entry.value.lines,
          pricingOf: pricingOf,
          subRecipeOf: (id) => nodes[id],
        ),
    };
  }

  Future<List<RecipeSummary>> _loadSummaries() async {
    final recipeRows = await _db.getAll(
      'SELECT id, title, servings_base, keeps_for_days, freezable, '
      'freezer_days, favorite, yield_qty, yield_unit, yield_qty_2, '
      'yield_unit_2 FROM recipe '
      'WHERE deleted_at IS NULL ORDER BY created_at DESC',
    );
    // Every live line item with its ingredient's nutrition and measure, in one
    // pass across all recipes. A component line joins its target for the title
    // and yields instead.
    final measuresByRecipe = await loadRecipeMeasures(_db);
    final lineRows = await _db.getAll(
      'SELECT g.recipe_id, li.id, li.ingredient_id, li.sub_recipe_id, '
      'li.quantity, li.unit, li.recipe_measure_id, li.optional, '
      'li.measure_id, im.label AS m_label, im.basis_amount AS m_amount, '
      'im.sort_order AS m_sort, im.source AS m_source, '
      'ing.canonical_name AS ing_name, '
      'ing.macros, ing.macros_basis, ing.density_g_per_ml, '
      'ing.piece_basis_amount, ing.status, '
      'sub.title AS sub_title, sub.yield_qty AS sub_yield_qty, '
      'sub.yield_unit AS sub_yield_unit, sub.yield_qty_2 AS sub_yield_qty_2, '
      'sub.yield_unit_2 AS sub_yield_unit_2 '
      'FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id AND g.deleted_at IS NULL '
      'LEFT JOIN ingredient ing '
      'ON ing.id = li.ingredient_id AND ing.deleted_at IS NULL '
      'LEFT JOIN ingredient_measure im '
      'ON im.id = li.measure_id AND im.deleted_at IS NULL '
      'LEFT JOIN recipe sub '
      'ON sub.id = li.sub_recipe_id AND sub.deleted_at IS NULL '
      'WHERE li.deleted_at IS NULL',
    );

    final linesByRecipe = <String, List<LineItem>>{};
    final nutritionByIngredient = <String, IngredientNutrition>{};
    for (final r in lineRows) {
      final measureId = r['measure_id'] as String?;
      final measureLabel = r['m_label'] as String?;
      final measureAmount = (r['m_amount'] as num?)?.toDouble();
      (linesByRecipe[r['recipe_id'] as String] ??= []).add(
        LineItem(
          id: r['id'] as String,
          ingredientId: r['ingredient_id'] as String?,
          subRecipeId: r['sub_recipe_id'] as String?,
          subRecipe: _toSubRecipeTarget(r, measuresByRecipe),
          // The name is carried because a macro summary names the lines it is
          // waiting on.
          ingredientName:
              r['sub_title'] as String? ?? r['ing_name'] as String? ?? '',
          unit: _lineUnit(r),
          recipeMeasureId: r['recipe_measure_id'] as String?,
          quantity: (r['quantity'] as num?)?.toDouble(),
          optional: _flag(r['optional']),
          measureId: measureId,
          // Full construction incl. sort_order/source (the 51c80b9 rule:
          // every loader selects what Measure's == compares).
          measure:
              measureId == null || measureLabel == null || measureAmount == null
              ? null
              : Measure(
                  id: measureId,
                  label: measureLabel,
                  amount: measureAmount,
                  // The line ingredient's basis denominates its measures
                  // (ADR-0008); a tombstoned ingredient falls back per-g.
                  basis: MacrosBasis.fromDb(r['macros_basis'] as String?),
                  sortOrder: (r['m_sort'] as int?) ?? 0,
                  source: r['m_source'] as String?,
                ),
        ),
      );
      // A tombstoned or unknown ingredient has a null status from the LEFT
      // JOIN, so its lines read as stubs. A component line is summed through
      // its target.
      final ingredientId = r['ingredient_id'] as String?;
      if (ingredientId != null && r['status'] != null) {
        nutritionByIngredient[ingredientId] = (
          // A stub's macros are excluded even if a value lingers on the row —
          // status is the source of truth for completeness (invariant 3).
          macros: r['status'] == 'complete'
              ? Macros.tryParse(r['macros'] as String?)
              : null,
          basis: MacrosBasis.fromDb(r['macros_basis'] as String?),
          densityGPerMl: (r['density_g_per_ml'] as num?)?.toDouble(),
          pieceBasisAmount: (r['piece_basis_amount'] as num?)?.toDouble(),
        );
      }
    }

    // Every recipe as a possible component TARGET, so the macro summation can
    // walk into one without a second pass over the database.
    final nodes = <String, SubRecipeNode>{
      for (final r in recipeRows)
        r['id'] as String: (
          servingsBase: (r['servings_base'] as num).toDouble(),
          lines: linesByRecipe[r['id']] ?? const <LineItem>[],
          yields: _yieldsOf(r),
          measures: measuresByRecipe[r['id']] ?? const <RecipeMeasure>[],
        ),
    };

    return [
      for (final r in recipeRows)
        RecipeSummary(
          id: r['id'] as String,
          title: r['title'] as String,
          servingsBase: (r['servings_base'] as num).toDouble(),
          keepsForDays: r['keeps_for_days'] as int?,
          freezable: (r['freezable'] as int? ?? 0) == 1,
          freezerDays: r['freezer_days'] as int?,
          favorite: (r['favorite'] as int? ?? 0) == 1,
          yieldQty: (r['yield_qty'] as num?)?.toDouble(),
          yieldUnit: unitById(r['yield_unit'] as String? ?? ''),
          yieldQty2: (r['yield_qty_2'] as num?)?.toDouble(),
          yieldUnit2: unitById(r['yield_unit_2'] as String? ?? ''),
          // Carried so [RecipeSummary.asSubRecipeTarget] can hand the measures
          // on.
          measures: measuresByRecipe[r['id']] ?? const <RecipeMeasure>[],
          macros: summarizeRecipeMacros(
            servingsBase: (r['servings_base'] as num).toDouble(),
            lines: linesByRecipe[r['id']] ?? const [],
            nutritionOf: (id) => nutritionByIngredient[id],
            subRecipeOf: (id) => nodes[id],
          ),
        ),
    ];
  }

  /// The component target joined onto a line row as `sub_title` /
  /// `sub_yield_*`, or null for an ingredient line or a missing target row.
  SubRecipeTarget? _toSubRecipeTarget(
    Row r,
    Map<String, List<RecipeMeasure>> measuresByRecipe,
  ) {
    final id = r['sub_recipe_id'] as String?;
    final title = r['sub_title'] as String?;
    if (id == null || title == null) return null;
    return SubRecipeTarget(
      id: id,
      title: title,
      yieldQty: (r['sub_yield_qty'] as num?)?.toDouble(),
      yieldUnit: unitById(r['sub_yield_unit'] as String? ?? ''),
      yieldQty2: (r['sub_yield_qty_2'] as num?)?.toDouble(),
      yieldUnit2: unitById(r['sub_yield_unit_2'] as String? ?? ''),
      // The target's own measures come from the batched map: one query for
      // every recipe rather than one per line.
      measures: measuresByRecipe[id] ?? const <RecipeMeasure>[],
    );
  }

  @override
  Stream<Recipe?> watchRecipe(String id) {
    // Every table [_loadRecipe] reads must be a source of this watched query,
    // including ingredient (names and nutrition) and book/section (the
    // breadcrumb). Each joined table must also select a column: SQLite omits a
    // LEFT JOIN whose columns go unused, and the table then never triggers.
    // Rows are ignored; each fire re-assembles the recipe.
    return _db
        .watch(
          'SELECT r.id, g.id, li.id, ing.canonical_name, im.label, b.name, '
          's.name, sub.title, rm.label '
          'FROM recipe r '
          'LEFT JOIN ingredient_group g ON g.recipe_id = r.id '
          'LEFT JOIN recipe_line_item li ON li.group_id = g.id '
          'LEFT JOIN ingredient ing ON ing.id = li.ingredient_id '
          'LEFT JOIN ingredient_measure im ON im.id = li.measure_id '
          // A component line's target: a rename or yield edit on it must
          // re-fire this page. A column is selected to keep the join alive.
          'LEFT JOIN recipe sub ON sub.id = li.sub_recipe_id '
          // The measures this recipe coins and the ones its component targets
          // coin; a change to either must re-assemble the page.
          'LEFT JOIN recipe_measure rm '
          'ON rm.recipe_id = r.id OR rm.recipe_id = sub.id '
          'LEFT JOIN book b ON b.id = r.book_id '
          'LEFT JOIN book_section s ON s.id = r.section_id '
          'WHERE r.id = ? AND r.deleted_at IS NULL LIMIT 1',
          parameters: [id],
        )
        .asyncMap((_) => _loadRecipe(id));
  }

  Future<Recipe?> _loadRecipe(String id) async {
    final r = await _db.getOptional(
      // Join the filing book/section for the recipe page's hero line. LEFT
      // joins + deleted_at guards so a deleted section (or none) reads as null.
      'SELECT r.*, b.name AS book_name, s.name AS section_name '
      'FROM recipe r '
      'LEFT JOIN book b ON b.id = r.book_id AND b.deleted_at IS NULL '
      'LEFT JOIN book_section s '
      'ON s.id = r.section_id AND s.deleted_at IS NULL '
      'WHERE r.id = ? AND r.deleted_at IS NULL',
      [id],
    );
    if (r == null) return null;

    final groupRows = await _db.getAll(
      'SELECT * FROM ingredient_group '
      'WHERE recipe_id = ? AND deleted_at IS NULL '
      'ORDER BY sort_order, created_at',
      [id],
    );
    final itemRows = await _db.getAll(
      // The nutrition columns feed the recipe page's macro panel, through the
      // same summation the picker rows use.
      'SELECT li.*, ing.canonical_name AS ingredient_name, '
      'ing.macros_basis AS ingredient_basis, ing.macros AS ingredient_macros, '
      'ing.density_g_per_ml AS ingredient_density, '
      'ing.piece_basis_amount AS ingredient_piece_weight, '
      'ing.status AS ingredient_status, '
      'ing.deleted_at AS ingredient_deleted_at, '
      'im.label AS measure_label, im.basis_amount AS measure_amount, '
      'im.sort_order AS measure_sort, im.source AS measure_source, '
      // The same measure without the liveness guard, so an unresolved
      // measure_id can be told apart as deleted or not yet synced. A column is
      // selected so the join stays watched.
      'imx.deleted_at AS measure_deleted_at, '
      // The component target: title and yields. Its measures arrive batched,
      // not joined here.
      'sub.title AS sub_title, sub.yield_qty AS sub_yield_qty, '
      'sub.yield_unit AS sub_yield_unit, sub.yield_qty_2 AS sub_yield_qty_2, '
      'sub.yield_unit_2 AS sub_yield_unit_2 '
      'FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id '
      'LEFT JOIN ingredient ing ON ing.id = li.ingredient_id '
      'LEFT JOIN ingredient_measure im '
      'ON im.id = li.measure_id AND im.deleted_at IS NULL '
      'LEFT JOIN ingredient_measure imx ON imx.id = li.measure_id '
      'LEFT JOIN recipe sub '
      'ON sub.id = li.sub_recipe_id AND sub.deleted_at IS NULL '
      'WHERE g.recipe_id = ? AND li.deleted_at IS NULL '
      'ORDER BY li.sort_order, li.created_at',
      [id],
    );

    final measuresByRecipe = await loadRecipeMeasures(_db);
    final itemsByGroup = <String, List<LineItem>>{};
    final lines = <LineItem>[];
    final nutritionByIngredient = <String, IngredientNutrition>{};
    for (final row in itemRows) {
      final line = _toLineItem(row, measuresByRecipe);
      lines.add(line);
      (itemsByGroup[row['group_id'] as String] ??= []).add(line);
      // A tombstoned or unknown ingredient contributes no nutrition, so its
      // lines read as stubs, matching the picker rows.
      final rowIngredientId = row['ingredient_id'] as String?;
      if (rowIngredientId != null &&
          row['ingredient_status'] != null &&
          row['ingredient_deleted_at'] == null) {
        nutritionByIngredient[rowIngredientId] = (
          // A stub's macros are excluded even if a value lingers on the row —
          // status is the source of truth for completeness (invariant 3).
          macros: row['ingredient_status'] == 'complete'
              ? Macros.tryParse(row['ingredient_macros'] as String?)
              : null,
          basis: MacrosBasis.fromDb(row['ingredient_basis'] as String?),
          densityGPerMl: (row['ingredient_density'] as num?)?.toDouble(),
          pieceBasisAmount: (row['ingredient_piece_weight'] as num?)
              ?.toDouble(),
        );
      }
    }

    // Only a recipe with a component line pays for the macro walk's extra read.
    final (subNodes, subNutrition) = lines.any((l) => l.isComponent)
        ? await _loadSubRecipeNodes()
        : (
            const <String, SubRecipeNode>{},
            const <String, IngredientNutrition>{},
          );
    // The walked recipes' own vocab, so a sub-recipe's lines sum against the
    // same nutrition the parent's do.
    nutritionByIngredient.addAll(subNutrition);

    final (plainSteps, methodSteps) = _parseSteps(r['steps'] as String?);
    return Recipe(
      id: r['id'] as String,
      title: r['title'] as String,
      servingsBase: (r['servings_base'] as num).toDouble(),
      steps: plainSteps,
      methodSteps: methodSteps,
      keepsForDays: r['keeps_for_days'] as int?,
      freezable: (r['freezable'] as int? ?? 0) == 1,
      freezerDays: r['freezer_days'] as int?,
      bookId: r['book_id'] as String?,
      sectionId: r['section_id'] as String?,
      bookName: r['book_name'] as String?,
      sectionName: r['section_name'] as String?,
      yieldQty: (r['yield_qty'] as num?)?.toDouble(),
      yieldUnit: unitById(r['yield_unit'] as String? ?? ''),
      yieldQty2: (r['yield_qty_2'] as num?)?.toDouble(),
      yieldUnit2: unitById(r['yield_unit_2'] as String? ?? ''),
      // This recipe's own measures as the editor lists them: each word once,
      // merge-hidden twins absent. Resolution reads the target's full list
      // instead.
      measures: offeredRecipeMeasures(
        measuresByRecipe[id] ?? const <RecipeMeasure>[],
      ),
      cookTimeSeconds: r['cook_time_seconds'] as int?,
      totalTimeSeconds: r['total_time_seconds'] as int?,
      macros: summarizeRecipeMacros(
        servingsBase: (r['servings_base'] as num).toDouble(),
        lines: lines,
        nutritionOf: (id) => nutritionByIngredient[id],
        subRecipeOf: (id) => subNodes[id],
      ),
      groups: [
        for (final g in groupRows)
          IngredientGroup(
            id: g['id'] as String,
            name: g['name'] as String?,
            items: itemsByGroup[g['id']] ?? const [],
          ),
      ],
    );
  }

  LineItem _toLineItem(
    Row r,
    Map<String, List<RecipeMeasure>> measuresByRecipe,
  ) {
    // The measure resolves only when its row is live locally; the raw
    // measure_id is kept regardless so a save never strips it (see [LineItem]).
    final measureId = r['measure_id'] as String?;
    final measureLabel = r['measure_label'] as String?;
    final measureAmount = (r['measure_amount'] as num?)?.toDouble();
    final subRecipeId = r['sub_recipe_id'] as String?;
    return LineItem(
      id: r['id'] as String,
      ingredientId: r['ingredient_id'] as String?,
      subRecipeId: subRecipeId,
      subRecipe: _toSubRecipeTarget(r, measuresByRecipe),
      // A component line's name is its target's title; a missing target reads
      // as unknown and derives nothing.
      ingredientName: subRecipeId != null
          ? r['sub_title'] as String? ?? '(unknown recipe)'
          : r['ingredient_name'] as String? ?? '(unknown ingredient)',
      unit: _lineUnit(r),
      recipeMeasureId: r['recipe_measure_id'] as String?,
      quantity: (r['quantity'] as num?)?.toDouble(),
      optional: _flag(r['optional']),
      measureId: measureId,
      // Null on every query that does not ask (the flag is a display fact,
      // and the surfaces that print it all read this one).
      measureDeleted: r['measure_deleted_at'] != null,
      // The vocab row is joined without the liveness guard so a retired
      // ingredient keeps its last name; this flag marks it as retired.
      ingredientDeleted: r['ingredient_deleted_at'] != null,
      measure:
          measureId == null || measureLabel == null || measureAmount == null
          ? null
          : Measure(
              id: measureId,
              label: measureLabel,
              amount: measureAmount,
              // The line ingredient's basis denominates its measures
              // (ADR-0008); a tombstoned ingredient falls back per-g.
              basis: MacrosBasis.fromDb(r['ingredient_basis'] as String?),
              sortOrder: (r['measure_sort'] as int?) ?? 0,
              source: r['measure_source'] as String?,
            ),
      note: r['note'] as String?,
    );
  }

  Future<(Map<String, SubRecipeNode>, Map<String, IngredientNutrition>)>
  _loadSubRecipeNodes() => loadRecipeMacroNodes(_db);

  @override
  Future<List<RecipeUse>> usedIn(String recipeId) async {
    // The count returned is also the count the delete refusal speaks. Every
    // line below points at this recipe, so one merged measure lookup answers
    // all of them.
    final measures =
        (await loadRecipeMeasures(_db))[recipeId] ?? const <RecipeMeasure>[];
    final rows = await _db.getAll(
      'SELECT li.id, li.quantity, li.unit, li.recipe_measure_id, '
      'g.recipe_id, r.title, '
      'target.yield_qty, target.yield_unit, target.yield_qty_2, '
      'target.yield_unit_2 '
      'FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id AND g.deleted_at IS NULL '
      'JOIN recipe r ON r.id = g.recipe_id AND r.deleted_at IS NULL '
      'JOIN recipe target ON target.id = li.sub_recipe_id '
      'WHERE li.sub_recipe_id = ? AND li.deleted_at IS NULL '
      'ORDER BY r.title, li.sort_order',
      [recipeId],
    );
    return [
      for (final r in rows)
        RecipeUse(
          lineId: r['id'] as String,
          recipeId: r['recipe_id'] as String,
          title: r['title'] as String,
          quantity: (r['quantity'] as num?)?.toDouble(),
          // Null exactly on a line said in one of this recipe's own words.
          // Never defaulted: `batch` would turn three blobs into three batches.
          unit: unitById(r['unit'] as String? ?? ''),
          // The word while this recipe still has it; null once retired.
          measureLabel: switch (r['recipe_measure_id'] as String?) {
            final id? => recipeMeasureById(id, measures)?.label,
            _ => null,
          },
          amount: resolveComponentAmount(
            quantity: (r['quantity'] as num?)?.toDouble(),
            unit: unitById(r['unit'] as String? ?? ''),
            yields: yieldDenominations(
              (r['yield_qty'] as num?)?.toDouble(),
              unitById(r['yield_unit'] as String? ?? ''),
              (r['yield_qty_2'] as num?)?.toDouble(),
              unitById(r['yield_unit_2'] as String? ?? ''),
            ),
            recipeMeasureId: r['recipe_measure_id'] as String?,
            measures: measures,
          ),
        ),
    ];
  }

  @override
  Future<bool> componentLinkWouldCycle({
    required String recipeId,
    required String subRecipeId,
  }) async {
    final rows = await _db.getAll(
      'SELECT g.recipe_id, li.sub_recipe_id FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id AND g.deleted_at IS NULL '
      'JOIN recipe r ON r.id = g.recipe_id AND r.deleted_at IS NULL '
      'WHERE li.sub_recipe_id IS NOT NULL AND li.deleted_at IS NULL',
    );
    final edges = <String, List<String>>{};
    for (final r in rows) {
      (edges[r['recipe_id'] as String] ??= []).add(
        r['sub_recipe_id'] as String,
      );
    }
    return closesComponentCycle(
      from: recipeId,
      to: subRecipeId,
      componentsOf: (id) => edges[id] ?? const [],
    );
  }

  /// Reads the `steps` jsonb: an array of plain-text strings, or an array of
  /// tokenized step objects (objects with `tokens`), never both.
  (List<String>, List<MethodStep>?) _parseSteps(String? raw) {
    final decoded = jsonDecode(raw ?? '[]');
    if (decoded is! List || decoded.isEmpty) return (const [], null);
    if (decoded.first is String) return (decoded.cast<String>(), null);
    return (
      const <String>[],
      [
        for (final e in decoded)
          MethodStep.fromJson((e as Map).cast<String, Object?>()),
      ],
    );
  }

  /// What the `steps` jsonb is written as. The tokenized shape wins whenever
  /// present: an imported recipe's plain [Recipe.steps] is empty, so writing it
  /// would erase the method.
  Object _stepsJson(Recipe recipe) {
    final tokenized = recipe.methodSteps;
    if (tokenized == null) return recipe.steps;
    return [for (final step in tokenized) step.toJson()];
  }

  @override
  Future<void> saveRecipe(Recipe recipe) async {
    // Refused before anything is written: the server rejects a line that fails
    // `num_nonnulls(unit, recipe_measure_id) = 1`, and a rejected upload makes
    // the connector drop the whole crud transaction.
    final columnsByLine = <String, _LineColumns>{};
    for (final group in recipe.groups) {
      for (final item in group.items) {
        final columns = _lineColumnsOf(item);
        if (columns.unit == null && columns.recipeMeasureId == null) {
          throw UndenominatedLineError(
            lineId: item.id,
            name: item.ingredientName,
          );
        }
        // A word needs a count beside it; the server's
        // `line_item_recipe_measure_needs_amount` rejects a row without one.
        if (columns.recipeMeasureId != null && item.quantity == null) {
          throw AmountlessLineError(lineId: item.id, name: item.ingredientName);
        }
        columnsByLine[item.id] = columns;
      }
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final steps = jsonEncode(_stepsJson(recipe));
    final freezable = recipe.freezable ? 1 : 0;
    await _db.writeTransaction((tx) async {
      // PowerSync's local tables are views with INSTEAD OF triggers, which
      // reject `INSERT ... ON CONFLICT`. Branch on existence and issue a plain
      // INSERT or UPDATE.
      final exists = await tx.getOptional('SELECT 1 FROM recipe WHERE id = ?', [
        recipe.id,
      ]);
      if (exists == null) {
        await tx.execute(
          'INSERT INTO recipe (id, household_id, title, servings_base, steps, '
          'keeps_for_days, freezable, freezer_days, book_id, section_id, '
          'yield_qty, yield_unit, yield_qty_2, yield_unit_2, '
          'cook_time_seconds, total_time_seconds, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            recipe.id,
            _householdId,
            recipe.title,
            recipe.servingsBase,
            steps,
            recipe.keepsForDays,
            freezable,
            recipe.freezerDays,
            recipe.bookId,
            recipe.sectionId,
            recipe.yieldQty,
            recipe.yieldUnit?.id,
            recipe.yieldQty2,
            recipe.yieldUnit2?.id,
            recipe.cookTimeSeconds,
            recipe.totalTimeSeconds,
            now,
            now,
          ],
        );
      } else {
        await tx.execute(
          'UPDATE recipe SET title = ?, servings_base = ?, steps = ?, '
          'keeps_for_days = ?, freezable = ?, freezer_days = ?, book_id = ?, '
          'section_id = ?, yield_qty = ?, yield_unit = ?, yield_qty_2 = ?, '
          'yield_unit_2 = ?, cook_time_seconds = ?, total_time_seconds = ?, '
          'updated_at = ? WHERE id = ?',
          [
            recipe.title,
            recipe.servingsBase,
            steps,
            recipe.keepsForDays,
            freezable,
            recipe.freezerDays,
            recipe.bookId,
            recipe.sectionId,
            recipe.yieldQty,
            recipe.yieldUnit?.id,
            recipe.yieldQty2,
            recipe.yieldUnit2?.id,
            recipe.cookTimeSeconds,
            recipe.totalTimeSeconds,
            now,
            recipe.id,
          ],
        );
      }

      // The recipe's measures, diffed like every other child and written before
      // the lines: the server requires a line's measure to already exist and be
      // live.
      //
      // This door rides the form's Save (ADR-0011). The component dock's ＋
      // writes on tap through [RecipeMeasureRepository].
      await writeRecipeMeasures(
        tx,
        recipeId: recipe.id,
        householdId: _householdId,
        measures: recipe.measures,
        now: now,
      );

      // Diff the children rather than delete + re-insert: PowerSync queues ops
      // literally and the connector maps DELETE to a server tombstone, so
      // replacing kept ids would soft-delete them everywhere. Kept ids become
      // UPDATEs, new ids INSERTs, dropped ids soft-deletes.
      final oldGroupRows = await tx.getAll(
        'SELECT id, deleted_at FROM ingredient_group WHERE recipe_id = ?',
        [recipe.id],
      );
      final oldItemRows = await tx.getAll(
        'SELECT li.id, li.deleted_at FROM recipe_line_item li '
        'JOIN ingredient_group g ON g.id = li.group_id WHERE g.recipe_id = ?',
        [recipe.id],
      );
      final oldGroupIds = {for (final r in oldGroupRows) r['id'] as String};
      final oldItemIds = {for (final r in oldItemRows) r['id'] as String};
      final keptGroupIds = {for (final g in recipe.groups) g.id};
      final keptItemIds = {
        for (final g in recipe.groups)
          for (final i in g.items) i.id,
      };

      // Soft-delete dropped children (items first — they hang off the groups).
      // Rows that are already tombstoned are left alone rather than re-stamped.
      for (final r in oldItemRows) {
        final id = r['id'] as String;
        if (!keptItemIds.contains(id) && r['deleted_at'] == null) {
          await tx.execute(
            'UPDATE recipe_line_item SET deleted_at = ?, updated_at = ? '
            'WHERE id = ?',
            [now, now, id],
          );
        }
      }
      for (final r in oldGroupRows) {
        final id = r['id'] as String;
        if (!keptGroupIds.contains(id) && r['deleted_at'] == null) {
          await tx.execute(
            'UPDATE ingredient_group SET deleted_at = ?, updated_at = ? '
            'WHERE id = ?',
            [now, now, id],
          );
        }
      }

      for (var gi = 0; gi < recipe.groups.length; gi++) {
        final group = recipe.groups[gi];
        if (oldGroupIds.contains(group.id)) {
          // Clearing deleted_at revives a group whose id is being reused.
          await tx.execute(
            'UPDATE ingredient_group SET name = ?, sort_order = ?, '
            'updated_at = ?, deleted_at = NULL WHERE id = ?',
            [group.name, gi, now, group.id],
          );
        } else {
          await tx.execute(
            'INSERT INTO ingredient_group (id, household_id, recipe_id, name, '
            'sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [group.id, _householdId, recipe.id, group.name, gi, now, now],
          );
        }
        for (var li = 0; li < group.items.length; li++) {
          final item = group.items[li];
          // The two XORs, written rather than assumed — see [_lineColumnsOf].
          final columns = columnsByLine[item.id]!;
          if (oldItemIds.contains(item.id)) {
            // group_id is included: an item can move between groups.
            await tx.execute(
              'UPDATE recipe_line_item SET group_id = ?, ingredient_id = ?, '
              'sub_recipe_id = ?, quantity = ?, unit = ?, measure_id = ?, '
              'recipe_measure_id = ?, note = ?, optional = ?, '
              'sort_order = ?, updated_at = ?, deleted_at = NULL WHERE id = ?',
              [
                group.id,
                columns.ingredientId,
                columns.subRecipeId,
                item.quantity,
                columns.unit,
                columns.measureId,
                columns.recipeMeasureId,
                item.note,
                // Written on every kept line, ingredient and component alike.
                if (item.optional) 1 else 0,
                li,
                now,
                item.id,
              ],
            );
          } else {
            await tx.execute(
              'INSERT INTO recipe_line_item (id, household_id, group_id, '
              'ingredient_id, sub_recipe_id, quantity, unit, measure_id, '
              'recipe_measure_id, note, '
              'optional, sort_order, created_at, updated_at) '
              'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
              [
                item.id,
                _householdId,
                group.id,
                columns.ingredientId,
                columns.subRecipeId,
                item.quantity,
                columns.unit,
                columns.measureId,
                columns.recipeMeasureId,
                item.note,
                if (item.optional) 1 else 0,
                li,
                now,
                now,
              ],
            );
          }
        }
      }
    });
  }

  @override
  Future<void> setFavorite(String id, bool favorite) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.execute(
      'UPDATE recipe SET favorite = ?, updated_at = ? WHERE id = ?',
      [if (favorite) 1 else 0, now, id],
    );
  }

  @override
  Future<void> setFiling(String id, String bookId, String? sectionId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.execute(
      'UPDATE recipe SET book_id = ?, section_id = ?, updated_at = ? '
      'WHERE id = ?',
      [bookId, sectionId, now, id],
    );
  }

  @override
  Future<void> deleteRecipe(String id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.execute(
      'UPDATE recipe SET deleted_at = ?, updated_at = ? WHERE id = ?',
      [now, now, id],
    );
  }
}

/// The recipe row's stated yields, from the four `yield_*` columns.
List<YieldDenomination> _yieldsOf(Row r) => yieldDenominations(
  (r['yield_qty'] as num?)?.toDouble(),
  unitById(r['yield_unit'] as String? ?? ''),
  (r['yield_qty_2'] as num?)?.toDouble(),
  unitById(r['yield_unit_2'] as String? ?? ''),
);

/// A 0/1 flag column as a bool. Null (a row synced from a server that had not
/// yet learned the column) reads as false — the column's own default.
bool _flag(Object? v) => v == 1 || v == true;

/// The catalog unit a line row is denominated in, or null when the row names a
/// recipe measure (`recipe_measure_id`).
///
/// The word is asked first, so a row carrying both columns reads as the word. A
/// wordless row with an unknown unit id falls back to `pieces` rather than
/// throwing. The row must carry both `recipe_measure_id` and `unit`.
Unit? _lineUnit(Row r) => r['recipe_measure_id'] != null
    ? null
    : unitById(r['unit'] as String? ?? '') ?? pieces;

/// What one line's identity and denomination columns are written as, resolved
/// in one place against the three stored XORs.
///
/// A component line stores its target and no ingredient or ingredient measure;
/// a line said in one of the target's words stores the word and no unit. The
/// word is dropped from a non-component line, as the server does; a line left
/// with no denomination is refused by [UndenominatedLineError].
typedef _LineColumns = ({
  String? ingredientId,
  String? subRecipeId,
  String? measureId,
  String? recipeMeasureId,
  String? unit,
});

_LineColumns _lineColumnsOf(LineItem item) {
  final component = item.subRecipeId != null;
  final recipeMeasureId = component ? item.recipeMeasureId : null;
  return (
    ingredientId: component ? null : item.ingredientId,
    subRecipeId: component ? item.subRecipeId : null,
    measureId: component ? null : item.measureId,
    recipeMeasureId: recipeMeasureId,
    unit: recipeMeasureId != null ? null : item.unit?.id,
  );
}

/// Every live recipe as a macro-walk node ([SubRecipeNode]) plus the vocab
/// nutrition its lines need.
///
/// Read whole, since the walk can descend through a component of a component.
/// The recipe page reads it only when it has a component line; the week always
/// does, to re-sum each planned recipe over its effective lines.
Future<(Map<String, SubRecipeNode>, Map<String, IngredientNutrition>)>
loadRecipeMacroNodes(SqliteConnection db) async {
  final recipeRows = await db.getAll(
    'SELECT id, servings_base, yield_qty, yield_unit, yield_qty_2, '
    'yield_unit_2 FROM recipe WHERE deleted_at IS NULL',
  );
  final measuresByRecipe = await loadRecipeMeasures(db);
  final lineRows = await db.getAll(
    'SELECT g.recipe_id, li.id, li.ingredient_id, li.sub_recipe_id, '
    'li.quantity, li.unit, li.recipe_measure_id, li.optional, li.measure_id, '
    'im.label AS m_label, im.basis_amount AS m_amount, '
    'im.sort_order AS m_sort, im.source AS m_source, '
    'ing.macros, ing.macros_basis, ing.density_g_per_ml, '
    'ing.piece_basis_amount, ing.status, '
    'ing.canonical_name AS ing_name, sub.title AS sub_title '
    'FROM recipe_line_item li '
    'JOIN ingredient_group g ON g.id = li.group_id AND g.deleted_at IS NULL '
    'LEFT JOIN ingredient ing '
    'ON ing.id = li.ingredient_id AND ing.deleted_at IS NULL '
    'LEFT JOIN ingredient_measure im '
    'ON im.id = li.measure_id AND im.deleted_at IS NULL '
    'LEFT JOIN recipe sub '
    'ON sub.id = li.sub_recipe_id AND sub.deleted_at IS NULL '
    'WHERE li.deleted_at IS NULL',
  );

  final linesByRecipe = <String, List<LineItem>>{};
  final nutrition = <String, IngredientNutrition>{};
  for (final r in lineRows) {
    final measureId = r['measure_id'] as String?;
    final measureLabel = r['m_label'] as String?;
    final measureAmount = (r['m_amount'] as num?)?.toDouble();
    (linesByRecipe[r['recipe_id'] as String] ??= []).add(
      LineItem(
        id: r['id'] as String,
        ingredientId: r['ingredient_id'] as String?,
        subRecipeId: r['sub_recipe_id'] as String?,
        // Named, because a refusal names the lines it is waiting on: the
        // week's re-summations and the cost walk both print these.
        ingredientName:
            (r['ing_name'] as String?) ?? (r['sub_title'] as String?) ?? '',
        unit: _lineUnit(r),
        recipeMeasureId: r['recipe_measure_id'] as String?,
        quantity: (r['quantity'] as num?)?.toDouble(),
        // A sub-recipe's own optional lines leave ITS total the same way
        // (the walk runs the same seam at every level).
        optional: _flag(r['optional']),
        measureId: measureId,
        measure:
            measureId == null || measureLabel == null || measureAmount == null
            ? null
            : Measure(
                id: measureId,
                label: measureLabel,
                amount: measureAmount,
                basis: MacrosBasis.fromDb(r['macros_basis'] as String?),
                sortOrder: (r['m_sort'] as int?) ?? 0,
                source: r['m_source'] as String?,
              ),
      ),
    );
    final ingredientId = r['ingredient_id'] as String?;
    if (ingredientId != null && r['status'] != null) {
      nutrition[ingredientId] = (
        macros: r['status'] == 'complete'
            ? Macros.tryParse(r['macros'] as String?)
            : null,
        basis: MacrosBasis.fromDb(r['macros_basis'] as String?),
        densityGPerMl: (r['density_g_per_ml'] as num?)?.toDouble(),
        pieceBasisAmount: (r['piece_basis_amount'] as num?)?.toDouble(),
      );
    }
  }

  return (
    {
      for (final r in recipeRows)
        r['id'] as String: (
          servingsBase: (r['servings_base'] as num).toDouble(),
          lines: linesByRecipe[r['id']] ?? const <LineItem>[],
          yields: _yieldsOf(r),
          // The node's own measures, which a parent's line resolves through.
          measures: measuresByRecipe[r['id']] ?? const <RecipeMeasure>[],
        ),
    },
    nutrition,
  );
}

/// The cost walk's ingredient lookup, from the vocab's dimension facts and the
/// price each row's cost reads (`costPriceOf`).
///
/// An unknown ingredient resolves to null ([CostLineReason.noPathToBasis]); a
/// known row with no price resolves with a null price
/// ([CostLineReason.noPrice]).
IngredientPricing? Function(String) pricingResolver(
  Map<String, IngredientNutrition> nutrition,
  Map<String, UnitPrice> prices,
) => (id) {
  final row = nutrition[id];
  return row == null ? null : (row: basisOf(row), price: prices[id]);
};
