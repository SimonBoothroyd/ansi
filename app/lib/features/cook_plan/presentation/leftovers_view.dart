/// Leftovers (`/leftovers`): the cooked food in the fridge and the freezer,
/// put right whenever somebody looks.
///
/// A row starts from the ticks and is corrected on its stepper. Nothing
/// clears itself: a row behind its date says so and stays until somebody
/// says it is gone, froze it, or clears the fridge. The bar's add opens *Add a
/// leftover*, for food the app never saw. Its one door is the fridge in the
/// Week's header.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/search/search_rank.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/portions.dart';
import '../../../shared/ansi_back.dart';
import '../../../shared/ansi_chip.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_micro_label.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_scroll.dart';
import '../../../shared/ansi_search_field.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/ansi_stepper_row.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/write.dart';
import '../../account/data/household_providers.dart';
import '../../planning/presentation/week_view_models.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/recipe_view_models.dart';
import '../data/cook_plan_providers.dart';
import '../domain/leftovers.dart';
import 'leftover_format.dart';
import 'leftovers_view_models.dart';

class LeftoversView extends ConsumerWidget {
  const LeftoversView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(fridgeAndFreezerProvider);
    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text('Leftovers', style: ansiHeaderTitle()),
        // Its door is on the Week, so a cold link goes home there.
        prefixes: [
          FHeaderAction.back(onPress: () => ansiBack(context, home: '/week')),
        ],
        suffixes: [
          FHeaderAction(
            icon: const Icon(FLucideIcons.plus),
            semanticsLabel: 'Add a leftover',
            onPress: () => unawaited(showAddLeftoverSheet(context)),
          ),
        ],
      ),
      child: rows.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (e, st) => AnsiErrorState(
          what: 'the leftovers',
          error: e,
          stackTrace: st,
          onRetry: () => ref.invalidate(leftoverShelvesProvider),
        ),
        // A batch not cooked yet is offered for planning, but not in the
        // fridge.
        data: (all) => _Shelves(
          rows: [
            for (final l in all)
              if (l.isCookedBy(ref.watch(todayProvider))) l,
          ],
        ),
      ),
    );
  }
}

/// The two shelves. One row at a time opens to its stepper and its moves.
class _Shelves extends HookConsumerWidget {
  const _Shelves({required this.rows});

  final List<Leftover> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = useState<String?>(null);
    final today = ref.watch(todayProvider);
    final repo = ref.read(leftoverRepositoryProvider);
    // Freezable is a recipe fact; the household's own words may go in.
    final freezable = {
      for (final r
          in ref.watch(recipeListProvider).asData?.value ??
              const <RecipeSummary>[])
        r.id: r.freezable,
    };
    final fridge = [
      for (final l in rows)
        if (l.place == LeftoverPlace.fridge) l,
    ];
    final freezer = [
      for (final l in rows)
        if (l.place == LeftoverPlace.freezer) l,
    ];
    final past = [
      for (final l in fridge)
        if (l.pastItsDate(today)) l,
    ];

    Widget row(Leftover left) {
      final key = _keyOf(left);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _LeftoverRow(
          key: ValueKey(key),
          left: left,
          freezable:
              left.recipeId == null || (freezable[left.recipeId] ?? false),
          open: open.value == key,
          onToggle: () => open.value = open.value == key ? null : key,
        ),
      );
    }

    return ListView(
      padding: ansiScrollPadding(
        context,
        const EdgeInsets.fromLTRB(20, 8, 20, 28),
      ),
      children: [
        Row(
          children: [
            Expanded(child: Text('FRIDGE', style: ansiLabel())),
            if (past.isNotEmpty)
              AnsiTap(
                onTap: () => unawaited(
                  ref.write(
                    context,
                    'clear the fridge',
                    () => repo.markLeftoversGone(past),
                  ),
                ),
                semanticsLabel: 'Clear all',
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 12,
                ),
                child: Text(
                  'Clear all',
                  style: ansiSans(
                    size: 12.5,
                    color: AnsiColors.herbDeep,
                    weight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (fridge.isEmpty) const _Empty(),
        for (final l in fridge) row(l),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('FREEZER', style: ansiLabel(color: AnsiColors.chillInk)),
        ),
        if (freezer.isEmpty) const _Empty(),
        for (final l in freezer) row(l),
      ],
    );
  }
}

/// A row's identity across a write: its stored id, else its batch.
String _keyOf(Leftover left) => left.id ?? 'batch:${left.batch}';

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text('empty', style: ansiMono(size: 11, color: AnsiColors.muted)),
  );
}

