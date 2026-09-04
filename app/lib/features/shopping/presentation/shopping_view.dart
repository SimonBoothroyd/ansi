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
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/sync_status_line.dart';
import '../../../shared/write.dart';
import '../../cook_plan/presentation/cook_view_models.dart';
import '../../planning/presentation/week_format.dart';
import '../../planning/presentation/week_header.dart';
import '../../planning/presentation/week_view_models.dart';
import '../data/shopping_providers.dart';
import '../domain/shopping.dart';
import 'add_shopping_item_sheet.dart';
import 'edit_top_up_sheet.dart';
import 'shopping_format.dart';
import 'shopping_view_models.dart';

class ShoppingView extends ConsumerWidget {
  const ShoppingView({super.key});

  /// The tab root's stable anchor: the header no longer names the screen, so
  /// the smoke test waits on this key instead of a title.
  static const rootKey = ValueKey('shop-root');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(currentShoppingListProvider);
    final viewed = ref.watch(viewedWeekStartProvider);

    return FScaffold(
      key: rootKey,
      // A tab root sits INSIDE the shell's scaffold, which already shrinks
      // the branch area for the keyboard; a second scaffold subtracting the
      // same inset squeezes the content twice (Android showed a list a few
      // lines tall after the sign-in keyboard).
      resizeToAvoidBottomInset: false,
      // D7a/D7c: the list derives from the ONE viewed week (and since 0018 its
      // check-offs and top-ups belong to that week), so the switcher is the
      // whole title — no screen name, no pill. No "copy last week": that is a
      // Week write (D7b).
      header: FHeader.nested(
        title: WeekSwitcher(
          showCopyLastWeek: false,
          // The menu speaks in this tab's derivation — "6 items" — for the
          // week it has already summed; the other rows stay bare.
          detailFor: (weekStart) {
            final data = list.asData?.value;
            if (data == null || weekStart != viewed) return null;
            return formatItemCount(
              data.groups.fold(0, (n, g) => n + g.items.length),
            );
          },
        ),
      ),
      // The status line sits between the header and the scroll, not inside it
      // (D9): mid-aisle, an answer that has scrolled away is no answer. The
      // shell's banner, when there is one, sits above this whole column — the
      // banner says something is wrong, this says where you stand.
      child: Column(
        children: [
          const AnsiSyncStatusLine(noun: 'tick'),
          Expanded(child: _list(context, ref, list)),
        ],
      ),
    );
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<ShoppingList> list,
  ) => list.when(
    loading: () => const Center(child: FCircularProgress()),
    error: (e, st) => AnsiErrorState(
      what: 'the shopping list',
      error: e,
      stackTrace: st,
      onRetry: () => ref.invalidate(currentShoppingListProvider),
    ),
    // D5b: the screen never swaps itself out for a data condition. An
    // empty list is a quiet line INSIDE the list chrome, keeping both of
    // this screen's affordances — the add-item door works with no plan at
    // all, which is exactly why it must not be taken away.
    data: (data) => ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 24),
      children: [
        const _ListCaption(),
        if (data.isEmpty) const _NothingToBuyLine(),
        for (final group in data.groups) _Group(group: group),
        // What the list is short by, and why it is silent about it
        // (step 8.6 / D4): an unresolved component contributes
        // nothing — never an invented quantity — so the parent it
        // belongs to says so and points at the surface that fixes
        // it. A list that is quietly short is worse than one that
        // says what it left out.
        for (final note in data.unresolvedComponents)
          _UnresolvedEcho(note: note),
        // …and what it left out BY RULE: an optional line contributes nothing,
        // and the recipe it belongs to says which lines, in the same voice —
        // muted, not amber, because a rule somebody chose is not a defect
        // somebody can fix.
        for (final note in data.optionalLines) OptionalLinesEcho(note: note),
        const _AddItemButton(),
      ],
    ),
  );
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

/// A recipe's "N optional lines not listed — lime, coriander" echo: the
/// group-header voice nested recipes' unresolved echo uses, because it is the
/// same shape of statement — a heading for the items that are NOT below it —
/// drawn muted rather than amber. Public so the screen test can find the row by
/// type.
class OptionalLinesEcho extends StatelessWidget {
  const OptionalLinesEcho({required this.note, super.key});

