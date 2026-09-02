/// The Shop screen — the DERIVED, provenance-aware shopping list (spec §4).
///
/// The list sums each ingredient's contributions from the batch cook plan, plus
/// any manual top-ups, and groups them by aisle. Check-off is on the rolled-up
/// item (spec §4). A "+ add item or top up" affordance opens the add sheet for
/// non-food staples and manual top-ups. Read-derived; edit the Week/Cook and
/// this re-sums. Only the thin overlay (check-off + manual contributions)
/// persists — and syncs, since step 7.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_bottom_nav.dart';
import '../../../shared/dashed_border_box.dart';
import '../../cook_plan/presentation/cook_view_models.dart';
import '../data/shopping_providers.dart';
import '../domain/shopping.dart';
import 'add_shopping_item_sheet.dart';
import 'edit_top_up_sheet.dart';
import 'shopping_format.dart';
import 'shopping_view_models.dart';

class ShoppingView extends ConsumerWidget {
  const ShoppingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(currentShoppingListProvider);

    return FScaffold(
      footer: const AnsiBottomNav(current: AnsiTab.shop),
      header: FHeader.nested(
        title: Text('Shopping list', style: ansiHeaderTitle()),
      ),
      child: list.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (e, _) {
          debugPrint('shopping list failed: $e');
          return Center(
            child: Text(
              'Could not build the shopping list.',
              textAlign: TextAlign.center,
              style: ansiMono(size: 13, color: AnsiColors.muted),
            ),
          );
        },
        data: (data) => data.isEmpty
            ? const _EmptyShoppingList()
            : ListView(
                padding: const EdgeInsets.only(top: 6, bottom: 24),
                children: [
                  const _ListCaption(),
                  for (final group in data.groups) _Group(group: group),
                  // What the list is short by, and why it is silent about it
                  // (step 8.6 / D4): an unresolved component contributes
                  // nothing — never an invented quantity — so the parent it
                  // belongs to says so and points at the surface that fixes
                  // it. A list that is quietly short is worse than one that
                  // says what it left out.
                  for (final note in data.unresolvedComponents)
                    _UnresolvedEcho(note: note),
                  const _AddItemButton(),
                ],
              ),
      ),
    );
  }
}

class _ListCaption extends StatelessWidget {
  const _ListCaption();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
      child: Text(
        'summed from the cook plan · with provenance',
        style: ansiMono(
          size: 10.5,
          color: AnsiColors.muted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.group});

  final ShoppingGroup group;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Text(
            group.label.toUpperCase(),
            style: ansiMono(
              size: 10,
              color: AnsiColors.muted,
              letterSpacing: 1.4,
            ),
          ),
        ),
        for (final item in group.items) _ItemRow(item: item),
      ],
    );
  }
}

/// A parent recipe's "N components unresolved — see Cook" echo, drawn in the
/// group-header voice (board frame g) because that is what it is: a heading
/// for the items that are NOT below it.
class _UnresolvedEcho extends StatelessWidget {
  const _UnresolvedEcho({required this.note});

  final UnresolvedComponentNote note;

  static const _foreground = Color(0xFF7A5A16);