/// One leftover. Past its date it offers **Froze it** (a freezable fridge
/// row) and **Gone** in place; otherwise a tap opens its stepper, **Freeze**
/// (a freezable fridge row) and **Gone**.
class _LeftoverRow extends ConsumerWidget {
  const _LeftoverRow({
    required this.left,
    required this.freezable,
    required this.open,
    required this.onToggle,
    super.key,
  });

  final Leftover left;
  final bool freezable;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final shape = ref.watch(weekShapeProvider);
    final repo = ref.read(leftoverRepositoryProvider);
    final frozen = left.place == LeftoverPlace.freezer;
    final fridge = !frozen;

    void gone() => unawaited(
      ref.write(
        context,
        'say ${left.title} is gone',
        () => repo.markLeftoversGone([left]),
      ),
    );

    if (left.pastItsDate(today)) {
      return DashedBorderBox(
        color: AnsiColors.line,
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    left.title,
                    style: ansiSans(size: 13.5, color: AnsiColors.muted),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    leftoverLine(left, today, shape),
                    style: ansiMono(size: 10.5, color: AnsiColors.cautionInk),
                  ),
                ],
              ),
            ),
            if (fridge && freezable)
              _ShelfButton(
                label: 'Froze it',
                chill: true,
                // Frozen on the night and not said: dated from its cook day.
                onTap: () => unawaited(
                  ref.write(
                    context,
                    'move ${left.title} to the freezer',
                    () => repo.freezeLeftover(left),
                  ),
                ),
              ),
            _ShelfButton(label: 'Gone', onTap: gone),
          ],
        ),
      );
    }

    final count = Text(
      leftoverCount(left),
      style: ansiMono(size: 10.5, color: AnsiColors.muted),
    );
    final when = Text(
      leftoverWhen(left, today, shape),
      style: ansiMono(
        size: 10.5,
        color: frozen ? AnsiColors.chillInk : AnsiColors.muted,
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: frozen ? AnsiColors.surface : AnsiColors.paper,
        border: Border.all(
          color: frozen ? AnsiColors.chillLine : AnsiColors.line,
        ),
        borderRadius: BorderRadius.circular(AnsiRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            label: '${left.title}, ${leftoverLine(left, today, shape)}',
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              left.title,
                              style: ansiSans(
                                size: 13.5,
                                color: open
                                    ? AnsiColors.herbDeep
                                    : AnsiColors.ink,
                                weight: open
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                            if (!open) ...[const SizedBox(height: 3), count],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      when,
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 8, 8),
              child: Row(
                children: [
                  _PortionStepper(left: left),
                  const Spacer(),
                  if (fridge && freezable)
                    _ShelfButton(
                      label: 'Freeze',
                      chill: true,
                      filled: true,
                      onTap: () => unawaited(
                        ref.write(
                          context,
                          'move ${left.title} to the freezer',
                          () => repo.freezeLeftover(left),
                        ),
                      ),
                    ),
                  _ShelfButton(label: 'Gone', onTap: gone),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// `−  3  +`, a whole portion a step. A part portion steps to the whole on
/// either side, so `1¾` reads `1` or `2`. It never reaches nothing: that is
/// **Gone**.
class _PortionStepper extends ConsumerWidget {
  const _PortionStepper({required this.left});

  final Leftover left;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = left.portions;
    final whole = (n - n.roundToDouble()).abs() < 1e-6;
    final down = whole ? n.roundToDouble() - 1 : n.floorToDouble();
    final up = whole ? n.roundToDouble() + 1 : n.ceilToDouble();
    void set(double to) => unawaited(
      ref.write(
        context,
        'change ${left.title}',
        () =>
            ref.read(leftoverRepositoryProvider).setLeftoverPortions(left, to),
      ),
    );
    return AnsiStepperRow(
      small: true,
      value: Semantics(
        label: formatPortions(n),
        child: ExcludeSemantics(
          child: SizedBox(
            width: 40,
            child: Text(
              formatFraction(n),
              textAlign: TextAlign.center,
              style: ansiMono(size: 15, weight: FontWeight.w500),
            ),
          ),
        ),
      ),
      onDecrement: down > 1e-6 ? () => set(down) : null,
      onIncrement: () => set(up),
    );
  }
}

/// A row's move: a small pill drawn at 32 inside a 44 target.
class _ShelfButton extends StatelessWidget {
  const _ShelfButton({
    required this.label,
    required this.onTap,
    this.chill = false,
    this.filled = false,
  });

  final String label;
  final VoidCallback onTap;

  /// The freezer's blue, for a move into it.
  final bool chill;

  /// The chill ground, for the move a row's card leads with.
  final bool filled;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: kAnsiTouchTarget),
          padding: const EdgeInsets.only(left: 6),
          alignment: Alignment.center,
          child: Container(
            constraints: const BoxConstraints(minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: filled ? AnsiColors.chill : AnsiColors.surface,
              border: Border.all(
                color: chill ? AnsiColors.chillLine : AnsiColors.line,
              ),
              borderRadius: BorderRadius.circular(AnsiRadii.pill),
            ),
            child: Text(
              label,
              style: ansiSans(
                size: 12,
                weight: FontWeight.w500,
                color: chill ? AnsiColors.chillInk : AnsiColors.muted,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// When a leftover added by hand was cooked or frozen, roughly: the chip's
/// day, not a calendar.
enum AddedWhen {
  thisWeek('This week', 0),
  lastWeek('Last week', 7),
  earlier('Earlier', 14);

  const AddedWhen(this.label, this.daysBack);

  final String label;

  /// How many days before today the row is dated.
  final int daysBack;

  DateTime sinceFrom(DateTime today) =>
      DateTime(today.year, today.month, today.day - daysBack);
}

/// Opens *Add a leftover*: a recipe or the household's own words, Fridge or
/// Freezer, portions, and roughly when. Writes on **Add**.
Future<void> showAddLeftoverSheet(BuildContext context) => showAnsiSheet<void>(
  context: context,
  builder: (_) => const _AddLeftoverSheet(),
);

class _AddLeftoverSheet extends HookConsumerWidget {
  const _AddLeftoverSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = useState('');
    // The recipe picked, or null while nothing is or the words are.
    final recipe = useState<RecipeSummary?>(null);
    final words = useState(false);
    final place = useState(LeftoverPlace.fridge);
    final portions = useState<double>(2);
    final when = useState(AddedWhen.thisWeek);

    final recipes =
        ref.watch(recipeListProvider).asData?.value ?? const <RecipeSummary>[];
    final typed = query.value.trim();
    final tier = bestTier([
      for (final r in recipes) recipeTitleHit(r.title, typed),
    ]);
    final hits = typed.isEmpty
        ? const <RecipeSummary>[]
        : [
            for (final r in recipes)
              if (recipeTitleHit(r.title, typed)?.tier == tier) r,
          ].take(4).toList();
    final chosen = recipe.value;
    final ready = chosen != null || (words.value && typed.isNotEmpty);

    Future<void> add() async {
      final today = ref.read(todayProvider);
      final ok = await ref.writeOk(
        context,
        'add the leftover',
        () => ref
            .read(leftoverRepositoryProvider)
            .addLeftover(
              place: place.value,
              portions: portions.value,
              since: when.value.sinceFrom(today),
              recipeId: chosen?.id,
              label: chosen == null ? typed : null,
            ),
      );
      if (ok && context.mounted) Navigator.of(context).pop();
    }

    Widget pick({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      bool words = false,
    }) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected ? AnsiColors.herbSoft : AnsiColors.surface,
                border: Border.all(
                  color: selected ? AnsiColors.herb : AnsiColors.line,
                ),
                borderRadius: BorderRadius.circular(AnsiRadii.card),
              ),
              child: Row(
                children: [
                  if (words) ...[
                    const Icon(
                      FLucideIcons.plus,
                      size: 14,
                      color: AnsiColors.herbDeep,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: ansiSans(
                        size: 13.5,
                        color: AnsiColors.herbDeep,
                        weight: selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(
                      FLucideIcons.check,
                      size: 16,
                      color: AnsiColors.herbDeep,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return AnsiSheetShell(
      title: 'Add a leftover',
      centerTitle: false,
      scrollable: true,
      children: [
        const SizedBox(height: 8),
        AnsiSearchField(
          hint: 'A recipe or your own words',
          onChanged: (q) {
            query.value = q;
            // A new word unpicks what the old one picked.
            recipe.value = null;
            words.value = false;
          },
        ),
        for (final r in hits)
          pick(
            label: r.title,
            selected: chosen?.id == r.id,
            onTap: () {
              recipe.value = r;
              words.value = false;
            },
          ),
        if (typed.isNotEmpty)
          pick(
            label: '“$typed”',
            words: true,
            selected: words.value,
            onTap: () {
              recipe.value = null;
              words.value = true;
            },
          ),
        const SizedBox(height: 18),
        const AnsiMicroLabel('Where'),
        Row(
          children: [
            for (final (i, p) in LeftoverPlace.values.indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              AnsiChip(
                label: p == LeftoverPlace.fridge ? 'Fridge' : 'Freezer',
                selected: place.value == p,
                expand: true,
                onTap: () => place.value = p,
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        const AnsiMicroLabel('Portions'),
        AnsiStepperRow(
          value: Expanded(
            child: Text(
              formatFraction(portions.value),
              textAlign: TextAlign.center,
              style: ansiMono(size: 15, weight: FontWeight.w500),
            ),
          ),
          onDecrement: portions.value > 1
              ? () => portions.value = portions.value - 1
              : null,
          onIncrement: () => portions.value = portions.value + 1,
        ),
        const SizedBox(height: 18),
        const AnsiMicroLabel('When'),
        Row(
          children: [
            for (final (i, w) in AddedWhen.values.indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              AnsiChip(
                label: w.label,
                selected: when.value == w,
                expand: true,
                onTap: () => when.value = w,
              ),
            ],
          ],
        ),
        const SizedBox(height: 22),
        FButton(onPress: ready ? add : null, child: const Text('Add')),
      ],
    );
  }
}

/// The page's one door: a fridge in the Week's header beside Ask, drawn as Ask
/// is, with a small dot while any row is behind its date.
class LeftoversDoor extends ConsumerWidget {
  const LeftoversDoor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = ref.watch(anyLeftoverPastItsDateProvider);
    return FHeaderAction(
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(FLucideIcons.refrigerator),
          if (due)
            Positioned(
              top: -2,
              right: -3,
              child: Container(
                key: kLeftoversDueDotKey,
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AnsiColors.aging,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      semanticsLabel: due ? 'Leftovers, past its date' : 'Leftovers',
      onPress: () => context.pushOnce('/leftovers'),
    );
  }
}

/// The door's dot, so the tests name it rather than a colour.
const kLeftoversDueDotKey = ValueKey('leftovers-due');
