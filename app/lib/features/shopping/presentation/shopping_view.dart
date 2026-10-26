/// The Shop screen: the derived, provenance-aware shopping list (spec §4),
/// grouped by aisle, with ticked rows moving to a basket section at the bottom.
/// Only the overlay (check-offs and manual top-ups) persists and syncs.
library;

import 'dart:async';

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
import '../../../shared/guarded_navigation.dart';
import '../../../shared/sync_status_line.dart';
import '../../../shared/write.dart';
import '../../account/data/household_providers.dart';
import '../../ask/domain/ask_screen.dart';
import '../../ask/presentation/ask_door.dart';
import '../../cook_plan/presentation/cook_view_models.dart';
import '../../planning/data/planning_providers.dart';
import '../../planning/presentation/week_format.dart';
import '../../planning/presentation/week_header.dart';
import '../../planning/presentation/week_in_the_location.dart';
import '../../planning/presentation/week_view_models.dart';
import '../../recipes/domain/effective_lines.dart';
import '../data/shopping_providers.dart';
import '../domain/at_home.dart';
import '../domain/shopping.dart';
import '../domain/shopping_cost.dart';
import 'at_home_sheet.dart';
import 'confetti_burst.dart';
import 'edit_top_up_sheet.dart';
import 'shop_add_field.dart';
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
    final checking = ref.watch(shopCheckingProvider);
    final anyOpen = ref.watch(shopOpenProvider.select((o) => o.isNotEmpty));
    // Leaving the tab ends the checking pass and folds whatever was opened.
    // The shell keeps a hidden tab mounted with its tickers off, so that is
    // how "left" reads here.
    if ((checking || anyOpen) && !TickerMode.valuesOf(context).enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref.read(shopCheckingProvider.notifier).done();
        ref.read(shopOpenProvider.notifier).reset();
      });
    }
    final wide = AnsiLayout.of(context) == AnsiLayout.expanded;

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
          suffixes: const [
            _ReceiptsDoor(),
            AskDoor(tab: AskWeekTab.shop),
          ],
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
            // At expanded the toggle and the add field sit over the walk's
            // own column instead.
            if (!wide) const ShopToggle(),
            // At expanded width the walk stays one column; the width buys only
            // the breakdown pane beside it.
            Expanded(
              child: wide
                  ? const _WideShop()
                  : ShopAddField(walk: _shoppingList(context, ref, list)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The receipts ledger's door in the header, always drawn: the ledger is where
/// a receipt is scanned, so the door cannot wait for the first one.
/// [FHeader.nested] keeps the week switcher centred, so no balancing spacer is
/// needed.
class _ReceiptsDoor extends StatelessWidget {
  const _ReceiptsDoor();

  @override
  Widget build(BuildContext context) => FHeaderAction(
    icon: const Icon(FLucideIcons.receipt),
    semanticsLabel: 'Receipts',
    onPress: () => context.pushOnce('/receipts'),
  );
}

/// `≈ $58 at the cheapest` on the sync line, the sum of the rows' figures at
/// the Shop's prices (ADR-0017); `at least $58 at the cheapest · 2 rows
/// unpriced` where a row has no price. Draws nothing when no open row can be
/// priced, since `≈ $0` would read as free.
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

/// The walk: the aisles, then three folded lines (the basket, *At home* and
/// the plan's notes). [selection] is null on a phone, where
/// a row opens its own breakdown from its amount. At [AnsiLayout.expanded] it
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
  // An empty list is a quiet line inside the list chrome, so the add field
  // above it stays available with no plan at all.
  data: (data) => ref.watch(shopCheckingProvider)
      ? _checkingList(context, data, selection: selection)
      : ListView(
          padding: ansiScrollPadding(
            context,
            const EdgeInsets.only(top: 6, bottom: 24),
          ),
          children: [
            if (data.isEmpty) const _NothingToBuyLine(),
            // The aisles hold only what is left to buy; when nothing is, a line
            // says why — all of it at home, or in the basket.
            if (data.allAtHome)
              const _EverythingAtHomeLine()
            else if (data.allTicked)
              const _EverythingInBasketLine(),
            for (final group in data.openGroups)
              _Group(group: group, selection: selection),
            // The folded lines close the walk, set off from the last aisle.
            if (data.basket.isNotEmpty ||
                data.atHome.isNotEmpty ||
                _noteCount(data) > 0)
              const SizedBox(height: 14),
            if (data.basket.isNotEmpty)
              _Basket(groups: data.basketGroups, selection: selection),
            // Then what was never on the trip.
            if (data.atHome.isNotEmpty)
              _AtHomeSection(items: data.atHome, selection: selection),
            if (_noteCount(data) > 0) _PlanNotes(list: data),
          ],
        ),
);

/// The rows the checking pass walks: every ingredient row not yet ticked, in
/// its aisle — at home or not, since a tap there takes it back.
List<ShoppingGroup> _checkingGroups(ShoppingList data) => [
  for (final g in data.groups)
    if (g.items.any(_checkable))
      g.copyWith(
        items: [
          for (final i in g.items)
            if (_checkable(i)) i,
        ],
      ),
];

bool _checkable(ShoppingItem i) => !i.isFreeText && !i.checked;

/// Whether the list holds an ingredient row, ticked or not: what the
/// `To buy · At home?` toggle needs before it is drawn.
bool _hasIngredientRow(ShoppingList data) =>
    data.groups.any((g) => g.items.any((i) => !i.isFreeText));

/// The checking pass: the same aisles, each row a house and an amount. No
/// provenance, prices, basket, free text or echo rows — the only question is
/// what is already here.
Widget _checkingList(
  BuildContext context,
  ShoppingList data, {
  _Selection? selection,
}) {
  final groups = _checkingGroups(data);
  return ListView(
    padding: ansiScrollPadding(
      context,
      const EdgeInsets.only(top: 6, bottom: 24),
    ),
    children: [
      if (groups.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Text(
            'nothing left to check',
            style: ansiMono(size: 11.5, color: AnsiColors.muted),
          ),
        ),
      for (final g in groups) ...[
        _GroupLabel(label: g.label),
        for (final item in g.items) _HomeRow(item: item, selection: selection),
      ],
    ],
  );
}

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
    final checking = ref.watch(shopCheckingProvider);
    // Aisle order, the walk before the basket — so "the first row" is the first
    // thing still to grab, which is where a shopper is. While checking, the
    // rows are the pass's own.
    final rows = <({ShoppingItem item, String aisle})>[
      if (checking && data != null)
        for (final g in _checkingGroups(data))
          for (final i in g.items) (item: i, aisle: g.label)
      else ...[
        for (final g in data?.openGroups ?? const <ShoppingGroup>[])
          for (final i in g.items) (item: i, aisle: g.label),
        for (final g in data?.basketGroups ?? const <ShoppingGroup>[])
          for (final i in g.items) (item: i, aisle: g.label),
        for (final i in data?.atHome ?? const <ShoppingItem>[])
          (item: i, aisle: 'At home'),
      ],
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ShopToggle(),
                  Expanded(
                    child: ShopAddField(
                      walk: _shoppingList(
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
                  ),
                ],
              ),
            ),
            // While checking, the pane trades its question: not where a row
            // came from, but how much of it is already here.
            if (checking)
              _AtHomePane(item: reading?.item)
            else
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
                if (atHomeWords(row) case final home
                    when home.isNotEmpty && !row.isAtHome)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      home,
                      style: ansiMono(size: 10.5, color: AnsiColors.muted),
                    ),
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
                      if (!row.checked && row.isAtHome) 'At home'.toUpperCase(),
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

