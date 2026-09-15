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
/// It says nothing when there is nothing to say — with one exception. After a
/// queue it *showed* drains it says **"Synced · just now"** for a few seconds
/// and then goes quiet again. That is the confirmation a shopper actually
/// wants ("it got there") without a permanent status bar on a grocery list.
///
/// Two rules keep it from moving the list under a walking thumb, which is what
/// a strip that comes and goes above a scroll does. **Its height is always
/// reserved**: an empty slot fades in and out, and the rows below never
/// travel. And a queue has to **outlive [waitingGrace]** before it is worth a
/// word — a tick that uploads in a fifth of a second is the system working,
/// not news, and the "Synced" that would follow it is not said either.
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

/// How long a queue must last before the line says so.
///
/// A tick's `ps_crud` row, its upload and the status that follows it are a
/// round trip on a good connection, and the derivation behind them is itself
/// throttled at 300 ms. Below this the queue is invisible to the person who
/// made it, and a strip that appeared for it would only be a flinch.
const waitingGrace = Duration(milliseconds: 700);

/// How long the slot takes to fade its content in or out.
const _fade = Duration(milliseconds: 160);

class AnsiSyncStatusLine extends HookConsumerWidget {
  const AnsiSyncStatusLine({this.noun = 'change', super.key});

  /// Singular; pluralised for the count. Shop passes `'tick'`.
  final String noun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(syncHealthProvider).asData?.value;
    final settled = health is SyncSettled;
    final waiting = health is SyncWaiting;

    // Whether the queue that is ending was ever on screen. It starts true so
    // that a screen opened onto an already-settled app still confirms once;
    // entering a queue clears it, and only the grace timer sets it again.
    final queueWasShown = useRef(true);

    // A queue earns its strip by lasting. One-shot timer keyed on the
    // transition INTO waiting, cancelled when the queue drains first.
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

    // "Synced" is worth saying only just after something the shopper watched
    // landed, so the line is driven by a one-shot timer keyed on the
    // transition INTO settled — never a `Timer.periodic` started in build,
    // and always disposed. The flag is consumed here: one queue, one
    // confirmation.
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
      // The banner above already says this one, loudly. Don't say it twice.
      null || SyncRefused() => null,
      SyncSettled() => showSettled.value ? line!.text : null,
      SyncWaiting() => showWaiting.value ? line!.text : null,
      _ => line!.text,
    };

    // The slot is drawn whether or not it is saying anything: this sits above
    // the Shop list's scroll, and a strip that collapsed would walk every row
    // up the screen under the thumb that ticked one. A blank line holds the
    // same height as a full one, so there is nothing to compute.
    return AnimatedOpacity(
      opacity: text == null ? 0 : 1,
      duration: _fade,
      child: IgnorePointer(
        ignoring: text == null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 7, 20, 7),
          decoration: const BoxDecoration(
            color: AnsiColors.surface,
            border: Border(bottom: BorderSide(color: AnsiColors.line)),
          ),
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
        ),
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
