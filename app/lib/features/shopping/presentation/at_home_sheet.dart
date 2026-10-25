/// How much of a row is already at home: the shared quantity
/// editor, asked the other way round. You say what you have, not what you
/// need, and the editor says what that leaves to buy as you type.
///
/// A phone opens it as a sheet from the amount chip in the checking pass; the
/// wide Shop draws the same editor in the pane beside the list, where pointing
/// at row after row walks the cupboard without opening anything.
library;

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/unit_choice.dart';
import '../../../core/units/units.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/write.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../../planning/presentation/week_view_models.dart';
import '../data/shopping_providers.dart';
import '../domain/at_home.dart';
import '../domain/shopping.dart';
import 'shopping_format.dart';

/// Opens the amount at home for [item] as a sheet (a dialog from 640 up).
Future<void> showAtHomeSheet(BuildContext context, ShoppingItem item) {
  if (item.ingredientId == null) return Future.value();
  return showAnsiSheet<void>(
    context: context,
    builder: (_) => AtHomeEditor(item: item),
  );
}

/// The amount at home for one row. In a sheet, Save and Remove close it; in
/// the wide pane ([inPane]) they write and the pane stays on the row, the
/// field waits for a tap rather than raising the keyboard, and the X calls
/// [onDismiss].
class AtHomeEditor extends ConsumerWidget {
  const AtHomeEditor({
    required this.item,
    this.inPane = false,
    this.onDismiss,
    super.key,
  });

  final ShoppingItem item;
  final bool inPane;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ingredientId = item.ingredientId!;
    final resolved = ref
        .watch(ingredientByIdProvider(ingredientId))
        .asData
        ?.value;
    final said = item.atHome;
    final all = amountForAll(item);
    // An unresolved vocab row still gets a working surface: a stub-shaped
    // stand-in in the unit the row is counted in (nothing invented for it).
    final ingredient =
        resolved ??
        Ingredient(
          id: ingredientId,
          canonicalName: item.name,
          defaultUnit: said?.unit ?? all?.unit ?? pieces,
          status: IngredientStatus.stub,
        );
    final storedMeasure = said?.measure ?? all?.measure;
    // A stored measure id whose row has not synced: kept on a re-save unless
    // a chip is picked, as a top-up's is.
    final unresolvedMeasureId = said != null && said.measure == null
        ? said.measureId
        : null;

    Future<void> save(QuantitySaved result) async {
      final qty = result.quantity;
      if (qty == null || qty <= 0) return;
      final repo = ref.read(shoppingRepositoryProvider);
      final week = ref.read(viewedWeekStartProvider);
      final saved = await ref.writeOk(
        context,
        'save what is at home',
        () async => switch (result.choice) {
          UnitOption(:final unit) => repo.setAtHome(
            ingredientId: ingredientId,
            quantity: qty,
            unit: unit,
            weekStart: week,
            measureId: result.unitPicked ? null : unresolvedMeasureId,
          ),
          MeasureOption(:final measure) => repo.setAtHome(
            ingredientId: ingredientId,
            quantity: qty,
            unit: pieces,
            weekStart: week,
            measureId: measure.id,
          ),
          RecipeMeasureOption(:final measure) => notAWordForAnIngredient(
            measure,
          ),
        },
      );
      if (saved && !inPane && context.mounted) Navigator.of(context).pop();
    }

    Future<void> remove() async {
      final week = ref.read(viewedWeekStartProvider);
      final removed = await ref.writeOk(
        context,
        'clear what is at home',
        () => ref
            .read(shoppingRepositoryProvider)
            .clearAtHome(ingredientId: ingredientId, weekStart: week),
      );
      if (removed && !inPane && context.mounted) Navigator.of(context).pop();
    }

    return QuantityUnitEditor(
      ingredient: ingredient,
      // Opens on what was said, else on the need — the likeliest answer is
      // "all of it", and the field is one edit away from "some".
      initialQuantity: said?.quantity ?? all?.quantity,
      initialChoice: storedMeasure != null
          ? MeasureOption(storedMeasure)
          : UnitOption(said?.unit ?? all?.unit ?? pieces),
      pendingMeasure: unresolvedMeasureId != null,
      requireQuantity: true,
      confirmLabel: 'Save',
      removeLabel: 'Remove',
      autofocus: !inPane,
      onDismiss: onDismiss,
      onDone: save,
      onRemove: said == null ? null : remove,
      summary: (quantity, choice) => AtHomeSummary(
        item: item,
        ingredient: ingredient,
        quantity: quantity,
        choice: choice,
      ),
    );
  }
}

/// The two lines under the amount: what the week needs, and what the amount
/// leaves to buy — or why it cannot come off.
class AtHomeSummary extends StatelessWidget {
  const AtHomeSummary({
    required this.item,
    required this.ingredient,
    required this.quantity,
    required this.choice,
    super.key,
  });

  final ShoppingItem item;
  final Ingredient ingredient;
  final double? quantity;
  final UnitChoice choice;

  /// What is left to buy after [quantity] of [choice]: a total, `nothing —
  /// it's all at home`, or `not counted (no density)`.
  static String leftWords({
    required ShoppingItem item,
    required Ingredient ingredient,
    required double? quantity,
    required UnitChoice choice,
  }) {
    final qty = quantity;
    if (qty == null || !(qty > 0)) return needTotal(item);
    final pieceWeight = ingredient.pieceBasisAmount;
    final result = leftToBuy(
      need: item.need,
      quantity: qty,
      unit: switch (choice) {
        UnitOption(:final unit) => unit,
        _ => pieces,
      },
      measure: switch (choice) {
        MeasureOption(:final measure) => measure,
        _ => null,
      },
      densityGPerMl: ingredient.densityGPerMl,
      pieceMeasure: pieceWeight == null || !(pieceWeight > 0)
          ? null
          : Measure(
              id: pieces.id,
              label: pieces.label,
              amount: pieceWeight,
              basis: ingredient.macrosBasis,
            ),
    );
    return switch (result) {
      AllAtHome() => 'nothing — it’s all at home',
      NotCounted(:final reason) => 'not counted ($reason)',
      SomeLeft(:final left) => itemAmount(
        item.copyWith(
          totals: left.totals,
          measureTotal: left.measureTotal,
          pieceTotal: left.pieceTotal,
        ),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final left = leftWords(
      item: item,
      ingredient: ingredient,
      quantity: quantity,
      choice: choice,
    );
    final refused = left.startsWith('not counted');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'this week needs',
                style: ansiMono(size: 11, color: AnsiColors.muted),
              ),
            ),
            Text(
              needTotal(item),
              style: ansiMono(size: 11, color: AnsiColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(height: 1, color: AnsiColors.line),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text('still to buy', style: ansiSans(size: 13))),
            Flexible(
              child: Text(
                left,
                textAlign: TextAlign.end,
                style: ansiMono(
                  size: refused ? 11 : 15,
                  weight: FontWeight.w500,
                  color: refused ? AnsiColors.cautionInk : AnsiColors.herbDeep,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
