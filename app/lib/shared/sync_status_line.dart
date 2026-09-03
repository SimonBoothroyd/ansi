/// A one-line, quiet readout of [syncHealthProvider] for a screen where the
/// answer matters *in the moment*.
///
/// Today that is Shop, and only Shop. Every other surface in Ansi is operated
/// by one person at a time; the shopping list is the one screen two phones
/// drive simultaneously, in a supermarket, while walking apart. A tick that has
/// not reached the other phone is not a background sync detail there — it is
/// the feature failing, silently, in the aisle, in exactly the place where
/// connectivity is worst.
///
/// It shares its provider with the Library `⋯` menu's line (`sync_health_row`)
/// and with the shell's banner (`sync_banner`) by construction, so the readouts
/// cannot disagree. What differs is the noun and the register: the banner says
/// *something is wrong*, this says *where you stand right now*.
///
/// It shows nothing when there is nothing to say — with one exception. After
/// the queue drains it says **"Synced · just now"** for a few seconds and then
/// retires itself. That is the confirmation a shopper actually wants ("it got
/// there") without a permanent status bar on a grocery list.
///
/// Explicitly **not** built: per-item pending marks. A queue is the system
/// working, and a dot on forty rows makes nothing look like something. The
/// count carries it — *which* two ticks are outstanding is not actionable,
/// since you cannot re-tick a tick and the fix for all of them is the same.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../core/sync/session.dart';
import '../core/sync/sync_health.dart';
import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';
import 'sync_words.dart';

/// How long "Synced · just now" lingers after the queue drains.
const settledLinger = Duration(seconds: 4);

class AnsiSyncStatusLine extends HookConsumerWidget {
  const AnsiSyncStatusLine({this.noun = 'change', super.key});

  /// Singular; pluralised for the count. Shop passes `'tick'`.
  final String noun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(syncHealthProvider).asData?.value;
    final settled = health is SyncSettled;

    // "Synced" is worth saying only just after something landed, so the line
    // is driven by a one-shot timer keyed on the transition INTO settled —
    // never a `Timer.periodic` started in build, and always disposed.
    final showSettled = useState(false);
    useEffect(() {
      if (!settled) {
        showSettled.value = false;
        return null;
      }
      showSettled.value = true;
      final timer = Timer(settledLinger, () => showSettled.value = false);
      return timer.cancel;
    }, [settled]);

    if (health == null) return const SizedBox.shrink();
    // The banner above already says this one, loudly. Don't say it twice.
    if (health is SyncRefused) return const SizedBox.shrink();
    if (settled && !showSettled.value) return const SizedBox.shrink();

    final line = syncLine(health, noun: noun, now: DateTime.now());
    final text = line.text;
    if (text == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 7, 20, 7),
      decoration: const BoxDecoration(
        color: AnsiColors.surface,
        border: Border(bottom: BorderSide(color: AnsiColors.line)),
      ),
      child: Row(
        children: [
          _Dot(tone: line.tone),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: ansiMono(size: 11, color: syncToneColor(line.tone)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (health is SyncStalled) ...[
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(
                ref.read(sessionControllerProvider.notifier).reconnect(),
              ),
              child: Text(
                'Try now',
                style: ansiMono(size: 11, color: AnsiColors.herbDeep),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The one mapping from a [SyncTone] to ink. Waiting is muted, never red.
Color syncToneColor(SyncTone tone) => switch (tone) {
  SyncTone.calm || SyncTone.busy => AnsiColors.muted,
  SyncTone.warn => AnsiColors.aging,
  SyncTone.bad => AnsiColors.gone,
};

class _Dot extends StatelessWidget {
  const _Dot({required this.tone});

  final SyncTone tone;

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: switch (tone) {
        SyncTone.calm => AnsiColors.fresh,
        SyncTone.busy || SyncTone.warn => AnsiColors.aging,
        SyncTone.bad => AnsiColors.gone,
      },
    ),
  );
}
