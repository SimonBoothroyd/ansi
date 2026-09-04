/// The persistent half of the error posture: **a banner reports a state**.
///
/// A toast is for an act that didn't happen; this is for a condition that is
/// true right now and stays true until something changes. It renders nothing
/// for the two healthy states, so the app is quiet until it isn't.
///
/// Hosted **once**, by the tab shell, above the routed child — never per
/// screen. That is what makes "changes aren't reaching the other phone" a fact
/// about the app rather than a fact about whichever tab you happened to open.
library;

import 'dart:async';

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
import 'sync_words.dart';

class AnsiSyncBanner extends ConsumerWidget {
  const AnsiSyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(syncHealthProvider).asData?.value;
    return switch (health) {
      // Settled and waiting are both the system working. Nothing to say.
      null || SyncSettled() || SyncWaiting() => const SizedBox.shrink(),
      SyncStalled(:final queued, :final since) => _Banner(
        tone: SyncTone.warn,
        title: 'Changes aren’t reaching the other phone.',
        body:
            '$queued ${plural(queued, 'change')} '
            '${plural(queued, 'has', plural: 'have')} been waiting since '
            '${clockTime(since)}. Ansi keeps trying.',
        action: 'Try now',
        onAction: () =>
            unawaited(ref.read(sessionControllerProvider.notifier).reconnect()),
      ),
      SyncRefused(:final drops) => _Banner(
        tone: SyncTone.bad,
        title: drops.length == 1
            ? 'One change couldn’t be saved to the server.'
            : '${drops.length} changes couldn’t be saved to the server.',
        body: _refusedBody(drops),
        action: 'What happened',
        onAction: () => unawaited(showDroppedWriteSheet(context, drops)),
      ),
    };
  }
}

String _refusedBody(List<DroppedWrite> drops) {
  final first = drops.first;
  final subject = '${_readableTable(first.table)} from ${clockTime(first.at)}';
  return drops.length == 1
      ? 'A $subject was refused and won’t sync. It’s still on this phone.'
      : 'The oldest was a $subject. They’re still on this phone.';
}

/// The table name in the user's vocabulary. A person never typed `plan_entry`.
String _readableTable(String table) => switch (table) {
  'recipe' => 'recipe edit',
  'recipe_line' || 'recipe_group' => 'recipe edit',
  'plan_entry' => 'meal',
  'shopping_entry' || 'shopping_contribution' => 'shopping list change',
  'ingredient' || 'ingredient_alias' => 'ingredient edit',
  'measure' => 'measure',
  'book' || 'book_section' => 'book change',
  _ => 'change',
};

/// The detail behind "What happened": the table, the operation and the server's
/// own code — the same string the connector's [debugPrint] carries, shown to
/// the person it happened to instead of to a console nobody is reading.
Future<void> showDroppedWriteSheet(
  BuildContext context,
  List<DroppedWrite> drops,
) => showAnsiSheet<void>(
  context: context,
  builder: (_) => _DroppedWriteSheet(drops: drops),
);

class _DroppedWriteSheet extends ConsumerWidget {
  const _DroppedWriteSheet({required this.drops});

  final List<DroppedWrite> drops;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AnsiSheetShell(
    title: 'What happened',
    centerTitle: false,
    dismiss: AnsiSheetDismiss.none,
    topPadding: 16,
    children: [
      const SizedBox(height: 8),
      Text(
        'The server refused these writes outright, so Ansi stopped trying '
        'rather than wedge everything behind them. They are still on this '
        'phone, and they are not on the other one. Re-saving what they '
        'changed is what puts them back.',
        style: ansiSans(size: 13, color: AnsiColors.muted),
      ),
      const SizedBox(height: 16),
      for (final drop in drops.reversed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${clockTime(drop.at)}  ${drop.table} · ${drop.op} · '
            '${drop.rowId}\n${drop.code}: ${drop.message}',
            style: ansiMono(size: 11),
          ),
        ),
      const SizedBox(height: 8),
      FButton(
        variant: FButtonVariant.outline,
        onPress: () {
          ref.read(droppedWritesProvider.notifier).acknowledge();
          Navigator.of(context).pop();
        },
        child: const Text('I’ve seen this'),
      ),
    ],
  );
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