  @override
  Widget build(BuildContext context) {
    final count = note.count;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        children: [
          Flexible(
            child: Text(
              note.recipeTitle.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: ansiMono(
                size: 10,
                color: AnsiColors.muted,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(FLucideIcons.flag, size: 11, color: _foreground),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '$count component${count == 1 ? '' : 's'} unresolved — see Cook',
              overflow: TextOverflow.ellipsis,
              style: ansiMono(size: 10.5, color: _foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// One shopping line: check box · name · total, with the provenance breakdown
/// beneath. Tapping the row (or its box) toggles check-off. A purely user-added
/// line (a non-food item, or an ingredient that's only a manual top-up) can be
/// removed by swiping it away or long-pressing — a cook-derived line can't (its
/// quantity comes from the week; drop its top-up via the edit sheet instead).
class _ItemRow extends ConsumerWidget {
  const _ItemRow({required this.item});

  final ShoppingItem item;

  Future<void> _toggle(WidgetRef ref) async {
    final repo = ref.read(shoppingRepositoryProvider);
    final entryId = item.entryId;
    // A touched line (free-text, checked, or topped-up) has an entry; a purely
    // derived ingredient doesn't yet — check-off lazily creates it.
    if (entryId != null) {
      await repo.setEntryChecked(entryId: entryId, checked: !item.checked);
    } else {
      await repo.setIngredientChecked(
        ingredientId: item.ingredientId!,
        checked: !item.checked,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = _rowBody(context, ref);
    if (!item.isUserAdded) return row;
    // Swipe-to-delete for user-added lines; the confirm dialog runs first, and
    // the stream-driven list drops the row once the entry is soft-deleted.
    return Dismissible(
      key: ValueKey('shop-item-${item.entryId}'),
      direction: DismissDirection.endToStart,
      background: const _DeleteBackground(),
      confirmDismiss: (_) async {
        await _confirmRemove(context, ref, item);
        return false; // the stream removes the row; don't double-dismiss.
      },
      child: row,
    );
  }

  Widget _rowBody(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggle(ref),
      onLongPress: item.isUserAdded
          ? () => _confirmRemove(context, ref, item)
          : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: const BoxDecoration(
          color: AnsiColors.surface,
          border: Border(bottom: BorderSide(color: AnsiColors.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _CheckBox(checked: item.checked),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    item.name,
                    style:
                        ansiSans(
                          size: 14,
                          color: item.checked
                              ? AnsiColors.muted
                              : AnsiColors.ink,
                        ).copyWith(
                          decoration: item.checked
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  itemTotal(item),
                  style: ansiMono(
                    size: 13,
                    weight: FontWeight.w500,
                    color: item.checked ? AnsiColors.muted : AnsiColors.ink,
                  ),
                ),
              ],
            ),
            // The whole-unit round-up hint ("≈ 2.25 potato, large → buy 3")
            // sits under the honest total, never replacing it (invariant 3).
            if (!item.checked && item.wholeUnitHint != null) ...[
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.only(left: 31),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    wholeUnitHintText(item.wholeUnitHint!),
                    style: ansiMono(size: 10.5, color: AnsiColors.herbDeep),
                  ),
                ),
              ),
            ],
            if (!item.checked && item.hasBreakdown) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 31),
                child: _Provenance(
                  itemName: item.name,
                  ingredientId: item.ingredientId,
                  contributions: item.contributions,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The red "delete" panel revealed behind a row as it's swiped away.
class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 8),
      color: AnsiColors.gone,
      child: const Icon(FLucideIcons.trash2, size: 18, color: AnsiColors.paper),
    );
  }
}

/// The provenance breakdown: one line per contribution, source on the left,
/// quantity on the right. Manual top-ups read muted + italic and are tappable
/// (a pencil affordance) to edit or remove that single top-up.
class _Provenance extends StatelessWidget {
  const _Provenance({
    required this.itemName,
    required this.ingredientId,
    required this.contributions,
  });

  final String itemName;
  final String? ingredientId;
  final List<ShoppingContribution> contributions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in contributions)
          _ProvenanceLine(
            itemName: itemName,
            ingredientId: ingredientId,
            contribution: c,
          ),
      ],
    );
  }
}

class _ProvenanceLine extends StatelessWidget {
  const _ProvenanceLine({
    required this.itemName,
    required this.ingredientId,
    required this.contribution,
  });

  final String itemName;
  final String? ingredientId;
  final ShoppingContribution contribution;

  @override
  Widget build(BuildContext context) {
    final c = contribution;
    final isManual = c.source == ContributionSource.manual;
    final editable = isManual && c.contributionId != null;

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          if (isManual) ...[
            const Icon(FLucideIcons.plus, size: 10, color: AnsiColors.muted),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              c.label,
              style: ansiMono(
                size: 10.5,
                color: isManual ? AnsiColors.muted : AnsiColors.herbDeep,
              ).copyWith(fontStyle: isManual ? FontStyle.italic : null),
            ),
          ),
          if (editable) ...[
            const Icon(FLucideIcons.pencil, size: 11, color: AnsiColors.herb),
            const SizedBox(width: 6),
          ],
          Text(
            contributionQuantity(c),
            style: ansiMono(size: 10.5, color: AnsiColors.muted),
          ),
        ],
      ),
    );

    if (!editable) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showEditTopUpSheet(
        context,
        itemName: itemName,
        ingredientId: ingredientId,
        contribution: c,
      ),
      child: row,
    );
  }
}