class _Group extends StatelessWidget {
  const _Group({required this.group, this.selection});

  final ShoppingGroup group;
  final _Selection? selection;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupLabel(label: group.label),
        for (final item in group.items)
          _ItemRow(item: item, selection: selection),
      ],
    );
  }
}

/// An aisle's label over its rows (`PRODUCE`).
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(
        label.toUpperCase(),
        style: ansiMono(size: 10, color: AnsiColors.muted, letterSpacing: 1.4),
      ),
    );
  }
}

/// The section every ticked row moves to, folded to one counted line (`IN THE
/// BASKET · 4`) until it is tapped open. Opened, it keeps its aisles inside it,
/// and tapping a row unticks it.
class _Basket extends ConsumerWidget {
  const _Basket({required this.groups, this.selection});

  final List<ShoppingGroup> groups;
  final _Selection? selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = groups.fold(0, (n, g) => n + g.items.length);
    final open = ref.watch(
      shopOpenProvider.select((o) => o.contains(ShopFold.basket)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FoldLine(
          fold: ShopFold.basket,
          open: open,
          label: 'In the basket · $count'.toUpperCase(),
        ),
        if (open)
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

/// The key on a folded section's counted line.
ValueKey<String> shopFoldKey(ShopFold fold) => ValueKey('shop-fold-$fold');

/// How a folded line reads: an uppercase label, or the notes' sentence in
/// amber with its flag, or the same sentence muted.
enum _FoldTone { label, defect, quiet }

/// One folded section's line: its words, and the chevron that says whether it
/// is open (down) or not (right). A tap opens or folds it in place. At least
/// 44 px tall, the whole width of the walk.
class _FoldLine extends ConsumerWidget {
  const _FoldLine({
    required this.fold,
    required this.open,
    required this.label,
    this.tone = _FoldTone.label,
  });

  final ShopFold fold;
  final bool open;
  final String label;
  final _FoldTone tone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = switch (tone) {
      _FoldTone.label => ansiMono(
        size: 10,
        color: AnsiColors.muted,
        letterSpacing: 1.4,
      ),
      _FoldTone.defect => ansiMono(size: 11, color: AnsiColors.cautionInk),
      _FoldTone.quiet => ansiMono(size: 11, color: AnsiColors.muted),
    };
    return GestureDetector(
      key: shopFoldKey(fold),
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(shopOpenProvider.notifier).toggle(fold),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        constraints: const BoxConstraints(minHeight: 44),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AnsiColors.line)),
        ),
        child: Row(
          children: [
            if (tone == _FoldTone.defect) ...[
              const Icon(
                FLucideIcons.flag,
                size: 11,
                color: AnsiColors.cautionInk,
              ),
              const SizedBox(width: 6),
            ],
            Expanded(child: Text(label, style: style)),
            _Chevron(open: open),
          ],
        ),
      ),
    );
  }
}

