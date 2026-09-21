/// The "add item or top up an ingredient" sheet.
///
/// Two modes: **Item** adds a free-text non-food entry; **Top up** picks an
/// ingredient and adds a `manual` contribution to its total. Both write through
/// [shoppingRepositoryProvider], and the list re-derives.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/units.dart';
import '../../../shared/ansi_chip.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_search_field.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/write.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/ingredient_picker.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../../planning/presentation/week_view_models.dart';
import '../data/shopping_providers.dart';

/// Opens the add/top-up sheet over the Shop screen.
Future<void> showAddShoppingItemSheet(BuildContext context) {
  return showAnsiSheet<void>(
    context: context,
    builder: (_) => const _AddShoppingItemSheet(),
  );
}

class _AddShoppingItemSheet extends HookConsumerWidget {
  const _AddShoppingItemSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topUp = useState(false); // false = free-text item, true = top up

    return AnsiSheetShell(
      title: 'Add to list',
      heightFactor: 0.82,
      children: [
        const SizedBox(height: 14),
        Row(
          children: [
            AnsiChip(
              label: 'Non-food item',
              selected: !topUp.value,
              onTap: () => topUp.value = false,
              tone: AnsiChipTone.ink,
              mono: true,
              expand: true,
            ),
            const SizedBox(width: 8),
            AnsiChip(
              label: 'Top up an ingredient',
              selected: topUp.value,
              onTap: () => topUp.value = true,
              tone: AnsiChipTone.ink,
              mono: true,
              expand: true,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: topUp.value ? const _TopUpBody() : const _FreeTextBody(),
        ),
      ],
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
      // The item joins the list on screen, exactly as a top-up does.
      final weekStart = ref.read(viewedWeekStartProvider);
      final added = await ref.writeOk(
        context,
        'add $value',
        () => ref
            .read(shoppingRepositoryProvider)
            .addFreeTextItem(text: value, weekStart: weekStart),
      );
      if (added && context.mounted) Navigator.of(context).pop();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('WHAT DO YOU NEED?', style: ansiLabel()),
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
          style: ansiMono(size: 10.5, color: AnsiColors.muted),
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

/// Search the vocab, pick an ingredient, then quantify it on the shared
/// quantity sheet.
class _TopUpBody extends HookConsumerWidget {
  const _TopUpBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = useIngredientSearch(ref, context);

    Future<void> pick(Ingredient ing) async {
      // The quantity sheet's keyboard can unmount the tapped row before Add
      // top-up is pressed. Resolve everything the write needs first, through
      // handles that outlive the row (`hostContextOf`); never use `ref` after
      // the await or bail on `context.mounted`, which would drop the top-up.
      final container = ProviderScope.containerOf(context, listen: false);
      final host = hostContextOf(context);
      final result = await showQuantityUnitSheet(
        context,
        ingredient: ing,
        requireQuantity: true,
        confirmLabel: 'Add top-up',
      );
      if (result is! QuantitySaved) return;
      final qty = result.quantity;
      if (qty == null) return;
      final repo = container.read(shoppingRepositoryProvider);
      // The top-up joins the list on screen.
      final weekStart = container.read(viewedWeekStartProvider);
      // A measure top-up stores the honest count fallback unit (`pieces`)
      // beside the measure id — see [ShoppingRepository.addTopUp].
      final added = await container.writeOk(
        host,
        'add ${ing.canonicalName}',
        () async => switch (result.choice) {
          UnitOption(:final unit) => repo.addTopUp(
            ingredientId: ing.id,
            quantity: qty,
            unit: unit,
            weekStart: weekStart,
          ),
          MeasureOption(:final measure) => repo.addTopUp(
            ingredientId: ing.id,
            quantity: qty,
            unit: pieces,
            measureId: measure.id,
            weekStart: weekStart,
          ),
          RecipeMeasureOption(:final measure) => notAWordForAnIngredient(
            measure,
          ),
        },
      );
      // This sheet is the top route again once the quantity sheet has popped,
      // so the host pops it whether or not the row lives (see [hostContextOf]).
      // ignore: use_build_context_synchronously
      if (added) Navigator.of(host.context).pop();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('TOP UP WHICH INGREDIENT?', style: ansiLabel()),
        const SizedBox(height: 10),
        AnsiSearchField(
          autofocus: true,
          hint: 'Search ingredients',
          onChanged: search.run,
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
        // The add-new chain: the ingredient form is pushed over this sheet, and
        // the row arrives only after it pops, so the quantity sheet [pick]
        // opens offers the units the form set.
        AddNewIngredientRow(query: search.query, onCreated: pick),
      ],
    );
  }
}
