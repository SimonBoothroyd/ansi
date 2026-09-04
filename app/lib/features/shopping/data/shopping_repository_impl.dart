/// [ShoppingRepository] over the local PowerSync SQLite (offline in step 6).
///
/// The read derives cook contributions live from the batch cook plan (spec §4):
/// it reads the week's planned meals, runs the same pure [buildCookPlan] the
/// Cook screen uses, then multiplies each covered recipe's line items by its
/// session scale factor. It overlays the persisted check-off + manual/free-text
/// rows and hands everything to the pure [buildShoppingList].
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
/// **The overlay is week-scoped** (migration 0018 / D3). An ingredient entry
/// carries the Monday it was ticked or topped up against, and the read only
/// takes that week's; a free-text staple carries no week and reads on every
/// one. So `_findOrCreateIngredientEntry` converges per WEEK, not per
/// household — two devices ticking Flour on next week still meet on one row,
/// and neither of them touches this week's.
library;

import 'dart:convert';

import 'package:sqlite3/common.dart' show Row;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../cook_plan/data/cook_plan_repository_impl.dart'
    show loadComponentGraph;
import '../../cook_plan/domain/cook_plan.dart';
import '../../planning/data/planning_repository_impl.dart' show loadMembers;
import '../../planning/domain/planning.dart' show eatersDemand, mondayOf;
import '../../recipes/domain/effective_lines.dart';
import '../../recipes/domain/recipe.dart';
import '../domain/shopping.dart';
import '../domain/shopping_repository.dart';

/// Mon..Sun short labels for the derived provenance labels ("· cook Mon").
/// Kept here (not imported from presentation) so the data layer doesn't depend
/// upwards; [buildShoppingList] takes the list so the domain stays formatless.
const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const _uuid = Uuid();

