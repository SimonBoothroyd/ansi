/// The Library `⋯` menu's footer line — sync health, one tap away.
///
/// Findable when wondered about, invisible when not, which is the right weight
/// for a fact that is boring 99.9% of the time. It costs no header space, needs
/// no route, and moves to `/account` whole — one widget, one provider — the day
/// a second thing wants to live there.
///
/// Non-interactive while healthy: a row that does nothing should not look like
/// a button. When it isn't healthy it turns amber and becomes the way through
/// to doing something about it.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../core/sync/session.dart';
import '../core/sync/sync_health.dart';
import '../core/theme/ansi_theme.dart';
import 'sync_banner.dart';
import 'sync_status_line.dart' show syncToneColor;
import 'sync_words.dart';

/// Mixes in [FItemMixin] so it can sit in the menu's own item group rather than
/// being a foreign widget bolted underneath it.
class SyncHealthRow extends ConsumerWidget with FItemMixin {
  const SyncHealthRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(syncHealthProvider).asData?.value;
    if (health == null) return const SizedBox.shrink();

    final line = syncLine(health, now: DateTime.now());
    final text = line.text;
    if (text == null) return const SizedBox.shrink();

    return FItem(
      title: Text(
        text,
        style: ansiMono(size: 11, color: syncToneColor(line.tone)),
      ),
      // Null while healthy: a row that does nothing must not look tappable.
      onPress: switch (health) {
        SyncSettled() || SyncWaiting() => null,
        SyncStalled() => () => unawaited(
          ref.read(sessionControllerProvider.notifier).reconnect(),
        ),
        SyncRefused(:final drops) => () => unawaited(
          showDroppedWriteSheet(context, drops),
        ),
      },
    );
  }
}