  final OptionalLinesNote note;

  /// `2 optional lines not listed — lime, coriander`.
  static String text(OptionalLinesNote note) {
    final n = note.names.length;
    return '$n optional line${n == 1 ? '' : 's'} not listed — '
        '${note.names.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
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
          Flexible(
            child: Text(
              text(note),
              overflow: TextOverflow.ellipsis,
              style: ansiMono(size: 10.5, color: AnsiColors.muted),
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

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(shoppingRepositoryProvider);
    final entryId = item.entryId;
    final what = item.checked ? 'untick ${item.name}' : 'tick ${item.name}';
    // A touched line (free-text, checked, or topped-up) has an entry; a purely
    // derived ingredient doesn't yet — check-off lazily creates it.
    if (entryId != null) {
      await ref.write(
        context,
        what,
        () => repo.setEntryChecked(entryId: entryId, checked: !item.checked),
      );
    } else {
      // The tick belongs to the week on screen (0018 / D3) — checking Flour
      // while looking at next week must not tick this week's Flour.
      await ref.write(
        context,
        what,
        () => repo.setIngredientChecked(
          ingredientId: item.ingredientId!,
          checked: !item.checked,
          weekStart: ref.read(viewedWeekStartProvider),
        ),
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
      onTap: () => _toggle(context, ref),
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

/// Nothing to buy, said inside the list chrome (D5b/D5c).
///
/// Shop was already closest to the house rule — it tells its two causes apart
/// and keeps `Add an item`, which works with no plan at all. All that changed
/// is that it stopped replacing the screen; the [_AddItemButton] below is now
/// permanently on screen rather than being swapped away with everything else.
class _NothingToBuyLine extends ConsumerWidget {
  const _NothingToBuyLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Two causes, told apart: nothing planned at all, versus meals planned
    // whose recipes have no ingredients to sum.
    final plannedButNoIngredients = ref
        .watch(currentCookPlanProvider)
        .maybeWhen(data: (plan) => !plan.isEmpty, orElse: () => false);
    final suffix = formatDerivedWeekSuffix(
      ref.watch(viewedWeekStartProvider),
      ref.watch(currentWeekStartProvider),
    );
    final week = suffix ?? 'this week';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plannedButNoIngredients
                ? 'nothing to sum yet — $week has meals, but their recipes '
                      'list no ingredients'
                : 'nothing to buy for $week yet — the list is summed from the '
                      'cook plan',
            style: ansiMono(size: 11.5, color: AnsiColors.muted),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () =>
                context.goOnce(plannedButNoIngredients ? '/' : '/week'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  plannedButNoIngredients
                      ? 'add ingredients to a recipe'
                      : 'plan a meal',
                  style: ansiMono(size: 11.5, color: AnsiColors.herbDeep),
                ),
                const SizedBox(width: 3),
                const Icon(
                  FLucideIcons.chevronRight,
                  size: 12,
                  color: AnsiColors.herbDeep,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmRemove(
  BuildContext context,
  WidgetRef ref,
  ShoppingItem item,
) async {
  // Everything the write needs is resolved BEFORE the dialog await: while it
  // sits open the watched stream can drop this row (say, the other device
  // removed it), unmounting the row widget — a `ref` used after the await
  // would then throw, and a `context.mounted` bail would drop the removal
  // the user just confirmed. The container and the host context outlive
  // the row (`hostContextOf`).
  final repo = ref.read(shoppingRepositoryProvider);
  final container = ProviderScope.containerOf(context, listen: false);
  final host = hostContextOf(context);
  final entryId = item.entryId;
  final remove = await askAnsi(
    context,
    title: 'Remove ${item.name}?',
    body: item.isFreeText
        ? 'This non-food item will be removed from the list.'
        : 'This removes ${item.name} and your top-up from the list.',
    confirm: 'Remove',
  );
  if (!remove || entryId == null) return;
  await container.write(
    host,
    'remove ${item.name}',
    () => repo.removeEntry(entryId: entryId),
  );
}
