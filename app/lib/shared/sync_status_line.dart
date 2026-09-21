/// A one-line readout of [syncHealthProvider] for Shop, the one screen two
/// phones drive at once.
///
/// It is quiet unless a queue outlives [waitingGrace], then says "Synced"
/// briefly once that queue drains. Its height is always reserved so the rows
/// below never move. There are no per-item pending marks.
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

/// How long a queue must last before the line says so. A tick that uploads
/// faster than this is not worth a word.
const waitingGrace = Duration(milliseconds: 700);

/// How long the slot takes to fade its content in or out.
const _fade = Duration(milliseconds: 160);

class AnsiSyncStatusLine extends HookConsumerWidget {
  const AnsiSyncStatusLine({this.noun = 'change', this.trailing, super.key});

  /// Singular; pluralised for the count. Shop passes `'tick'`.
  final String noun;

  /// One steady thing at the end of the strip: the Shop's trip estimate. It
  /// sits outside the fade.
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(syncHealthProvider).asData?.value;
    final settled = health is SyncSettled;
    final waiting = health is SyncWaiting;

    // Whether the ending queue was ever shown. Starts true so a screen opened
    // onto a settled app confirms once; only the grace timer sets it again.
    final queueWasShown = useRef(true);

    // One-shot timer keyed on the transition INTO waiting.
    final showWaiting = useState(false);
    useEffect(() {
      if (!waiting) {
        showWaiting.value = false;
        return null;
      }
      queueWasShown.value = false;
      final timer = Timer(waitingGrace, () {
        queueWasShown.value = true;
        showWaiting.value = true;
      });
      return timer.cancel;
    }, [waiting]);

    // One-shot timer keyed on the transition INTO settled, always disposed.
    // The flag is consumed here: one queue, one confirmation.
    final showSettled = useState(false);
    useEffect(() {
      if (!settled) {
        showSettled.value = false;
        return null;
      }
      if (!queueWasShown.value) {
        showSettled.value = false;
        return null;
      }
      queueWasShown.value = false;
      showSettled.value = true;
      final timer = Timer(settledLinger, () => showSettled.value = false);
      return timer.cancel;
    }, [settled]);

    final line = health == null
        ? null
        : syncLine(health, noun: noun, now: DateTime.now());
    final text = switch (health) {
      // The banner above already says this one.
      null || SyncRefused() => null,
      SyncSettled() => showSettled.value ? line!.text : null,
      SyncWaiting() => showWaiting.value ? line!.text : null,
      _ => line!.text,
    };

    // The slot is drawn even when blank, so the list below never moves.
    final trailing = this.trailing;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 7, 20, 7),
      decoration: const BoxDecoration(
        color: AnsiColors.surface,
        border: Border(bottom: BorderSide(color: AnsiColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: AnimatedOpacity(
              opacity: text == null ? 0 : 1,
              duration: _fade,
              child: IgnorePointer(
                ignoring: text == null,
                child: Row(
                  children: [
                    _Dot(tone: line?.tone ?? SyncTone.calm),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        text ?? ' ',
                        style: ansiMono(
                          size: 11,
                          color: syncToneColor(line?.tone ?? SyncTone.calm),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (text != null && health is SyncStalled) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => unawaited(
                          ref
                              .read(sessionControllerProvider.notifier)
                              .reconnect(),
                        ),
                        child: Text(
                          'Try now',
                          style: ansiMono(size: 11, color: AnsiColors.herbDeep),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing],
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