/// The design-board check box: a rounded square, filled herb-green with a white
/// tick when on.
class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: checked ? AnsiColors.herb : AnsiColors.surface,
        border: Border.all(
          color: checked ? AnsiColors.herb : AnsiColors.line,
          width: 1.6,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: checked
          ? const Icon(FLucideIcons.check, size: 13, color: AnsiColors.surface)
          : null,
    );
  }
}

class _AddItemButton extends StatelessWidget {
  const _AddItemButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showAddShoppingItemSheet(context),
        child: DashedBorderBox(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(FLucideIcons.plus, size: 12, color: AnsiColors.herb),
              const SizedBox(width: 5),
              Text(
                'add item or top up an ingredient',
                textAlign: TextAlign.center,
                style: ansiMono(
                  size: 11,
                  color: AnsiColors.herb,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyShoppingList extends ConsumerWidget {
  const _EmptyShoppingList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The list can be empty for two very different reasons — tell them apart so
    // the copy isn't misleading. If the week already has planned recipes but
    // nothing summed, those recipes simply have no ingredients yet.
    final plannedButNoIngredients = ref
        .watch(currentCookPlanProvider)
        .maybeWhen(data: (plan) => !plan.isEmpty, orElse: () => false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
      children: [
        const Icon(
          FLucideIcons.shoppingBasket,
          size: 44,
          color: AnsiColors.herb,
        ),
        const SizedBox(height: 14),
        Text(
          plannedButNoIngredients ? 'Nothing to sum yet' : 'Nothing to buy yet',
          textAlign: TextAlign.center,
          style: ansiSerif(size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          plannedButNoIngredients
              ? "You've planned meals, but their recipes don't list any "
                    'ingredients yet — add ingredients to a recipe and Ansi '
                    'sums them here.'
              : 'Plan meals on the Week and Ansi sums the shopping from the '
                    "cook plan — or add a non-food staple you're out of.",
          textAlign: TextAlign.center,
          style: ansiMono(size: 12, color: AnsiColors.muted),
        ),
        const SizedBox(height: 22),
        Builder(
          builder: (context) => FButton(
            onPress: () => showAddShoppingItemSheet(context),
            variant: FButtonVariant.outline,
            child: const Text('Add an item'),
          ),
        ),
        const SizedBox(height: 10),
        Builder(
          builder: (context) => FButton(
            onPress: () => context.go(plannedButNoIngredients ? '/' : '/week'),
            child: Text(
              plannedButNoIngredients ? 'Open the library' : 'Plan the week',
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _confirmRemove(
  BuildContext context,
  WidgetRef ref,
  ShoppingItem item,
) async {
  // Read the keep-alive repo and the entry id BEFORE the dialog await: while
  // it sits open the watched stream can drop this row (say, the other device
  // removed it), unmounting the row widget — a `ref.read` after the await
  // would then throw on a disposed ref.
  final repo = ref.read(shoppingRepositoryProvider);
  final entryId = item.entryId;
  final remove = await showFDialog<bool>(
    context: context,
    builder: (context, style, animation) => FDialog(
      title: Text('Remove ${item.name}?', style: ansiSerif(size: 18)),
      body: Text(
        item.isFreeText
            ? 'This non-food item will be removed from the list.'
            : 'This removes ${item.name} and your top-up from the list.',
        style: ansiSans(size: 14, color: AnsiColors.muted),
      ),
      actions: [
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FButton(
          onPress: () => Navigator.of(context).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if ((remove ?? false) && entryId != null) {
    await repo.removeEntry(entryId: entryId);
  }
}