/// A recipe line as the shopping list needs it. `line` is the domain
/// [LineItem] the `effectiveLines` seam rules on (id, name, `optional`);
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
  const SqliteShoppingRepository(this._db, {required String householdId})
    : _householdId = householdId;

  final SqliteConnection _db;

  /// The household stamped on rows this repo writes (injected — the app passes
  /// the signed-in household, tests pass their own).
  final String _householdId;

  String _weekKey(DateTime weekStart) {
    final m = mondayOf(weekStart);
    final mm = m.month.toString().padLeft(2, '0');
    final dd = m.day.toString().padLeft(2, '0');
    return '${m.year}-$mm-$dd';
  }

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
          'i.id, im.id, hm.id '
          'FROM week_plan wp '
          'LEFT JOIN plan_entry pe '
          'ON pe.week_plan_id = wp.id AND pe.deleted_at IS NULL '
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
    final (cook, unresolved, optional) = await _deriveCookContributions(
      weekKey,
    );
    final (entries, manual) = await _loadOverlay(weekKey);
    final meta = await _loadIngredientMeta({
      ...cook.map((c) => c.ingredientId),
      ...entries.map((e) => e.ingredientId).whereType<String>(),
    });
    return buildShoppingList(
      cook: cook,
      entries: entries,
      manual: manual,
      meta: meta,
      weekdayShort: _weekdayShort,
      unresolvedComponents: unresolved,
      optionalLines: optional,
    );
  }

  /// Runs the cook plan for the week, then expands each session's recipe line
  /// items scaled by the session's factor into per-ingredient contributions.
  ///
  /// Since 8.6 the plan also carries **component** sessions (D3/D4): a
  /// component session is a cook session, so the sub-recipe's own ingredient
  /// lines flow through this same pipeline, scaled by its batch factor, and
  /// carry one extra provenance segment naming the plan they serve. The
  /// component LINE itself never becomes an item — `_loadLineItems` skips any
  /// row without an `ingredient_id`, which is exactly the component rows (you
  /// buy almonds, not aioli). The second return value is the per-parent
  /// "N components unresolved" echo built from the plan's gaps.
  ///
  /// Each recipe's lines pass through the `effectiveLines` seam before any
  /// session expands them — this is where lines meet the week, so it is where
  /// the per-week override will join later — and the third return value is the
  /// per-recipe "N optional lines not listed" echo built from what the seam
  /// dropped.
  Future<
    (
      List<CookContributionInput>,
      List<UnresolvedComponentNote>,
      List<OptionalLinesNote>,
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
      'ORDER BY pe.day_of_week, pe.sort_order, pe.created_at',
      [weekKey],
    );
    if (rows.isEmpty) {
      return (
        const <CookContributionInput>[],
        const <UnresolvedComponentNote>[],
        const <OptionalLinesNote>[],
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
    final plan = buildCookPlan([
      for (final e in byRecipe.entries)
        e.value.copyWith(meals: meals[e.key] ?? const []),
    ], components: await loadComponentGraph(_db));

    // Line items per recipe, read once — for every recipe the plan cooks,
    // which since 8.6 includes the sub-recipes it derived component sessions
    // for as well as the ones somebody planned.
    final lineItems = await _loadLineItems({
      for (final r in plan.recipes) r.recipeId,
    });

    final contributions = <CookContributionInput>[];
    final optionalNotes = <OptionalLinesNote>[];
    for (final recipe in plan.recipes) {
      final batched = recipe.sessions.length > 1;
      final stored = lineItems[recipe.recipeId] ?? const <_LineItem>[];
      // The seam (D6b): the sessions below expand only the kept lines, and
      // the dropped ones become this recipe's echo row — never a silent
      // hole in a list somebody shops from.
      final effective = effectiveLines(stored.map((i) => i.line));
      final keptIds = {for (final l in effective.kept) l.id};
      final items = [
        for (final i in stored)
          if (keptIds.contains(i.line.id)) i,
      ];
      final dropped = droppedNames(effective, LineDropReason.optional);
      if (dropped.isNotEmpty) {
        optionalNotes.add((
          recipeId: recipe.recipeId,
          recipeTitle: recipe.title,
          names: dropped,
        ));
      }
      for (final session in recipe.sessions) {
        for (final item in items) {
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
    return (contributions, unresolved, optionalNotes);
  }

  Future<Map<String, List<_LineItem>>> _loadLineItems(
    Set<String> recipeIds,
  ) async {
    if (recipeIds.isEmpty) return const {};
    final placeholders = List.filled(recipeIds.length, '?').join(', ');
    final rows = await _db.getAll(
      'SELECT g.recipe_id, li.id, li.ingredient_id, li.quantity, li.unit, '
      'li.optional, ing.canonical_name AS ingredient_name, '
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

  /// The week's overlay: THIS week's ingredient entries plus the global
  /// free-text staples (0018 / D3). An ingredient row stamped with another
  /// week — or, since there was no backfill, with no week at all — belongs to
  /// a list this is not, so it is not read here.
  Future<(List<ShoppingEntryInput>, Map<String, List<ManualContributionInput>>)>
  _loadOverlay(String weekKey) async {
    final entryRows = await _db.getAll(
      'SELECT id, ingredient_id, free_text, category, checked, unit, '
      'created_at '
      'FROM shopping_list_entry WHERE deleted_at IS NULL '
      'AND (week_start_date = ? '
      'OR (week_start_date IS NULL AND free_text IS NOT NULL))',
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
      'AND (se.week_start_date = ? '
      'OR (se.week_start_date IS NULL AND se.free_text IS NOT NULL)) '
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

  Future<Map<String, IngredientMetaInput>> _loadIngredientMeta(
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await _db.getAll(
      'SELECT id, canonical_name, category, density_g_per_ml, default_unit '
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
  Future<void> addFreeTextItem({required String text, String? category}) async {
    // No `week_start_date`: a staple you are out of belongs to the cupboard,
    // not to a week, so it reads on every week's list (0018).
    final now = _now();
    await _db.execute(
      'INSERT INTO shopping_list_entry '
      '(id, household_id, free_text, category, checked, created_at, '
      'updated_at) VALUES (?, ?, ?, ?, 0, ?, ?)',
      [_uuid.v4(), _householdId, text, category, now, now],
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
