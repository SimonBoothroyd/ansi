/// The Shop screen: the derived, provenance-aware shopping list (spec §4),
/// grouped by aisle, with ticked rows moving to a basket section at the bottom.
/// Only the overlay (check-offs and manual top-ups) persists and syncs.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_layout.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_scroll.dart';
import '../../../shared/cost_words.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/sync_status_line.dart';
import '../../../shared/write.dart';
import '../../account/data/household_providers.dart';
import '../../cook_plan/presentation/cook_view_models.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../planning/data/planning_providers.dart';
import '../../planning/presentation/week_format.dart';
import '../../planning/presentation/week_header.dart';
import '../../planning/presentation/week_in_the_location.dart';
import '../../planning/presentation/week_view_models.dart';
import '../../receipts/data/receipt_providers.dart';
import '../../recipes/domain/effective_lines.dart';
import '../data/shopping_providers.dart';
import '../domain/shopping.dart';
import '../domain/shopping_cost.dart';
import 'add_shopping_item_sheet.dart';
import 'confetti_burst.dart';
import 'edit_top_up_sheet.dart';
import 'shopping_format.dart';
import 'shopping_view_models.dart';

class ShoppingView extends ConsumerWidget {
  const ShoppingView({this.weekKey, super.key});

  /// The tab root's stable anchor: the header no longer names the screen, so
  /// the smoke test waits on this key instead of a title.
  static const rootKey = ValueKey('shop-root');

  /// `?week=YYYY-MM-DD`: the week this tab was opened at. It only seats the
  /// shared [viewedWeekStartProvider] on arrival ([WeekInTheLocation]).
  final String? weekKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(currentShoppingListProvider);
    final viewed = ref.watch(viewedWeekStartProvider);

    return WeekInTheLocation(
      path: '/shop',
      weekKey: weekKey,
      child: FScaffold(
        key: rootKey,
        // A tab root sits inside the shell's scaffold, which already shrinks
        // for the keyboard; a second inset would squeeze the content twice.
        resizeToAvoidBottomInset: false,
        // The list derives from the one viewed week, so the switcher is the
        // title.
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
          suffixes: const [_ReceiptsDoor()],
        ),
        // The status line sits outside the scroll and keeps its height whether
        // or not it says anything, so a tick never shifts the rows.
        child: Column(
          children: [
            // The trip estimate rides the sync line.
            AnsiSyncStatusLine(
              noun: 'tick',
              trailing: _TripEstimate(trip: ref.watch(shopTripCostProvider)),
            ),
            // At expanded width the walk stays one column; the width buys only
            // the breakdown pane beside it.
            Expanded(
              child: AnsiLayout.of(context) == AnsiLayout.expanded
                  ? const _WideShop()
                  : _shoppingList(context, ref, list),
            ),
          ],
        ),
      ),
    );
  }
}

/// The receipts ledger's door in the header, drawn only once the household has
/// kept a receipt. [FHeader.nested] keeps the week switcher centred, so no
/// balancing spacer is needed. [ScanReceiptDoor] is what introduces the
/// feature.
class _ReceiptsDoor extends ConsumerWidget {
  const _ReceiptsDoor();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(hasAnyReceiptProvider)
      ? FHeaderAction(
          icon: const Icon(FLucideIcons.receipt),
          semanticsLabel: 'Receipts',
          onPress: () => context.pushOnce('/receipts'),
        )
      : const SizedBox.shrink();
}

/// `≈ $58 still to buy` on the sync line, at the latest prices (ADR-0017); `at
/// least $58 still to buy · 2 rows unpriced` where a row has no price. Draws
/// nothing when no open row can be priced, since `≈ $0` would read as free.
class _TripEstimate extends StatelessWidget {
  const _TripEstimate({required this.trip});

  final TripCost trip;

  @override
  Widget build(BuildContext context) {
    final line = tripEstimate(trip);
    return line == null
        ? const SizedBox.shrink()
        : Text(line, style: ansiMono(size: 11, color: AnsiColors.muted));
  }
}

