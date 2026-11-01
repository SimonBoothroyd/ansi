/// [UseUpRepository] over the local PowerSync SQLite.
///
/// Last week is read through the derivations the screens already trust: the
/// cook plan says which batches were cooked (a tick) and the shop says what
/// the week needed and what it left to buy. The meals of a batch whose days
/// are behind us and that nobody ticked were never cooked, so the list is
/// derived a second time without them for what was used. What was bought is
/// the week's receipt packs where a receipt carries the row, else the shop's
/// own whole count or the pack its price states. Everything is weighed in the
/// row's basis unit through [quantityInBasis]; a row that cannot be is left
/// out.
library;

import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/result/result.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
import '../../../core/week_shape.dart';
import '../../cook_plan/data/cook_plan_repository_impl.dart';
import '../../cook_plan/domain/leftovers.dart';
import '../../ingredients/data/price_repository_impl.dart'
    show loadBoughtPacks, loadCostPrices;
import '../../ingredients/domain/price.dart';
import '../../recipes/data/recipe_repository_impl.dart'
    show loadRecipeMacroNodes;
import '../../recipes/domain/line_basis.dart';
import '../../shopping/data/shopping_repository_impl.dart';
import '../../shopping/domain/shopping.dart';
import '../../shopping/domain/shopping_cost.dart';
import '../domain/use_up.dart';
import '../domain/use_up_repository.dart';

/// A vocabulary row as spare food reads it.
typedef _Row = ({String name, String? category, IngredientBasis basis});

class SqliteUseUpRepository implements UseUpRepository {
  const SqliteUseUpRepository(
    this._db, {
    required String householdId,
    WeekShape weekShape = WeekShape.monday,
  }) : _householdId = householdId,
       _weekShape = weekShape;

  final SqliteConnection _db;
  final String _householdId;
  final WeekShape _weekShape;

  @override
  Future<UseUpFacts> lastWeekFor(
    DateTime weekStart, {
    required DateTime today,
  }) async {
    final last = _weekShape.weekStartOf(
      DateTime(weekStart.year, weekStart.month, weekStart.day - 7),
    );
    final rows = await _rows();
    return (
      spare: spareOf(await _inputs(last, today: today, rows: rows)),
      recipes: await _recipeUses(rows),
    );
  }

  Future<List<SpareInput>> _inputs(
    DateTime last, {
    required DateTime today,
    required Map<String, _Row> rows,
  }) async {
    // A batch whose days are all behind us and that nobody ticked was never
    // cooked; one with days to come is still to be.
    final plan = await SqliteCookPlanRepository(_db).watchCookPlan(last).first;
    final day = DateTime(today.year, today.month, today.day);
    final uncooked = <String>{
      for (final recipe in plan.recipes)
        for (final s in recipe.mealSessions)
          if (!wasCooked(s) && dateOfDay(last, s.lastCoveredDay).isBefore(day))
            for (final m in s.covers)
              if (m.entryId case final id?) id,
    };
    final shop = SqliteShoppingRepository(
      _db,
      householdId: _householdId,
      weekShape: _weekShape,
    );
    final full = _byIngredient(await shop.loadShoppingList(last));
    final cooked = uncooked.isEmpty
        ? full
        : _byIngredient(await shop.loadShoppingList(last, leaveOut: uncooked));
    final bought = await _receiptPacks(last);
    final prices = await loadCostPrices(_db);

    final inputs = <SpareInput>[];
    for (final id in {...full.keys, ...bought.keys}) {
      final row = rows[id];
      if (row == null || !isFresh(row.category)) continue;
      final item = full[id];
      final need = _inBasis(item?.need.totals, row.basis);
      final toBuy = _inBasis(item?.totals, row.basis);
      final used = _inBasis(cooked[id]?.need.totals, row.basis);
      // A row that will not weigh is left out, never guessed.
      if (need == null || toBuy == null || used == null) continue;
      final price = prices[id];
      final samePrice = price != null && price.basis == row.basis.basis
          ? price
          : null;
      inputs.add((
        ingredientId: id,
        name: row.name,
        category: row.category,
        unit: row.basis.basis.baseUnit,
        need: need,
        toBuy: toBuy,
        bought: bought[id] ?? _estimate(item, toBuy, samePrice),
        usedCooked: used,
        centsPerUnit: switch (samePrice?.per100) {
          Ok(:final value) => value.cents / 100,
          _ => null,
        },
      ));
    }
    return inputs;
  }

