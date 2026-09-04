/// The week switcher — the title of the Week, Cook and Shop screens.
///
/// The week is a **position**, so the header title is itself the control:
/// `‹ This week · 31 Aug ▾ ›`. The chevrons step one week (unbounded — a week
/// with no row costs nothing, because `_getOrCreateWeek` only writes on the
/// first meal); tapping the title opens the short week menu.
///
/// There is ONE viewed week ([ViewedWeekStart], D3): Cook and Shop derive from
/// it, so all three tabs carry this same switcher as their only title. Its herb
/// dot and its "This week" item are how a derived tab says which week it shows
/// and offers the tap home, without a pill or a banner saying it a second
/// time. Two things differ per host: "Copy last week into this one" is a Week
/// *write* and stays off the derived tabs ([WeekSwitcher.showCopyLastWeek]),
/// and each tab's menu rows speak in that tab's own derivation
/// ([WeekSwitcher.detailFor]).
///
/// Lives apart from `week_view.dart` because all three tabs draw it.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/write.dart';
import '../data/planning_providers.dart';
import 'week_format.dart';
import 'week_view_models.dart';

/// The header title of every tab that shows a week: chevrons either side of
/// the week's name, the name itself opening the week menu.
class WeekSwitcher extends ConsumerWidget {
  const WeekSwitcher({this.showCopyLastWeek = true, this.detailFor, super.key});

  /// Whether the menu offers "Copy last week into this one". It is a Week
  /// write, and a derived tab's rule is "edit the Week, and this re-derives"
  /// (D7b) — so Cook and Shop pass false and never read the planning
  /// repository at all.
  final bool showCopyLastWeek;

  /// The trailing label for the menu row of a given week (its Monday), in the
  /// host tab's own words — `2 cooks`, `6 items`, `9 meals` — or null for a
  /// bare row. A tab only knows the week it has derived, so the rows it can
  /// label are the ones it already has data for.
  final String? Function(DateTime weekStart)? detailFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewed = ref.watch(viewedWeekStartProvider);
    final today = ref.watch(currentWeekStartProvider);
    final title = formatWeekTitle(viewed, today);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Chevron(
          icon: FLucideIcons.chevronLeft,
          semantics: 'Previous week',
          onTap: () => ref.read(viewedWeekStartProvider.notifier).step(-1),
        ),
        Flexible(
          child: _WeekMenu(
            title: title,
            showCopyLastWeek: showCopyLastWeek,
            detailFor: detailFor,
          ),
        ),
        _Chevron(
          icon: FLucideIcons.chevronRight,
          semantics: 'Next week',
          onTap: () => ref.read(viewedWeekStartProvider.notifier).step(1),
        ),
      ],
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({
    required this.icon,
    required this.semantics,
    required this.onTap,
  });

  final IconData icon;
  final String semantics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantics,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Icon(icon, size: 18, color: AnsiColors.muted),
        ),
      ),
    );
  }
}

/// The title, tappable: `● This week · 31 Aug ▾`. The herb dot marks the
/// current week so the emphasis survives a glance.
class _WeekMenu extends ConsumerWidget {
  const _WeekMenu({
    required this.title,
    required this.showCopyLastWeek,
    required this.detailFor,
  });

  final ({String label, String? date, bool isThisWeek}) title;
  final bool showCopyLastWeek;
  final String? Function(DateTime weekStart)? detailFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewed = ref.watch(viewedWeekStartProvider);
    final thisWeek = ref.watch(currentWeekStartProvider);
    // Only the Week screen's menu has a reason to know whether there is a
    // last week to copy; the derived tabs never touch the planning repository.
    final hasLastWeek =
        showCopyLastWeek && ref.watch(lastWeekProvider).asData?.value != null;
    final notifier = ref.read(viewedWeekStartProvider.notifier);

    Widget? detail(DateTime weekStart) {
      final label = detailFor?.call(weekStart);
      return label == null
          ? null
          : Text(label, style: ansiMono(size: 11, color: AnsiColors.muted));
    }

    return FPopoverMenu(
      // `menuBuilder`, not `menu`: an item has to be able to dismiss the menu
      // it was picked from before it acts.
      menuBuilder: (_, controller, _) => [
        FItemGroup(
          children: [
            FItem(
              prefix: const Icon(FLucideIcons.dot),
              title: const Text('This week'),
              details: detail(thisWeek),
              onPress: () {
                unawaited(controller.hide());
                notifier.today();
              },
            ),
            FItem(
              prefix: const Icon(FLucideIcons.chevronRight),
              title: const Text('Next week'),
              details: detail(thisWeek.add(const Duration(days: 7))),
              onPress: () {
                unawaited(controller.hide());
                notifier.set(thisWeek.add(const Duration(days: 7)));
              },
            ),
            FItem(
              prefix: const Icon(FLucideIcons.chevronLeft),
              title: const Text('Last week'),
              details: detail(thisWeek.subtract(const Duration(days: 7))),
              onPress: () {
                unawaited(controller.hide());
                notifier.set(thisWeek.subtract(const Duration(days: 7)));
              },
            ),
          ],
        ),
        FItemGroup(
          children: [
            if (hasLastWeek)
              FItem(
                prefix: const Icon(FLucideIcons.copy),
                title: const Text('Copy last week into this one'),
                onPress: () {
                  unawaited(controller.hide());
                  unawaited(
                    ref.write(
                      context,
                      'copy last week',
                      () => ref
                          .read(planningRepositoryProvider)
                          .copyLastWeek(viewed),
                    ),
                  );
                },
              ),
            FItem(
              prefix: const Icon(FLucideIcons.crosshair),
              title: const Text('Jump to today'),
              onPress: () {
                unawaited(controller.hide());
                notifier.today();
              },
            ),
          ],
        ),
      ],
      builder: (context, controller, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: controller.toggle,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title.isThisWeek) ...[
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AnsiColors.herb,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(
                title.date == null
                    ? title.label
                    : '${title.label} · ${title.date}',
                overflow: TextOverflow.ellipsis,
                style: ansiHeaderTitle(),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              FLucideIcons.chevronDown,
              size: 15,
              color: AnsiColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}
