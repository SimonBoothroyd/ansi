/// The week switcher and its two return affordances (D2/D3).
///
/// The week is a **position**, so the Week screen's header title is itself the
/// control: `‹ This week · 31 Aug ▾ ›`. The chevrons step one week (unbounded
/// — a week with no row costs nothing, because `_getOrCreateWeek` only writes
/// on the first meal); tapping the title opens the short week menu, which is
/// also where "copy last week" now lives.
///
/// Cook and Shop derive from the same [ViewedWeekStart] (D3), so they must say
/// which week they are showing and offer one tap home: [BackToThisWeekPill] in
/// their header, and [ViewedWeekBanner] on the Week screen itself.
///
/// These live apart from `week_view.dart` because all three tabs draw them.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../data/planning_providers.dart';
import 'week_format.dart';
import 'week_view_models.dart';

/// The header title of the Week screen: chevrons either side of the week's
/// name, the name itself opening the week menu.
class WeekSwitcher extends ConsumerWidget {
  const WeekSwitcher({super.key});

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
        Flexible(child: _WeekMenu(title: title)),
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
  const _WeekMenu({required this.title});

  final ({String label, String? date, bool isThisWeek}) title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewed = ref.watch(viewedWeekStartProvider);
    final hasLastWeek = ref.watch(lastWeekProvider).asData?.value != null;
    final notifier = ref.read(viewedWeekStartProvider.notifier);
    final repo = ref.read(planningRepositoryProvider);

    return FPopoverMenu(
      // `menuBuilder`, not `menu`: an item has to be able to dismiss the menu
      // it was picked from before it acts.
      menuBuilder: (_, controller, _) => [
        FItemGroup(
          children: [
            FItem(
              prefix: const Icon(FLucideIcons.dot),
              title: const Text('This week'),
              onPress: () {
                unawaited(controller.hide());
                notifier.today();
              },
            ),
            FItem(
              prefix: const Icon(FLucideIcons.chevronRight),
              title: const Text('Next week'),
              onPress: () {
                unawaited(controller.hide());
                notifier.set(
                  ref
                      .read(currentWeekStartProvider)
                      .add(const Duration(days: 7)),
                );
              },
            ),
            FItem(
              prefix: const Icon(FLucideIcons.chevronLeft),
              title: const Text('Last week'),
              onPress: () {
                unawaited(controller.hide());
                notifier.set(
                  ref
                      .read(currentWeekStartProvider)
                      .subtract(const Duration(days: 7)),
                );
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
                  unawaited(repo.copyLastWeek(viewed));
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

/// The Week screen's own banner while another week is on screen: it says the
/// derived tabs came along (D3) and offers the one tap home.
class ViewedWeekBanner extends ConsumerWidget {
  const ViewedWeekBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewed = ref.watch(viewedWeekStartProvider);
    final today = ref.watch(currentWeekStartProvider);
    final suffix = formatDerivedWeekSuffix(viewed, today);
    if (suffix == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AnsiColors.herbSoft,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'You’re looking at $suffix — Cook and Shop follow it too',
              style: ansiMono(size: 11, color: AnsiColors.herbDeep),
            ),
          ),
          const SizedBox(width: 8),
          const BackToThisWeekPill(),
        ],
      ),
    );
  }
}

/// `back to this week ›` — the return, shown only while another week is
/// viewed. Cook and Shop carry it in their header (D3).
class BackToThisWeekPill extends ConsumerWidget {
  const BackToThisWeekPill({this.label = 'this week', super.key});

  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewed = ref.watch(viewedWeekStartProvider);
    final today = ref.watch(currentWeekStartProvider);
    if (viewed == today) return const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(viewedWeekStartProvider.notifier).today(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AnsiColors.surface,
          border: Border.all(color: AnsiColors.herb),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: ansiMono(size: 11, color: AnsiColors.herbDeep)),
            const SizedBox(width: 3),
            const Icon(
              FLucideIcons.chevronRight,
              size: 12,
              color: AnsiColors.herbDeep,
            ),
          ],
        ),
      ),
    );
  }
}