  /// What a list row bought with no receipt to say: the whole count it
  /// rounded up to, else whole packs of the size its price states, else
  /// exactly what it left to buy.
  static double _estimate(ShoppingItem? item, double toBuy, UnitPrice? price) {
    if (item == null || toBuy <= 0) return 0;
    final rounded = roundedBuy(item);
    if (rounded != null && rounded.need > 0) {
      return toBuy * rounded.buy / rounded.need;
    }
    final pack = price?.packBasisAmount;
    if (pack != null && pack > 0) return (toBuy / pack - 1e-9).ceil() * pack;
    return toBuy;
  }

  static Map<String, ShoppingItem> _byIngredient(ShoppingList list) => {
    for (final g in list.groups)
      for (final item in g.items)
        if (item.ingredientId case final id?) id: item,
  };

  /// [totals] in [row]'s basis unit, 0 for none, or null when one cannot be
  /// weighed.
  static double? _inBasis(List<Quantity>? totals, IngredientBasis row) {
    var sum = 0.0;
    for (final q in totals ?? const <Quantity>[]) {
      final amount = quantityInBasis(q.amount, q.unit, row);
      if (amount == null) return null;
      sum += amount;
    }
    return sum;
  }

  /// What the receipts filed to the week beginning [weekStart] bought of each
  /// row, in its basis unit.
  Future<Map<String, double>> _receiptPacks(DateTime weekStart) async {
    final sums = <String, double>{};
    for (final pack in await loadBoughtPacks(_db)) {
      // A receipt is filed by its own wall date, as the ledger files it.
      final date = DateTime(pack.when.year, pack.when.month, pack.when.day);
      if (_weekShape.weekStartOf(date) != weekStart) continue;
      sums.update(
        pack.ingredientId,
        (v) => v + pack.amount,
        ifAbsent: () => pack.amount,
      );
    }
    return sums;
  }

  Future<Map<String, _Row>> _rows() async => {
    for (final r in await _db.getAll(
      'SELECT id, canonical_name, category, macros_basis, density_g_per_ml, '
      'piece_basis_amount FROM ingredient WHERE deleted_at IS NULL',
    ))
      r['id'] as String: (
        name: r['canonical_name'] as String,
        category: r['category'] as String?,
        basis: (
          basis: MacrosBasis.fromDb(r['macros_basis'] as String?),
          densityGPerMl: (r['density_g_per_ml'] as num?)?.toDouble(),
          pieceBasisAmount: (r['piece_basis_amount'] as num?)?.toDouble(),
        ),
      ),
  };

  /// Every live recipe's own ingredient lines, per batch, in each row's basis
  /// unit. An optional line is not cooked unless a week ticks it in, and a
  /// component's lines belong to the component, so neither counts.
  Future<List<RecipeUse>> _recipeUses(Map<String, _Row> rows) async {
    final (nodes, _) = await loadRecipeMacroNodes(_db);
    final titles = {
      for (final r in await _db.getAll(
        'SELECT id, title FROM recipe WHERE deleted_at IS NULL',
      ))
        r['id'] as String: r['title'] as String,
    };
    return [
      for (final MapEntry(key: id, value: node) in nodes.entries)
        if (titles[id] case final title?)
          (
            recipeId: id,
            title: title,
            servingsBase: node.servingsBase,
            perBatch: {
              for (final line in node.lines)
                if (!line.optional)
                  if (line.ingredientId case final ingredientId?)
                    if (rows[ingredientId] case final row?)
                      if (lineAmountInBasis(line, row.basis) case final a?)
                        ingredientId: a,
            },
          ),
    ];
  }
}