/// The walk: aisles, basket, echo rows and the add door. [selection] is null on
/// a phone, where each row draws its own breakdown. At [AnsiLayout.expanded] it
/// drives the pane: a tap outside a row's check box selects that row, and no
/// row draws a breakdown.
Widget _shoppingList(
  BuildContext context,
  WidgetRef ref,
  AsyncValue<ShoppingList> list, {
  _Selection? selection,
}) => list.when(
  loading: () => const Center(child: FCircularProgress()),
  error: (e, st) => AnsiErrorState(
    what: 'the shopping list',
    error: e,
    stackTrace: st,
    onRetry: () => ref.invalidate(currentShoppingListProvider),
  ),
  // An empty list is a quiet line inside the list chrome, so the add-item door
  // stays available with no plan at all.
  data: (data) => ListView(
    padding: ansiScrollPadding(
      context,
      const EdgeInsets.only(top: 6, bottom: 24),
    ),
    children: [
      const _ListCaption(),
      if (data.isEmpty) const _NothingToBuyLine(),
      // The aisles hold only unticked rows; when all are ticked a line says so.
      if (data.allTicked) const _EverythingInBasketLine(),
      for (final group in data.openGroups)
        _Group(group: group, selection: selection),
      if (data.basket.isNotEmpty)
        _Basket(groups: data.basketGroups, selection: selection),
      // An unresolved component contributes nothing, so its parent recipe says
      // so and points at the Cook tab.
      for (final note in data.unresolvedComponents) _UnresolvedEcho(note: note),
      // A line or planned meal whose vocab row was retired. Amber: it is
      // fixable.
      for (final note in data.retiredIngredients)
        RetiredIngredientEcho(note: note),
      // Optional lines left out by rule. Muted: a choice, not a defect.
      for (final note in data.optionalLines) OptionalLinesEcho(note: note),
      const _AddItemButton(),
      const ScanReceiptDoor(),
    ],
  ),
);

/// The row the provenance pane is reading, named by [shoppingItemIdentity]
/// because an index does not survive a re-derivation.
class _Selection {
  const _Selection({required this.identity, required this.read});

  /// The identity of the row the pane is on.
  final String identity;

  /// Points the pane at a row — what a tap on the row does at this width. The
  /// check box keeps the tick.
  final ValueChanged<ShoppingItem> read;
}

/// The Shop at [AnsiLayout.expanded]: the walk, with the breakdown pane beside
/// it. The pane reads one row and changes nothing.
class _WideShop extends ConsumerStatefulWidget {
  const _WideShop();

  @override
  ConsumerState<_WideShop> createState() => _WideShopState();
}

class _WideShopState extends ConsumerState<_WideShop> {
  /// The row the pane was pointed at, or null while it reads the first row. An
  /// identity, so the pane follows a row that is ticked into the basket.
  String? _reading;

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(currentShoppingListProvider);
    final data = list.asData?.value;
    // Aisle order, the walk before the basket — so "the first row" is the first
    // thing still to grab, which is where a shopper is.
    final rows = <({ShoppingItem item, String aisle})>[
      for (final g in data?.openGroups ?? const <ShoppingGroup>[])
        for (final i in g.items) (item: i, aisle: g.label),
      for (final g in data?.basketGroups ?? const <ShoppingGroup>[])
        for (final i in g.items) (item: i, aisle: g.label),
    ];
    final reading =
        rows
            .where((r) => shoppingItemIdentity(r.item) == _reading)
            .firstOrNull ??
        rows.firstOrNull;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ansiMeasureWidth(context) + kProvenancePaneWidth,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _shoppingList(
                context,
                ref,
                list,
                selection: reading == null
                    ? null
                    : _Selection(
                        identity: shoppingItemIdentity(reading.item),
                        read: (item) => setState(
                          () => _reading = shoppingItemIdentity(item),
                        ),
                      ),
              ),
            ),
            _ProvenancePane(item: reading?.item, aisle: reading?.aisle),
          ],
        ),
      ),
    );
  }
}

