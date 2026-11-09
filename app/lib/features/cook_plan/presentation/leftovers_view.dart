/// Leftovers (`/leftovers`): the cooked food in the fridge and the freezer,
/// put right whenever somebody looks.
///
/// A row starts from the ticks and is corrected on its stepper. Nothing
/// clears itself: a row behind its date says so and stays until somebody
/// counts it to nothing, freezes it or removes what has gone off. The bar's
/// add opens *Add a leftover*, for food the app never saw. Its one door is
/// the fridge in the Week's header.
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
import '../../../shared/ansi_toast.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/write.dart';
import '../../account/data/household_providers.dart';
import '../../planning/presentation/week_view_models.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/recipe_view_models.dart';
import '../data/cook_plan_providers.dart';
import '../domain/leftover_repository.dart';
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
        // A pot not cooked yet is offered for planning, but is not in the
        // fridge, even on the day it cooks.
        data: (all) => _Shelves(
          rows: [
            for (final l in all)
              if (l.cooked && l.isCookedBy(ref.watch(todayProvider))) l,
          ],
        ),
      ),
    );
  }
}

/// The two shelves, soonest to go off first. One row at a time opens its
/// count to the stepper.
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
    // Both shelves: a freezer row past its date has gone off too.
    final goneOff = [
      for (final l in rows)
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
        Text('FRIDGE', style: ansiLabel()),
        const SizedBox(height: 6),
        if (fridge.isEmpty) const _Empty(),
        for (final l in fridge) row(l),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              const Icon(
                FLucideIcons.snowflake,
                size: 10,
                color: AnsiColors.chillInk,
              ),
              const SizedBox(width: 4),
              Text('FREEZER', style: ansiLabel(color: AnsiColors.chillInk)),
            ],
          ),
        ),
        if (freezer.isEmpty) const _Empty(),
        for (final l in freezer) row(l),
        // One link under both shelves, while anything has gone off.
        if (goneOff.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: AnsiTap(
              onTap: () => unawaited(
                writeWithUndo(
                  context,
                  ref,
                  done: goneOff.length == 1
                      ? 'Removed ${goneOff.single.title}.'
                      : 'Removed ${goneOff.length} gone off.',
                  write: (container, host) => container.write(
                    host,
                    'remove what has gone off',
                    () => repo.markLeftoversGone(goneOff),
                  ),
                ),
              ),
              semanticsLabel: 'Remove gone off',
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Remove gone off',
                style: ansiSans(
                  size: 12.5,
                  color: AnsiColors.herbDeep,
                  weight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Makes [write], then says [done] with an Undo that takes back what it
/// wrote ([LeftoverRepository.undoLeftovers]). The handles [write] is given
/// are captured before it: the row that started it has moved shelves or gone
/// by the time it lands.
Future<void> writeWithUndo(
  BuildContext context,
  WidgetRef ref, {
  required String done,
  required Future<LeftoverUndo?> Function(
    ProviderContainer container,
    HostContext host,
  )
  write,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final host = hostContextOf(context);
  final repo = ref.read(leftoverRepositoryProvider);
  final undo = await write(container, host);
  if (undo == null) return;
  showAnsiUndoToast(
    // The host outlives the row, which has moved or gone.
    // ignore: use_build_context_synchronously
    host.context,
    what: done,
    onUndo: () => unawaited(
      container.write(host, 'put it back', () => repo.undoLeftovers(undo)),
    ),
  );
}

/// A row's identity across a write: its cooking and its shelf.
String _keyOf(Leftover left) => '${left.id}:${left.place.name}';

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text('empty', style: ansiMono(size: 11, color: AnsiColors.muted)),
  );
}

/// One leftover: its dish and date, then its `N left` chip, what is planned
/// from it, and its move. The chip opens the stepper in its place. A fridge
/// row of a dish that freezes offers **Freeze** while in date and **Froze
/// it** once past; a count set to nothing takes the row away.
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
    final past = left.pastItsDate(today);
    final forDays = leftoverFor(left, today, shape);
    final freezeFor = leftoverFreezeFor(left, today, shape);
    final short = leftoverShortFor(left, today, shape);
    final when = leftoverWhen(left, today, shape);

    final head = Semantics(
      button: true,
      expanded: open,
      label: [
        left.title,
        when,
        leftCount(left.inBox),
        ?short,
        ?forDays,
        ?freezeFor,
      ].join(', '),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  left.title,
                  style: ansiSans(
                    size: 13.5,
                    color: past
                        ? AnsiColors.muted
                        : open
                        ? AnsiColors.herbDeep
                        : AnsiColors.ink,
                    weight: open ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                when,
                style: ansiMono(
                  size: 10.5,
                  color: past
                      ? AnsiColors.cautionInk
                      : frozen
                      ? AnsiColors.chillInk
                      : AnsiColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final Widget? move = frozen || !freezable
        ? null
        : _ShelfButton(
            label: past ? 'Froze it' : 'Freeze',
            chill: true,
            filled: !past,
            // Frozen on the night and not said, or now: dated from its cook
            // day either way.
            onTap: () => unawaited(
              writeWithUndo(
                context,
                ref,
                done: 'Froze ${left.title}.',
                write: (container, host) => container.write(
                  host,
                  'move ${left.title} to the freezer',
                  () => repo.freezeLeftover(left),
                ),
              ),
            ),
          );

    final line = Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (open)
                _PortionStepper(left: left)
              else
                _CountChip(portions: left.inBox, onTap: onToggle),
              // A meal planned from it that wants more than is there.
              if (short != null)
                Text(
                  short,
                  style: ansiMono(
                    size: 10.5,
                    color: AnsiColors.cautionInk,
                    weight: FontWeight.w600,
                  ),
                ),
              if (forDays != null)
                Text(
                  forDays,
                  style: ansiMono(size: 10.5, color: AnsiColors.muted),
                ),
              if (freezeFor != null) _FreezeBy(words: freezeFor),
            ],
          ),
        ),
        ?move,
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [head, const SizedBox(height: 2), line],
    );
    if (past) {
      return DashedBorderBox(
        color: AnsiColors.line,
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
        child: body,
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
      decoration: BoxDecoration(
        color: frozen ? AnsiColors.surface : AnsiColors.paper,
        border: Border.all(
          color: frozen ? AnsiColors.chillLine : AnsiColors.line,
        ),
        borderRadius: BorderRadius.circular(AnsiRadii.card),
      ),
      child: body,
    );
  }
}

