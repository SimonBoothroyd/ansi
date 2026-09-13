/// The Shop screen — the DERIVED, provenance-aware shopping list (spec §4).
///
/// The list sums each ingredient's contributions from the batch cook plan, plus
/// any manual top-ups, and groups them by aisle. Check-off is on the rolled-up
/// item (spec §4), and a ticked row leaves its aisle for one basket section at
/// the bottom. A "+ add item or top up" affordance opens the add sheet for
/// non-food staples and manual top-ups. Read-derived; edit the Week/Cook and
/// this re-sums. Only the thin overlay (check-off + manual contributions)
/// persists — and syncs, since step 7.
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
import '../../../shared/dashed_border_box.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/sync_status_line.dart';
import '../../../shared/write.dart';
import '../../account/data/household_providers.dart';
import '../../cook_plan/presentation/cook_view_models.dart';
import '../../planning/data/planning_providers.dart';
import '../../planning/presentation/week_format.dart';
import '../../planning/presentation/week_header.dart';
import '../../planning/presentation/week_view_models.dart';
import '../../recipes/domain/effective_lines.dart';
import '../data/shopping_providers.dart';
import '../domain/shopping.dart';
import 'add_shopping_item_sheet.dart';
import 'confetti_burst.dart';
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
          // The width buys ONE thing here: the breakdown a phone opens under a
          // row, held open in a pane beside the walk. The walk itself is the
          // same single column at the measure — two phones drive this screen
          // at once, and a second column to re-find a row in is not an offer.
          Expanded(
            child: AnsiLayout.of(context) == AnsiLayout.expanded
                ? const _WideShop()
                : _shoppingList(context, ref, list),
          ),
        ],
      ),
    );
  }
}

/// The walk: the aisles, the basket section, the echo rows and the add door.
///
/// [selection] is null on a phone, where every row draws its own breakdown
/// under it. At [AnsiLayout.expanded] it is the pane's seam: the row it is
/// reading lights up, a row's NAME points the pane at it, and no row draws a
/// breakdown of its own.
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
  // D5b: the screen never swaps itself out for a data condition. An
  // empty list is a quiet line INSIDE the list chrome, keeping both of
  // this screen's affordances — the add-item door works with no plan at
  // all, which is exactly why it must not be taken away.
  data: (data) => ListView(
    padding: ansiScrollPadding(
      context,
      const EdgeInsets.only(top: 6, bottom: 24),
    ),
    children: [
      const _ListCaption(),
      if (data.isEmpty) const _NothingToBuyLine(),
      // The aisles hold only what is still to grab; a ticked row leaves for
      // the basket section at the bottom, so what is and isn't in the
      // trolley reads at a glance. When the aisles are empty but the trip
      // is not, the line below says so where they were.
      if (data.allTicked) const _EverythingInBasketLine(),
      for (final group in data.openGroups)
        _Group(group: group, selection: selection),
      if (data.basket.isNotEmpty)
        _Basket(groups: data.basketGroups, selection: selection),
      // What the list is short by, and why it is silent about it
      // (step 8.6 / D4): an unresolved component contributes
      // nothing — never an invented quantity — so the parent it
      // belongs to says so and points at the surface that fixes
      // it. A list that is quietly short is worse than one that
      // says what it left out.
      for (final note in data.unresolvedComponents) _UnresolvedEcho(note: note),
      // …and what it cannot buy because the thing itself is gone: a line, or
      // a planned meal, whose vocab row was retired. Amber like the
      // unresolved echo, because it is the same kind of news — a defect
      // somebody can fix — and the words name where the pick is.
      for (final note in data.retiredIngredients)
        RetiredIngredientEcho(note: note),
      // …and what it left out BY RULE: an optional line contributes nothing,
      // and the recipe it belongs to says which lines, in the same voice —
      // muted, not amber, because a rule somebody chose is not a defect
      // somebody can fix.
      for (final note in data.optionalLines) OptionalLinesEcho(note: note),
      const _AddItemButton(),
    ],
  ),
);

/// The row the provenance pane is reading, and how a row asks to be read.
///
/// The row is named by [shoppingItemIdentity] rather than by a position: the
/// list re-derives whenever the week, a tick or the other shopper changes it,
/// and an index does not survive that.
class _Selection {
  const _Selection({required this.identity, required this.read});

  /// The identity of the row the pane is on.
  final String identity;

  /// Points the pane at a row. The row's own tap is still the tick.
  final ValueChanged<ShoppingItem> read;
}

/// The Shop at [AnsiLayout.expanded]: the walk at the measure, and the
/// breakdown beside it.
///
/// The pane reads one row at a time and changes nothing — a tick is still what
/// sends a row to the basket, and a row the pane is reading stays exactly where
/// the aisles put it.
class _WideShop extends ConsumerStatefulWidget {
  const _WideShop();

  @override
  ConsumerState<_WideShop> createState() => _WideShopState();
}