/// The row the provenance pane is reading — exported so a test names the lit
/// row rather than hunting for a background colour. Only one row carries it.
const kShopReadingRowKey = ValueKey('shop-reading-row');

/// How wide the provenance pane is drawn on a wide screen.
const kProvenancePaneWidth = 360.0;

/// The breakdown held open beside the walk: the row, its total, the
/// contributions behind it and the editable manual top-up.
class _ProvenancePane extends StatelessWidget {
  const _ProvenancePane({required this.item, required this.aisle});

  /// Null only while the list is empty or still loading — there is no row to
  /// read then, and the pane says so rather than drawing an empty frame.
  final ShoppingItem? item;
  final String? aisle;

  @override
  Widget build(BuildContext context) {
    final row = item;
    return Container(
      width: kProvenancePaneWidth,
      decoration: const BoxDecoration(
        color: AnsiColors.paper,
        border: Border(left: BorderSide(color: AnsiColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
      child: row == null
          ? Text(
              'nothing to trace yet',
              style: ansiMono(size: 11.5, color: AnsiColors.muted),
            )
          : ListView(
              children: [
                Text(
                  'Where it came from'.toUpperCase(),
                  style: ansiMono(
                    size: 10,
                    color: AnsiColors.muted,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(child: Text(row.name, style: ansiSans(size: 14))),
                    const SizedBox(width: 8),
                    Text(
                      itemTotal(row),
                      style: ansiMono(size: 13, weight: FontWeight.w500),
                    ),
                  ],
                ),
                if (itemSecondary(row) case final secondary
                    when secondary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      secondary,
                      style: ansiMono(size: 10.5, color: AnsiColors.herbDeep),
                    ),
                  ),
                // The row's aisle, and whether it is already in the basket.
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    [
                      ?aisle?.toUpperCase(),
                      if (row.checked) 'In the basket'.toUpperCase(),
                    ].join(' · '),
                    style: ansiMono(
                      size: 9,
                      color: AnsiColors.muted,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(height: 1, color: AnsiColors.line),
                const SizedBox(height: 12),
                if (row.contributions.isEmpty)
                  Text(
                    'nothing to trace — an item you added by hand',
                    style: ansiMono(size: 10.5, color: AnsiColors.muted),
                  )
                else
                  _Provenance(
                    itemName: row.name,
                    ingredientId: row.ingredientId,
                    contributions: row.contributions,
                  ),
              ],
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
  const _Group({required this.group, this.selection});

  final ShoppingGroup group;
  final _Selection? selection;

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
        for (final item in group.items)
          _ItemRow(item: item, selection: selection),
      ],
    );
  }
}

/// The section every ticked row moves to (`IN THE BASKET · 4`), keeping its
/// aisles inside it. Tapping a row unticks it.
class _Basket extends StatelessWidget {
  const _Basket({required this.groups, this.selection});

  final List<ShoppingGroup> groups;
  final _Selection? selection;

  @override
  Widget build(BuildContext context) {
    final count = groups.fold(0, (n, g) => n + g.items.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
          child: Text(
            'In the basket · $count'.toUpperCase(),
            style: ansiMono(
              size: 10,
              color: AnsiColors.muted,
              letterSpacing: 1.4,
            ),
          ),
        ),
        for (final group in groups) ...[
          // The aisle's own label, a size down and set in from the box so it
          // reads as a section OF the basket rather than a second aisle.
          Padding(
            padding: const EdgeInsets.fromLTRB(51, 8, 20, 4),
            child: Text(
              group.label.toUpperCase(),
              style: ansiMono(
                size: 9,
                color: AnsiColors.muted,
                letterSpacing: 1.2,
              ),
            ),
          ),
          for (final item in group.items)
            _ItemRow(item: item, selection: selection),
        ],
      ],
    );
  }
}

/// Shown where the aisles were once every item is ticked.
class _EverythingInBasketLine extends StatelessWidget {
  const _EverythingInBasketLine();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Text(
        'everything’s in the basket',
        style: ansiMono(size: 11.5, color: AnsiColors.muted),
      ),
    );
  }
}

