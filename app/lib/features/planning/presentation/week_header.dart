/// The week switcher: the title of the Week, Cook and Shop screens — `‹ This
/// week · 31 Aug ▾ ›`.
///
/// The chevrons step [ViewedWeekStart] one week, unbounded; the title opens the
/// week menu. Cook and Shop derive from the same viewed week. Per host, "Copy
/// last week" is Week-only ([WeekSwitcher.showCopyLastWeek]) and the menu rows
/// use the tab's own wording ([WeekSwitcher.detailFor]).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_tap.dart';
import '../../account/data/household_providers.dart';
import 'copy_last_week.dart';
import 'week_format.dart';
import 'week_view_models.dart';

/// Chevrons either side of the week's name; the name opens the week menu.
class WeekSwitcher extends ConsumerWidget {
  const WeekSwitcher({this.showCopyLastWeek = true, this.detailFor, super.key});

  /// Whether the menu offers "Copy last week into this one". A Week write, so
  /// Cook and Shop pass false and never read the planning repository.
  final bool showCopyLastWeek;

  /// The trailing label for a week's menu row in the host tab's words (`2
  /// cooks`, `6 items`, `9 meals`), or null for a bare row.
  final String? Function(DateTime weekStart)? detailFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewed = ref.watch(viewedWeekStartProvider);
    final today = ref.watch(currentWeekStartProvider);
    final title = formatWeekTitle(viewed, today, ref.watch(weekShapeProvider));

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
    return AnsiTap(
      onTap: onTap,
      semanticsLabel: semantics,
      color: AnsiColors.muted,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Icon(icon, size: 18),
    );
  }
}

/// The tappable title: `● This week · 31 Aug ▾`. The herb dot marks the current
/// week.
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
    // Only the Week screen's menu reads the planning repository.
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
      // `menuBuilder`, not `menu`: an item must be able to dismiss the menu
      // before it acts.
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
                  unawaited(copyLastWeekInto(context, ref, weekStart: viewed));
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