class _WideShopState extends ConsumerState<_WideShop> {
  /// The row a name has pointed the pane at, or null while the pane is reading
  /// the first row of the walk.
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

/// How wide the provenance pane is drawn — the one measurement this screen's
/// wide frame adds, and the same 360 the board's pane is drawn at.
const kProvenancePaneWidth = 360.0;

/// The breakdown the phone opens under a row, held open beside the walk: what
/// the row is, what it came to, which recipes and sessions asked for it, and
/// the manual top-up, which is editable here exactly as it is inline.
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
                // Where the row is: the aisle it is walked to, and whether it
                // is already in the basket — the two words the list says about
                // its position, said here for the row the pane is on.
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

/// The one section every ticked row moves to — `IN THE BASKET · 4` in the
/// group-header voice — keeping its aisles inside it, so a row is re-found
/// the way it was found: under `PRODUCE`, then `PANTRY`, in the order the
/// aisles would have put them. A ticked row keeps its ticked look and its
/// tap: tapping unticks it and it returns to its aisle on the next derivation.
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

/// Every item is ticked: the aisles are empty but the trip is not, and the
/// line says so where the aisles were, in [_NothingToBuyLine]'s voice. The
/// single place the screen knows the trip is done.
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

/// A parent recipe's "N components unresolved — see Cook" echo, drawn in the
/// group-header voice (board frame g) because that is what it is: a heading
/// for the items that are NOT below it.
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

/// A line at a RETIRED ingredient: "SAUERKRAUT · ingredient removed · pick
/// again in the recipe" — the same group-header row the unresolved echo uses,
/// amber, because it is the same kind of statement: a heading for something
/// that is NOT below it, and a defect somebody can fix.
///
/// The list buys nothing from a retired row (there is no honest name, aisle or
/// density left on it) and drops nothing either — a planned snack that
/// vanished with its check-off row is how this went unnoticed. So the row
/// leaves the aisles and says, here, which thing is missing and where the pick
/// is: the recipe for a recipe line, the plan for a bare-ingredient meal.
/// Public so the screen test can find the row by type.
class RetiredIngredientEcho extends StatelessWidget {
  const RetiredIngredientEcho({required this.note, super.key});

  final RetiredIngredientNote note;

  /// `Sauerkraut · ingredient removed · pick again in the recipe`.
  ///
  /// `ingredient removed · pick again` is the recipe page's and the editor's
  /// exact words (`RemovedIngredientTag`) — one vocabulary for one kind of
  /// broken line — with the surface that holds the pick named at the end,
  /// because from an aisle it is a different tap.
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

/// A recipe's "N optional lines not listed — lime, coriander" echo: the
/// group-header voice nested recipes' unresolved echo uses, because it is the
/// same shape of statement — a heading for the items that are NOT below it —
/// drawn muted rather than amber. Public so the screen test can find the row by
/// type.
///
/// A line THIS WEEK left out takes the same row in the same grammar — "1 line
/// left out this week — Red wine". An exclusion cannot be a provenance segment
/// (there is no row left to hang one on), and a list that is quietly short is
/// worse than one that says what it dropped.
///
/// **On an optional row the names are doors.** Each one is a tap that writes
/// this week's include row for that line, so the question the row raises can be
/// answered where it is asked rather than three screens away in the editor. A
/// line the WEEK left out keeps its plain words: that is a change somebody
/// made, and it is undone where it was made.
///
/// Stateful only to own the names' tap recognizers.
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
    // A door only where there is a decision to make. The ids ride beside the
    // names, and a row that somehow carries fewer of one than the other says
    // its sentence plainly rather than pointing a tap at the wrong line.
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

/// One shopping line: check box · name · total, with the provenance breakdown
/// beneath. Tapping the row (or its box) toggles check-off. A purely user-added
/// line (a non-food item, or an ingredient that's only a manual top-up) can be
/// removed by swiping it away or long-pressing — a cook-derived line can't (its
/// quantity comes from the week; drop its top-up via the edit sheet instead).
class _ItemRow extends ConsumerStatefulWidget {
  const _ItemRow({required this.item, this.selection});

  final ShoppingItem item;

  /// Non-null at [AnsiLayout.expanded], where the breakdown is held open in the
  /// pane beside the list instead of under the row: the row's NAME is then the
  /// door that points the pane at it, the row's tap is still the tick, and the
  /// row the pane is on is lit.
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
    // Decided on the list as it stands, before the write and before any
    // await: the derivation that follows would call the partner's last tick
    // a finish too.
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

  /// The last tick's celebration: a light haptic and, unless the phone asks
  /// for no animation, the confetti from this row's box. Asked of the list as
  /// it stands before the write ([completesTheList]), so the other phone's
  /// finish plays nothing and every finishing tick here plays — untick the
  /// last row, tick it again, and the confetti comes back.
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
    final secondary = item.checked ? '' : itemSecondary(item);
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
      onTap: _toggle,
      onLongPress: item.isUserAdded
          ? () => _confirmRemove(context, ref, item)
          : null,
      child: Container(
        key: reading ? kShopReadingRowKey : null,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: EdgeInsets.symmetric(
          vertical: 11,
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
                _CheckBox(key: _box, checked: item.checked),
                const SizedBox(width: 11),
                Expanded(
                  child: selection == null
                      ? name
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => selection.read(item),
                          child: name,
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
            // What a measure-counted row weighs ("400 g"), or the whole-unit
            // round-up ("≈ 2.25 potato, large → buy 3"). Either way it sits
            // under the honest total, never replacing it (invariant 3).
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
            // Every row says where it came from — a single source is still a
            // source, and a shopper reading one line should not have to
            // remember which recipe asked for it.
            // …under the row on a phone, and in the pane beside the list at
            // expanded, which is the whole of what the width buys here.
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
