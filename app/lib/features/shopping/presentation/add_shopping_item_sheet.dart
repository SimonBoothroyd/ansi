/// The "add item or top up an ingredient" sheet (design board).
///
/// Two modes, toggled at the top:
///   * **Item** — a free-text non-food staple ("paper towels") → a free-text
///     shopping entry.
///   * **Top up** — search the vocab, pick an ingredient, add a manual quantity
///     → a `manual` contribution merged into that ingredient's total.
///
/// Both write through the keep-alive `shoppingRepositoryProvider`; the list
/// re-derives from the overlay change.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../../core/units/units.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/ingredient_picker.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../data/shopping_providers.dart';

/// Opens the add/top-up sheet over the Shop screen.
Future<void> showAddShoppingItemSheet(BuildContext context) {
  return showFSheet<void>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    useSafeArea: true,
    builder: (_) => const _AddShoppingItemSheet(),
  );
}

class _AddShoppingItemSheet extends HookConsumerWidget {
  const _AddShoppingItemSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topUp = useState(false); // false = free-text item, true = top up

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.82,
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
          // Clear the keyboard (viewInsets) OR the home indicator (safe-area
          // padding) — whichever is present — so the bottom action button is
          // never tucked under the home-indicator gesture area.
          bottom:
              math.max(
                MediaQuery.viewInsetsOf(context).bottom,
                MediaQuery.paddingOf(context).bottom,
              ) +
              12,
        ),
        child: Column(
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
                    'Add to list',
                    textAlign: TextAlign.center,
                    style: miseSerif(size: 20),
                  ),
                ),
                const SizedBox(width: 22),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _ModeTab(
                  label: 'Non-food item',
                  selected: !topUp.value,
                  onTap: () => topUp.value = false,
                ),
                const SizedBox(width: 8),
                _ModeTab(
                  label: 'Top up an ingredient',
                  selected: topUp.value,
                  onTap: () => topUp.value = true,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: topUp.value ? const _TopUpBody() : const _FreeTextBody(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? MiseColors.ink : MiseColors.surface,
            border: Border.all(
              color: selected ? MiseColors.ink : MiseColors.line,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: miseMono(
              size: 11.5,
              color: selected ? MiseColors.surface : MiseColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Add a free-text non-food item.
class _FreeTextBody extends HookConsumerWidget {
  const _FreeTextBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = useState('');

    Future<void> add() async {
      final value = text.value.trim();
      if (value.isEmpty) return;
      await ref.read(shoppingRepositoryProvider).addFreeTextItem(text: value);
      if (context.mounted) Navigator.of(context).pop();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('WHAT DO YOU NEED?', style: miseLabel()),
        const SizedBox(height: 10),
        FTextField(
          autofocus: true,
          hint: 'e.g. Paper towels',
          control: FTextFieldControl.managed(
            onChange: (v) => text.value = v.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Non-food staples live in their own group and just get checked off.',
          style: miseMono(size: 10.5, color: MiseColors.muted),
        ),
        const Spacer(),
        FButton(
          onPress: text.value.trim().isEmpty ? null : add,
          child: const Text('Add item'),
        ),
      ],
    );
  }
}

/// Search the vocab (picker v2 rows — frame a), pick an ingredient, then
/// quantify it on the shared quantity + unit-chip sheet (frame b).
class _TopUpBody extends HookConsumerWidget {
  const _TopUpBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = useIngredientSearch(ref, context);

    Future<void> pick(Ingredient ing) async {
      final result = await showQuantityUnitSheet(
        context,
        ingredient: ing,
        requireQuantity: true,
        confirmLabel: 'Add top-up',
      );
      if (result is! QuantitySaved || !context.mounted) return;
      final qty = result.quantity;
      if (qty == null) return;
      final repo = ref.read(shoppingRepositoryProvider);
      // A measure top-up stores the honest count fallback unit (`pieces`)
      // beside the measure id — see [ShoppingRepository.addTopUp].
      await switch (result.choice) {
        UnitOption(:final unit) => repo.addTopUp(
          ingredientId: ing.id,
          quantity: qty,
          unit: unit,
        ),
        MeasureOption(:final measure) => repo.addTopUp(
          ingredientId: ing.id,
          quantity: qty,
          unit: pieces,
          measureId: measure.id,
        ),
      };
      if (context.mounted) Navigator.of(context).pop();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('TOP UP WHICH INGREDIENT?', style: miseLabel()),
        const SizedBox(height: 10),
        FTextField(
          autofocus: true,
          hint: 'Search ingredients',
          control: FTextFieldControl.managed(
            onChange: (v) => search.run(v.text),
          ),
          prefixBuilder: (context, style, _) => const Icon(FLucideIcons.search),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: IngredientResultList(
            results: search.results,
            query: search.query,
            showingRecents: search.showingRecents,
            onPick: pick,
          ),
        ),
        const SizedBox(height: 8),
        AddNewIngredientRow(query: search.query, onCreated: pick),
      ],
    );
  }
}