/// `2 left`: a row's count as a small chip, drawn at 26 inside a 44 target;
/// a tap opens the stepper.
class _CountChip extends StatelessWidget {
  const _CountChip({required this.portions, required this.onTap});

  final double portions;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${leftCount(portions)}, change',
    child: ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: kAnsiTouchTarget),
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AnsiColors.surface,
              border: Border.all(color: AnsiColors.line),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              leftCount(portions),
              style: ansiMono(size: 10.5, color: AnsiColors.herbDeep),
            ),
          ),
        ),
      ),
    ),
  );
}

/// `❄ freeze by Mon for Wed`, in the freezer's blue.
class _FreezeBy extends StatelessWidget {
  const _FreezeBy({required this.words});

  final String words;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(FLucideIcons.snowflake, size: 10, color: AnsiColors.chillInk),
      const SizedBox(width: 3),
      Flexible(
        child: Text(
          words,
          style: ansiMono(size: 10.5, color: AnsiColors.chillInk),
        ),
      ),
    ],
  );
}

/// `−  3  +`, a whole portion a step, down to nothing. A part portion steps
/// to the whole on either side, so `1¾` reads `1` or `2`.
class _PortionStepper extends ConsumerWidget {
  const _PortionStepper({required this.left});

  final Leftover left;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = left.inBox;
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
        label: leftCount(n),
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
      onDecrement: down > -1e-6 ? () => set(down < 0 ? 0 : down) : null,
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
    // Only titles the words hit, at the best tier: no hit at all lists none.
    final hits = typed.isEmpty || tier == null
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
