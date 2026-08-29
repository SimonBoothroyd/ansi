/// Edit or remove a single manual top-up (a `manual` contribution).
///
/// Opened from a manual line in an item's provenance breakdown. Since 7.7 it
/// IS the shared quantity + unit-chip surface (frame b): pre-filled quantity
/// and selection, the chip row instead of a dropdown, plus a Remove
/// affordance. **Save** edits the contribution in place; **Remove**
/// soft-deletes just that top-up (the item's cook contributions and
/// check-off stay). Writes through the keep-alive
/// `shoppingRepositoryProvider`.
///
/// A top-up whose stored `measure_id` doesn't resolve (row unsynced or
/// soft-deleted) renders as its honest count fallback with a pending note,
/// and **Save keeps the id verbatim** unless the user explicitly picks a
/// chip — mirroring the recipe editor, so an unrelated edit never wipes the
/// FK for every device (invariant 3's degrade-don't-destroy).
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/units/units.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../data/shopping_providers.dart';
import '../domain/shopping.dart';

/// Opens the edit/remove sheet for [contribution] (a manual top-up on
/// [itemName], whose vocab row is [ingredientId] — null for a free-text
/// item). No-op if the contribution has no persisted id.
Future<void> showEditTopUpSheet(
  BuildContext context, {
  required String itemName,
  required String? ingredientId,
  required ShoppingContribution contribution,
}) {
  if (contribution.contributionId == null) return Future.value();
  return showFSheet<void>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    useSafeArea: true,
    builder: (_) => _EditTopUpSheet(
      itemName: itemName,
      ingredientId: ingredientId,
      contribution: contribution,
    ),
  );
}

class _EditTopUpSheet extends ConsumerWidget {
  const _EditTopUpSheet({
    required this.itemName,
    required this.ingredientId,
    required this.contribution,
  });

  final String itemName;
  final String? ingredientId;
  final ShoppingContribution contribution;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = ingredientId == null
        ? null
        : ref.watch(ingredientByIdProvider(ingredientId!)).asData?.value;
    // An unresolved vocab row still gets a working surface: a stub-shaped
    // stand-in scoped to the stored unit's family (nothing invented for it).
    final ingredient =
        resolved ??
        Ingredient(
          id: ingredientId ?? 'unknown',
          canonicalName: itemName,
          defaultUnit: contribution.measure != null
              ? pieces
              : contribution.unit ?? pieces,
          status: IngredientStatus.stub,
        );

    final storedMeasure = contribution.measure;
    // A stored measure_id whose row didn't resolve: shown as the count
    // fallback + a pending note, and preserved verbatim on save.
    final unresolvedMeasureId = storedMeasure == null
        ? contribution.measureId
        : null;
    final contributionId = contribution.contributionId!;

    Future<void> save(QuantitySaved result) async {
      final qty = result.quantity;
      if (qty == null || qty <= 0) return;
      final repo = ref.read(shoppingRepositoryProvider);
      // A measure top-up stores the honest count fallback unit (`pieces`)
      // beside the measure id — see [ShoppingRepository.addTopUp].
      await switch (result.choice) {
        UnitOption(:final unit) => repo.editContribution(
          contributionId: contributionId,
          quantity: qty,
          unit: unit,
          // An unresolved measure id survives a re-save untouched; only an
          // explicit chip pick clears it (mirrors the recipe editor).
          measureId: result.unitPicked ? null : unresolvedMeasureId,
        ),
        MeasureOption(:final measure) => repo.editContribution(
          contributionId: contributionId,
          quantity: qty,
          unit: pieces,
          measureId: measure.id,
        ),
      };
      if (context.mounted) Navigator.of(context).pop();
    }

    Future<void> remove() async {
      await ref
          .read(shoppingRepositoryProvider)
          .removeContribution(contributionId: contributionId);
      if (context.mounted) Navigator.of(context).pop();
    }

    return QuantityUnitEditor(
      ingredient: ingredient,
      initialQuantity: contribution.quantity,
      initialChoice: storedMeasure != null
          ? MeasureOption(storedMeasure)
          : UnitOption(contribution.unit ?? pieces),
      pendingMeasure: unresolvedMeasureId != null,
      requireQuantity: true,
      confirmLabel: 'Save changes',
      onDone: save,
      onRemove: remove,
    );
  }
}
