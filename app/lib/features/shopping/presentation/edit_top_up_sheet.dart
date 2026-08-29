/// Edit or remove a single manual top-up (a `manual` contribution).
///
/// Opened from a manual line in an item's provenance breakdown. Pre-fills the
/// current quantity + unit (or named measure); **Save** edits the contribution
/// in place, and **Remove** soft-deletes just that top-up (the item's cook
/// contributions and check-off stay). Writes through the keep-alive
/// `shoppingRepositoryProvider`.
///
/// The unit dropdown is filtered by the resolved vocab row
/// (`allowedUnitChoicesFor` — honest units plus the ingredient's measures),
/// falling back to the full catalog while unresolved; the stored selection
/// stays selectable so an existing top-up never renders an orphaned value.
///
/// A top-up whose stored `measure_id` doesn't resolve (row unsynced or
/// soft-deleted) renders as its honest count fallback with a "(measure
/// pending sync)" note, and **Save keeps the id verbatim** unless the user
/// explicitly picks a different unit — mirroring the recipe editor, so an
/// unrelated edit never wipes the FK for every device (invariant 3's
/// degrade-don't-destroy).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/domain/allowed_units.dart';
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

class _EditTopUpSheet extends HookConsumerWidget {
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
    final quantity = useState<double?>(contribution.quantity);
    final storedMeasure = contribution.measure;
    final choice = useState<UnitChoice>(
      storedMeasure == null
          ? UnitOption(contribution.unit ?? pieces)
          : MeasureOption(storedMeasure),
    );
    // True once the user explicitly picked from the dropdown — only then may
    // a plain-unit save clear a stored (possibly unresolved) measure id.
    final pickedUnit = useState(false);
    // A stored measure_id whose row didn't resolve: shown as the count
    // fallback + a pending note, and preserved verbatim on save.
    final unresolvedMeasureId = storedMeasure == null
        ? contribution.measureId
        : null;
    final contributionId = contribution.contributionId!;

    final ingredient = ingredientId == null
        ? null
        : ref.watch(ingredientByIdProvider(ingredientId!)).asData?.value;
    final measures = ingredientId == null
        ? const <Measure>[]
        : ref.watch(ingredientMeasuresProvider(ingredientId!)).asData?.value ??
              const <Measure>[];
    final allowed = ingredient == null
        ? [for (final u in kAllUnits) UnitOption(u)]
        : allowedUnitChoicesFor(ingredient, measures);
    final choices = allowed.contains(choice.value)
        ? allowed
        : [...allowed, choice.value];

    Future<void> save() async {
      final qty = quantity.value;
      if (qty == null || qty <= 0) return;
      final repo = ref.read(shoppingRepositoryProvider);
      // A measure top-up stores the honest count fallback unit (`pieces`)
      // beside the measure id — see [ShoppingRepository.addTopUp].
      await switch (choice.value) {
        UnitOption(:final unit) => repo.editContribution(
          contributionId: contributionId,
          quantity: qty,
          unit: unit,
          // An unresolved measure id survives a re-save untouched; only an
          // explicit unit pick clears it (mirrors the recipe editor).
          measureId: pickedUnit.value ? null : unresolvedMeasureId,
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

    final canSave = quantity.value != null && quantity.value! > 0;

    return Container(
      decoration: const BoxDecoration(
        color: MiseColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: MiseColors.line)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom:
              math.max(
                MediaQuery.viewInsetsOf(context).bottom,
                MediaQuery.paddingOf(context).bottom,
              ) +
              12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(FLucideIcons.x, size: 22),
                ),
                Expanded(
                  child: Text(
                    'Edit top-up',
                    textAlign: TextAlign.center,
                    style: miseSerif(size: 20),
                  ),
                ),
                const SizedBox(width: 22),
              ],
            ),
            const SizedBox(height: 14),
            Text(itemName, style: miseSerif(size: 22)),
            const SizedBox(height: 4),
            Text(
              'Your manual addition to the list.',
              style: miseMono(size: 11, color: MiseColors.muted),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: FTextField(
                    autofocus: true,
                    hint: 'Qty',
                    keyboardType: TextInputType.number,
                    control: FTextFieldControl.managed(
                      initial: TextEditingValue(
                        text: formatQuantityInput(contribution.quantity),
                      ),
                      onChange: (v) => quantity.value = v.text.trim().isEmpty
                          ? null
                          : double.tryParse(v.text.trim()),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: FSelect<UnitChoice>.rich(
                    hint: 'unit',
                    // The count fallback of an unresolved measure carries a
                    // subtle note until the user picks something explicit.
                    format: (c) =>
                        unresolvedMeasureId != null && !pickedUnit.value
                        ? '${c.label} (measure pending sync)'
                        : c.label,
                    control: FSelectControl<UnitChoice>.lifted(
                      value: choice.value,
                      onChange: (c) {
                        if (c != null) {
                          choice.value = c;
                          pickedUnit.value = true;
                        }
                      },
                    ),
                    children: [
                      for (final c in choices)
                        FSelectItem(title: Text(c.label), value: c),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FButton(
              onPress: canSave ? save : null,
              child: const Text('Save changes'),
            ),
            const SizedBox(height: 8),
            FButton(
              variant: FButtonVariant.ghost,
              onPress: remove,
              child: Text(
                'Remove top-up',
                style: miseSans(size: 15, color: MiseColors.gone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formats a stored quantity for the edit field's initial value (integers show
/// without a trailing `.0`).
String formatQuantityInput(double? amount) {
  if (amount == null) return '';
  if (amount == amount.roundToDouble()) return amount.toStringAsFixed(0);
  return amount.toString();
}