/// The open cue, as the Library's folds draw it: right while closed, down once
/// open. It says what is, not what a tap will do.
class _Chevron extends StatelessWidget {
  const _Chevron({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) => Icon(
    open ? FLucideIcons.chevronDown : FLucideIcons.chevronRight,
    size: 13,
    color: AnsiColors.herb,
  );
}

/// How many notes the plan left: the unresolved components, the retired
/// ingredients and the lines left out.
int _noteCount(ShoppingList list) =>
    list.unresolvedComponents.length +
    list.retiredIngredients.length +
    list.optionalLines.length;

/// The plan's notes, folded behind one line: `3 notes from the plan`, amber
/// with a flag while any of them is a defect (an unresolved component, a
/// retired ingredient), muted when every one is a line left out. Opened, it
/// holds today's echo rows, the optional names still doors.
class _PlanNotes extends ConsumerWidget {
  const _PlanNotes({required this.list});

  final ShoppingList list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = _noteCount(list);
    final defect =
        list.unresolvedComponents.isNotEmpty ||
        list.retiredIngredients.isNotEmpty;
    final open = ref.watch(
      shopOpenProvider.select((o) => o.contains(ShopFold.notes)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FoldLine(
          fold: ShopFold.notes,
          open: open,
          label: '$count ${plural(count, 'note')} from the plan',
          tone: defect ? _FoldTone.defect : _FoldTone.quiet,
        ),
        if (open) ...[
          // An unresolved component contributes nothing, so its parent recipe
          // says so and points at the Cook tab.
          for (final note in list.unresolvedComponents)
            _UnresolvedEcho(note: note),
          // A line or planned meal whose vocab row was retired. Amber: it is
          // fixable.
          for (final note in list.retiredIngredients)
            RetiredIngredientEcho(note: note),
          // Optional lines left out by rule. Muted: a choice, not a defect.
          for (final note in list.optionalLines) OptionalLinesEcho(note: note),
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

/// One shopping line: check box, name, total and its sub-line. On a phone a
/// tap on the row toggles the tick, and a tap on the amount (its chevron, its
/// sub-line) opens the breakdown under it; at [AnsiLayout.expanded] only the
/// box ticks, and the breakdown is the pane's. A purely user-added line can be
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
    // A ticked row folds its breakdown; unticked, it comes back closed.
    if (!item.checked) {
      ref.read(shopOpenProvider.notifier).close(shoppingItemIdentity(item));
    }
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
    final pricing = ref.watch(shopPricingProvider)[item.ingredientId];
    final secondary = item.checked
        ? ''
        : itemSecondaryWithCost(
            item,
            cents: shoppingItemCostCents(item, pricing),
            price: pricing?.price,
            // A blank row is a gap only once something on this trip has a
            // price; before that the household simply has not started.
            anyPriced: ref.watch(shopTripCostProvider).cents != null,
          );
    // A part-have opens the sub-line, and a rounded row's need follows it,
    // both muted: the reasons the headline is what it is, read at the same
    // glance as it. The need is where [itemSecondary] starts.
    final home = item.checked ? '' : atHomeWords(item);
    final need = item.checked ? '' : itemNeed(item);
    final rest = need.isNotEmpty && secondary.startsWith(need)
        ? secondary.substring(need.length).replaceFirst(' · ', '')
        : secondary;
    final muted = [home, need].where((w) => w.isNotEmpty).join(' · ');
    final hasSub = muted.isNotEmpty || rest.isNotEmpty;
    final selection = widget.selection;
    final identity = shoppingItemIdentity(item);
    final reading = selection != null && selection.identity == identity;
    // The breakdown opens on a phone only, from a row that has one and is
    // still to grab.
    final canOpen =
        selection == null && !item.checked && item.contributions.isNotEmpty;
    final open =
        canOpen &&
        ref.watch(shopOpenProvider.select((o) => o.contains(identity)));
    void flip() => ref.read(shopOpenProvider.notifier).toggle(identity);

    final name = Text(
      item.name,
      style: ansiSans(
        size: 14,
        color: item.checked ? AnsiColors.muted : AnsiColors.ink,
      ).copyWith(decoration: item.checked ? TextDecoration.lineThrough : null),
    );
    final total = Text(
      itemTotal(item),
      style: ansiMono(
        size: 13,
        weight: FontWeight.w500,
        color: item.checked ? AnsiColors.muted : AnsiColors.ink,
      ),
    );
    // What a counted row weighs, its need, or what is at home; always under
    // the headline, never replacing it (invariant 3).
    final subLine = Align(
      alignment: Alignment.centerRight,
      child: Text.rich(
        TextSpan(
          children: [
            if (muted.isNotEmpty)
              TextSpan(
                text: muted,
                style: ansiMono(size: 10.5, color: AnsiColors.muted),
              ),
            if (muted.isNotEmpty && rest.isNotEmpty)
              const TextSpan(text: ' · '),
            if (rest.isNotEmpty) TextSpan(text: rest),
          ],
        ),
        style: ansiMono(size: 10.5, color: AnsiColors.herbDeep),
      ),
    );

    final Widget body;
    if (selection != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The wide row's tick target: the box where the phone draws it,
              // inside a 31 × 44 target spanning the row's height.
              GestureDetector(
                key: shopTickTargetKey(identity),
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
              total,
            ],
          ),
          if (hasSub) ...[
            const SizedBox(height: 3),
            Padding(padding: const EdgeInsets.only(left: 31), child: subLine),
            // The bottom half of the padding the tick target took, put back
            // under a tail that would otherwise sit on the hairline.
            const SizedBox(height: 11),
          ],
        ],
      );
    } else {
      // On a phone each part of the top line carries the row's vertical
      // padding itself, so the amount's target reaches the row's edge and,
      // with the sub-line under it, is never less than 44 px tall.
      final pad = EdgeInsets.only(top: 12, bottom: hasSub ? 3 : 12);
      final amount = canOpen
          ? GestureDetector(
              key: shopAmountTargetKey(identity),
              behavior: HitTestBehavior.opaque,
              onTap: flip,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: 44,
                  minHeight: hasSub ? 0 : 44,
                ),
                child: Padding(
                  padding: pad.copyWith(left: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      total,
                      const SizedBox(width: 5),
                      _Chevron(open: open),
                    ],
                  ),
                ),
              ),
            )
          : Padding(padding: pad.copyWith(left: 8), child: total);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Padding(
                padding: pad,
                child: _CheckBox(key: _box, checked: item.checked),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Padding(padding: pad, child: name),
              ),
              amount,
            ],
          ),
          // The sub-line is the amount's target too: one door, under the
          // figure it explains.
          if (hasSub)
            GestureDetector(
              behavior: canOpen
                  ? HitTestBehavior.opaque
                  : HitTestBehavior.deferToChild,
              onTap: canOpen ? flip : null,
              child: Padding(
                padding: EdgeInsets.only(left: 31, bottom: open ? 0 : 11),
                child: subLine,
              ),
            ),
          if (open)
            Padding(
              padding: EdgeInsets.fromLTRB(31, hasSub ? 6 : 0, 0, 11),
              child: _Provenance(
                itemName: item.name,
                ingredientId: item.ingredientId,
                contributions: item.contributions,
              ),
            ),
        ],
      );
    }

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
        padding: EdgeInsets.symmetric(horizontal: reading ? 11 : 0),
        decoration: reading
            ? BoxDecoration(
                color: AnsiColors.herbSoft,
                borderRadius: BorderRadius.circular(11),
              )
            : const BoxDecoration(
                color: AnsiColors.surface,
                border: Border(bottom: BorderSide(color: AnsiColors.line)),
              ),
        child: body,
      ),
    );
  }
}

