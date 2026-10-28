/// The sync banner: reports a state that stays wrong until something changes.
/// It renders nothing for the two healthy states.
///
/// Hosted once, by the tab shell, above the routed child.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../core/sync/dropped_write.dart';
import '../core/sync/session.dart';
import '../core/sync/sync_health.dart';
import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';
import '../core/words.dart';
import 'ansi_callout.dart';
import 'ansi_modals.dart';
import 'ansi_sheet_shell.dart';
import 'ansi_toast.dart';
import 'dropped_write_subject.dart';
import 'guarded_navigation.dart';
import 'sync_words.dart';
import 'write.dart';

class AnsiSyncBanner extends ConsumerWidget {
  const AnsiSyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(syncHealthProvider).asData?.value;
    return switch (health) {
      // Settled and waiting are healthy.
      null || SyncSettled() || SyncWaiting() => const SizedBox.shrink(),
      SyncStalled(:final queued, :final since) => _Banner(
        tone: SyncTone.warn,
        title: 'Changes aren’t reaching the other phone.',
        body:
            '$queued ${plural(queued, 'change')} not synced since '
            '${clockTime(since)}',
        action: 'Try now',
        onAction: () =>
            unawaited(ref.read(sessionControllerProvider.notifier).reconnect()),
      ),
      SyncRefused(:final drops) => _Banner(
        tone: SyncTone.bad,
        title: '${drops.length} ${plural(drops.length, 'change')} didn’t sync.',
        body: drops.length == 1
            ? 'It’s only on this phone.'
            : 'They’re only on this phone.',
        action: 'Show me',
        onAction: () => unawaited(showDroppedWriteSheet(context, drops)),
      ),
    };
  }
}

/// "Didn’t sync": each refused write named by the thing it changed, opening
/// it, since saving it there again is the retry. The table, the operation and
/// the server's code sit behind Copy details, for a bug report.
Future<void> showDroppedWriteSheet(
  BuildContext context,
  List<DroppedWrite> drops,
) {
  final host = hostContextOf(context);
  return showAnsiSheet<void>(
    context: context,
    builder: (sheetContext) => _DroppedWriteSheet(
      drops: drops,
      open: (route) {
        Navigator.of(sheetContext).pop();
        // A tab is gone to; every other page is pushed over the current one.
        if (_tabRoots.contains(Uri.parse(route).path)) {
          host.context.goOnce(route);
        } else {
          host.context.pushOnce(route);
        }
      },
      copied: () => showAnsiCopiedToast(host.context, what: 'Details'),
    ),
  );
}

const _tabRoots = {'/', '/week', '/cook', '/shop'};

/// The connector's record of [drops], newest first, for the clipboard.
String droppedWriteDetails(List<DroppedWrite> drops) => drops.reversed
    .map(
      (drop) =>
          '${drop.at.toIso8601String()}  ${drop.table} · ${drop.op} · '
          '${drop.rowId}\n${drop.code}: ${drop.message}',
    )
    .join('\n\n');

class _DroppedWriteSheet extends ConsumerWidget {
  const _DroppedWriteSheet({
    required this.drops,
    required this.open,
    required this.copied,
  });

  final List<DroppedWrite> drops;
  final ValueChanged<String> open;
  final VoidCallback copied;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AnsiSheetShell(
    title: 'Didn’t sync',
    centerTitle: false,
    dismiss: AnsiSheetDismiss.none,
    topPadding: 16,
    children: [
      const SizedBox(height: 8),
      for (final drop in drops.reversed)
        _DroppedWriteRow(drop: drop, open: open),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: FButton(
              variant: FButtonVariant.outline,
              onPress: () {
                unawaited(
                  Clipboard.setData(
                    ClipboardData(text: droppedWriteDetails(drops)),
                  ),
                );
                copied();
              },
              child: const Text('Copy details'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FButton(
              onPress: () {
                ref.read(droppedWritesProvider.notifier).acknowledge();
                Navigator.of(context).pop();
              },
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    ],
  );
}

/// `Weeknight Chicken Curry` over `recipe edit · 14:02`, with a chevron when
/// there is a page to open.
class _DroppedWriteRow extends ConsumerWidget {
  const _DroppedWriteRow({required this.drop, required this.open});

  final DroppedWrite drop;
  final ValueChanged<String> open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subject = switch (ref.watch(droppedWriteSubjectProvider(drop))) {
      AsyncData(:final value) => value,
      AsyncError() => DroppedWriteSubject.unfound(drop.table),
      // A local read: blank for a frame rather than a noun that then changes.
      _ => null,
    };
    final route = subject?.route;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: route == null ? null : () => open(route),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AnsiColors.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject?.name ?? '',
                    style: ansiSerif(size: AnsiType.row),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${droppedWriteKind(drop.table)} · ${clockTime(drop.at)}',
                    style: ansiMono(size: 10.5, color: AnsiColors.muted),
                  ),
                ],
              ),
            ),
            if (route != null)
              const Icon(
                FLucideIcons.chevronRight,
                size: 16,
                color: AnsiColors.muted,
              ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.tone,
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
  });

  final SyncTone tone;
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => AnsiCallout.banner(
    tone: tone == SyncTone.bad ? AnsiTone.alarm : AnsiTone.caution,
    icon: FLucideIcons.triangleAlert,
    title: title,
    body: body,
    action: action,
    onAction: onAction,
  );
}