/// A parent recipe's "N components unresolved — see Cook" echo, in the
/// group-header voice.
class _UnresolvedEcho extends StatelessWidget {
  const _UnresolvedEcho({required this.note});

  final UnresolvedComponentNote note;

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
          const Icon(FLucideIcons.flag, size: 11, color: AnsiColors.cautionInk),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '$count ${plural(count, 'component')} unresolved — see Cook',
              overflow: TextOverflow.ellipsis,
              style: ansiMono(size: 10.5, color: AnsiColors.cautionInk),
            ),
          ),
        ],
      ),
    );
  }
}

/// A line at a retired ingredient: "SAUERKRAUT · ingredient removed · pick
/// again in the recipe". Amber, like the unresolved echo. Names where the pick
/// is: the recipe for a recipe line, the plan for a bare-ingredient meal.
/// Public so the screen test can find the row by type.
class RetiredIngredientEcho extends StatelessWidget {
  const RetiredIngredientEcho({required this.note, super.key});

  final RetiredIngredientNote note;

  /// `Sauerkraut · ingredient removed · pick again in the recipe`: the words of
  /// `RemovedIngredientTag`, with the surface that holds the pick named last.
  static String text(RetiredIngredientNote note) {
    final where = switch (note.site) {
      RetiredIngredientSite.recipeLine => 'recipe',
      RetiredIngredientSite.planEntry => 'plan',
    };
    return '${note.ingredientName} · ingredient removed · '
        'pick again in the $where';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        children: [
          Flexible(
            child: Text(
              note.heading.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: ansiMono(
                size: 10,
                color: AnsiColors.muted,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(FLucideIcons.flag, size: 11, color: AnsiColors.cautionInk),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text(note),
              overflow: TextOverflow.ellipsis,
              style: ansiMono(size: 10.5, color: AnsiColors.cautionInk),
            ),
          ),
        ],
      ),
    );
  }
}

/// A recipe's "N optional lines not listed — lime, coriander" echo, muted. A
/// line this week left out takes the same row ("1 line left out this week — Red
/// wine").
///
/// On an optional row each name is a door: a tap writes this week's include row
/// for that line. A week exclusion keeps plain words; it is undone where it was
/// made. Stateful only to own the tap recognizers. Public so the screen test
/// can find the row by type.
class OptionalLinesEcho extends ConsumerStatefulWidget {
  const OptionalLinesEcho({required this.note, super.key});

  final OptionalLinesNote note;

  /// `2 optional lines not listed — lime, coriander`, or
  /// `1 line left out this week — Red wine`.
  static String text(OptionalLinesNote note) =>
      lead(note) + note.names.join(', ');

  /// The sentence up to the names — `2 optional lines not listed — `, the run
  /// that stays plain when the names become doors.
  static String lead(OptionalLinesNote note) {
    final n = note.names.length;
    return switch (note.reason) {
      LineDropReason.optional =>
        '$n optional ${plural(n, 'line')} not listed — ',
      LineDropReason.thisWeek =>
        '$n ${plural(n, 'line')} left out this week — ',
    };
  }

  @override
  ConsumerState<OptionalLinesEcho> createState() => _OptionalLinesEchoState();
}