/// The key on a phone row's amount target — the amount, its chevron and (as a
/// second detector) its sub-line — named by [shoppingItemIdentity].
ValueKey<String> shopAmountTargetKey(String identity) =>
    ValueKey('shop-amount-$identity');

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
    final id = c.contributionId;
    final label = Text(
      c.label,
      style: ansiMono(
        size: 10.5,
        color: isManual ? AnsiColors.muted : AnsiColors.herbDeep,
      ).copyWith(fontStyle: isManual ? FontStyle.italic : null),
    );
    final quantity = Text(
      contributionQuantity(c),
      style: ansiMono(size: 10.5, color: AnsiColors.muted),
    );

    if (!isManual || id == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            if (isManual) ...[
              const Icon(FLucideIcons.plus, size: 10, color: AnsiColors.muted),
              const SizedBox(width: 4),
            ],
            Expanded(child: label),
            quantity,
          ],
        ),
      );
    }
    // A manual top-up is the one editable line, so it is a full-size row of
    // its own: a 44 px target that cannot be mistaken for the row's tick.
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: GestureDetector(
        key: shopTopUpKey(id),
        behavior: HitTestBehavior.opaque,
        onTap: () => showEditTopUpSheet(
          context,
          itemName: itemName,
          ingredientId: ingredientId,
          contribution: c,
        ),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AnsiColors.paper,
            border: Border.all(color: AnsiColors.line),
            borderRadius: BorderRadius.circular(AnsiRadii.box),
          ),
          child: Row(
            children: [
              const Icon(FLucideIcons.plus, size: 10, color: AnsiColors.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  c.label,
                  style: ansiMono(
                    size: 10.5,
                    color: AnsiColors.muted,
                  ).copyWith(fontStyle: FontStyle.italic),
                ),
              ),
              Text(
                contributionQuantity(c),
                style: ansiMono(size: 10.5, color: AnsiColors.muted),
              ),
              const SizedBox(width: 8),
              const Icon(FLucideIcons.pencil, size: 11, color: AnsiColors.herb),
            ],
          ),
        ),
      ),
    );
  }
}

