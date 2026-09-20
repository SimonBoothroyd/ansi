/// [RecipeRepository] over the local PowerSync SQLite (offline in step 2).
///
/// Reads assemble the recipe/group/line-item rows into the domain aggregate and
/// react to local writes via `watch`. Writes go through `saveRecipe`, which
/// diffs a recipe's children against the stored tree (see the interface doc)
/// inside a transaction. Deletes are soft (tombstone), per spec §3.
library;

import 'dart:convert';

import 'package:sqlite3/common.dart' show Row;
import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import '../../ingredients/data/price_repository_impl.dart'
    show loadLatestPrices;
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
    // The summaries carry computed per-serving macros (step 7.7), so the
    // watch must fire on any change to the tables the load below reads —
    // groups, line items, the vocab (macros/basis/density/status) and the
    // measures. Each LEFT JOIN contributes a *selected* column: SQLite omits
    // a join whose columns go unused, and an omitted join is an undetected
    // table (the stale-breadcrumb class). Rows are ignored; each fire
    // re-loads.
    return _db
        .watch(
          'SELECT r.id, g.id, li.id, ing.id, im.id, sub.title, rm.id '
          'FROM recipe r '
          'LEFT JOIN ingredient_group g ON g.recipe_id = r.id '
          'LEFT JOIN recipe_line_item li ON li.group_id = g.id '
          'LEFT JOIN ingredient ing ON ing.id = li.ingredient_id '
          'LEFT JOIN ingredient_measure im ON im.id = li.measure_id '
          'LEFT JOIN recipe sub ON sub.id = li.sub_recipe_id '
          // A component line said in one of its target's own words resolves
          // through that word, so coining, re-stating or retiring one moves
          // a summary's macros exactly as a yield edit does.
          'LEFT JOIN recipe_measure rm ON rm.recipe_id = sub.id '
          'WHERE r.deleted_at IS NULL',
        )
        .asyncMap((_) => _loadSummaries());
  }

  /// Every recipe's cost, keyed by id — one stream for the panel, the week's
  /// band and anything else that asks what a recipe is worth.
  ///
  /// It is a SEPARATE read from [watchRecipes] on purpose. A cost moves when a
  /// receipt lands, which the summaries' watch knows nothing about, and a
  /// macro summary must never carry money (ADR-0017 / the structural test), so
  /// the two facts ride two streams and a surface reads whichever it is
  /// showing.
  @override
  Stream<Map<String, RecipeCostSummary>> watchRecipeCosts() {
    // Every table the load reads, each contributing a selected column: the
    // recipes and their lines, the vocab the conversion needs, the measures,
    // and the receipt rows the prices come off. A LEFT JOIN nothing selects
    // from is dropped by SQLite and never becomes a trigger.
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
    final pricingOf = pricingResolver(nutrition, await loadLatestPrices(_db));
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
    // Every live line item with its ingredient's nutrition and (when
    // resolved) its measure, in one pass across all recipes. A component line
    // (step 8.6) joins its target for the title and the yields the batch math
    // reads instead.
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
          // The NAME matters here as well as on the page: a macro summary
          // now names the lines it is waiting on (seam D5), and the picker
          // row and the recipe page must not disagree about what a line is
          // called.
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
      // A tombstoned/unknown ingredient never lands here (LEFT JOIN nulls its
      // status), so the lookup below treats its lines as stubs. A component
      // line has no ingredient at all and is summed through its target.
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
    // walk into one (step 8.6 / D8) without a second pass over the database.
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
          // Carried so a picker row that hands this summary on as a component
          // TARGET hands over the words with it — the reason
          // [RecipeSummary.asSubRecipeTarget] can exist at all.
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
  /// `sub_yield_*` (step 8.6), or null when the line is an ingredient line —
  /// or when its target row is missing (a dangling link degrades to plain
  /// text and derives nothing, D5).
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
      // The target's OWN words, read off the batched map rather than joined
      // onto the line: a word belongs to the recipe being used, and one
      // query for every recipe beats one per line.
      measures: measuresByRecipe[id] ?? const <RecipeMeasure>[],
    );
  }

  @override
  Stream<Recipe?> watchRecipe(String id) {
    // The triggers for this stream are the watched query's source tables, so
    // every table [_loadRecipe] reads must be one — including ingredient
    // (line-item names AND the nutrition behind the macro panel, so a vocab
    // row gaining macros/density re-fires the page) and book/section (the
    // breadcrumb). Each joined table
    // must also contribute a *selected* column: SQLite omits a LEFT JOIN whose
    // columns go unused, and an omitted join is an undetected table (the
    // stale-breadcrumb class). The rows themselves are ignored; each fire
    // re-assembles the recipe.
    return _db
        .watch(
          'SELECT r.id, g.id, li.id, ing.canonical_name, im.label, b.name, '
          's.name, sub.title, rm.label '
          'FROM recipe r '
          'LEFT JOIN ingredient_group g ON g.recipe_id = r.id '
          'LEFT JOIN recipe_line_item li ON li.group_id = g.id '
          'LEFT JOIN ingredient ing ON ing.id = li.ingredient_id '
          'LEFT JOIN ingredient_measure im ON im.id = li.measure_id '
          // A component line's target (step 8.6): its title is on the line and
          // its yields drive the batch math, so a rename or a yield edit on
          // the TARGET must re-fire this page. Selecting a column keeps the
          // join alive: SQLite drops a LEFT JOIN with no selected column, and
          // PowerSync then never registers that table as a trigger.
          'LEFT JOIN recipe sub ON sub.id = li.sub_recipe_id '
          // Both sides of the word: the ones THIS recipe coins (the page's
          // own list, and what another recipe's line may say) and the ones
          // its component targets coin, which is what a measured line here
          // resolves through. Coining, re-stating or retiring either must
          // re-assemble the page.
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
      // The nutrition columns feed the recipe page's macro panel (step 9) —
      // the same summation the picker rows use, so the two agree.
      'SELECT li.*, ing.canonical_name AS ingredient_name, '
      'ing.macros_basis AS ingredient_basis, ing.macros AS ingredient_macros, '
      'ing.density_g_per_ml AS ingredient_density, '
      'ing.piece_basis_amount AS ingredient_piece_weight, '
      'ing.status AS ingredient_status, '
      'ing.deleted_at AS ingredient_deleted_at, '
      'im.label AS measure_label, im.basis_amount AS measure_amount, '
      'im.sort_order AS measure_sort, im.source AS measure_source, '
      // The same measure WITHOUT the liveness guard, so an unresolved
      // measure_id can say which kind it is: a tombstone the household made,
      // or a row that has not synced down yet. A column of its own is
      // selected, not just joined — an unselected LEFT JOIN is optimized away
      // and `watch` then never re-fires on that table.
      'imx.deleted_at AS measure_deleted_at, '
      // The component target (step 8.6 / D1): title for the identity cell,
      // yields for the batch math. Its own words arrive batched, not joined
      // here — one query for every recipe, keyed by id.
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
      // lines read as stubs and the panel says so — matching what the picker
      // rows do for the same recipe (its LEFT JOIN nulls the status instead).
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

    // Only a recipe that actually HAS a component line pays for the macro
    // walk's extra read (step 8.6 / D8) — every other recipe page loads
    // exactly what it always did.
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
      // This recipe's OWN words, as the editor's MEASURES list shows them:
      // each word once. A merge-hidden twin is deliberately absent — a list
      // offering `blob` twice is what the merge exists to stop — and the Save
      // that diffs this list knows to leave it standing. Resolution is the
      // other way round and reads the target's full list.
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
      // A component line's identity is its TARGET's title; a dangling link
      // (target row missing) keeps the same honest "unknown" shape an
      // unresolved ingredient gets, and derives nothing (D5).
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
      // The vocab row is joined WITHOUT the liveness guard precisely so a
      // retired ingredient still hands over its last known name; this is the
      // flag that stops that name reading as if the row were fine.
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
    // The count this returns is the count D5's delete refusal speaks — one
    // query, two uses (the refusal and the "Used in · N" tab).
    // This recipe's own live words — every line below points at THIS recipe,
    // so one lookup answers all of them, and it is the same merged list every
    // other loader resolves against rather than a second reading of the table.
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
          // NULL exactly on a line said in one of this recipe's own words.
          // It is left null rather than defaulted: reading such a line as
          // `batch` would print `3 batch` and derive three whole batches from
          // a line that asked for three blobs.
          unit: unitById(r['unit'] as String? ?? ''),
          // The word while this recipe still has it; null the moment it is
          // retired, which is exactly when the row must print the refusal
          // instead of a number.
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

  /// Reads the `steps` jsonb, which holds one of two shapes and never both at
  /// once: an array of plain-text strings (the editor) or an array of tokenized
  /// step objects (import, step 8). A string element ⇒ plain text; an object
  /// with `tokens` ⇒ tokenized.
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

  /// What the `steps` jsonb is written as. The column holds ONE of the two
  /// shapes [_parseSteps] reads, and a recipe carries whichever
  /// one it was loaded with: an imported recipe's [Recipe.methodSteps] is the
  /// tokenized shape and its plain [Recipe.steps] is empty, so serializing the
  /// plain list unconditionally would erase the imported method on the first
  /// save. The tokenized shape therefore wins whenever it is present.
  Object _stepsJson(Recipe recipe) {
    final tokenized = recipe.methodSteps;
    if (tokenized == null) return recipe.steps;
    return [for (final step in tokenized) step.toJson()];
  }

  @override
  Future<void> saveRecipe(Recipe recipe) async {
    // Refused BEFORE anything is written, because of what the server does
    // with it: `num_nonnulls(unit, recipe_measure_id) = 1` rejects the upload,
    // and a rejected upload makes the PowerSync connector drop the WHOLE crud
    // transaction — so one undenominated line would take every queued write
    // beside it, on this device and in silence. A throw here costs this save;
    // a refusal up there costs the queue.
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
        // The other half of the same rule: a word IS the denomination, so it
        // says something only beside a count, and the server's
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
      // PowerSync's local tables are SQLite VIEWS with INSTEAD OF triggers,
      // which do NOT support `INSERT ... ON CONFLICT` (UPSERT). Branch on
      // existence and issue a plain INSERT or UPDATE instead.
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

      // The recipe's own words, diffed like every other child — and written
      // BEFORE the lines, so a word and a line saying it land in that order in
      // one crud transaction, which is the order the server's own guard
      // insists on (a line may only point at a measure that already exists and
      // is live).
      //
      // This is the DEFERRED door: the recipe editor's MEASURES list rides the
      // form's Save, so a word typed there lands with the recipe (ADR-0011).
      // The component dock's ＋ writes on tap instead — that door is
      // [RecipeMeasureRepository], and neither knows about the other.
      await writeRecipeMeasures(
        tx,
        recipeId: recipe.id,
        householdId: _householdId,
        measures: recipe.measures,
        now: now,
      );

      // Diff the children against the stored tree instead of delete +
      // re-insert: PowerSync queues ops literally (a DELETE then a PUT of the
      // same id, no consolidation), and the connector maps DELETE to a
      // server-side tombstone — so replacing kept ids would soft-delete them
      // on the server and every other device. Kept ids become UPDATEs, new
      // ids INSERTs, and dropped ids soft-deletes.
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
                // Written on every kept line, so a flag flipped in the editor
                // is a change like any other field — a component line carries
                // it exactly as an ingredient line does.
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

/// The catalog unit a line row is denominated in — **null exactly when the row
/// names one of the target's own words** (`recipe_measure_id`), which is the
/// half of the stored XOR a reader has to honour.
///
/// The word is asked first, so a row carrying both columns (foreign data, or a
/// writer that has not learned the XOR) reads as the word rather than as the
/// unit: `3 blob` must never be re-read as `3 piece` against a target that
/// makes 8 piece. A wordless row keeps the old `pieces` fallback, so an
/// unknown persisted unit id still never throws its way out of a mapper — and
/// so the pair is total, which is what [LineItem]'s own assert insists on.
///
/// The row must carry `recipe_measure_id` and `unit`; every line SELECT in
/// this file asks for both.
Unit? _lineUnit(Row r) => r['recipe_measure_id'] != null
    ? null
    : unitById(r['unit'] as String? ?? '') ?? pieces;

/// What one line's identity and denomination columns are actually written as.
///
/// Three stored XORs meet on this row and none of them is the caller's to get
/// wrong, so they are resolved in ONE place that the refusal and both
/// statements read: a component line stores its target and no ingredient and
/// no *ingredient* measure (`line_item_identity_xor`,
/// `line_item_component_has_no_measure`), and a line said in one of the
/// target's own words stores that word and **no unit**
/// (`line_item_unit_xor_recipe_measure`) — the word is the denomination, and
/// `batch` beside it would be the right dimension carrying the wrong number.
///
/// The word is dropped from a line that is not a component at all, because the
/// server drops it too (`line_item_recipe_measure_is_a_component`); such a line
/// then denominates in nothing, which [UndenominatedLineError] refuses rather
/// than sending up for the server to reject the whole transaction over.
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
/// nutrition its lines need (step 8.6 / D8).
///
/// Read whole: the walk can descend through a component of a component, and a
/// household's recipes fit comfortably in one pass — one query beats one per
/// edge. The recipe page reads it only when it actually has a component line;
/// the WEEK reads it whole, because a week's macro lens must re-sum every
/// planned recipe over that week's own effective lines rather than borrow the
/// Library's figure.
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
          // The node's own words: a PARENT line saying one of them resolves
          // through this list, and a word it has not got is the named gap the
          // macro and cost walks both print (never a count of the yield).
          measures: measuresByRecipe[r['id']] ?? const <RecipeMeasure>[],
        ),
    },
    nutrition,
  );
}

/// The cost walk's ingredient lookup, built from the two maps the loads
/// already have: the vocab's dimension facts, and the latest price per row.
///
/// An ingredient the vocab does not know resolves to null — the line is then
/// [CostLineReason.noPathToBasis], because an unknown row states no basis to
/// convert into. A known row with no price resolves WITH a null price, which
/// is the different and more useful answer: [CostLineReason.noPrice], whose
/// fix is the price sheet.
IngredientPricing? Function(String) pricingResolver(
  Map<String, IngredientNutrition> nutrition,
  Map<String, PriceObservation> prices,
) => (id) {
  final row = nutrition[id];
  return row == null ? null : (row: basisOf(row), price: prices[id]);
};