class _OptionalLinesEchoState extends ConsumerState<OptionalLinesEcho> {
  final _taps = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final tap in _taps) {
      tap.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final muted = ansiMono(size: 10.5, color: AnsiColors.muted);
    // A door only where there is a decision; a row whose ids and names do not
    // line up says its sentence plainly.
    final isDoor =
        note.reason == LineDropReason.optional &&
        note.lineIds.length == note.names.length;
    final week = ref.watch(viewedWeekStartProvider);

    final wanted = isDoor ? note.names.length : 0;
    while (_taps.length < wanted) {
      _taps.add(TapGestureRecognizer());
    }
    while (_taps.length > wanted) {
      _taps.removeLast().dispose();
    }
    for (var i = 0; i < wanted; i++) {
      final lineId = note.lineIds[i];
      _taps[i].onTap = () => ref.write(
        context,
        'include it this week',
        () => ref
            .read(weekVariantRepositoryProvider)
            .setLineIncluded(week, note.recipeId, lineId, included: true),
      );
    }

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
            child: Text.rich(
              TextSpan(
                text: OptionalLinesEcho.lead(note),
                children: [
                  for (var i = 0; i < note.names.length; i++) ...[
                    if (i > 0) const TextSpan(text: ', '),
                    TextSpan(
                      text: note.names[i],
                      style: isDoor
                          ? ansiMono(
                              size: 10.5,
                              color: AnsiColors.herbDeep,
                            ).copyWith(fontWeight: FontWeight.w500)
                          : null,
                      recognizer: isDoor ? _taps[i] : null,
                    ),
                  ],
                ],
              ),
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// One shopping line: check box, name, total, and the provenance breakdown
/// under it. On a phone a tap anywhere toggles the tick; at
/// [AnsiLayout.expanded] only the box does. A purely user-added line can be
/// removed by swipe or long-press; a cook-derived one cannot.
class _ItemRow extends ConsumerStatefulWidget {
  const _ItemRow({required this.item, this.selection});

  final ShoppingItem item;

  /// Non-null at [AnsiLayout.expanded]: the check box is then the only thing
  /// that ticks, a tap elsewhere points the pane at the row, and the selected
  /// row is lit.
  final _Selection? selection;

  @override
  ConsumerState<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends ConsumerState<_ItemRow> {
  /// The check box's own box, so the burst comes from under the thumb.
  final _box = GlobalKey();

  ShoppingItem get item => widget.item;

  Future<void> _toggle() async {
    final repo = ref.read(shoppingRepositoryProvider);
    final entryId = item.entryId;
    final what = item.checked ? 'untick ${item.name}' : 'tick ${item.name}';
    // Decided on the list as it stands, before the write and before any await.
    _celebrateIfLastTick();
    // A touched line (free-text, checked, or topped-up) has an entry; a purely
    // derived ingredient doesn't yet — check-off lazily creates it.
    if (entryId != null) {
      await ref.write(
        context,
        what,
        () => repo.setEntryChecked(entryId: entryId, checked: !item.checked),
      );
    } else {
      // The tick belongs to the week on screen: checking Flour while looking at
      // next week must not tick this week's Flour.
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

  /// The last tick's celebration: a light haptic and, unless animations are
  /// off, confetti from this row's box. Asked before the write
  /// ([completesTheList]), so another phone's finish plays nothing.
  void _celebrateIfLastTick() {
    final list = ref.read(currentShoppingListProvider).asData?.value;
    if (list == null || !completesTheList(list, item)) return;
    unawaited(HapticFeedback.lightImpact());
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    final box = _box.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    playConfettiBurst(
      context,
      origin: box.localToGlobal(box.size.center(Offset.zero)),
      seed: shoppingItemIdentity(item).hashCode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = _rowBody();
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

  Widget _rowBody() {
    // A ticked row carries no estimate: it is in the basket, and the figure
    // on the sync line is about what is left to buy.
    final secondary = item.checked
        ? ''
        : itemSecondaryWithCost(
            item,
            cents: shoppingItemCostCents(
              item,
              ref.watch(ingredientPricingProvider)[item.ingredientId],
            ),
            // A blank row is a gap only once something on this trip has a
            // price; before that the household simply has not started.
            anyPriced: ref.watch(shopTripCostProvider).cents != null,
          );
    final selection = widget.selection;
    final reading =
        selection != null && selection.identity == shoppingItemIdentity(item);
    final name = Text(
      item.name,
      style: ansiSans(
        size: 14,
        color: item.checked ? AnsiColors.muted : AnsiColors.ink,
      ).copyWith(decoration: item.checked ? TextDecoration.lineThrough : null),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // On a phone the row is the tick; at expanded the row points the pane.
      onTap: selection == null ? _toggle : () => selection.read(item),
      onLongPress: item.isUserAdded
          ? () => _confirmRemove(context, ref, item)
          : null,
      child: Container(
        key: reading ? kShopReadingRowKey : null,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: EdgeInsets.symmetric(
          // At expanded the vertical padding moves into the tick target below.
          vertical: selection == null ? 11 : 0,
          horizontal: reading ? 11 : 0,
        ),
        decoration: reading
            ? BoxDecoration(
                color: AnsiColors.herbSoft,
                borderRadius: BorderRadius.circular(11),
              )
            : const BoxDecoration(
                color: AnsiColors.surface,
                border: Border(bottom: BorderSide(color: AnsiColors.line)),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (selection == null) ...[
                  _CheckBox(key: _box, checked: item.checked),
                  const SizedBox(width: 11),
                ] else
                  // The wide row's tick target: the box where the phone draws
                  // it, inside a 31 × 44 target spanning the row's height.
                  GestureDetector(
                    key: shopTickTargetKey(shoppingItemIdentity(item)),
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggle,
                    child: SizedBox(
                      width: 31,
                      height: 44,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _CheckBox(key: _box, checked: item.checked),
                      ),
                    ),
                  ),
                Expanded(child: name),
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
            // What a measure-counted row weighs, or the whole-unit round-up;
            // always under the total, never replacing it (invariant 3).
            if (secondary.isNotEmpty) ...[
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.only(left: 31),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    secondary,
                    style: ansiMono(size: 10.5, color: AnsiColors.herbDeep),
                  ),
                ),
              ),
            ],
            // Every row says where it came from: under the row on a phone, in
            // the pane at expanded.
            if (selection == null &&
                !item.checked &&
                item.contributions.isNotEmpty) ...[
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
            // The bottom half of the padding the tick target took, put back
            // under a tail that would otherwise sit on the hairline.
            if (selection != null && secondary.isNotEmpty)
              const SizedBox(height: 11),
          ],
        ),
      ),
    );
  }
}

/// The key on a wide row's tick target, named by [shoppingItemIdentity] so a
/// test can tick a named row.
ValueKey<String> shopTickTargetKey(String identity) =>
    ValueKey('shop-tick-$identity');

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

/// The provenance breakdown: one line per contribution, source left, quantity
/// right. Manual top-ups read muted italic and tap to edit or remove.
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

/// The check box: a rounded square, filled herb-green with a white tick when
/// on.
class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.checked, super.key});

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

/// The scan-receipt door at the foot of the list, beside the top-up door. On
/// the web the photo import is gated (`photo_intake.dart`), so the door says
/// what it can do there. The ledger's door is [_ReceiptsDoor] in the header.
class ScanReceiptDoor extends StatelessWidget {
  const ScanReceiptDoor({this.web = kIsWeb, super.key});

  /// The platform, injectable so both sets of words are testable on a VM that
  /// is never `kIsWeb`.
  final bool web;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.pushOnce('/receipts/review'),
            child: DashedBorderBox(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    FLucideIcons.camera,
                    size: 12,
                    color: AnsiColors.herb,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'scan a receipt',
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
          if (web)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'in a browser there is no camera and no crop step — shoot the '
                'receipt on the phone, and review it anywhere',
                style: ansiMono(size: 10.5, color: AnsiColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// Nothing to buy, said inside the list chrome; the [_AddItemButton] below
/// stays on screen.
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
      ref.watch(weekShapeProvider),
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
  // Resolve everything the write needs before the dialog await: the watched
  // stream can drop this row while the dialog is open, after which `ref` throws
  // and a `context.mounted` bail would lose the confirmed removal. The
  // container and host context outlive the row (`hostContextOf`).
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
