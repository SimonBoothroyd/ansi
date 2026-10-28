/// The Shop's one way to add (spec §4): a search field over the vocabulary,
/// under the `To buy · At home?` toggle.
///
/// While it holds text and has focus, its answer stands where the walk was:
/// the picker's own tiers (spelled-right rows, else the *did you mean* band),
/// then the same two rows whatever matched — the words as a non-food item, and
/// the words as a new ingredient. Picking an ingredient opens the shared
/// quantity sheet on its usual amount, and nothing is added until that sheet's
/// **Add to list**. Clearing the field, or leaving it, brings the walk back.
/// It is not drawn during the at-home pass, which asks only what is here.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/units.dart';
import '../../../shared/ansi_search_field.dart';
import '../../../shared/write.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/ingredient_picker.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../../ingredients/presentation/usual_amount.dart';
import '../../planning/presentation/week_view_models.dart';
import '../data/shopping_providers.dart';
import '../domain/shopping.dart';
import 'shopping_format.dart';
import 'shopping_view_models.dart';

/// The field itself, for a test to type into.
const kShopAddFieldKey = ValueKey('shop-add-field');

/// The answer that stands in for the walk while the field is searching.
const kShopAddResultsKey = ValueKey('shop-add-results');

/// `＋ "…" as a non-food item`.
const kShopAddFreeTextKey = ValueKey('shop-add-free-text');

/// `＋ "…" as a new ingredient`.
const kShopAddNewIngredientKey = ValueKey('shop-add-new-ingredient');

/// The field over [walk]: the walk below it until the field is searching,
/// then the field's answer in its place.
class ShopAddField extends HookConsumerWidget {
  const ShopAddField({required this.walk, super.key});

  /// What stands under the field while it is not searching.
  final Widget walk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checking = ref.watch(shopCheckingProvider);
    final controller = useTextEditingController();
    final focus = useFocusNode();
    final search = useIngredientSearch(ref, context, loadRecents: false);
    // Whether the answer stands in for the walk. Focus decides it, except
    // while a chain this field opened is up: a sheet takes the focus, and the
    // results behind it should still be there when it closes.
    final active = useState(false);
    final holds = useRef(0);

    useEffect(() {
      void onFocus() {
        if (focus.hasFocus) {
          active.value = true;
        } else if (holds.value == 0) {
          active.value = false;
        }
      }

      focus.addListener(onFocus);
      return () => focus.removeListener(onFocus);
    }, [focus]);

    void onChanged(String text) {
      if (text == search.query) return;
      active.value = true;
      search.run(text);
    }

    /// The field empties and lets go once something is on the list.
    void clear() {
      controller.clear();
      active.value = false;
      focus.unfocus();
    }

    /// Runs one chain (a sheet, or the form then a sheet) with the answer held
    /// up behind it. Backed out, the answer is as it was.
    Future<void> held(Future<void> Function() chain) async {
      holds.value++;
      try {
        await chain();
      } finally {
        holds.value--;
        if (holds.value == 0 &&
            context.mounted &&
            controller.text.trim().isNotEmpty) {
          active.value = true;
        }
      }
    }

    Future<void> pick(Ingredient ing) => held(() async {
      // The sheet's keyboard reflows the Shop. Resolve everything the write
      // needs first, through handles that outlive this field
      // (`hostContextOf`); never `ref` after the await, and never a
      // `context.mounted` bail on the write, which would drop the top-up.
      final container = ProviderScope.containerOf(context, listen: false);
      final host = hostContextOf(context);
      // Opens filled in: the last top-up of it, else one of its word for one
      // (`defaultAmountFor`).
      final usual = await usualAmountOf(container, ing, forMeal: false);
      final result = await showQuantityUnitSheet(
        // The host outlives the field — see [hostContextOf].
        // ignore: use_build_context_synchronously
        host.context,
        ingredient: ing,
        initialQuantity: usual?.quantity,
        initialChoice: usual?.choice,
        requireQuantity: true,
        confirmLabel: 'Add to list',
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
      if (added && context.mounted) clear();
    });

    Future<void> addFreeText(String text) async {
      // The item joins the list on screen, exactly as a top-up does.
      final weekStart = ref.read(viewedWeekStartProvider);
      final added = await ref.writeOk(
        context,
        'add $text',
        () => ref
            .read(shoppingRepositoryProvider)
            .addFreeTextItem(text: text, weekStart: weekStart),
      );
      if (added && context.mounted) clear();
    }

    if (checking) return walk;

    final name = search.query.trim();
    final searching = active.value && name.isNotEmpty;
    // What this week's list already holds, by ingredient: a pick tops it up,
    // so its result says so.
    final list = ref.watch(currentShoppingListProvider).asData?.value;
    final listed = <String, String>{
      for (final g in list?.groups ?? const <ShoppingGroup>[])
        for (final item in g.items)
          if (item.ingredientId case final id?) id: itemTotal(item),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: AnsiSearchField(
            key: kShopAddFieldKey,
            hint: 'Add to the list',
            controller: controller,
            focusNode: focus,
            clearable: true,
            onChanged: onChanged,
          ),
        ),
        Expanded(
          child: searching
              // A tap here is inside the field's region, so a pointer picking
              // a result does not first take the focus away and the answer
              // with it.
              ? TextFieldTapRegion(
                  child: Padding(
                    key: kShopAddResultsKey,
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                    child: IngredientResultList(
                      results: search.results,
                      query: search.query,
                      showingRecents: false,
                      guessed: search.guessed,
                      onPick: (ing) => unawaited(pick(ing)),
                      noteFor: (ing) => switch (listed[ing.id]) {
                        final total? => 'on the list · $total',
                        null => null,
                      },
                      // The two rows end the same answer; they are not a
                      // second section to head.
                      labelIngredients: false,
                      trailing: [
                        if (search.results.isNotEmpty)
                          Container(height: 1, color: AnsiColors.line),
                        _AddRow(
                          key: kShopAddFreeTextKey,
                          title: '"$name" as a non-food item',
                          onTap: () => unawaited(addFreeText(name)),
                        ),
                        Container(height: 1, color: AnsiColors.line),
                        // The add-new chain: the form is pushed over the
                        // Shop, and the row it pops lands on the quantity
                        // sheet with the units the form set.
                        AddNewIngredientRow(
                          query: search.query,
                          onCreated: (ing) => unawaited(pick(ing)),
                          builder: (words, start) => _AddRow(
                            key: kShopAddNewIngredientKey,
                            title: '"$words" as a new food',
                            onTap: start == null
                                ? null
                                : () => unawaited(held(start)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : walk,
        ),
      ],
    );
  }
}

/// One of the two rows every search ends with, worded in parallel: what the
/// words become, and what happens next.
class _AddRow extends StatelessWidget {
  const _AddRow({required this.title, required this.onTap, super.key});

  final String title;

  /// Null while the row cannot act (a chain it started is still open).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        // A full-height tap target around one line of text.
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            const Icon(FLucideIcons.plus, size: 16, color: AnsiColors.herbDeep),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: ansiSans(
                  size: 15,
                  weight: FontWeight.w600,
                  color: AnsiColors.herbDeep,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
