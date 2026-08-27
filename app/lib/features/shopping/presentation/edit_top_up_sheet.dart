/// Edit or remove a single manual top-up (a `manual` contribution).
///
/// Opened from a manual line in an item's provenance breakdown. Pre-fills the
/// current quantity + unit; **Save** edits the contribution in place, and
/// **Remove** soft-deletes just that top-up (the item's cook contributions and
/// check-off stay). Writes through the keep-alive `shoppingRepositoryProvider`.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../../core/units/units.dart';
import '../data/shopping_providers.dart';
import '../domain/shopping.dart';

/// Opens the edit/remove sheet for [contribution] (a manual top-up on
/// [itemName]). No-op if the contribution has no persisted id.
Future<void> showEditTopUpSheet(
  BuildContext context, {
  required String itemName,
  required ShoppingContribution contribution,
}) {
  if (contribution.contributionId == null) return Future.value();
  return showFSheet<void>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    useSafeArea: true,
    builder: (_) =>
        _EditTopUpSheet(itemName: itemName, contribution: contribution),
  );
}

class _EditTopUpSheet extends HookConsumerWidget {
  const _EditTopUpSheet({required this.itemName, required this.contribution});

  final String itemName;
  final ShoppingContribution contribution;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quantity = useState<double?>(contribution.quantity);
    final unit = useState<Unit?>(contribution.unit ?? pieces);
    final contributionId = contribution.contributionId!;

    Future<void> save() async {
      final qty = quantity.value;
      final u = unit.value;
      if (qty == null || qty <= 0 || u == null) return;
      await ref
          .read(shoppingRepositoryProvider)
          .editContribution(
            contributionId: contributionId,
            quantity: qty,
            unit: u,
          );
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
                  child: FSelect<Unit>.rich(
                    hint: 'unit',
                    format: (u) => u.label,
                    control: FSelectControl<Unit>.lifted(
                      value: unit.value,
                      onChange: (u) {
                        if (u != null) unit.value = u;
                      },
                    ),
                    children: [
                      for (final u in kAllUnits)
                        FSelectItem(title: Text(u.label), value: u),
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