/// The key on an opened breakdown's manual top-up row, named by its
/// contribution id.
ValueKey<String> shopTopUpKey(String contributionId) =>
    ValueKey('shop-top-up-$contributionId');

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

/// Nothing to buy, said inside the list chrome; the add field above stays on
/// screen.
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

// --- What is already at home ----------------------------------------------

/// The `To buy · At home?` toggle under the sync line: the way into the
/// checking pass and, tapped back to `To buy`, out of it. It reads and writes
/// [shopCheckingProvider] and nothing else. Drawn while the list holds an
/// ingredient row (and while the pass is on, so it can always be left); at
/// expanded it sits over the walk's column. Public so the screen test can find
/// it by type.
class ShopToggle extends ConsumerWidget {
  const ShopToggle({super.key});

  static const _labels = ['To buy', 'At home?'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checking = ref.watch(shopCheckingProvider);
    final data = ref.watch(currentShoppingListProvider).asData?.value;
    if (!checking && (data == null || !_hasIngredientRow(data))) {
      return const SizedBox.shrink();
    }
    final index = checking ? 1 : 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: FTabs(
        control: FTabControl.lifted(
          index: index,
          onChange: (i) {
            final pass = ref.read(shopCheckingProvider.notifier);
            i == 1 ? pass.start() : pass.done();
          },
        ),
        style: FTabsStyleDelta.delta(
          decoration: DecorationDelta.value(
            BoxDecoration(
              color: AnsiColors.paper,
              border: Border.all(color: AnsiColors.line),
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          indicatorDecoration: DecorationDelta.value(
            BoxDecoration(
              color: AnsiColors.surface,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1418211C),
                  offset: Offset(0, 1),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
          padding: const EdgeInsetsGeometryDelta.value(EdgeInsets.all(3)),
          height: 32,
          spacing: 0,
        ),
        children: [
          for (var i = 0; i < _labels.length; i++)
            FTabEntry(
              label: Text(
                _labels[i],
                style: ansiMono(
                  size: 10.5,
                  color: i == index ? AnsiColors.ink : AnsiColors.muted,
                ),
              ),
              child: const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

/// One row of the checking pass. The row (the house at expanded) says all of
/// it, or clears what was said; the amount opens the sheet (points the pane at
/// expanded). A row with two measurable totals cannot take an amount: its
/// house is muted and the reason sits under its name.
class _HomeRow extends ConsumerWidget {
  const _HomeRow({required this.item, this.selection});

  final ShoppingItem item;
  final _Selection? selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final said = item.atHome;
    final why = said == null ? whyNotAtHome(item) : null;
    final identity = shoppingItemIdentity(item);
    final selection = this.selection;
    final reading = selection != null && selection.identity == identity;

    Future<void> toggle() async {
      final repo = ref.read(shoppingRepositoryProvider);
      final week = ref.read(viewedWeekStartProvider);
      final id = item.ingredientId!;
      if (said != null) {
        await ref.write(
          context,
          'put ${item.name} back on the list',
          () => repo.clearAtHome(ingredientId: id, weekStart: week),
        );
        return;
      }
      final all = amountForAll(item);
      if (all == null) return;
      await ref.write(
        context,
        'say ${item.name} is at home',
        () => repo.setAtHome(
          ingredientId: id,
          quantity: all.quantity,
          unit: all.unit,
          measureId: all.measure?.id,
          weekStart: week,
        ),
      );
    }

    final house = _HouseBox(
      state: why != null
          ? _HouseState.off
          : said == null
          ? _HouseState.none
          : (said.all ? _HouseState.all : _HouseState.some),
    );
    final chip = GestureDetector(
      key: shopHomeAmountKey(identity),
      behavior: HitTestBehavior.opaque,
      onTap: why != null
          ? null
          : selection != null
          ? () => selection.read(item)
          : () => showAtHomeSheet(context, item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: said == null ? AnsiColors.paper : AnsiColors.herbSoft,
          border: Border.all(
            color: said == null ? AnsiColors.line : AnsiColors.herb,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          atHomeChip(item),
          style: ansiMono(
            size: 12,
            weight: FontWeight.w500,
            color: said == null ? AnsiColors.ink : AnsiColors.herbDeep,
          ),
        ),
      ),
    );

    return GestureDetector(
      key: shopHomeRowKey(identity),
      behavior: HitTestBehavior.opaque,
      onTap: selection != null
          ? () => selection.read(item)
          : (why == null ? toggle : null),
      child: Container(
        key: reading ? kShopReadingRowKey : null,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: EdgeInsets.symmetric(
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
                  house,
                  const SizedBox(width: 11),
                ] else
                  // The house carries the 44 px target the check box does.
                  GestureDetector(
                    key: shopHomeTargetKey(identity),
                    behavior: HitTestBehavior.opaque,
                    onTap: why == null ? toggle : null,
                    child: SizedBox(
                      width: 31,
                      height: 44,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: house,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    item.name,
                    style: ansiSans(
                      size: 14,
                      color: why == null ? AnsiColors.ink : AnsiColors.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                chip,
              ],
            ),
            if (why != null)
              Padding(
                padding: EdgeInsets.only(
                  left: 31,
                  top: 3,
                  bottom: selection == null ? 0 : 11,
                ),
                child: Text(
                  why,
                  style: ansiMono(size: 10.5, color: AnsiColors.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The key on a checking row, named by [shoppingItemIdentity].
ValueKey<String> shopHomeRowKey(String identity) =>
    ValueKey('shop-home-row-$identity');

/// The key on a checking row's amount chip.
ValueKey<String> shopHomeAmountKey(String identity) =>
    ValueKey('shop-home-amount-$identity');

/// The key on a wide checking row's house target.
ValueKey<String> shopHomeTargetKey(String identity) =>
    ValueKey('shop-home-$identity');

enum _HouseState { none, some, all, off }

/// Where the tick box was: an empty box, ½ for some, a house for all of it,
/// and a faded box for a row that cannot take an amount.
class _HouseBox extends StatelessWidget {
  const _HouseBox({required this.state});

  final _HouseState state;

  @override
  Widget build(BuildContext context) {
    final said = state == _HouseState.some || state == _HouseState.all;
    final box = Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: said ? AnsiColors.herbSoft : AnsiColors.surface,
        border: Border.all(
          color: said ? AnsiColors.herb : AnsiColors.line,
          width: 1.6,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: switch (state) {
        _HouseState.all => const Icon(
          FLucideIcons.house,
          size: 12,
          color: AnsiColors.herbDeep,
        ),
        _HouseState.some => Text(
          '½',
          style: ansiMono(size: 11, color: AnsiColors.herbDeep),
        ),
        _ => null,
      },
    );
    return state == _HouseState.off ? Opacity(opacity: 0.4, child: box) : box;
  }
}

/// The *At home* section, under the basket: folded to one counted line (`AT
/// HOME · 3`) until it is tapped open. Its rows are all at home, muted but
/// never struck through, a house where the tick would be and no price. A tap
/// puts the row back in its aisle, as a tap on a basket row unticks it.
class _AtHomeSection extends ConsumerWidget {
  const _AtHomeSection({required this.items, this.selection});

  final List<ShoppingItem> items;
  final _Selection? selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(
      shopOpenProvider.select((o) => o.contains(ShopFold.atHome)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FoldLine(
          fold: ShopFold.atHome,
          open: open,
          label: 'At home · ${items.length}'.toUpperCase(),
        ),
        if (open)
          for (final item in items)
            _AtHomeRow(item: item, selection: selection),
      ],
    );
  }
}

class _AtHomeRow extends ConsumerWidget {
  const _AtHomeRow({required this.item, this.selection});

  final ShoppingItem item;
  final _Selection? selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = shoppingItemIdentity(item);
    final selection = this.selection;
    final reading = selection != null && selection.identity == identity;

    Future<void> putBack() async {
      final repo = ref.read(shoppingRepositoryProvider);
      final week = ref.read(viewedWeekStartProvider);
      await ref.write(
        context,
        'put ${item.name} back on the list',
        () =>
            repo.clearAtHome(ingredientId: item.ingredientId!, weekStart: week),
      );
    }

    const house = _HouseBox(state: _HouseState.all);
    return GestureDetector(
      key: shopAtHomeRowKey(identity),
      behavior: HitTestBehavior.opaque,
      onTap: selection == null ? putBack : () => selection.read(item),
      child: Container(
        key: reading ? kShopReadingRowKey : null,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: EdgeInsets.symmetric(
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
        child: Row(
          children: [
            if (selection == null) ...[
              house,
              const SizedBox(width: 11),
            ] else
              GestureDetector(
                key: shopHomeTargetKey(identity),
                behavior: HitTestBehavior.opaque,
                onTap: putBack,
                child: const SizedBox(
                  width: 31,
                  height: 44,
                  child: Align(alignment: Alignment.centerLeft, child: house),
                ),
              ),
            Expanded(
              child: Text(
                item.name,
                style: ansiSans(size: 14, color: AnsiColors.muted),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              needTotal(item),
              style: ansiMono(
                size: 13,
                weight: FontWeight.w500,
                color: AnsiColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The key on a row of the *At home* section.
ValueKey<String> shopAtHomeRowKey(String identity) =>
    ValueKey('shop-at-home-$identity');

/// Shown where the aisles were when everything left is at home and nothing
/// was put in the basket.
class _EverythingAtHomeLine extends StatelessWidget {
  const _EverythingAtHomeLine();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Text(
        'everything’s at home',
        style: ansiMono(size: 11.5, color: AnsiColors.muted),
      ),
    );
  }
}

/// The wide pane while checking: the amount editor for the row the list is
/// pointed at, in place of where it came from. Keyed by row and amount, so it
/// opens fresh on each row and on what was last saved.
class _AtHomePane extends ConsumerWidget {
  const _AtHomePane({required this.item});

  final ShoppingItem? item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = item;
    return Container(
      width: kProvenancePaneWidth,
      decoration: const BoxDecoration(
        color: AnsiColors.paper,
        border: Border(left: BorderSide(color: AnsiColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: row == null || whyNotAtHome(row) != null
          ? Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                row == null
                    ? 'nothing left to check'
                    : '${row.name} · ${whyNotAtHome(row)}',
                style: ansiMono(size: 11.5, color: AnsiColors.muted),
              ),
            )
          : SingleChildScrollView(
              child: AtHomeEditor(
                key: ValueKey(
                  'at-home-${shoppingItemIdentity(row)}-'
                  '${row.atHome?.quantity}-${row.atHome?.unit?.id}',
                ),
                item: row,
                inPane: true,
                // The pane’s × closes the pass, as tapping back to To buy does.
                onDismiss: () => ref.read(shopCheckingProvider.notifier).done(),
              ),
            ),
    );
  }
}
